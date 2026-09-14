# Loady workstation commands. Source from ~/.zprofile and ~/.zshrc on the Mac and on the VM:
#
#   [ -f "$HOME/loady-vm/scripts/loady-shell.zsh" ] && source "$HOME/loady-vm/scripts/loady-shell.zsh"
#
# No function here may have a name starting with an underscore, however private it is. Claude Code
# snapshots the interactive shell once and replays that snapshot into every command, and the
# snapshot drops functions whose names begin with one — it treats them as the shell's own
# completion internals. The symptom is that half the commands work and the rest die with
# "command not found", which reads as a broken repository rather than a shell that dropped half a
# file. Prefix helpers `ld_`.
#
# Nothing here commits, pushes, merges or opens a pull request. See AGENTS.md rule 2.

LOADY_VM_REPO="${LOADY_VM_REPO:-$HOME/loady-vm}"
LOADY_REPO="${LOADY_REPO:-$HOME/loady-one}"
LOADY_WORKTREES="${LOADY_WORKTREES:-$HOME/loady-worktrees}"

ld_run() {
  # `script`, never `path`: zsh ties `path` to PATH, so a local named `path` would replace the
  # shell's PATH with a relative script path for the life of the call.
  local script="$1"
  shift
  "$LOADY_VM_REPO/$script" "$@"
}

ld_run_with_bw_session() {
  command -v bw >/dev/null || { print -ru2 -- "Bitwarden CLI (bw) is not installed"; return 1 }
  command -v jq >/dev/null || { print -ru2 -- "jq is not installed"; return 1 }
  [[ -z "${BW_SESSION:-}" ]] || export BW_SESSION
  ld_bitwarden_session || return 1
  ld_run "$@"
}

# ---------------------------------------------------------------------------------------------
# The VM, from the Mac
# ---------------------------------------------------------------------------------------------

# Any command on the VM, in its login shell from the checkout, so the ld-* functions exist there
# too: ld-vm ld-status, ld-vm 'ld-start --public', ld-vm 'cd ~/loady-vm && git status'.
# LC_ALL: ssh forwards the Mac's LC_CTYPE=UTF-8, which the VM does not have, and every perl-based
# apt step there warns about it.
ld-vm()       { ssh -t "${LD_VM_HOST:-loady-vm}" -- "export LC_ALL=C.UTF-8; cd ~/loady-one && zsh -lic ${(q)*}"; }
ld-vm-setup() { ld_run infra/setup.sh "$@"; }
# The two workstation VMs on the Proxmox host, switched by name: starting one stops the other,
# because only one may run at a time. `vm-start loady`, `vm-stop dev`, `vm-status`.
vm-start()    { ld_run scripts/vm.sh start "$@"; }
vm-stop()     { ld_run scripts/vm.sh stop "$@"; }
vm-status()   { ld_run scripts/vm.sh status "$@"; }
# ld-up and ld-down name this VM without repeating which one it is.
ld-up()       { ld_run scripts/vm.sh start loady "$@"; }
ld-down()     { ld_run scripts/vm.sh stop loady; }
ld-tfd()      { ld_run_with_bw_session scripts/rebuild-loady-vm.zsh "$@"; }

# ---------------------------------------------------------------------------------------------
# The stack, on the VM
# ---------------------------------------------------------------------------------------------
ld-start()   { ld_run scripts/ld-dev.sh start "$@"; }
ld-stop()    { ld_run scripts/ld-dev.sh stop "$@"; }
ld-restart() { ld_run scripts/ld-dev.sh restart "$@"; }
ld-status()  { ld_run scripts/ld-dev.sh status "$@"; }
ld-logs()    { ld_run scripts/ld-dev.sh logs "$@"; }
ld-build()   { ld_run scripts/ld-dev.sh build "$@"; }
ld-seed()    { ld_run scripts/ld-dev.sh seed "$@"; }
ld-reset()   { ld_run scripts/ld-reset.sh "$@"; }

# The frontend dev server in local mode: the four variables frontend.ps1 exports, without needing
# PowerShell on the machine. Defaults are that script's defaults.
ld-fe() {
  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$repo" && -f "$repo/backend/Loady.slnx" ]] || repo="$LOADY_REPO"
  [[ -d "$repo/frontend" ]] || { print -ru2 -- "ld-fe: no frontend in $repo"; return 1; }
  (
    cd "$repo/frontend" || return 1
    export VUE_APP_API_BASE_URL="http://localhost:7000/app"
    export VUE_APP_AUTH_ENABLE_LOCAL_MODE=true
    export VUE_APP_AUTH_LOCAL_COMPANY_ID="${1:-TESTCOMPANY1}"
    export VUE_APP_AUTH_LOCAL_USER_ID="${2:-99999999-9999-9999-9999-999999999999}"
    yarn install --frozen-lockfile && yarn start
  )
}

