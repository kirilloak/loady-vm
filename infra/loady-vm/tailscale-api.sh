#!/usr/bin/env bash
# Remove every exact-hostname `loady-vm` registration from the tailnet, and confirm the tailnet is
# actually clear before returning.
#
# Terraform runs this before creating the VM and again on destroy. The confirmation loop is the
# point: the devices list is eventually consistent and a node that is still online re-registers
# itself, so a DELETE that returns 200 is not the end of it. A registration that survives is what
# makes the replacement VM come back as `loady-vm-1`, after which `ssh loady-vm-ts` reaches
# nothing and the cause is not obvious.
set -euo pipefail

: "${LD_TAILSCALE_HOSTNAME:?}"
tailscale_api_key="${LD_TAILSCALE_API_KEY:-${TF_VAR_tailscale_api_key:-}}"
[[ -n "$tailscale_api_key" ]] || {
  echo "tailscale-api: run ld-tfin first so TF_VAR_tailscale_api_key is available" >&2
  exit 1
}

# Terraform hides this script's output when a sensitive value is in play, so keep a copy on the
# Mac; each run is one timestamped block and a rerun's diagnosis starts from here.
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/loady-vm"
mkdir -p "$log_dir"
exec > >(tee -a "$log_dir/tailscale-api.log") 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) hostname=$LD_TAILSCALE_HOSTNAME"

curl_config="$(mktemp)"
trap 'rm -f "$curl_config"' EXIT
chmod 600 "$curl_config"
printf 'user = "%s:"\n' "$tailscale_api_key" >"$curl_config"
unset tailscale_api_key LD_TAILSCALE_API_KEY TF_VAR_tailscale_api_key

tailscale_api() {
  local method="$1" path="$2"
  # Runs under macOS's bash 3.2 from Terraform, where expanding an empty array under `set -u` is
  # an unbound variable; hence the guarded expansion.
  local -a retry=()
  [[ "$method" != GET ]] || retry=(--retry 3 --retry-all-errors)
  curl --fail --silent --show-error --config "$curl_config" \
    --connect-timeout 10 --max-time 60 \
    ${retry[@]+"${retry[@]}"} \
    --request "$method" "https://api.tailscale.com/api/v2$path"
}

matching_devices() {
  local devices
  devices="$(tailscale_api GET /tailnet/-/devices)"
  jq -e '.devices | arrays' >/dev/null <<<"$devices"
  jq -r --arg hostname "$LD_TAILSCALE_HOSTNAME" '
    .devices[]
    | select(
        .hostname == $hostname
        or .name == $hostname
        or (.name | startswith($hostname + "."))
      )
    | [(.nodeId // .id), .name]
    | @tsv
  ' <<<"$devices"
}

found=false
while IFS=$'\t' read -r id name; do
  [[ -n "$id" ]] || continue
  found=true
  echo "tailscale-api: removing $name ($id)"
  tailscale_api DELETE "/device/$id" >/dev/null
done < <(matching_devices)

if [[ "$found" != true ]]; then
  echo "tailscale-api: no $LD_TAILSCALE_HOSTNAME registration exists; devices on the tailnet:"
  tailscale_api GET /tailnet/-/devices | jq -r '.devices[] | "  \(.hostname)\t\(.name)\t\(.nodeId // .id)"'
  exit 0
fi

for _ in 1 2 3 4 5 6; do
  remaining="$(matching_devices)"
  [[ -n "$remaining" ]] || { echo "tailscale-api: $LD_TAILSCALE_HOSTNAME is gone from the tailnet"; exit 0; }
  sleep 5
done
echo "tailscale-api: $LD_TAILSCALE_HOSTNAME is still registered after removal:" >&2
echo "$remaining" >&2
exit 1
