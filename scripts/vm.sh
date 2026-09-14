#!/usr/bin/env bash
# Start and stop the workstation VMs on the Proxmox host, from the Mac.
#
#   vm-start loady     stop whatever else is running, then start loady-vm
#   vm-start dev       the same the other way round
#   vm-stop loady      shut it down
#   vm-status          what is running
#
# Only one workstation VM may run at a time: 32 GB each plus the cluster guests overcommits the
# node, and under memory pressure a guest OOM-kills its own build. So starting one stops the other,
# which is the switch this is for. The shutdown is a graceful ACPI shutdown that waits for the
# machine to actually stop — never a hard stop — but a build running there is still lost, so the
# command says what it is stopping before it does it. `--no-switch` refuses instead, for when that
# matters.
#
# Credentials come from the environment if `ld-tfin` has run, and from Bitwarden directly if not,
# so these work as one-off commands in any shell.
set -euo pipefail
LD_PROG=vm
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need curl jq

ENDPOINT="${LD_PROXMOX_ENDPOINT:-${TF_VAR_virtual_environment_endpoint:-https://192.168.1.22:8006}}"
USERNAME="${LD_PROXMOX_USERNAME:-${TF_VAR_virtual_environment_username:-root@pam}}"
NODE="${LD_PROXMOX_NODE:-${TF_VAR_node_name:-pve-2}}"

# The workstation VMs this switches between. Both live on the same node; `loady` is this
# repository's, `dev` is the founder's other one and is only ever read, started and shut down.
vm_id_for() {
  case "$1" in
    loady | loady-vm) echo "${LD_VM_ID:-201}" ;;
    dev | dev-vm) echo "${LD_OTHER_VM_ID:-200}" ;;
    *) return 1 ;;
  esac
}
KNOWN_VMS=(loady dev)

proxmox_password() {
  # The environment first, then Bitwarden, so `vm-start loady` works without `ld-tfin`.
  if [[ -n "${LD_PROXMOX_PASSWORD:-${TF_VAR_virtual_environment_password:-}}" ]]; then
    printf '%s' "${LD_PROXMOX_PASSWORD:-$TF_VAR_virtual_environment_password}"
    return 0
  fi
  command -v bw >/dev/null || ld_die "no Proxmox password in the environment and no Bitwarden CLI.
       Run 'ld-tfin' in infra/loady-vm, or set LD_PROXMOX_PASSWORD."
  local item
  item="$(awk '$1 == "TF_VAR_virtual_environment_password" { print $2 }' \
    "$(ld_vm_repo)/infra/loady-vm/.tf-vars")"
  [[ -n "$item" ]] || ld_die "could not find the Proxmox item id in infra/loady-vm/.tf-vars"
  bw get item "$item" 2>/dev/null | jq -er '.login.password' 2>/dev/null || ld_die \
    "Bitwarden is locked. Unlock it first:
           export BW_SESSION=\"\$(bw unlock --raw)\""
}

ticket_file="$(mktemp)"
trap 'rm -f "$ticket_file"' EXIT
chmod 600 "$ticket_file"

curl -sSk --max-time 20 \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$(proxmox_password)" \
  "$ENDPOINT/api2/json/access/ticket" >"$ticket_file" \
  || ld_die "could not reach $ENDPOINT"
jq -e .data.ticket >/dev/null <"$ticket_file" || ld_die "Proxmox rejected the credentials"

api() {
  local method="$1" path="$2"
  local ticket csrf
  ticket="$(jq -r .data.ticket <"$ticket_file")"
  csrf="$(jq -r .data.CSRFPreventionToken <"$ticket_file")"
  curl -sSk --max-time 30 -X "$method" \
    -H "Cookie: PVEAuthCookie=$ticket" \
    -H "CSRFPreventionToken: $csrf" \
    "$ENDPOINT/api2/json$path"
}

status_of() { api GET "/nodes/$NODE/qemu/$1/status/current" | jq -r '.data.status // "unknown"'; }
name_of() { api GET "/nodes/$NODE/qemu/$1/status/current" | jq -r '.data.name // "vmid '"$1"'"'; }

wait_for() {
  # wait_for <vmid> <wanted state> <timeout>
  local vmid="$1" wanted="$2" timeout="$3" waited=0
  while [[ "$(status_of "$vmid")" != "$wanted" ]]; do
    ((waited >= timeout)) && return 1
    sleep 5
    waited=$((waited + 5))
    printf '.'
  done
  printf ' %s\n' "$wanted"
}

shutdown_vm() {
  local vmid="$1" label="$2"
  ld_log "stopping $label"
  api POST "/nodes/$NODE/qemu/$vmid/status/shutdown" >/dev/null
  printf '    waiting'
  wait_for "$vmid" stopped 240 || ld_die "$label did not stop within 240s; check the Proxmox UI"
}

command="${1:-status}"
target="${2:-}"

case "$command" in
  start)
    [[ -n "$target" ]] || ld_die "usage: vm-start <loady|dev> [--no-switch]"
    vmid="$(vm_id_for "$target")" || ld_die "unknown VM '$target'; known: ${KNOWN_VMS[*]}"

    # Stop every other workstation VM first. Reading the state before acting means the common case
    # — the other one already stopped — costs nothing and says nothing.
    for other in "${KNOWN_VMS[@]}"; do
      other_id="$(vm_id_for "$other")"
      [[ "$other_id" == "$vmid" ]] && continue
      [[ "$(status_of "$other_id" 2>/dev/null || echo unknown)" == running ]] || continue
      other_name="$(name_of "$other_id")"
      if [[ "${3:-}" == --no-switch ]]; then
        ld_die "$other_name is running and --no-switch was given; nothing done"
      fi
      echo "    $other_name is running and will be shut down first."
      shutdown_vm "$other_id" "$other_name"
    done

    if [[ "$(status_of "$vmid")" == running ]]; then
      ld_log "$(name_of "$vmid") is already running"
    else
      ld_log "starting $(name_of "$vmid")"
      api POST "/nodes/$NODE/qemu/$vmid/status/start" >/dev/null
      printf '    waiting'
      wait_for "$vmid" running 180 || ld_die "it did not start; check the Proxmox UI"
      echo "    SSH is usually ready within a minute."
    fi
    ;;

  stop)
    [[ -n "$target" ]] || ld_die "usage: vm-stop <loady|dev>"
    vmid="$(vm_id_for "$target")" || ld_die "unknown VM '$target'; known: ${KNOWN_VMS[*]}"
    if [[ "$(status_of "$vmid")" != running ]]; then
      ld_log "$(name_of "$vmid") is already stopped"
    else
      shutdown_vm "$vmid" "$(name_of "$vmid")"
    fi
    ;;

  status)
    printf '%-12s %-6s %s\n' NAME ID STATE
    for vm in "${KNOWN_VMS[@]}"; do
      vmid="$(vm_id_for "$vm")"
      printf '%-12s %-6s %s\n' "$(name_of "$vmid" 2>/dev/null || echo "$vm")" "$vmid" \
        "$(status_of "$vmid" 2>/dev/null || echo unknown)"
    done
    ;;

  *)
    ld_die "usage: vm.sh <start|stop|status> [loady|dev]"
    ;;
esac
