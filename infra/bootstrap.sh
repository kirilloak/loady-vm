#!/usr/bin/env bash
# Bootstrap the Loady development VM: the machine that holds the checkout, builds, runs the local
# stack and the coding agents, while the Mac only presents the UI. docs/remote-development.md owns
# the architecture and README.md beside this file owns the runbook; this file owns what is
# installed, how it is upgraded, how the host is hardened, and which secrets land where.
#
# Convergent and safe to rerun: every run brings the VM to the state this file describes and
# upgrades what it manages, so a rerun is also the upgrade. It runs as the `dev` user (not root) on
# the Ubuntu Server VM the Terraform root beside it creates; that root runs it as a post step over
# SSH on every apply, and setup.sh reruns it from the Mac at any time.
#
# Nothing here needs a version bump by hand. Every tool resolves its current stable release at run
# time, except the .NET channel, which comes from the checkout's backend/global.json, and Node,
# which is pinned to the major the frontend requires because a Node major is a change the lockfile
# has to be tested against.
set -euo pipefail

NODE_MAJOR=22
DEFAULT_DOTNET_CHANNEL=10.0

DOTNET_ROOT=/usr/share/dotnet
REPO="$HOME/loady-one"
VM_REPO="$HOME/loady-vm"
WORKTREES="$HOME/loady-worktrees"
GIT_USER_NAME="Kirill Starodubtsev"
# One address on this machine, in every checkout.
GIT_EMAIL="kirill.starodubtsev@loady.com"

LOADY_REPO_URL="git@ssh.dev.azure.com:v3/Loady-Logistics/loady/loady-one"

# Azure DevOps publishes one RSA host key for ssh.dev.azure.com. Pinning by fingerprint rather than
# trusting whatever ssh-keyscan returns is the difference between a known host and a hope.
# Confirmed 2026-09-14 against the founder's own profile page
# (dev.azure.com/Loady-Logistics/_usersSettings/keys), which prints the same value; the MD5 form
# there is 97:70:33:82:fd:29:3a:73:39:af:6a:07:ad:f8:80:49.
ADO_RSA_FINGERPRINT="SHA256:ohD8VZEXGWo6Ez8GSEJQ9WpafgLFsOfLOtGGQCQo6Og"

bootstrap_started=$SECONDS
log() { echo "==> $*"; }
die() { echo "loady-vm-bootstrap: $1" >&2; exit 1; }

# --------------------------------------------------------------------------------------------------
# Logging: everything to a 0600 log inside the VM as well as to the caller, with a stable symlink.
# --------------------------------------------------------------------------------------------------
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/loady-vm/bootstrap"
install -d -m 700 "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ).log"
: >"$LOG_FILE"
chmod 600 "$LOG_FILE"
ln -sfn "$LOG_FILE" "$LOG_DIR/latest.log"
find "$LOG_DIR" -name '*.log' -mtime +30 -delete 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

try_with_progress() {
  # try_with_progress <label> <command...>: stream the command's output, with a heartbeat every 20
  # seconds so a long step does not look like a hang to whoever is watching the apply. Returns the
  # command's status, for the caller that treats some failure as something other than fatal.
  local label="$1"
  shift
  local started=$SECONDS
  ("$@") &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 20
    kill -0 "$pid" 2>/dev/null && echo "    ... $label ($((SECONDS - started))s)"
  done
  wait "$pid"
}

run_with_progress() {
  # The fatal form, which is what nearly every step wants.
  try_with_progress "$@" || die "$1 failed"
}

download() {
  local label="$1" url="$2" dest="$3"
  curl -fsSL --connect-timeout 10 --max-time 900 --retry 3 --retry-all-errors "$url" -o "$dest" \
    || die "could not download $label from $url"
}

# A package upgrade restarts the service it replaces, and openssh-server's restart takes down the
# ssh session this script runs in — which kills the script, and leaves the caller with a channel
# that closed without a status. Deny every service action for the duration of the upgrade, record
# what was denied, and let the reboot at the end of the run apply them. Scoped to the upgrade: the
# install transaction after it must be free to start what it installs.
#
# Two mechanisms restart services, and both have to be stopped: dpkg's maintainer scripts, which
# consult policy-rc.d, and needrestart's apt hook, which does not and takes NEEDRESTART_SUSPEND
# instead. apt() below adds that variable exactly while the shield file exists.
APT_RESTART_SHIELD=/usr/sbin/policy-rc.d
APT_DENIED_RESTARTS=/run/loady-bootstrap-denied-restarts

