# Loady Infrastructure

Terraform IaC for the **Loady** logistics platform on Azure. Manages all cloud resources across 4 environments via Azure Pipelines.

> **No tests.** Do not write, generate, or suggest Terraform tests (native `terraform test`, Terratest, or any other testing framework). Validation is handled by the pipeline (Trivy + `terraform validate` + plan).

## Environments

| Env  | Subscription | TF State Storage    | TF Workspace | Custom Domains           |
|------|--------------|---------------------|--------------|--------------------------|
| dev  | Development  | `loadydevsa`        | `dev`        | None (SWA defaults)      |
| qa   | Development  | `loadydevsa`        | `qa`         | `*-qa.loady.com`         |
| pg   | Playground   | `loadyplaygroundsa` | `pg`         | `*-playground.loady.com` |
| prod | Production   | `loadyprodsa`       | `prod`       | `*.loady.com`            |

- **Region**: West Europe (shortcode `euw`)
- **DNS zone**: `loady.com` in `rg-network-global` (prod subscription)
- **Terraform version**: 1.14.0 (pipeline-pinned; `required_version` in `providers.tf` is `>= 0.13` — see Gotchas)
- **Backend**: azurerm (`shared` RG, container `global-tf`, key `global.tfstate`)

## Providers

| Provider    | Version  | Purpose                             |
|-------------|----------|-------------------------------------|
| azurerm     | ~> 4.0   | Azure resources                     |
| azuredevops | = 0.8.0  | Service connections, var groups     |
| azuread     | 2.25.0   | App registrations, Graph roles      |
| azapi       | >= 1.8.0 | Used in cosmos-db and function-app-service modules (module-level only, not declared in root `providers.tf`) |

## Resource Naming Convention

```
{resource-type}-{purpose}-{region-short}-{env}
```

Examples: `func-loady-backend-euw-dev`, `rg-kv-euw-prod`, `sql-server-loady-euw-qa`

Storage accounts: `st{env}{region}{purpose}` (e.g., `stdeveuwassets`)

## Project Structure

```
.
├── main.tf                          # random_string, ADO project data, subscription data
├── providers.tf                     # azurerm, azuredevops, azuread providers + backend config
├── variables.tf                     # All input variables (env, SKUs, B2C, secrets, etc.)
├── locals.tf                        # Custom URLs for loady2go, loady2share, loady (per env)
├── roles.tf                         # Azure RBAC role definition IDs (constants map)
│
├── rg_api_functions_main.tf         # Largest file. Function Apps, app plans, queues, photo/import storage
├── rg_kv_main.tf                    # Two Key Vaults + all secrets + access policies
├── rg_monitorlogs_main.tf           # Log Analytics, App Insights, alert rules, action groups
├── rg_frontdoor_main.tf             # Azure Front Door (QA/PG/PROD only), DNS, WAF
├── rg_sql_database_main.tf          # SQL Server + loady-db, diagnostics
├── rg_cosmos_main.tf                # CosmosDB account
├── rg_abp_main.tf                   # Backoffice App Service (DEV only)
├── rg_apim_main.tf                  # API Management instance
├── rg_caching_main.tf               # Redis Cache
├── rg_search_main.tf                # Azure Cognitive Search
├── rg_website_main.tf               # Frontend SWA (signing-page)
├── rg_loady2share_main.tf           # Loady2Share SWA
├── rg_asset_storage.tf              # Asset storage + translations/images containers
├── rg_import_storage.tf             # Import storage + import containers
├── rg_templateb2c_main.tf           # B2C template storage
├── rg_synapse_main.tf               # Synapse workspace (DEV + PROD only)
├── rg_automation_account.tf         # Expiring secrets automation (DEV only)
├── az_ad_ado_main.tf                # ADO service principal, service connection, CosmosDB/KV perms
├── ado_var_grps.main.tf             # ADO variable group linked to Key Vault
│
├── _dev.tfvars / _qa.tfvars / _pg.tfvars / _prod.tfvars
│
├── modules/                         # Reusable modules (see below)
├── pipelines/                       # Azure Pipelines YAML
├── scripts/                         # PowerShell helper scripts
├── tests/                           # Terraform native test (valid_plan)
└── certificates/                    # Webhook client certificate (pfx)
```

## Modules

