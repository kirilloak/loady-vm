# Result: make ~/loady-vm on the VM a real checkout the founder can commit from

Plan: [2026_09_14_loady_vm_repo_on_the_vm.md](2026_09_14_loady_vm_repo_on_the_vm.md)

## Status

Complete and verified on the rebuilt VM: the bootstrap runs to status 0, `~/loady-vm` there is a
GitHub checkout bound to the `dev-vm-github` key, and `~/loady-one` still uses the Loady key and the
Loady address.

## Files created or edited

- `infra/.tf-vars` — two entries added: `TF_VAR_github_ssh_base64` (`workstation/keys`, field
  `ssh_dev_vm_github_base64`) and `TF_VAR_github_token` (`prod-infra/prod-github`, field `pat`),
  both already in the vault for the kirilloak dev VM. The Loady key's comment no longer claims it
  serves every remote.
- `infra/variables.tf` — `github_ssh_base64` (required, validated non-empty) and `github_token`
  (optional). The Loady key's description now says which checkout it is for.
- `infra/main.tf` — the environment file carries `LD_SECRET_SSH_GITHUB_BASE64` and
  `LD_SECRET_GITHUB_TOKEN`; the `send-tree` `local-exec` provisioner and its `send_tree_path` local
  are gone.
- `infra/setup.sh` — carries the same three secrets, each optional so a converge without the
  register still upgrades the machine; no longer sends the tree.
- `infra/send-tree.sh` — deleted.
- `infra/bootstrap.sh` — the GitHub half: `VM_REPO_URL`, `GITHUB_EMAIL`, the `dev-vm-github` key
  placed at `~/.ssh/kirilloak/dev-vm-github/id_ed25519`, the PAT written 0600 to
  `~/.config/loady/github-token` and exported as `GH_TOKEN`/`GITHUB_TOKEN` from the login profile,
  host keys pinned from `api.github.com/meta` (authenticated when the PAT is there), a `ls-remote`
  probe before the clone, `clone_checkout` for `$VM_REPO`, and `user.email` set locally in that
  checkout to the founder's GitHub noreply address. `key_usable` replaces the two inline key checks:
  the Azure DevOps key is still fatal, the GitHub key is a todo line, and an old copy at
  `~/loady-vm` is left alone with a todo rather than dying.
- `infra/bootstrap.sh`, second pass — two defects the first real run exposed; see below.
- `scripts/rebuild-loady-vm.zsh` — the pre-rebuild check loops over both checkouts instead of
  `cd`-ing into `loady-one` (and so no longer skips everything when that one is missing).
- `AGENTS.md` — rule 3 rewritten around two checkouts and two keys, with the boundary restated as
  what may be on each service rather than how many services there are; rule 5 now covers both
  working trees and says the setup is edited on the VM; `send-tree.sh` out of the knowledge table.
- `docs/manual-secrets.md` — four items, the GitHub key and PAT documented, the shared-credential
  cost stated, and the "not on GitHub" note corrected to "must not be, because dev-vm-github is".
- `docs/remote-development.md` — a new "Editing the setup itself" section; the rebuild refusal
  covers both checkouts.
- `infra/README.md` — the keys step, what `ld-tfd` does, and the rebuild description.
- `plans/done/2026_09_14_loady_vm.md`, `plans/done/2026_09_14_loady_vm_result.md`, and this plan —
  the other project's name replaced, by the founder's instruction that it not appear in this
  repository.

## Manual actions for the founder

- Rerun `ld-tfd`. The apply failed at the bootstrap, so Terraform never recorded
  `terraform_data.bootstrap`; the VM itself is converged and correct, and the rerun is Terraform
  catching up with it rather than more work on the machine.
- The end-to-end check the goal names, which needs a real commit and is therefore the founder's
  under rule 2: edit something in `~/loady-vm` on the VM, commit, push, and pull it on the Mac.
- Nothing to register anywhere. Both GitHub credentials already exist in Bitwarden.

## Notes

- `gh` is still not installed. The only thing the bootstrap wants from the API is
  `meta.ssh_keys`, which is one `curl`, and under rule 2 nothing here opens a pull request.
- No fingerprint for `github.com` is pinned in the file, unlike `ssh.dev.azure.com`: GitHub rotates
  its host keys and publishes them through its own API, which is the stronger source.
- `dotfiles/sync.sh` writes into `$VM_REPO`. That directory is now a checkout, so what it writes is
  a working-tree change the founder can commit on the VM — previously it was overwritten at the
  next converge.
- The Claude deny list is unchanged and repository-agnostic, so agents on the VM still cannot
  commit or push in either checkout.

## Defects found by running it, and fixed

1. **`sudo` strips the environment.** `env LOADY_REPO_DIR=... sudo docker compose pull` lost the
   variable, and the compose file's `${LOADY_REPO_DIR:?}` on the nginx.conf mount failed the run
   with "container images failed". On a first boot the `dev` user is not yet in the `docker` group
   for that session, so the sudo branch is exactly the branch a fresh VM takes — which is why this
   had never fired before: no earlier run reached this step. The `env` now goes inside the sudo.
2. **A converge without the register reported the PAT missing** even though an earlier run had
   placed it. The token block now falls back to the file it wrote, and only reports a missing PAT
   when neither the variable nor the file is there.

## Verification performed

- `shellcheck` on the VM for `bootstrap.sh`, `setup.sh` and `run-bootstrap.sh`: clean.
- `bash -n` on `bootstrap.sh` and `setup.sh`: pass.
- The generated `/etc/profile.d/loady-dev.sh` rendered from the script and checked with `bash -n`:
  the PAT block expands to a guarded `if [ -r ... ]` reading the 0600 file, with no token in the
  world-readable profile.
- `terraform fmt -check` and `terraform validate`: pass.
- `zsh -n` on `scripts/rebuild-loady-vm.zsh` and `scripts/loady-shell.zsh`: pass.
- `grep -ril costfluent` over the repository: no matches.
- On the rebuilt VM, a full `run-bootstrap.sh` to `Done in 289s: the VM matches this script`, with
  no todo lines: the images pull, and the second run is a clean converge.
- `git -C ~/loady-vm remote -v` is `git@github.com:kirilloak/loady-vm.git`; its `core.sshCommand`
  names `~/.ssh/kirilloak/dev-vm-github/id_ed25519` and `~/loady-one`'s names `~/.ssh/loady/id_rsa`.
- `GIT_AUTHOR_IDENT` is `79607671+kirilloak@users.noreply.github.com` in `~/loady-vm` and
  `kirill.starodubtsev@loady.com` in `~/loady-one`.
- Three `github.com` host keys in the VM's `known_hosts`, from the API; the clone's own key probe
  printed `dev-vm-github key reads git@github.com:kirilloak/loady-vm.git`.
- `~/.config/loady/github-token` is 0600, and a login shell has `GH_TOKEN` and `GITHUB_TOKEN` at 40
  characters each. `gh` is not installed.
- The rebuild refusal: the check from `rebuild-loady-vm.zsh` run against the VM with a probe file in
  `~/loady-vm` reported `loady-vm: ?? .ld-refusal-probe`. The probe was removed and that checkout is
  clean again.
- `ld-status` lists every function host and the compose stack.
- Not run: a commit and push from the VM, which under rule 2 is the founder's.
