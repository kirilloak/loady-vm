# Result: Terraform state in Azure Blob Storage

Plan: [plans/2026_09_15_terraform_remote_state_azure.md](2026_09_15_terraform_remote_state_azure.md)

## Status

Complete. Both roots read and write state from Azure Blob Storage; no state file remains in either
working tree. One verification is left to the founder because it needs an interactive Bitwarden
unlock (below).

## Azure resources created

In subscription `loady-vm` (`d17722fc-3eb6-42ac-a074-5a43602cf703`), tenant `tomorrowops.com`
(`385bd049-aaa0-4d85-9bd8-d777e354c0a7`):

- `Microsoft.Storage` resource provider registered on the subscription.
- Resource group `rg-loady-tfstate` in `westeurope`, tagged `project=loady-vm`,
  `purpose=terraform-state`.
- Storage account `stloadytfstate`: StorageV2, Standard_LRS, Hot, HTTPS only, TLS 1.2 minimum,
  `allowBlobPublicAccess=false`, `allowSharedKeyAccess=false`.
- Role assignment **Storage Blob Data Owner** on the account for the signed-in user
  (`tomorrowops@outlook.com`, object id `86a9d822-04a2-47e4-bbc3-59b4962ec700`).
- Blob service: versioning on, blob soft delete 30 days, container soft delete 30 days.
- Containers `infra` and `sso-idp-tomorrowops`, both private.

## Created or edited

- `plans/2026_09_15_terraform_remote_state_azure.md` — created, the plan.
- `plans/2026_09_15_terraform_remote_state_azure_result.md` — created, this file.
- `infra/versions.tf` — added the `azurerm` backend block; replaced the comment that argued for
  local state.
- `integrations/sso-idp-tomorrowops/providers.tf` — added the `azurerm` backend block.
- `integrations/sso-idp-tomorrowops/variables.tf` — folded the untracked `local.auto.tfvars` values
  in as defaults (`tenant_id`, `application_display_name`, `b2c_callback_url`,
  `client_secret_end_date`, `domain_hint`), so the root is reproducible from a clean checkout.
  `test_users` keeps its empty default and stays out of tracked configuration because its values are
  passwords.
- `integrations/sso-idp-tomorrowops/local.auto.tfvars` — deleted, now redundant. It was untracked
  (`*.tfvars` is gitignored there), so it does not appear in `git status`.
- `infra/README.md` — the state paragraph now points at the backend and `docs/manual-secrets.md`.
- `docs/manual-secrets.md` — "The Terraform state" rewritten: where state lives, why there is no
  account key, the `az login` a Terraform command now needs, how to restore the role assignment, and
  what soft delete does and does not cover.
- `infra/.terraform.tfstate.lock.info` — deleted, a stale `OperationTypeApply` lock from
  2026-09-14 with no `terraform` process behind it. It blocked the migration.
- `infra/terraform.tfstate{,.backup}` and `integrations/sso-idp-tomorrowops/terraform.tfstate{,.backup}`
  — moved, not deleted, to `~/.local/state/loady-vm/tfstate-migrated-2026-09-15/`, mode `go-rwx`.

## Manual actions for the founder

1. **Run the `infra` plan.** It could not be verified here: `terraform plan` in `infra` needs
   `TF_VAR_*` values that come from Bitwarden through `ld-tfin`, which needs an interactive unlock.
   Expect no changes:

   ```bash
   cd infra && ld-tfin && terraform plan
   ```

2. **Delete the migrated local state** once that plan is clean and you are satisfied:
   `rm -rf ~/.local/state/loady-vm/tfstate-migrated-2026-09-15`. It holds the Proxmox password and
   the OIDC client secret in clear.

3. **Review and commit.** Under `AGENTS.md` rule 2 nothing here commits. Suggested message:

   ```
   Move Terraform state to Azure Blob Storage

   Both roots now keep state in the loady-vm subscription rather than on the
   Mac's disk: storage account stloadytfstate, one container per root, Entra
   auth only with shared key access disabled, blob versioning and 30 day soft
   delete. Fold the sso-idp-tomorrowops tfvars into variables.tf so that root
   is reproducible from a clean checkout.
   ```

## Notes

- The founder created a dedicated `loady-vm` subscription during implementation. The plan had
  recommended a resource group in `loady-private` instead; the plan's approach section was updated
  to match the decision before the resources were created.
- Shared key access is disabled, so `az storage` commands against this account need `--auth-mode
  login`, and `terraform` needs a current `az login` in this tenant.
- `terraform init -migrate-state` deleted and rewrote both `.terraform.lock.hcl` files
  byte-identically, which briefly left them staged as deletions in Git. The index was restored;
  `git status` shows them unchanged.
- Backend blocks cannot take variables, so tenant, subscription, resource group, account and
  container are literals. All are non-secret identifiers.

## Verification

- `az storage account show -n stloadytfstate`: `allowSharedKeyAccess=false`,
  `allowBlobPublicAccess=false`, `minimumTlsVersion=TLS1_2`, `enableHttpsTrafficOnly=true`,
  `provisioningState=Succeeded`. **Pass.**
- `az storage account blob-service-properties show`: versioning enabled, blob and container soft
  delete both 30 days. **Pass.**
- `az storage container list --auth-mode login`: `infra`, `sso-idp-tomorrowops`. **Pass** — which
  also proves the role assignment, since there is no account key.
- `terraform init -migrate-state` in both roots: successful. **Pass.**
- State compared after migration, remote blob against the pre-migration local backup:
  `infra` lineage `d1419a9c-…` on both, serial 58 to 59, 2 resources on both;
  `sso-idp-tomorrowops` lineage `49a0303d-…` on both, serial 6 to 7, 3 resources on both. Same
  lineage and contents, serial bumped by the migration. **Pass.**
- `terraform state list` from the remote backend: `infra` returns
  `proxmox_download_file.ubuntu_cloud_image` and `proxmox_virtual_environment_vm.loady_vm`;
  `sso-idp-tomorrowops` returns `azuread_application.oidc`, `azuread_application_password.oidc`,
  `azuread_service_principal.oidc`. **Pass.**
- `terraform plan` in `integrations/sso-idp-tomorrowops`, after the `variables.tf` change:
  "No changes. Your infrastructure matches the configuration." Blob state lock acquired and
  released. **Pass.**
- `terraform validate` in both roots: valid. `terraform fmt -check -recursive infra integrations`:
  clean. **Pass.**
- `find . -name '*.tfstate*'` outside `.terraform/`: nothing. **Pass.**
- `git status --short`: five modified files and the two new plan files, nothing else. **Pass.**
- `terraform plan` in `infra`: **not run**, see manual action 1.