# ---------------------------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------------------------
ld-add()    { ld_run scripts/ld-migrate.sh add "$@"; }
ld-update() { ld_run scripts/ld-migrate.sh update "$@"; }
ld-remove() { ld_run scripts/ld-migrate.sh remove "$@"; }
ld-mig()    { ld_run scripts/ld-migrate.sh list "$@"; }

# ---------------------------------------------------------------------------------------------
# Worktrees
# ---------------------------------------------------------------------------------------------
ld-agents() { ld_run scripts/link-agent-files.sh "$@"; }
ld-stl()    { ld_run scripts/ld-stream.sh list "$@"; }
ld-str()    { ld_run scripts/ld-stream.sh remove "$@"; }

ld-stn() {
  ld_run scripts/ld-stream.sh new "$@" || return
  ld-st "${1:-}"
}

ld-st() {
  if (( $# != 1 )); then
    print -ru2 -- "usage: ld-st <branch>"
    return 2
  fi
  cd "$LOADY_WORKTREES/$1" || return
}

# ---------------------------------------------------------------------------------------------
# Terraform, from the Mac
# ---------------------------------------------------------------------------------------------

# Load this root's secrets from Bitwarden and initialise Terraform. Every TF_VAR_* is cleared
# first: variables live in the shell, not in the root, so one loaded for another root stays
# exported and silently overrides this root's variable of the same name.
ld-tfin() {
  emulate -L zsh
  setopt localoptions pipefail

  command -v bw >/dev/null || { print -ru2 -- "Bitwarden CLI (bw) is not installed"; return 1 }
  command -v jq >/dev/null || { print -ru2 -- "jq is not installed"; return 1 }

  local -a stale
  stale=(${(k)parameters[(I)TF_VAR_*]})
  (( ${#stale} )) && unset "${stale[@]}"

  if [[ ! -f .tf-vars ]]; then
    print -ru2 -- "ld-tfin: no .tf-vars here; run it in infra"
    return 1
  fi

  ld_bitwarden_session || return 1

  print -- "Loading secrets from Bitwarden..."
  bw sync >/dev/null || return 1

  local ids items var id type field value
  ids="$(awk '!/^[[:space:]]*(#|$)/ { print $2 }' .tf-vars | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')" || return 1
  items="$(bw list items | jq -ce --argjson ids "$ids" '[.[] | select(.id as $i | $ids | index($i))]')" || return 1

  while read -r var id type field || [[ -n "$var" ]]; do
    [[ -z "$var" || "$var" == \#* ]] && continue
    type="${type:-password}"
    case "$type" in
      password) value="$(jq -er --arg id "$id" '.[] | select(.id == $id) | .login.password // empty' <<< "$items")" ;;
      username) value="$(jq -er --arg id "$id" '.[] | select(.id == $id) | .login.username // empty' <<< "$items")" ;;
      notes)    value="$(jq -er --arg id "$id" '.[] | select(.id == $id) | .notes // empty' <<< "$items")" ;;
      field)    value="$(jq -er --arg id "$id" --arg f "$field" '.[] | select(.id == $id) | .fields[]? | select(.name == $f) | .value // empty' <<< "$items")" ;;
      *) print -ru2 -- "ld-tfin: unknown value type '$type' for $var"; return 1 ;;
    esac
    if [[ -z "$value" ]]; then
      print -ru2 -- "ld-tfin: $var is missing on Bitwarden item $id (${type}${field:+ $field})."
      print -ru2 -- "         docs/manual-secrets.md says what belongs there."
      return 1
    fi
    export "$var=$value"
    printf "%-44s %s...\n" "$var:" "${value:0:12}"
  done < .tf-vars
  print -- "---"

  terraform init "$@"
}

ld_bitwarden_session() {
  local state
  state="$(bw status | jq -r .status)" || return 1
  case "$state" in
    unauthenticated)
      print -ru2 -- "Bitwarden login required."
      export BW_SESSION="$(bw login --raw)" || return 1
      ;;
    locked)
      print -ru2 -- "Bitwarden vault is locked."
      export BW_SESSION="$(bw unlock --raw)" || return 1
      ;;
    unlocked)
      [[ -n "${BW_SESSION:-}" ]] || export BW_SESSION="$(bw unlock --raw)" || return 1
      ;;
    *)
      print -ru2 -- "Unknown Bitwarden status: $state"
      return 1
      ;;
  esac
}