shield_service_restarts() {
  sudo rm -f "$APT_DENIED_RESTARTS"
  printf '%s\n' '#!/bin/sh' "echo \"\$1\" >>$APT_DENIED_RESTARTS" 'exit 101' \
    | sudo tee "$APT_RESTART_SHIELD" >/dev/null
  sudo chmod 0755 "$APT_RESTART_SHIELD"
}

unshield_service_restarts() {
  sudo rm -f "$APT_RESTART_SHIELD"
  # Ubuntu's own flag file, which the end of this script already acts on.
  [[ ! -s "$APT_DENIED_RESTARTS" ]] || sudo touch /var/run/reboot-required
}

bootstrap_finished() {
  local status=$?
  sudo rm -f "$APT_RESTART_SHIELD" 2>/dev/null || true
  ((status == 0)) || echo "loady-vm-bootstrap: failed after $((SECONDS - bootstrap_started))s; log: $LOG_FILE" >&2
  return $status
}
trap bootstrap_finished EXIT

log "bootstrap started; log: $LOG_FILE"

# --------------------------------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------------------------------
[[ "$(id -u)" -ne 0 ]] || die "run as the development user, not root — the script uses sudo where it must"
# shellcheck disable=SC1091
[[ -r /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "this script targets Ubuntu Server, found '${PRETTY_NAME:-unknown}'"
[[ "$(dpkg --print-architecture)" == "amd64" ]] || die "this script targets amd64, found $(dpkg --print-architecture)"
for tool in curl gpg; do
  command -v "$tool" >/dev/null || die "the cloud image must provide $tool"
done
sudo -n true 2>/dev/null || sudo -v || die "the development user needs sudo"
# The sshd hardening below turns password logins off; without a key the next login would be the last.
[[ -s "$HOME/.ssh/authorized_keys" ]] || die "no $HOME/.ssh/authorized_keys — add the Mac's public key before hardening sshd"

# First boot: cloud-init is still writing the user and the network when the Terraform post step
# connects, so wait for it rather than race it.
if command -v cloud-init >/dev/null; then
  cloud_init_status=0
  try_with_progress "cloud-init" sudo cloud-init status --wait || cloud_init_status=$?
  case "$cloud_init_status" in
    0) ;;
    2) log "cloud-init completed with recoverable warnings"; sudo cloud-init status --long || true ;;
    *) sudo cloud-init status --long || true; die "cloud-init did not complete successfully" ;;
  esac
fi

# sudo resets the environment, so the frontend and the conffile policy travel on every apt call: a
# debconf prompt or a "keep your version?" question would hang a run nobody is watching. The lock
# timeout waits out unattended-upgrades instead of failing on its lock.
apt() {
  local operation="apt-get $*"
  local -a deadline=()
  if [[ "$1" == update ]]; then
    deadline=(timeout --signal=TERM --kill-after=30s 5m)
  fi
  # ACCEPT_EULA is what mssql-tools18 and the ODBC driver under it read instead of prompting; a
  # debconf prompt no one can answer would hang the transaction.
  local -a apt_env=(DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y)
  [[ ! -e "$APT_RESTART_SHIELD" ]] || apt_env+=(NEEDRESTART_SUSPEND=1)
  run_with_progress "$operation" "${deadline[@]}" sudo env "${apt_env[@]}" apt-get \
    -o DPkg::Lock::Timeout=600 \
    -o Acquire::Retries=3 \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    -o Acquire::Languages=none \
    -o APT::Get::Always-Include-Phased-Updates=true \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}
CODENAME="${VERSION_CODENAME:?}"
KEYRINGS=/etc/apt/keyrings
sudo install -m 0755 -d "$KEYRINGS"

apt_updated=false
apt_update() {
  if [[ "$apt_updated" != true ]]; then
    apt update
    apt_updated=true
  fi
}

apt_repo() {
  # apt_repo <name> <key-url> <deb-line>: add a third-party source once, as a keyring plus a .list
  # file; a rerun re-downloads nothing and rewrites the list only when its line changed.
  local name="$1" key_url="$2" deb_line="$3"
  local keyring="$KEYRINGS/$name.gpg" list="/etc/apt/sources.list.d/$name.list"
  if [[ ! -f "$keyring" ]]; then
    local key
    key="$(mktemp)"
    curl -fsSL --connect-timeout 10 --max-time 120 --retry 3 --retry-all-errors "$key_url" -o "$key"
    if grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$key"; then
      sudo gpg --dearmor -o "$keyring" "$key"
    else
      sudo install -m 0644 "$key" "$keyring"
    fi
    rm -f "$key"
    sudo chmod a+r "$keyring"
  fi
  if [[ "$(cat "$list" 2>/dev/null || true)" != "$deb_line" ]]; then
    echo "$deb_line" | sudo tee "$list" >/dev/null
    apt_updated=false
  fi
}

