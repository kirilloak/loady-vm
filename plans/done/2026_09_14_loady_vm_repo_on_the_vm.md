# Make ~/loady-vm on the VM a real checkout the founder can commit from

## Goal

`~/loady-vm` on the VM is a GitHub checkout of this repository, cloned and kept by the bootstrap
with the founder's existing `dev-vm-github` key and PAT, so an edit made on the VM to a bootstrap
script, an `ld-*` function or an AI config can be committed and pushed there instead of being
overwritten at the next converge.

## Success criteria

- On the VM, `git -C ~/loady-vm remote -v` shows `git@github.com:kirilloak/loady-vm.git`, and
  `git -C ~/loady-vm push` works with no prompt and no agent forwarded from the Mac.
- A commit made in `~/loady-vm` on the VM carries `79607671+kirilloak@users.noreply.github.com`;
  a commit in `~/loady-one` still carries `kirill.starodubtsev@loady.com`.
- `ld-tfd` on an existing VM leaves uncommitted work in `~/loady-vm` untouched; nothing rsyncs over
  it and nothing deletes from it.
- `ld-tfd --rebuild` refuses while `~/loady-vm` on the VM holds uncommitted or unpushed work, the
  same as `~/loady-one`.
- The Mac's checkout and the VM's checkout exchange work only through GitHub. Neither script copies
  the tree between them.
- `github.com`'s host keys are in the VM's `known_hosts`, taken from `api.github.com/meta` rather
  than from whatever `ssh-keyscan` answers.
- `gh` is still not installed.
- A full bootstrap ends with status 0, and `ld-status` still works.

## Blockers

None. The credentials already exist and are already registered:

- `workstation/keys` (`59967647-9d93-4e60-917f-b4bf015de599`), field `ssh_dev_vm_github_base64` —
  `dev-vm-github`, a passphrase-less user key on the founder's GitHub account, already used by the
  kirilloak dev VM.
- `prod-infra/prod-github` (`72c148f2-f62c-491f-97ca-b39a0171e3e3`), field `pat` — the founder's
  PAT, the same one kirilloak uses.

Both are read straight from Bitwarden by `ld-tfin`, so nothing has to be generated, copied or
registered by hand. The one thing to confirm on first run is that the key can read
`kirilloak/loady-vm`, which a user key on that account should; step 2 probes it and says so.

## Approach

This reverses one half of `plans/2026_09_14_no_github_on_the_vm.md`. That plan removed GitHub from
the VM for two reasons: the clone was failing, and the VM should not reach the team's world. The
first was a key that had never been registered — and the key the setup was trying to use was the
wrong one, the Azure DevOps key, when a working GitHub key was already sitting in the same vault.
The second reason still holds for `loady-one` and the Loady org, and is untouched here:
`kirilloak/loady-vm` is the founder's own private repository.

So: the VM clones this repository from GitHub, the Mac stops sending it, and `~/loady-vm` goes back
to being working-tree state that nothing on either machine may destroy. `infra/send-tree.sh` and its
two callers are removed rather than kept as a fallback — two paths for the same tree is how a copy
and a checkout end up disagreeing.

The credential design is lifted from the kirilloak dev VM, which has run it since 2026-09-12:
one key per service, each bound to its checkout through `core.sshCommand`, and the register as the
only place a private key lives.

| | Azure DevOps | GitHub |
|---|---|---|
| Key | `~/.ssh/loady/id_rsa` (`ssh_loady_git_base64`) | `~/.ssh/loady/dev-vm-github/id_ed25519` (`ssh_dev_vm_github_base64`) |
| Checkout | `~/loady-one` | `~/loady-vm` |
| Identity | `kirill.starodubtsev@loady.com` (global) | `79607671+kirilloak@users.noreply.github.com` (repository-local) |
| Host keys | pinned by published RSA fingerprint | `api.github.com/meta`, `.ssh_keys[]` |

Two keys rather than one, because both already exist and each is registered where it belongs.
Adding the Azure DevOps key to GitHub — option A of the first draft of this plan — is now the worse
answer: it would need a manual registration, and it would couple a rotation in an org the founder
does not own to his personal account.

