# Terraform state in Azure Blob Storage

## Goal

Move the state of both local Terraform roots, `infra/` and `integrations/sso-idp-tomorrowops/`, off
the Mac's disk into one Azure Storage account in the founder's own `loady-vm` subscription, so
that state holding clear-text secrets is encrypted at rest, versioned, recoverable and locked
against concurrent applies.

## Success criteria

- `terraform plan` in each root reports no changes against the remote state.
- Both backends authenticate with the signed-in Azure identity; the storage account has shared key
  access disabled, so no access key or SAS exists to leak.
- No `terraform.tfstate` remains in either working tree.
- Blob versioning and soft delete are on, so a destroyed or corrupted state is recoverable.
- `infra/versions.tf`, `infra/README.md` and `docs/manual-secrets.md` agree with the new reality,
  each owning its own fact.

## Blockers

None. `az` is signed in to the `loady-vm` subscription
(`d17722fc-3eb6-42ac-a074-5a43602cf703`), which the founder created for this purpose, in the
`tomorrowops.com` tenant (`385bd049-aaa0-4d85-9bd8-d777e354c0a7`) — the same tenant the SSO root
already targets. `Microsoft.Storage` is `NotRegistered` on the new subscription and is registered as
step 1.

## Approach

**A dedicated `loady-vm` subscription.** The founder created one rather than sharing
`loady-private`. It is a cleaner billing and RBAC boundary than a resource group: this setup's spend
is visible on its own, and a blast radius that stops at the subscription costs nothing here. One
resource group inside it, `rg-loady-tfstate`, holds everything this plan creates.

**One storage account, two containers.** The two roots are unrelated: `infra` manages a Proxmox VM,
`sso-idp-tomorrowops` manages an Entra application. A container each (`infra`,
`sso-idp-tomorrowops`) keeps them independently deletable and independently grantable, at no cost
over a shared one. Both use the key `terraform.tfstate`.

**Entra auth, no shared keys.** Both state files hold secrets in clear: the Proxmox `root@pam`
password in `infra`, the OIDC client secret and any test-user passwords in the SSO root. The
account is created with `--allow-shared-key-access false`, so the only way in is an Entra identity
holding **Storage Blob Data Owner**; there is no account key to end up in a shell history, an
environment variable or a `.terraform` directory. The backends set `use_azuread_auth = true` and
inherit the `az` login.

**Literal backend blocks.** A `backend` block cannot take variables. Tenant id, subscription id,
resource group, account and container are all non-secret identifiers, so they are written as
literals and tracked.

Tradeoff accepted: the comment now in `infra/versions.tf` argued against a remote backend on the
grounds of new spend or a borrowed bucket. Neither holds once the founder owns a subscription — LRS
blob storage for two files under 16 KB costs cents a year, and locking plus versioning is worth more
than that on a state file that is the only record of the VM.

## Steps

1. **Register the storage resource provider.**
   What: `az provider register -n Microsoft.Storage --wait`.
   Why: the subscription is empty and has never created storage; every later step fails without it.
   Depends on: nothing.
   Verify: `az provider show -n Microsoft.Storage --query registrationState` is `Registered`.

2. **Create the resource group.**
   What: `rg-loady-tfstate` in `westeurope`.
   Why: a single management and deletion boundary for everything this plan creates.
   Depends on: 1.
   Verify: `az group show -n rg-loady-tfstate`.

3. **Create the storage account.**
   What: `stloadytfstate<suffix>`, StorageV2, Standard_LRS, HTTPS only, TLS 1.2 minimum, public blob
   access off, shared key access off. The suffix makes the globally unique name.
   Why: the state store itself, locked down so that Entra identity is the only way in.
   Depends on: 2.
   Verify: `az storage account show` reports `allowSharedKeyAccess: false` and
   `allowBlobPublicAccess: false`.

4. **Grant the founder Storage Blob Data Owner on the account.**
   What: role assignment at the account scope for the signed-in object id.
   Why: with shared keys disabled, Owner on the subscription grants no data-plane access; without
   this, every blob call is 403.
   Depends on: 3.
   Verify: `az storage container list --auth-mode login` succeeds.

5. **Turn on blob versioning, blob soft delete and container soft delete.**
   What: 30 day retention on both, versioning enabled.
   Why: the point of moving state off a disposable Mac is recoverability; a bad apply or a wrong
   `terraform state rm` must be undoable.
   Depends on: 3.
   Verify: `az storage account blob-service-properties show` reports all three.

6. **Create the two containers.**
   What: `infra` and `sso-idp-tomorrowops`, private, created with `--auth-mode login`.
   Why: one per root.
   Depends on: 4, 5.
   Verify: `az storage container list --auth-mode login` lists both.

7. **Remove the stale local lock in `infra/`.**
   What: delete `infra/.terraform.tfstate.lock.info`.
   Why: it records an `OperationTypeApply` from 2026-09-14 that never released; no `terraform`
   process is running, so it is an artifact of an interrupted run and it blocks the migration.
   Depends on: nothing.
   Verify: no `terraform` in `ps`, and `terraform init -migrate-state` acquires its own lock.

8. **Add the `azurerm` backend to `infra/versions.tf` and migrate.**
   What: backend block with `use_azuread_auth = true`, then `terraform init -migrate-state`.
   Why: the move itself.
   Depends on: 6, 7.
   Verify: `terraform state list` returns the same two resources from the remote backend, and
   `terraform plan` reports no changes.

9. **Add the `azurerm` backend to `integrations/sso-idp-tomorrowops/providers.tf` and migrate.**
   What: the same, pointing at the `sso-idp-tomorrowops` container.
   Why: the move itself.
   Depends on: 6.
   Verify: `terraform state list` matches the previous local state, and `terraform plan` reports no
   changes.

10. **Retire the local state files.**
    What: move both roots' `terraform.tfstate` and `terraform.tfstate.backup` to a dated folder
    outside the repository rather than deleting them.
    Why: they hold live secrets and the migration is verified, but a one-command undo costs nothing
    until the founder is satisfied.
    Depends on: 8, 9 verified.
    Verify: neither working tree contains a `.tfstate`; `git status --short` shows only the intended
    edits.

11. **Correct the documentation.**
    What: replace the "no backend block" comment in `infra/versions.tf`, the state paragraph in
    `infra/README.md`, and "The Terraform state" section in `docs/manual-secrets.md`.
    Why: one fact, one file. Three places currently assert that state is local and disposable.
    Depends on: 8, 9.
    Verify: `grep -rn 'state is local'` finds nothing stale.

## Assumptions

- `westeurope` is the right region. Nothing in either root is region-bound — the Proxmox host is
  on-premises and Entra is global — so this is latency and residency preference only, and a storage
  account is cheap to recreate elsewhere.
- The founder's `az login` identity is the only one that needs data access. No CI, no service
  principal, no second person.
- Both roots keep running from the Mac. Rule 4 puts Terraform on the Mac because it talks to the
  Proxmox API; that does not change.

## Risks

- **Losing data-plane access locks out the state.** Shared key access is off by design, so an Entra
  sign-in is mandatory. Mitigated by the role assignment being on the founder's own user object and
  by `docs/manual-secrets.md` recording how to restore it.
- **A failed migration.** `terraform init -migrate-state` copies before it switches. The local files
  are kept (step 10) until both plans are clean, so the rollback is deleting the backend block.
- **Soft delete is not a backup.** 30 days of versions protect against mistakes, not against losing
  the subscription. The existing recovery path — reimport or rebuild — stays documented.

## Open questions

None requiring the founder before implementation. Two choices are stated as assumptions above
(region, single subscription) and both are cheap to reverse.