# --------------------------------------------------------------------------------------------------
# Third-party apt sources
#
# Deliberately absent: gh (AGENTS.md rule 3 — this machine's remote is Azure DevOps), and the
# packages.microsoft.com/.../prod repository that carries pwsh and mssql-tools. That repository is
# keyed by Ubuntu version and lags new releases badly, which would fail the bootstrap on exactly the
# image it targets. sqlcmd comes from Microsoft's prod repo instead, and PowerShell is not installed at
# all: ld-fe replaces frontend.ps1 and ld-dev.sh replaces backend.ps1.
# --------------------------------------------------------------------------------------------------
log "apt sources"
apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
  "deb [arch=amd64 signed-by=$KEYRINGS/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable"
apt_repo nodesource https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  "deb [arch=amd64 signed-by=$KEYRINGS/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main"
apt_repo azure-cli https://packages.microsoft.com/keys/microsoft.asc \
  "deb [arch=amd64 signed-by=$KEYRINGS/azure-cli.gpg] https://packages.microsoft.com/repos/azure-cli/ $CODENAME main"
# mssql-tools18 carries sqlcmd. Microsoft's prod repo is keyed by release number rather than
# codename, and publishes for this one (checked 2026-09-14 for 26.04/resolute).
apt_repo mssql-prod https://packages.microsoft.com/keys/microsoft.asc \
  "deb [arch=amd64 signed-by=$KEYRINGS/mssql-prod.gpg] https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod $CODENAME main"
# Ubuntu freezes git at release; the maintainers' PPA tracks upstream stable for every release.
apt_repo git-core "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" \
  "deb [arch=amd64 signed-by=$KEYRINGS/git-core.gpg] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu $CODENAME main"

# --------------------------------------------------------------------------------------------------
# Upgrade everything apt manages within this Ubuntu release, then install the development packages
# in one transaction. Separate installs repeatedly re-solve the same graph and rerun dpkg triggers.
# --------------------------------------------------------------------------------------------------
log "apt upgrade"
apt_update
shield_service_restarts
apt upgrade --with-new-pkgs -y
unshield_service_restarts

log "development packages"
apt install -y --no-install-recommends \
  openssh-server ufw unattended-upgrades \
  ca-certificates curl wget gnupg jq \
  git make build-essential python3 \
  unzip zip tmux htop lsof zsh cron rsync \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  nodejs azure-cli \
  ripgrep fd-find shellcheck mssql-tools18

# --------------------------------------------------------------------------------------------------
# Docker Engine
# --------------------------------------------------------------------------------------------------
log "docker"
# Published ports default to 127.0.0.1: on Linux the daemon answers published ports on every
# interface, ahead of ufw, and nothing in the local stack should be reachable from the LAN. The
# compose file also binds loopback explicitly; this is the backstop for anything that does not.
# live-restore keeps containers up across the daemon upgrades this script performs.
daemon_json='{
  "ip": "127.0.0.1",
  "live-restore": true,
  "default-ulimits": { "nofile": { "Name": "nofile", "Hard": 1048576, "Soft": 1048576 } },
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}'
if [[ "$(sudo cat /etc/docker/daemon.json 2>/dev/null || true)" != "$daemon_json" ]]; then
  echo "$daemon_json" | sudo tee /etc/docker/daemon.json >/dev/null
  sudo systemctl restart docker
fi
sudo systemctl enable --now docker >/dev/null
id -nG "$USER" | tr ' ' '\n' | grep -qx docker || sudo usermod -aG docker "$USER"

# --------------------------------------------------------------------------------------------------
# .NET
# --------------------------------------------------------------------------------------------------
DOTNET_CHANNEL="$DEFAULT_DOTNET_CHANNEL"
[[ -f "$REPO/backend/global.json" ]] && DOTNET_CHANNEL="$(sed -nE 's/.*"version":[[:space:]]*"([0-9]+\.[0-9]+).*/\1/p' "$REPO/backend/global.json" | sed -n '1p')"