| Module                           | Purpose                                                                |
|----------------------------------|------------------------------------------------------------------------|
| `api-management`                 | APIM instance                                                          |
| `api-mapped-settings-function`   | Composite: RG + storage + function + CosmosDB RBAC + availability test |
| `app-insights-availability-test` | Standard availability test with alert                                  |
| `app-service-plan`               | App Service Plan (Windows)                                             |
| `app-service`                    | Windows App Service (used for Backoffice)                              |
| `automation-account`             | Azure Automation Account                                               |
| `azad-spn`                       | Azure AD app registration + SPN                                        |
| `cognitive-search`               | Azure Cognitive Search service                                         |
| `cosmos-db`                      | CosmosDB account with diagnostics                                      |
| `cosmosdb-role-assignment`       | CosmosDB data plane RBAC                                               |
| `cost-management-budget`         | Cost budget alerts                                                     |
| `dns-records`                    | DNS record management                                                  |
| `frontdoor`                      | CDN Front Door profile + origins + security policy                     |
| `frontdoor-firewall-policy`      | WAF policy for Front Door                                              |
| `frontdoor-origin`               | Single Front Door origin + endpoint + route + DNS                      |
| `function-app-service`           | Windows Function App + warmup deployment slot                          |
| `key-vault`                      | Key Vault with optional RBAC                                           |
| `rbac-role-assignment`           | Generic RBAC role assignment                                           |
| `redis_cache`                    | Redis Cache instance                                                   |
| `sa_blob`                        | Storage container (blob)                                               |
| `signalr`                        | SignalR service                                                        |
| `sql-instance`                   | SQL Server + database + firewall (`prevent_destroy`)                   |
| `static-site`                    | Static Web App + availability test                                     |
| `storage_accounts`               | Storage account with CORS + soft delete                                |
| `synapse-workspace`              | Synapse Analytics workspace                                            |

## Function Apps

All function apps use `dotnet-isolated` runtime (.NET 9), Windows OS, Functions v4.

### Private API (behind APIM, B2C private token)

- **api_group** (for_each `cosmos_entity_names`): `driverview`, `event`, `report` - full access to all services
- **backend** (`backend`): Main backend - B2C user mgmt, webhooks, certificates, data encryption
- **backoffice** (`backoffice`): APIM management, B2C user mgmt
- **loady2share** (`loady2share`): Sharing functionality
- **imports** (`imports`): File import processing with blob/queue storage

### Public API (B2C public token, separate app plan in prod)

- **public_lanes** (`plane`): Lanes public API
- **public_loadingpoints** (`ploading`): Loading points public API
- **public_unloadingpoints** (`punloading`): Unloading points public API
- **public_businesspartner** (`pbpartner`): Business partner public API
- **public_product** (`pproduct`): Product public API
- **public_api** (`public`): General public API

### Prod-specific

- Public APIs use dedicated `EP2` Elastic Premium plan (`plan-public-loady-euw-prod`)
- Private APIs use dedicated `EP1` Elastic Premium plan (`plan-private-loady-euw-prod`)
- Non-prod uses `Y1` consumption plan per function

### Security

- All function apps have IP restrictions: allow APIM IPs + health checks, deny all else
- System-assigned managed identity with RBAC to Key Vault, CosmosDB, Search, Storage, etc.
- Each function + its warmup slot get identical role assignments

## Key Vault Strategy

Two Key Vaults per environment:

1. **`kv-loady-azdo-euw-{env}`** (access policy-based): ADO secrets, deploy tokens, legacy secrets
2. **`kv-loady-euw-{env}`** (RBAC-based): Application secrets referenced via `@Microsoft.KeyVault()` URI syntax

Secrets are injected into function apps as Key Vault references (versionless).

## Monitoring & Alerting

- **Log Analytics workspace** + **Application Insights** per env
- **Action groups**: `notify` (Monitoring Reader role), `sendtoteams` (Logic App webhook, QA/PG/PROD)
- **Alert rules** (PROD only):
    - Rate limiting (>50% 429s)
    - Error rate (any 5xx)
    - Failing public APIs (0% success over 24h)
    - Availability (<99%)
    - Webhook poison queue new items
- **Service health alerts**: all environments
- **Availability tests**: all function apps + static sites (5 EMEA locations)

## Front Door (QA, PG, PROD only)

Standard SKU CDN Front Door with origins:

- `app` / `app-{env}` - Frontend SWA
- `api` / `api-{env}` - APIM gateway
- `auth` / `auth-{env}` - B2C authentication
- `loady2go` / `loady2go-{env}` - DriverView SWA
- `loady2share` / `loady2share-{env}` - Loady2Share SWA
- `developer` / `developer-{env}` - APIM developer portal
- `assets` / `assets-{env}` - Asset storage (30min cache)

WAF security policy applied to all origins. PROD uses customer-managed TLS certificate from Key Vault.

## Azure Pipelines

| Pipeline              | File                                      | Trigger | Purpose                                                           |
|-----------------------|-------------------------------------------|---------|-------------------------------------------------------------------|
| Validation            | `pipelines/validation.yml`                | Manual  | Trivy scan + `terraform validate` + plan (DEV workspace, no lock) |
| Environment Provision | `pipelines/env-provision.yml`             | Manual  | Plan → manual approval → apply (any env)                          |
| SQL Permissions       | `pipelines/functions_sql_permissions.yml` | Manual  | Assigns SQL permissions to function app identities                |

### Pipeline Flow (env-provision)

1. `terraform init` with env-specific backend storage account
2. `terraform workspace select -or-create=true {env}`
3. `terraform plan` with `-var-file _{env}.tfvars` + sensitive vars from ADO variable groups
4. **Manual approval** step
5. `terraform apply -auto-approve`