The PAT is placed as a file and exported, not handed to `gh`. `gh` stays uninstalled (rule 3); the
only thing the bootstrap needs from the API is `meta.ssh_keys`, which is one `curl`. Agents and
scripts on the VM get `GH_TOKEN` in the environment for read-only API work. Installing `gh` later
is one `apt_repo` line if it earns its place, but rule 2 means it would never open a pull request
anyway.

The tradeoff bought: uncommitted work on the Mac no longer reaches the VM. A change to `scripts/`
or `dotfiles/` has to be committed and pushed on the Mac before `ld-tfd` shows it on the VM — or,
more usually, made on the VM in the first place. That is the point of the change, and it is what
rule 4 already says about where daily work happens.

## Steps

1. **Register entries.** Add to `infra/.tf-vars`: `TF_VAR_github_ssh_base64`
   (`59967647-…` field `ssh_dev_vm_github_base64`) and `TF_VAR_github_token`
   (`72c148f2-…` field `pat`). Carry both through `infra/setup.sh` and `infra/main.tf` the way
   `TF_VAR_loady_ssh_git_base64` already travels — the 0600 environment file over stdin, and the
   `local-exec` export block — as `LD_SECRET_SSH_GITHUB_BASE64` and `LD_SECRET_GITHUB_TOKEN`.
   Why: the bootstrap cannot place what the converge does not carry. Depends on nothing.
   Verify: `ld-tfin` prints no missing-field error, `shellcheck`, `terraform validate`, and the
   variables arrive on the VM (`sudo grep -c LD_SECRET .../environment` during a run).

2. **`infra/bootstrap.sh` — the GitHub block.** Ported from kirilloak's, minus `gh`:
   place the key at `~/.ssh/loady/dev-vm-github/id_ed25519`; write the PAT to
   `~/.config/loady/github-token` at 0600 and export `GH_TOKEN`/`GITHUB_TOKEN` from the login shell;
   pin host keys from `curl -fsS https://api.github.com/meta` (the token in an `Authorization`
   header when present, since unauthenticated is rate-limited), filtered through `jq -r
   '.ssh_keys[]'` into `known_hosts`; probe the key with a `BatchMode` `git ls-remote` against
   `kirilloak/loady-vm` before anything depends on it; then `clone_checkout` `$VM_REPO` with
   `github_ssh_command`. Every failure here is a `git_todo` line, not a `die` — a VM whose GitHub
   clone failed must still converge everything else. Keep the `-d "$VM_REPO"` guard on the block
   that reads `$VM_REPO/scripts` and `$VM_REPO/dotfiles`, and keep the clone before it.
   Why: the VM owns its own copy of this repository again. Depends on step 1.
   Verify: `shellcheck`, `bash -n`, then a real run whose probe line prints and whose clone is
   green, with `github.com` in `known_hosts` and no `gh` on the box.

3. **Git identity per checkout.** The global identity stays Loady's, for `loady-one`. The bootstrap
   sets `user.name`/`user.email` locally in `~/loady-vm` to `Kirill Starodubtsev` and
   `79607671+kirilloak@users.noreply.github.com`, beside the `core.sshCommand` `clone_checkout`
   already sets. Why: a personal repository should not carry the company address, and GitHub's
   noreply form keeps the real one off a public commit log. Depends on step 2.
   Verify: `git -C ~/loady-vm var GIT_AUTHOR_IDENT` and the same in `~/loady-one`, on the VM.

4. **Migrate the existing VM directory.** `~/loady-vm` there is a copy with no `.git`, and
   `clone_checkout` refuses to replace it by design. Remove it on the VM once, by hand, after
   `diff -r` against the Mac shows nothing the founder wants. Why: the one-time cost of the
   previous plan. Depends on step 2. Verify: `ld-vm 'test ! -e ~/loady-vm'` before the converge,
   and a `.git` there after it.