log ".NET SDK $DOTNET_CHANNEL"
# Every run: the installer is a no-op when the channel's latest SDK is already there, and installs
# it side by side otherwise, which is how the SDK follows global.json's rollForward.
download ".NET installer" https://dot.net/v1/dotnet-install.sh /tmp/dotnet-install.sh
# The installer fetches a 200 MB tarball with a curl of its own, and that curl carries no timeout:
# when the CDN edge goes silent mid-transfer the run waits on a dead connection rather than failing
# (seen 2026-09-14 — 189 MB in, then an established socket with nothing arriving for nine minutes).
# Bound each attempt and open a new connection instead of waiting on that one.
dotnet_installed=false
for attempt in 1 2 3; do
  if try_with_progress ".NET SDK install (attempt $attempt)" \
    sudo timeout --signal=TERM --kill-after=30s 10m bash /tmp/dotnet-install.sh \
    --channel "$DOTNET_CHANNEL" --install-dir "$DOTNET_ROOT"; then
    dotnet_installed=true
    break
  fi
  log ".NET SDK install did not finish; starting over"
done
[[ "$dotnet_installed" == true ]] || die ".NET SDK install did not finish in three attempts"
rm -f /tmp/dotnet-install.sh
[[ -e /usr/bin/dotnet ]] || sudo ln -s "$DOTNET_ROOT/dotnet" /usr/bin/dotnet
export DOTNET_ROOT
export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"
# The workload manifests lag the SDK they ship with, and Rider asks for `dotnet workload update`
# until they match; a no-op in under a second once they do.
run_with_progress ".NET workload manifests" sudo "$DOTNET_ROOT/dotnet" workload update
# ld-migrate.sh and Rider's EF integration both need this.
run_with_progress "dotnet-ef global tool" "$DOTNET_ROOT/dotnet" tool update -g dotnet-ef

# --------------------------------------------------------------------------------------------------
# Ubuntu names two of these differently from the commands everyone types, and Microsoft keeps
# sqlcmd off PATH. Link rather than alias, so a script and a login shell find them alike.
# --------------------------------------------------------------------------------------------------
log "tool names"
[[ -e /usr/local/bin/fd ]] || sudo ln -s "$(command -v fdfind)" /usr/local/bin/fd
[[ -e /usr/local/bin/sqlcmd ]] || sudo ln -s /opt/mssql-tools18/bin/sqlcmd /usr/local/bin/sqlcmd

# --------------------------------------------------------------------------------------------------
# npm-delivered tools: yarn (the frontend uses Yarn Classic), the Azure Functions Core Tools that
# run the function hosts, the Bitwarden CLI, and Codex. Core Tools comes from npm rather than apt
# for the codename reason above; npm has one package for every platform.
# --------------------------------------------------------------------------------------------------
log "yarn, func, codex, bw"
if ! command -v yarn >/dev/null || ! command -v func >/dev/null || ! command -v bw >/dev/null \
  || ! command -v codex >/dev/null \
  || npm outdated -g --json 2>/dev/null | jq -e 'has("npm") or has("yarn") or has("azure-functions-core-tools") or has("@openai/codex") or has("@bitwarden/cli")' >/dev/null; then
  run_with_progress "npm global installs" sudo npm install -g --unsafe-perm \
    npm@latest yarn@1 azure-functions-core-tools@4 @openai/codex@latest @bitwarden/cli@latest
fi

log "claude"
# `claude update` is a version check when current; the installer downloads the binary every time.
if [[ ! -x "$HOME/.local/bin/claude" ]] || ! try_with_progress "Claude update" "$HOME/.local/bin/claude" update; then
  download "Claude installer" https://claude.ai/install.sh /tmp/claude-install.sh
  run_with_progress "Claude install" bash /tmp/claude-install.sh
  rm -f /tmp/claude-install.sh
fi

# --------------------------------------------------------------------------------------------------
# Environment: PATH and the variables the Loady tooling expects, for every login shell
# --------------------------------------------------------------------------------------------------
log "profile"
profile=/etc/profile.d/loady-dev.sh
profile_content="export DOTNET_ROOT=$DOTNET_ROOT
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=1
export LOADY_REPO=$REPO
export LOADY_VM_REPO=$VM_REPO
export LOADY_WORKTREES=$WORKTREES
# backend.ps1 sets both of these; the function hosts read them to select
# appsettings.Localhost.json and the Localhost authentication middleware.
export AZURE_FUNCTIONS_ENVIRONMENT=Localhost
export EnvironmentName=Localhost
# AppDbContextDesignFactory falls back to this when no --connection argument is given.
export loady_relational_database_connection='Server=localhost,1433;Database=loady;User Id=sa;Password=Passw0rd!;TrustServerCertificate=True;'
# The Cosmos emulator's self-signed certificate goes into the system trust store, which .NET and
# curl read; Node reads only its own compiled-in bundle, so it is pointed at the copy
# scripts/cosmos-cert.sh writes. Guarded because a NODE_EXTRA_CA_CERTS naming a file that does not
# exist yet makes every node process warn on startup.
[ -f /usr/local/share/loady/cosmos-emulator.pem ] \
  && export NODE_EXTRA_CA_CERTS=/usr/local/share/loady/cosmos-emulator.pem
