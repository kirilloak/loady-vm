#!/usr/bin/env bash
# Trust the Cosmos emulator's self-signed certificate on this machine.
#
# The emulator generates its own certificate on first start and keeps it in the data volume, so it
# changes whenever ld-reset destroys that volume. On Windows and macOS the emulator installer, or
# the founder with Keychain Access, puts that certificate in the system trust store; on Linux
# nothing does, and every .NET or Node client that talks to https://localhost:8081 fails the
# handshake with an untrusted-root error. Disabling validation in the client is not the fix: that
# would mean changing loady-one, which rule 1 forbids, and it would hide real failures.
#
# So this installs the certificate the emulator is actually serving into the system trust store:
#   /usr/local/share/ca-certificates/cosmos-emulator*.crt  +  update-ca-certificates
# which is the store OpenSSL, curl and .NET on Linux all read. Node keeps its own compiled-in
# bundle, so the same certificate is also written to a bundle NODE_EXTRA_CA_CERTS points at
# (/etc/profile.d/loady-dev.sh, written by infra/bootstrap.sh).
#
# Idempotent and cheap: when what the emulator serves is already what is installed, it does
# nothing. ld-dev.sh runs it on every `ld-start`, right after the emulator reports ready, which is
# what keeps the trust store correct across a reset.
#
# Usage:
#   cosmos-cert.sh              install or refresh, then verify
#   cosmos-cert.sh --print      write the certificate chain to stdout and exit (for the Mac:
#                               `ld-vm 'ld-cosmos-cert --print' > cosmos.pem`, then add it to the
#                               login keychain as Always Trust for a browser or a Mac-side client)
#   cosmos-cert.sh --remove     take it back out of the trust store
set -euo pipefail
LD_PROG=ld-cosmos-cert
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/lib.sh"

ld_need openssl curl

COSMOS_HOST="${LOADY_COSMOS_HOST:-localhost}"
COSMOS_PORT="${LOADY_COSMOS_PORT:-8081}"
ANCHOR_DIR=/usr/local/share/ca-certificates
ANCHOR_PREFIX=cosmos-emulator
BUNDLE=/usr/local/share/loady/cosmos-emulator.pem

fetch_chain() {
  # The certificates the emulator is serving right now, leaf first, as one PEM stream.
  #
  # From the handshake rather than from https://localhost:8081/_explorer/emulator.pem: that
  # endpoint belongs to the old Windows emulator's explorer and the vnext image does not have to
  # serve it, while the handshake is the same on every image and is the thing being trusted.
  openssl s_client -showcerts -connect "$COSMOS_HOST:$COSMOS_PORT" -servername "$COSMOS_HOST" \
    </dev/null 2>/dev/null \
    | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/'
}

split_chain() {
  # split_chain <pem file> <output dir>: one cert.N.pem per certificate, in chain order.
  awk -v dir="$2" '
    /-----BEGIN CERTIFICATE-----/ { n++ }
    n { print > sprintf("%s/cert.%02d.pem", dir, n) }
  ' "$1"
}

is_ca() {
  openssl x509 -in "$1" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE'
}

is_self_signed() {
  local subject issuer
  subject="$(openssl x509 -in "$1" -noout -subject 2>/dev/null)"
  issuer="$(openssl x509 -in "$1" -noout -issuer 2>/dev/null)"
  [[ "${subject#subject=}" == "${issuer#issuer=}" ]]
}

describe() {
  openssl x509 -in "$1" -noout -subject -enddate 2>/dev/null | tr '\n' ' '
}

remove_anchors() {
  local found=0 file
  for file in "$ANCHOR_DIR/$ANCHOR_PREFIX"*.crt; do
    [[ -e "$file" ]] || continue
    sudo rm -f "$file"
    found=1
  done
  sudo rm -f "$BUNDLE"
  if ((found)); then
    sudo update-ca-certificates --fresh >/dev/null
    ld_log "removed the Cosmos emulator certificate from the trust store"
  else
    ld_log "nothing to remove"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "${1:-}" in
  --remove)
    remove_anchors
    exit 0
    ;;
  --print) ;;
  "") ;;
  *) ld_die "unknown argument '$1'; see the header of ${BASH_SOURCE[0]}" ;;
esac

fetch_chain >"$work/chain.pem"
[[ -s "$work/chain.pem" ]] || ld_die \
  "no TLS certificate from $COSMOS_HOST:$COSMOS_PORT — is the emulator running? ('ld-status')"

if [[ "${1:-}" == --print ]]; then
  cat "$work/chain.pem"
  exit 0
fi

split_chain "$work/chain.pem" "$work"

# The vnext image serves two certificates with the same distinguished name: a CA:TRUE root and the
# CA:FALSE leaf it signed. The root is the anchor; the leaf is trusted through it. An image that
# ever serves a bare self-signed leaf and no CA is handled by the fallback.
anchors=()
for cert in "$work"/cert.*.pem; do
  is_ca "$cert" && anchors+=("$cert")
done
if ((${#anchors[@]} == 0)); then
  for cert in "$work"/cert.*.pem; do
    is_self_signed "$cert" && anchors+=("$cert")
  done
fi
((${#anchors[@]})) || ld_die "the emulator's certificate chain carries nothing that can be trusted as a root"

# Written together so a partial refresh cannot leave one stale anchor behind: build the intended
# set first, compare it with what is installed, and replace the lot only when they differ.
installed="$(cat "$ANCHOR_DIR/$ANCHOR_PREFIX"*.crt 2>/dev/null || true)"
intended="$(cat "${anchors[@]}")"

if [[ "$installed" == "$intended" ]]; then
  ld_log "Cosmos emulator certificate already trusted: $(describe "${anchors[0]}")"
else
  ld_log "installing the Cosmos emulator certificate"
  sudo rm -f "$ANCHOR_DIR/$ANCHOR_PREFIX"*.crt
  index=1
  for cert in "${anchors[@]}"; do
    # One certificate per file: update-ca-certificates reads only the first one in a bundle.
    sudo install -m 0644 "$cert" "$(printf '%s/%s-%02d.crt' "$ANCHOR_DIR" "$ANCHOR_PREFIX" "$index")"
    echo "    $(describe "$cert")"
    index=$((index + 1))
  done
  sudo update-ca-certificates --fresh >/dev/null
fi

# Node ignores the system store, so the same anchors go in a bundle NODE_EXTRA_CA_CERTS names.
sudo install -d -m 0755 "$(dirname "$BUNDLE")"
printf '%s\n' "$intended" | sudo tee "$BUNDLE" >/dev/null
sudo chmod 0644 "$BUNDLE"

# Verify against the store rather than assume: an anchor that is trusted but whose subject
# alternative names do not cover the host the code connects to still fails, and that failure is
# worth seeing here rather than inside a seeder.
if curl -fsS --max-time 15 -o /dev/null "https://$COSMOS_HOST:$COSMOS_PORT/" 2>"$work/curl.err" \
  || grep -q '^curl: (22)' "$work/curl.err"; then
  ld_log "https://$COSMOS_HOST:$COSMOS_PORT verifies against the system trust store"
else
  ld_warn "the certificate is installed but https://$COSMOS_HOST:$COSMOS_PORT still does not verify:
       $(tr -d '\n' <"$work/curl.err")
       Names on the certificate: $(openssl x509 -in "${anchors[0]}" -noout -ext subjectAltName 2>/dev/null | tail -n1 | sed 's/^ *//')"
  exit 1
fi