5. **Stop sending the tree.** Delete `infra/send-tree.sh`, its call in `infra/setup.sh`, and the
   `local-exec` provisioner and `send_tree_path` local in `infra/main.tf`. Why: one owner for the
   tree on the VM, and a converge that cannot overwrite the founder's uncommitted work. Depends on
   step 2. Verify: `shellcheck`, `terraform fmt -check`, `terraform validate`, and a converge that
   leaves a deliberately dirty file on the VM untouched.

6. **Protect the work on rebuild.** `scripts/rebuild-loady-vm.zsh` checks `~/loady-one` and its
   worktrees for uncommitted and unpushed work; add `~/loady-vm` to that check. Why: rule 5 again
   covers it. Depends on step 5. Verify: `zsh -n`, then `ld-tfd --rebuild` with a dirty file in
   `~/loady-vm` on the VM refuses and names it, and `--force` passes.

7. **Documentation.** Rule 3 in `AGENTS.md`: the VM reaches Azure DevOps for `loady-one` and GitHub
   for this repository alone, `gh` still not installed, no GitHub release downloads, nothing Loady
   on GitHub. Rule 5 loses the copy-not-checkout exception; both checkouts on the VM are
   authoritative working trees. `docs/manual-secrets.md` gains the two new register fields, what
   each key opens, and the note that both are shared with the kirilloak dev VM so a rotation is
   two machines. `infra/README.md` and `infra/variables.tf` lose `send-tree.sh` and the copy claim.
   `docs/remote-development.md` gains the workflow in one line: edit on the VM, commit there, push,
   pull on the Mac before touching Terraform. Why: one fact, one file, and five files currently
   assert the opposite. Depends on steps 2-6. Verify: read, and
   `rg -n 'send-tree|a copy the Mac sends'` returns nothing.

8. **Full converge.** `ld-tfin && ld-vm-setup` to status 0, then on the VM make a trivial edit in
   `~/loady-vm`, commit it, push it, and pull it on the Mac. Why: the goal is committing from the
   VM, so the check is a commit from the VM. Verify: the run's exit status, `ld-vm ld-status`, the
   author line on the new commit, and the commit present on the Mac after `git pull`.

## Assumptions

- `kirilloak/loady-vm` is private and on the founder's own account, so putting it on the VM does
  not put this setup anywhere near the team's org. Rule 1 is unaffected: nothing here touches
  `loady-one`.
- Rule 2 is unaffected. The VM gains the ability to commit; the deny list in
  `dotfiles/ai/claude/settings.json` still stops every agent on it from doing so. Committing and
  pushing from the VM is the founder's hand on the keyboard, and the founder's alone.
- The `dev-vm-github` user key can read and write `kirilloak/loady-vm`. It is a user key, not a
  deploy key, so it carries the account's access; step 2's probe is what proves it.
- The Mac keeps its checkout. Terraform has to run there, so "may or may not exist on the host" is
  true for daily work but not for `infra/`.
- Nothing on the current VM's `~/loady-vm` is wanted. Step 4 checks before removing.

## Risks

- **Two checkouts, one repository, no automatic sync.** They will diverge and a pull will conflict
  eventually. Accepted: it is ordinary Git, and the alternative is the copy-overwrite this plan
  exists to remove. Mitigation is habit — push from the VM, pull on the Mac before editing.
- **A converge no longer carries Mac-side work.** An edit made on the Mac and not pushed is
  invisible to the VM, which will read as "the converge did nothing" until it is understood. Step 7
  is what prevents that, which is why it is not optional.
- **Shared credentials across two VMs.** The key and the PAT now serve both the kirilloak dev VM
  and this one. A rotation is two register updates and two converges, and a compromise is two
  machines. Accepted deliberately: the alternative is a third key to manage, and both machines are
  the founder's own.
- **The PAT on disk.** It sits at `~/.config/loady/github-token`, 0600, on a VM whose disk is not
  encrypted at rest beyond Proxmox's storage. Same exposure the register's SSH keys already have.
- **Bootstrap ordering.** The firewall step reads `$VM_REPO/compose/processes.json` and the linking
  step reads `$VM_REPO/scripts`; both must stay after the clone, and both must tolerate its absence.

## Open questions

None. The founder chose the kirilloak credentials, key and PAT, and the personal GitHub identity.