export PATH=\$HOME/.local/bin:\$HOME/.dotnet/tools:\$DOTNET_ROOT:\$PATH"
if [[ "$(cat "$profile" 2>/dev/null || true)" != "$profile_content" ]]; then
  echo "$profile_content" | sudo tee "$profile" >/dev/null
fi

for rc in "$HOME/.zprofile" "$HOME/.zshrc"; do
  if ! grep -qsF 'loady-shell.zsh' "$rc"; then
    cat >>"$rc" <<'EOF'
# Loady workstation commands (infra/bootstrap.sh)
[ -f /etc/profile.d/loady-dev.sh ] && . /etc/profile.d/loady-dev.sh
[ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
alias claude-ask='command claude'
alias codex-ask='command codex'
alias claude='claude --dangerously-skip-permissions'
alias codex='codex --yolo'
alias cl='claude'
alias cx='codex'
EOF
  fi
done
# Completion, shared history, and a prompt with the directory and branch — which matters here
# because several worktrees are open at once and a session in the wrong one is the expensive
# mistake. Plain zsh, so there is no framework to install or update.
if ! grep -qsF 'loady-prompt' "$HOME/.zshrc"; then
  cat >>"$HOME/.zshrc" <<'EOF'
# loady-prompt (infra/bootstrap.sh)
autoload -Uz compinit vcs_info && compinit
HISTFILE=~/.zsh_history HISTSIZE=50000 SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space prompt_subst
zstyle ':vcs_info:git:*' formats ' %F{blue}(%b)%f'
precmd() { vcs_info; }
PROMPT='%F{green}%~%f${vcs_info_msg_0_} $ '
EOF
fi
[[ "$(getent passwd "$USER" | cut -d: -f7)" == "$(command -v zsh)" ]] || sudo chsh -s "$(command -v zsh)" "$USER"

mkdir -p "$WORKTREES"

# --------------------------------------------------------------------------------------------------
# SSH keys and git identity. One key, one remote: Azure DevOps for loady-one, the only checkout on
# this machine. It is bound to the key with core.sshCommand, so nothing depends on an agent
# forwarded from the Mac and every headless session — Rider's backend, tmux, cron — pushes the same.
# --------------------------------------------------------------------------------------------------
log "ssh keys"
git_todo=""

place_secret() {
  # place_secret <env var> <destination>: write a base64 secret 0600, only when it differs.
  local var="$1" dest="$2" content
  content="${!var:-}"
  content="${content// /}"
  [[ -n "$content" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  chmod 700 "$(dirname "$dest")"
  if [[ "$(base64 -d <<<"$content" | cmp -s - "$dest" 2>/dev/null && echo same)" != same ]]; then
    base64 -d <<<"$content" >"$dest.tmp"
    chmod 600 "$dest.tmp"
    mv "$dest.tmp" "$dest"
    echo "    wrote ${dest/#$HOME/~}"
  fi
  chmod 600 "$dest"
}

# One key for every git remote this machine talks to. It is the founder's existing Loady key, which
# is already registered on Azure DevOps, the only git service this machine reaches, so nothing new
# changes. IdentitiesOnly matters more than it looks: Azure DevOps accepts the first key offered and
# may reject the request outright rather than trying the next one.
git_key="$HOME/.ssh/loady/id_rsa"
place_secret LD_SECRET_SSH_GIT_BASE64 "$git_key"
git_ssh_command="ssh -i $git_key -o IdentitiesOnly=yes"

mkdir -p "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
add_known_host() {
  local line="$1"
  grep -qxF "$line" "$HOME/.ssh/known_hosts" || echo "$line" >>"$HOME/.ssh/known_hosts"
}

# Azure DevOps publishes one RSA host key. Take whatever ssh-keyscan offers, but keep only the key
# whose fingerprint matches the published one — that is the difference between pinning and hoping.
ado_scanned="$(ssh-keyscan -t rsa ssh.dev.azure.com 2>/dev/null || true)"
if [[ -n "$ado_scanned" ]]; then
  ado_fingerprint="$(printf '%s\n' "$ado_scanned" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' | head -n1)"
  if [[ "$ado_fingerprint" == "$ADO_RSA_FINGERPRINT" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && add_known_host "$line"; done <<<"$ado_scanned"
  else
    git_todo="$git_todo
  - ssh.dev.azure.com offered host key $ado_fingerprint, not the published $ADO_RSA_FINGERPRINT; not pinned"
  fi
else
  git_todo="$git_todo
  - could not reach ssh.dev.azure.com to pin its host key"
fi

log "git identity"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_EMAIL"
# Never a rebase on pull: a rebased branch needs a force-push, and nothing here force-pushes.
git config --global pull.rebase false

clone_checkout() {
  # clone_checkout <url> <path> <ssh command>: clone when missing, and always bind the checkout to
  # its own key. A path that exists but is not a checkout fails without replacing it.
  local url="$1" path="$2" ssh_command="$3"
  if [[ -e "$path" && ! -e "$path/.git" ]]; then
    die "$path exists but is not a Git checkout; left untouched"
  fi
  if [[ ! -e "$path/.git" ]]; then
    run_with_progress "clone $(basename "$path")" env GIT_SSH_COMMAND="$ssh_command" \
      git clone -q "$url" "$path"
  fi
  git -C "$path" remote set-url origin "$url"
  git -C "$path" config core.sshCommand "$ssh_command"
}

log "checkouts"
if [[ ! -f "$git_key" ]]; then
  die "no git key in the register; run 'ld-tfin' in infra on the Mac and rerun (docs/manual-secrets.md)"
elif ! ssh-keygen -y -P "" -f "$git_key" >/dev/null 2>&1; then
  # A passphrase here would make every headless push prompt forever; the register is supposed to
  # hold the passphrase-less copy, so say so plainly rather than hang later.
  die "the git key is passphrase-protected; replace the register field with a passphrase-less copy (docs/manual-secrets.md)"
else
  clone_checkout "$LOADY_REPO_URL" "$REPO" "$git_ssh_command"
fi

# --------------------------------------------------------------------------------------------------
# The checkout: agent files, dotfiles, and a warm cache so Rider's first open and the first
# ld-start are not a download.
#
# Nothing here touches a dirty working tree. Under AGENTS.md rule 2 nothing commits automatically,
# so uncommitted work is the normal state on this machine and the disk is its only copy.
# --------------------------------------------------------------------------------------------------
if [[ -d "$VM_REPO" ]]; then
  log "agent files and dotfiles"
  [[ -x "$VM_REPO/scripts/link-agent-files.sh" ]] \
    || die "$VM_REPO/scripts/link-agent-files.sh is missing or not executable"
  "$VM_REPO/scripts/link-agent-files.sh" "$REPO"
  if [[ -x "$VM_REPO/dotfiles/sync.sh" ]]; then
    "$VM_REPO/dotfiles/sync.sh" install
    "$VM_REPO/dotfiles/sync.sh" || git_todo="$git_todo
  - dotfiles sync conflict; see $VM_REPO/dotfiles/README.md"
  fi
fi

log "loady commands"
for command_name in ld-reset ld-start ld-stop ld-status ld-build ld-fe ld-agents ld-cosmos-cert; do
  zsh -lic "whence -w $command_name" 2>/dev/null | grep -qx "$command_name: function" \
    || die "$command_name is not available in the VM login shell"
done

if [[ -d "$REPO/.git" ]]; then
  if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
    log "checkout has uncommitted work; leaving it exactly as it is"
  fi

  log "warming the build cache"
  run_with_progress "dotnet restore" dotnet restore "$REPO/backend/Loady.slnx" --nologo --verbosity quiet
  run_with_progress "dotnet build" dotnet build "$REPO/backend/Loady.slnx" --no-restore --nologo --verbosity quiet
  run_with_progress "yarn install" yarn --cwd "$REPO/frontend" install --frozen-lockfile

  # The container images, so the first ld-start is not a download. The docker group joined above is
  # not in this session's groups until the next login, hence sudo when it is missing.
  docker_cmd=(docker)
  id -nG | tr ' ' '\n' | grep -qx docker || docker_cmd=(sudo docker)
  run_with_progress "container images" env LOADY_REPO_DIR="$REPO" "${docker_cmd[@]}" compose \
    --project-directory "$VM_REPO/compose" -f "$VM_REPO/compose/loady-vm.yaml" pull --quiet

  # The Cosmos emulator's certificate can only be taken from a running emulator, so a first
  # bootstrap cannot install it — ld-start does, every time. This is for the other case: a converge
  # on a VM where the stack is already up, where the trust store should be correct when this
  # returns. Silent and non-fatal when the emulator is not listening, which is the normal case.
  if curl -fsSk --max-time 5 -o /dev/null https://localhost:8081/ 2>/dev/null; then
    log "Cosmos emulator certificate"
    "$VM_REPO/scripts/cosmos-cert.sh" || log "could not trust the emulator certificate; 'ld-cosmos-cert' after the next ld-start"
  fi
else
  die "$REPO was not cloned"
fi

# --------------------------------------------------------------------------------------------------
# Host tuning for Rider and the containers
# --------------------------------------------------------------------------------------------------
log "host tuning"
# Rider's backend and the dev server each watch the whole checkout; the kernel default runs out on
# a repository this size and the IDE silently stops seeing changes.
sysctl_conf=/etc/sysctl.d/60-loady-dev.conf
sysctl_content="fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152
fs.aio-max-nr = 1048576
vm.dirty_background_ratio = 10
vm.dirty_ratio = 20
net.core.somaxconn = 4096"
if [[ "$(cat "$sysctl_conf" 2>/dev/null || true)" != "$sysctl_content" ]]; then
  echo "$sysctl_content" | sudo tee "$sysctl_conf" >/dev/null
  sudo sysctl -q -p "$sysctl_conf"
fi

# Spectre/MDS mitigations cost 5-20% on the syscall-heavy work here (msbuild, docker, git). Only
# the founder's own code runs in this guest; the host keeps its own mitigations.
grub_conf=/etc/default/grub.d/60-loady-perf.cfg
# shellcheck disable=SC2016  # expanded by grub-mkconfig when it sources the file
grub_content='GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT mitigations=off"'
if [[ "$(cat "$grub_conf" 2>/dev/null || true)" != "$grub_content" ]]; then
  echo "$grub_content" | sudo tee "$grub_conf" >/dev/null
  sudo update-grub >/dev/null 2>&1
  sudo touch /var/run/reboot-required
fi

# noatime: every read of obj/, node_modules and the git object store otherwise queues an inode write.
if grep -qsE '^[^#]\S*\s+/\s+ext4\s+' /etc/fstab && ! grep -qsE '^[^#]\S*\s+/\s+ext4\s+\S*noatime' /etc/fstab; then
  sudo sed -i -E 's#^([^#]\S*\s+/\s+ext4\s+)(\S+)#\1noatime,\2#' /etc/fstab
  sudo mount -o remount /
fi

# The zvol behind scsi0 already schedules on the host; a second queue in the guest adds latency.
udev_rule=/etc/udev/rules.d/60-loady-io-scheduler.rules
udev_content='ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="none"'
if [[ "$(cat "$udev_rule" 2>/dev/null || true)" != "$udev_content" ]]; then
  echo "$udev_content" | sudo tee "$udev_rule" >/dev/null
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=block --action=change
fi

# /tmp in RAM: NuGet extraction and the SDK installers stage there. Takes effect on the next boot
# so a populated /tmp is not shadowed under a running session.
if ! systemctl is-enabled --quiet tmp.mount 2>/dev/null; then
  sudo cp /usr/share/systemd/tmp.mount /etc/systemd/system/tmp.mount
  sudo systemctl enable --quiet tmp.mount
  sudo touch /var/run/reboot-required
fi

# Rider's indexer, the dev server and eleven function hosts together exceed the default 1024.
for scope in system user; do
  limits_conf="/etc/systemd/$scope.conf.d/60-loady-dev.conf"
  limits_content="[Manager]
DefaultLimitNOFILE=1048576:1048576"
  if [[ "$(cat "$limits_conf" 2>/dev/null || true)" != "$limits_content" ]]; then
    sudo mkdir -p "$(dirname "$limits_conf")"
    echo "$limits_content" | sudo tee "$limits_conf" >/dev/null
    sudo touch /var/run/reboot-required
  fi
done

# --------------------------------------------------------------------------------------------------
# Hardening: sshd keys only, ufw deny-by-default, unattended security updates
# --------------------------------------------------------------------------------------------------
log "sshd"
# sshd keeps the first value it reads and Include sorts drop-ins lexically, so this file sorts ahead
# of the image's 50-cloud-init.conf rather than deferring to it.
sshd_conf=/etc/ssh/sshd_config.d/10-loady.conf
sshd_content="PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowTcpForwarding yes
ClientAliveInterval 30
ClientAliveCountMax 3"
# `sshd -t` refuses to run without the privilege-separation directory, which systemd creates for
# ssh.service and removes when it stops — including across the openssh-server upgrade above.
sudo install -d -m 0755 /run/sshd
if [[ "$(sudo cat "$sshd_conf" 2>/dev/null || true)" != "$sshd_content" ]]; then
  echo "$sshd_content" | sudo tee "$sshd_conf" >/dev/null
  sudo sshd -t
  sudo systemctl restart ssh
fi
sshd_effective="$(sudo sshd -T)"
grep -qx 'allowtcpforwarding yes' <<<"$sshd_effective" || die "sshd must allow TCP forwarding for JetBrains Gateway"
grep -Eq '^subsystem sftp ' <<<"$sshd_effective" || die "sshd must provide SFTP for JetBrains Gateway"

log "ufw"
lan_iface="$(ip -o route show default | awk '!found {print $5; found=1}')"
lan_cidr="$(ip -o -4 route show dev "$lan_iface" scope link | awk '!found {print $1; found=1}')"
[[ -n "$lan_cidr" ]] || die "could not determine the LAN subnet on $lan_iface"
# No reset: ufw skips a rule that already exists, so the policy converges without ever dropping the
# firewall on a machine in use.
sudo ufw default deny incoming >/dev/null
sudo ufw default allow outgoing >/dev/null
sudo ufw allow from "$lan_cidr" to any port 22 proto tcp comment "ssh from LAN" >/dev/null

# The second half of the host.docker.internal fix. nginx in the apim container calls back to the
# function hosts on the VM's bridge address, and that traffic arrives inbound on a br-* interface,
# which the default deny drops — the symptom is a 502 from nginx with no other clue. Opened for the
# Docker bridge address space and only for the ports in compose/processes.json: a blanket
# `allow in on docker0` would miss the compose network's own bridge anyway, since it is named
# dynamically, and would outlive the reason for it.
if [[ -f "$VM_REPO/compose/processes.json" ]]; then
  while read -r port; do
    sudo ufw allow from 172.16.0.0/12 to any port "$port" proto tcp comment "function host from docker bridge" >/dev/null
  done < <(jq -r '.groups[].processes[].port' "$VM_REPO/compose/processes.json")
else
  git_todo="$git_todo
  - compose/processes.json is missing, so the docker bridge cannot reach the function hosts; rerun after the clone"
fi
sudo ufw --force enable >/dev/null

log "unattended-upgrades"
auto_upgrades='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
if [[ "$(cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true)" != "$auto_upgrades" ]]; then
  echo "$auto_upgrades" | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
fi
sudo systemctl enable --now unattended-upgrades >/dev/null

log "cleanup"
apt autoremove -y --purge
apt clean

# --------------------------------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------------------------------
log "installed"
printf '  %-12s %s\n' \
  dotnet "$(dotnet --version)" \
  node "$(node --version)" \
  npm "$(npm --version)" \
  yarn "$(yarn --version 2>/dev/null)" \
  func "$(func --version 2>/dev/null || echo installed)" \
  docker "$(docker --version | awk '{print $3}' | tr -d ,)" \
  compose "$(docker compose version --short)" \
  az "$(az version -o tsv --query '"azure-cli"' 2>/dev/null || echo installed)" \
  sqlcmd "$(sqlcmd --version 2>/dev/null | head -n1)" \
  git "$(git --version | awk '{print $3}')" \
  jq "$(jq --version | sed 's/^jq-//')" \
  rg "$(rg --version | awk 'NR == 1 {print $2}')" \
  fd "$(fd --version | awk '{print $2}')" \
  shellcheck "$(shellcheck --version | awk '/^version:/ {print $2}')" \
  claude "$("$HOME/.local/bin/claude" --version 2>/dev/null | head -n1 || echo installed)" \
  codex "$(codex --version 2>/dev/null | head -n1 || echo installed)" \
  bw "$(bw --version 2>/dev/null)" \
  ufw "$(sudo ufw status | head -n1)"

echo
# A short timer rather than `shutdown -r +1`: the caller's SSH session ends on its own terms, and a
# timer does not raise pam_nologin, which would refuse every login until the reboot lands.
if [[ -f /var/run/reboot-required ]]; then
  echo "Ubuntu requires a reboot: rebooting in 15 seconds."
  sudo systemd-run --quiet --on-active=15 systemctl reboot
fi
[[ -z "$git_todo" ]] || echo "$git_todo"
if [[ ! -d "$REPO/.git" ]]; then
  die "the checkout is missing after bootstrap"
else
  echo "Done in $((SECONDS - bootstrap_started))s: the VM matches this script."
fi
