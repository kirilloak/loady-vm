# Result: Populate first/last name from the SSO token

Plan: `plans/2026_09_15_sso_name_from_token_claims.md`
Status: DONE (backend code, steps 1-4 and 7; Terraform, step 5, edited in `~/loady-vm` but left uncommitted for the
founder to review and apply - see "Manual actions"). Step 6 (manual B2C portal config, per environment/customer,
outside any repo) is not applied anywhere - full instructions are inlined below in "Loady B2C configuration".

## Files changed

- `src/Shared/Loady.Azure.Functions/Extensions/ClaimsIdentityExtensions.cs` - `GetGivenName()`/`GetSurname()`,
  dual-checking the raw and WS-*-mapped claim names, same shape as `GetPolicy`/`GetIdentityProvider`.
- `src/Shared/Loady.Azure.Functions/Extensions/FunctionContextExtensions.cs` - `SetSsoNameClaims`/
  `TryGetSsoNameClaims` on `FunctionContext.Items`. Stores empty string instead of null (avoids a nullable
  warning against the non-nullable-annotated `IDictionary<object, object>`); `TryGetSsoNameClaims` already treats
  blank as absent, so behavior is unchanged.
- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs` - stashes the two
  claims via `SetSsoNameClaims` right before `return user;` in `GetUserFromValidationResultAsync`, only when
  `ssoDomain is not null`.
- `src/Shared/Loady.Common/Interfaces/ICurrentUserAccessor.cs` - added `TryGetSsoNameClaims(out givenName, out surname)`.
- `src/Shared/Loady.Azure.Functions/Services/CurrentUserAccessor.cs` - implements it by delegating to the
  `FunctionContext` extension.
- `src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs` - the backfill
  block, next to the existing `AcceptInvitationAsync` one-time-write pattern. Injects
  `IValidator<UpdateUserProfileDto>` and validates explicitly before calling `UserService.UpdateUserProfileAsync`
  (see "Notes" - that service method does not validate internally).
- Four other `ICurrentUserAccessor` implementations updated to satisfy the widened interface (none of these run
  through SSO, all return `false`/no claims):
  - `src/Domains/Loady.Imports.Api/Services/CurrentUserAccessorForImports.cs`
  - `src/Seeder/Loady.TranslationsCleaner/CurrentUserAccessor.cs`
  - `src/Seeder/Loady.TestDataSeeder/Stubs/CurrentUserAccessorStub.cs`
  - `src/Seeder/Loady.Seeder/CurrentUserAccessorForSystemOperation.cs`
- Tests:
  - `src/Shared/Loady.Azure.Functions.UnitTests/Tests/Extensions/ClaimsIdentityExtensionsTests.cs` - claim-mapping
    theory extended with `given_name`/`family_name`, plus `GetGivenName`/`GetSurname` read/missing cases.
  - `src/Shared/Loady.Azure.Functions.UnitTests/Tests/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicyTests.cs` -
    SSO login with name claims stashes them; local-flow login does not stash them.
  - `src/Shared/Loady.Services.IntegrationTests/Domains/Users/GetCurrentUserProfileQueryHandlerTests.cs` - nameless
    SSO user with claims gets backfilled (response and Cosmos both checked); nameless user without claims stays
    nameless; a user who already has a name ignores the claims (no overwrite).
- `plans/done/sso-docs.md` (actual location of the doc named in the plan as `backend/plans/sso-docs.md`) - documented
  the optional Given Name/Surname application claims and identity-provider claims mapping, and the auto-fill
  behavior under "Good to know".
- `~/loady-vm/integrations/sso-idp-tomorrowops/variables.tf` - `test_users` object type gained two optional fields,
  `given_name` and `surname` (`optional(string)`, so existing untracked tfvars entries that don't set them still
  apply cleanly).
- `~/loady-vm/integrations/sso-idp-tomorrowops/main.tf` - `azuread_user.test` now passes `given_name`/`surname`
  through from `var.test_users[each.key]`. `outputs.tf` needed no change - its `claims_mapping` output already
  advertised `given_name`/`surname` before this task. Edited in place, left uncommitted (private repo, separate
  apply/commit flow - the founder reapplies manually).

## Manual actions for the founder

- Review and commit the `~/loady-vm/integrations/sso-idp-tomorrowops` Terraform edits (`variables.tf`, `main.tf`),
  then add `given_name`/`surname` values for the test users in the untracked tfvars file, then `terraform apply`.
  Not verified from this session: whether `given_name`/`surname` are valid arguments on the `azuread_user` resource
  at the pinned provider version (`hashicorp/azuread ~> 3.9`, locked to `3.9.0` in `.terraform.lock.hcl`) - these
  are standard Microsoft Graph user properties and the provider almost certainly supports them, but no `terraform
  plan`/`validate` ran here (no `terraform` binary and no Azure credentials in this session).
- Configure Loady B2C per "Loady B2C configuration" below, for every environment/customer this ships to.
- Whether other SSO customers besides BASF/tomorrowops are live and would need the same two B2C settings is still
  open per the plan's own "Assumptions" section - not verifiable from this repo; check with Nelia/Heinz which
  environments already have `IsSsoEnabled = true` companies.

## Loady B2C configuration (manual, per environment/customer - self-contained, no other doc needed)

This feature needs two settings turned on in the Azure AD B2C portal. Until both are set for a given
environment/customer, behavior is unchanged - the code path in `GetCurrentUserProfileQueryHandler` just never finds
the claims and does nothing.

### 1. User flow application claims (once per environment - shared by every identity provider using that flow)

Azure AD B2C portal → User flows → `B2C_1_sso_sign_up_sign_in` → **Application claims**

- Check **Given Name** and **Surname**, in addition to the existing **Email Addresses** and **Identity Provider**.
- This is a pass-through gate, not a mapping: it just allows `given_name`/`family_name` to appear in the issued
  token when the active identity provider supplied them. It does not know or care what the identity provider's own
  claim was originally called.
- Leaving this unchecked means the claims never reach the token even if the identity provider mapping below is set
  correctly - both steps are required.

### 2. Identity provider claims mapping (once per customer, i.e. once per identity provider entry)

Azure AD B2C portal → Identity Providers → the specific customer's OIDC provider entry (e.g. `basf-idp`,
`tomorrowops-idp`) → edit → **Claims mapping**

- Add two entries alongside the existing ones: **Given Name → `given_name`**, **Surname → `family_name`**.
- The left side (Given Name, Surname) is B2C's fixed target claim name - always the same regardless of customer.
  The right side is whatever the *source* field is called in that specific identity provider's own token; B2C
  reads it from there and republishes it under the fixed name. This is the layer that absorbs differences between
  customers' IdPs (one company's IdP might call it `given_name`, another might use `firstName` or something
  nonstandard) - no code change is ever needed for a naming difference, only this mapping.
- For BASF specifically: their tenant's default token already includes `family_name`/`given_name` under those
  exact names (confirmed by Dennis), so the mapping is `given_name → given_name`, `family_name → family_name` -
  only this B2C-side step is needed, no change on BASF's own app registration.
- For the `tomorrowops` test identity provider (Terraform-managed, see "Files changed" above): the Terraform
  root's `claims_mapping` output already documents this exact mapping
  (`given_name → given_name`, `surname → family_name`) - copy those two rows into the portal's claims mapping UI
  for that provider. The Terraform-managed test users won't have anything to map from until their `given_name`/
  `surname` fields are populated via the tfvars file and applied (see "Manual actions" above).

### 3. Verify end to end

- Sign in through the SSO flow, decode the issued id token on jwt.ms: confirm `given_name` and `family_name` are
  now present (in addition to the existing `emails`, `tfp`, `idp`).
- As an already-invited, nameless SSO user on that domain, call `GET members/profiles/my` (or just load the
  frontend): the response should already have non-empty `FirstName`/`LastName`, and the "Update user" modal should
  not appear.
- If a customer's IdP token carries the name claims but under different types than a standard OIDC token (rare),
  double check the mapping's source-claim spelling against a decoded raw token from that specific provider, not
  assumptions from another customer's setup.

## Notes

- Confirmed `UserService.UpdateUserProfileAsync` does **not** validate internally: `UserProfile.cs`'s
  `UserUpdateProfileAsync` endpoint calls `validator.ThrowIfInvalidAsync(payload)` before calling the service, and
  the service itself has no validator call. The query handler therefore injects
  `IValidator<UpdateUserProfileDto>` and validates explicitly, skipping the update (not throwing) when invalid -
  simpler than the plan's original try/catch sketch, since there is nothing for that catch to ever catch on this
  path (confirmed: the plan's own "Assumptions" section flagged this as unverified before implementation).
- `NSubstitute` 2.0.3 is the version actually resolved in this repo (via `AutoFixture.AutoNSubstitute`) and does not
  support the `out Arg.Any<T>()` shorthand for setting up an out-parameter method here; the new integration tests use
  plain local `out` variables instead.

## Verification

- `dotnet build Loady.slnx` - succeeded, 0 warnings, 0 errors.
- `dotnet test src/Shared/Loady.Azure.Functions.UnitTests/Loady.Azure.Functions.UnitTests.csproj` - 101/101 passed.
- `dotnet test src/Shared/Loady.Services.IntegrationTests/Loady.Services.IntegrationTests.csproj --filter "FullyQualifiedName~Domains.Users"` -
  21/21 passed (against the local SQL Server/Cosmos emulator/Azurite on this VM), including the 3 new tests.
- Not run: `Loady.Services.UnitTests`, `Loady.Common.UnitTests`, and the rest of `Loady.Services.IntegrationTests`
  outside the Users domain - out of blast radius for this change (only `ICurrentUserAccessor` implementations and
  one query handler touched), but not exercised in this session.
