# Take GitHub out of the setup, and the loady-vm repository off the VM

## Goal

The VM reaches exactly one git service, Azure DevOps over SSH, and holds exactly one checkout,
`~/loady-one`. This repository lives only on the Mac; the VM receives the files it needs from it.

## Success criteria

- `infra/bootstrap.sh` contains no `github.com` and no `api.github.com`.
- The VM has `~/loady-vm` as plain files with no `.git`, and `~/loady-one` as the only checkout.
- `ld-start`, `ld-status`, `ld-fe` and the other `ld-*` commands still work on the VM, which means
  `scripts/`, `compose/` and `dotfiles/` are present there.
- One git identity everywhere: `kirill.starodubtsev@loady.com`.
- A full bootstrap ends with status 0.

## Blockers

None. The Loady RSA key is registered on Azure DevOps and authenticates from the VM (verified
2026-09-14); it is **not** registered on GitHub, which is what made the old `loady-vm` clone fail
and is no longer needed.

## Approach

The VM needs six things out of this repository: `scripts/` for the `ld-*` functions its login shell
sources, `compose/` for the stack and the function-host ports the firewall opens, `dotfiles/` for
the agent and Rider configuration, `scripts/link-agent-files.sh` for the symlinks into the
`loady-one` checkout, `scripts/cosmos-cert.sh`, and `agents/` behind those symlinks. All of it is
read on the VM and edited on the Mac.

So the Mac sends the working tree and the VM stops cloning it. `infra/send-tree.sh` owns the
transfer — one rsync, `.git` and Terraform state excluded — and both callers use it, `setup.sh`
before the bootstrap and the Terraform post step through a `local-exec`. The alternative, a second
Azure DevOps repository, was rejected: it puts this setup in the team's org, which is what rule 1
exists to prevent.

The cost is that `~/loady-vm` on the VM becomes a copy rather than a checkout: an edit made there
is lost at the next converge, and there is nowhere to commit it. That is the point of the change —
the setup is edited on the Mac — and it needs saying in `AGENTS.md`, because rule 5 currently
promises that nothing on the VM is thrown away.

## Steps

1. **`infra/send-tree.sh`** — rsync this repository to `~/loady-vm` on the VM, excluding `.git`,
   `infra/.terraform*`, `infra/terraform.tfstate*` and `.DS_Store`. Why: one owner for the
   transfer, used by both callers. Depends on nothing. Verify: `shellcheck`, then run it and
   compare `find` output on both sides.
2. **`infra/bootstrap.sh`** — drop `VM_REPO_URL` and the `clone_checkout` call for it; drop the
   GitHub host-key seeding; gate the `$VM_REPO` blocks on the directory rather than on `.git`.
   Why: the VM no longer clones or reaches GitHub. Depends on step 1 for the files to exist.
   Verify: `shellcheck`, `bash -n`, and no `github` left in the file.
3. **`infra/setup.sh` and `infra/main.tf`** — call `send-tree.sh` before the bootstrap runs. Why:
   the bootstrap reads those files. Depends on step 1. Verify: `terraform validate`, `shellcheck`,
   and a converge run that finds `compose/processes.json` on the VM.
4. **Documentation** — rule 3 and rule 5 in `AGENTS.md`, `infra/README.md`, `docs/manual-secrets.md`
   and `infra/variables.tf`'s description lose the GitHub claims and gain the copy-not-checkout
   fact. Why: one fact, one file, and the current text is now wrong about the key. Verify: read.
5. **Full bootstrap** — `ld-tfin && ld-vm-setup`, to status 0. Verify: the run's own exit status,
   then `ld-vm ld-status` and `dotnet --version` on the VM.

## Assumptions

- `~/loady-vm` on the VM holds nothing the founder wants to keep. True today: it was never cloned
  on the current machine, because that clone is what has been failing.
- rsync is present on both sides. Ubuntu's `rsync` is in the archive; the Mac ships with it.

## Risks

- An agent working on the VM that edits `~/loady-vm` loses the edit at the next converge. Mitigated
  only by documentation, which is why step 4 is not optional.
- `send-tree.sh` from the Terraform post step runs on the Mac, so it needs the Mac's key to reach
  the VM. The same key Terraform's own connection uses.

## Open questions

None outstanding. The founder decided: no GitHub anywhere, one email, apt instead of GitHub
releases, and no loady-vm repository on the VM.
