#!/usr/bin/env bash
# Run bootstrap.sh on this machine, detached from whatever started it, and follow it to its end.
# This runs on the VM. Both callers use it: the Terraform post step in main.tf beside this file,
# and setup.sh, which is the same run without Terraform.
#
# Why a unit rather than `bash bootstrap.sh` over the ssh channel: the bootstrap upgrades the
# machine under itself, replacing openssh-server among everything else, and it runs for a quarter of
# an hour. A session that owns the run loses it whenever that channel goes — an sshd restart, a
# dropped connection, a client that gives up. systemd owns the run instead, in nobody's session, so
# the channel carries only the log. Losing it costs an attach. Calling this again attaches to the
# run already in progress rather than starting a second one, which is what makes a retry cheap.
#
# It expects bootstrap.sh beside it, and optionally an `environment` file to source, which it
# removes once the run is over because that file holds the keys.
set -euo pipefail

UNIT=loady-bootstrap
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE=/run/loady-bootstrap

# The run's own copy of the script and the keys, so that a caller re-uploading either while the
# bootstrap is running cannot change the file bash is still reading. /run is tmpfs: nothing here
# survives a reboot, which is the right lifetime for a secret.
sudo install -d -m 0700 -o dev -g dev "$STATE"

if systemctl is-active --quiet "$UNIT"; then
  echo "==> $UNIT is already running; attaching to it"
else
  [[ -f "$DIR/bootstrap.sh" ]] || { echo "no bootstrap.sh beside $0" >&2; exit 1; }
  install -m 0700 "$DIR/bootstrap.sh" "$STATE/bootstrap.sh"
  if [[ -f "$DIR/environment" ]]; then
    install -m 0600 "$DIR/environment" "$STATE/environment"
    rm -f "$DIR/environment"
  else
    rm -f "$STATE/environment"
  fi
  rm -f "$STATE/status" "$STATE/log"
  : >"$STATE/log"

  # --collect removes the unit whichever way it ends, so the name is free for the next run; the
  # status therefore has to outlive it in a file rather than in the unit's state.
  sudo systemd-run --quiet --collect --unit="$UNIT" --uid=dev --gid=dev \
    --setenv=LC_ALL=C.UTF-8 \
    --property=WorkingDirectory=/home/dev \
    --property=StandardOutput="append:$STATE/log" \
    --property=StandardError="append:$STATE/log" \
    bash -c "set -a; [[ ! -f '$STATE/environment' ]] || . '$STATE/environment'; set +a
      bash '$STATE/bootstrap.sh'
      status=\$?
      echo \$status >'$STATE/status'
      exit \$status"
fi

# The channel carries the log and nothing else. tail -F rather than -f: the file is replaced, not
# appended to, when a later run starts.
tail -n +1 -F "$STATE/log" 2>/dev/null &
tail_pid=$!
ld_stop_tail() { kill "$tail_pid" 2>/dev/null || true; }
trap ld_stop_tail EXIT

while systemctl is-active --quiet "$UNIT"; do
  sleep 2
done
# The unit is gone before its last lines have been read out of the file.
sleep 1
ld_stop_tail

rm -f "$STATE/environment"
status=1
[[ ! -f "$STATE/status" ]] || status="$(cat "$STATE/status")"
exit "$status"