### ADO Variable Groups

- `unmanaged-secrets-{env}` - B2C secrets, SendGrid keys, ADO tokens
- `expiringsecrets-notifications` - Expiring secrets runbook credentials
- `translation-platform` - Translation service credentials
- `trimble-maps-{prod|nonprod}` - Trimble Maps API keys
- `maps-{prod|nonprod}` - Maps provider API keys
- `{env}-env-secrets` - KV-linked variable group (managed by Terraform)
- `azuredevops` - ADO access tokens (validation pipeline only)

## Conditional Resources

| Resource                    | Condition                            |
|-----------------------------|--------------------------------------|
| Front Door + WAF            | QA, PG, PROD                         |
| Teams action group          | QA, PG, PROD                         |
| Alert rules (query-based)   | PROD only                            |
| Dedicated app service plans | PROD only                            |
| Synapse workspace           | DEV, PROD                            |
| Automation account          | DEV only                             |
| Expiring secrets KV entries | DEV only                             |
| Backoffice App Service      | DEV only                             |
| Webhook client certificate  | Non-PROD (imported manually in PROD) |

## Important Patterns & Gotchas

- **Trivy scanning**: Validation pipeline runs Trivy v0.49.1 for misconfig scanning (CRITICAL/HIGH). `.trivyignore.yml` suppresses Key Vault network ACL (AVD-AZU-0013) and asset storage public access (AVD-AZU-0007).
- **Storage container lifecycle**: `default_encryption_scope` and `encryption_scope_override_enabled` are in `ignore_changes` due to azurerm provider breaking changes.
- **Import containers**: Several were created manually and need to be imported or recreated in Terraform (see comments in `rg_import_storage.tf`).
- **Backoffice App Service Plan**: Cannot be moved due to webspace hosting constraints (see comment in `rg_abp_main.tf`).
- **Function slot `service_plan_id`**: Ignored in lifecycle due to azurerm provider bug - set separately via AzureRM deployment resource.
- **App Insights tags**: `hidden-link:*` tags are in `ignore_changes` due to provider issue #16569.
- **Private API elastic workers**: Limited to 1 instance pending LOADY-12620 resolution.
- **Certificate renewal**: Webhook client certificates are renewed manually in Azure portal. The checked-in PFX is expired. See Confluence: `How-to renew certificates`.
- **Loose `required_version`**: `providers.tf` has `required_version = ">= 0.13"` while pipelines pin 1.14.0. A contributor on a different TF version locally could produce divergent plans. Consider tightening to `~> 1.14`.
- **`.terraform.lock.hcl` is gitignored**: Provider versions can drift between machines. HashiCorp recommends committing the lock file. This is a conscious trade-off — be aware that `terraform init` may resolve different provider versions locally vs. pipeline.
- **`azapi` provider unpinned at root**: The `azapi` provider is only declared in child modules with no version constraint in the root. A `terraform init` could pull a breaking version.

## Authentication

- **Azure AD B2C** for user authentication
    - Separate B2C tenants per environment
    - Three token flows: `sign_in_flow` (private), `sign_in_publicapi_flow` (public), `sign_in_backoffice_flow` (backoffice)
- **Service principal** per env (`{env}-ado-spn-terraform`) with Contributor role + Workload Identity Federation
- **SQL Server**: Entra ID admin (`Backend-Developers` group on DEV, `Cloud Admins` on PROD)

## Working with This Repo

### Adding a new Function App

1. Add a new `module` block in `rg_api_functions_main.tf` using `api-mapped-settings-function`
2. Specify `entity_name` (used for naming), app settings, and required role assignments
3. Run pipeline to provision; then run SQL permissions pipeline if the function needs DB access

### Adding a new Key Vault secret

1. Add `azurerm_key_vault_secret` resource in `rg_kv_main.tf`
2. Reference it in function app settings via `@Microsoft.KeyVault(SecretUri=${...versionless_id})`
3. If the value comes from a pipeline variable, add a new `variable` in `variables.tf` and pass it via `-var` in pipeline YAML

### Adding a new import container

1. Add the container name to the `for_each` set in `rg_import_storage.tf`

### Adding a new Front Door origin

1. Add a new `module` block in `modules/frontdoor/frontdoor.tf` using `frontdoor-origin`
2. Add the domain to the security policy association block

### Adding a new alert rule

1. Add `azurerm_monitor_scheduled_query_rules_alert_v2` in `rg_monitorlogs_main.tf`
2. Condition on `var.env == "prod"` (alert rules are PROD only)
3. Associate with the appropriate action group (`notify` or `sendtoteams`)

### Changing provider versions

- Provider versions are pinned in `providers.tf`. The lock file `.terraform.lock.hcl` is gitignored.

### Local development

- Use `_local.tfvars` (gitignored) for local overrides
- Bootstrap: `pwsh ./bootstrap.ps1`
