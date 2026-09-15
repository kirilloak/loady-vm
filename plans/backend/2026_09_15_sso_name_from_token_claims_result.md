# Result: Populate first/last name from the SSO token

Plan: `plans/2026_09_15_sso_name_from_token_claims.md`
Status: DONE (backend code, steps 1-4 and 7; Terraform, step 5, edited in `~/loady-vm` but left uncommitted for the
founder to review and apply - see "Manual actions"). Step 6 (manual B2C portal config, per environment/customer, outside
any repo) is not applied anywhere - full instructions are inlined below in "Loady B2C configuration".

## Files changed

- `src/Shared/Loady.Azure.Functions/Extensions/ClaimsIdentityExtensions.cs` - `GetGivenName()`/`GetSurname()`,
  dual-checking the raw and WS-*-mapped claim names, same shape as `GetPolicy`/`GetIdentityProvider`.
- `src/Shared/Loady.Azure.Functions/Extensions/FunctionContextExtensions.cs` - `SetSsoNameClaims`/
  `TryGetSsoNameClaims` on `FunctionContext.Items`. Stores empty string instead of null (avoids a nullable warning
  against the non-nullable-annotated `IDictionary<object, object>`); `TryGetSsoNameClaims` already treats blank as
  absent, so behavior is unchanged.
- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs` - stashes the two
  claims via `SetSsoNameClaims` right before `return user;` in `GetUserFromValidationResultAsync`, only when
  `ssoDomain is not null`.
- `src/Shared/Loady.Common/Interfaces/ICurrentUserAccessor.cs` - added
  `TryGetSsoNameClaims(out givenName, out surname)`.
- `src/Shared/Loady.Azure.Functions/Services/CurrentUserAccessor.cs` - implements it by delegating to the
  `FunctionContext` extension.
- `src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs` - the backfill block,
  next to the existing `AcceptInvitationAsync` one-time-write pattern. Injects
  `IValidator<UpdateUserProfileDto>` and validates explicitly before calling `UserService.UpdateUserProfileAsync`
  (see "Notes" - that service method does not validate internally).
- Four other `ICurrentUserAccessor` implementations updated to satisfy the widened interface (none of these run through
  SSO, all return `false`/no claims):
    - `src/Domains/Loady.Imports.Api/Services/CurrentUserAccessorForImports.cs`
    - `src/Seeder/Loady.TranslationsCleaner/CurrentUserAccessor.cs`
    - `src/Seeder/Loady.TestDataSeeder/Stubs/CurrentUserAccessorStub.cs`
    - `src/Seeder/Loady.Seeder/CurrentUserAccessorForSystemOperation.cs`
- Tests:
    - `src/Shared/Loady.Azure.Functions.UnitTests/Tests/Extensions/ClaimsIdentityExtensionsTests.cs` - claim-mapping
      theory extended with `given_name`/`family_name`, plus `GetGivenName`/`GetSurname` read/missing cases.
    -
    `src/Shared/Loady.Azure.Functions.UnitTests/Tests/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicyTests.cs` -
    SSO login with name claims stashes them; local-flow login does not stash them.
    - `src/Shared/Loady.Services.IntegrationTests/Domains/Users/GetCurrentUserProfileQueryHandlerTests.cs` - nameless
      SSO user with claims gets backfilled (response and Cosmos both checked); nameless user without claims stays
      nameless; a user who already has a name ignores the claims (no overwrite).
- `plans/done/sso-docs.md` (actual location of the doc named in the plan as `backend/plans/sso-docs.md`) - documented
  the optional Given Name/Surname application claims and identity-provider claims mapping, and the auto-fill behavior
  under "Good to know".
- `~/loady-vm/integrations/sso-idp-tomorrowops/variables.tf` - `test_users` object type gained two optional fields,
  `given_name` and `surname` (`optional(string)`, so existing untracked tfvars entries that don't set them still apply
  cleanly).
- `~/loady-vm/integrations/sso-idp-tomorrowops/main.tf` - `azuread_user.test` now passes `given_name`/`surname`
  through from `var.test_users[each.key]`. `outputs.tf` needed no change - its `claims_mapping` output already
  advertised `given_name`/`surname` before this task. Edited in place, left uncommitted (private repo, separate
  apply/commit flow - the founder reapplies manually).

## Manual actions for the founder

- `terraform apply` of the `~/loady-vm/integrations/sso-idp-tomorrowops` edits ran on 2026-09-15: `Apply complete!
  Resources: 0 added, 0 changed, 0 destroyed.` This confirms `given_name`/`surname` are valid arguments on
  `azuread_user` at the pinned provider version (`hashicorp/azuread ~> 3.9`, locked to `3.9.0`) - the schema change
  applied cleanly, resolving the one open unknown from the plan. `0 changed` is expected at this point: the fields exist
  on the resource now but every existing test user still has them unset (`null`), same as before the change, so there's
  nothing yet for Terraform to diff.
- Still needed: add real `given_name`/`surname` values per test user to the untracked tfvars file, then
  `terraform apply` again - that run should show existing `azuread_user.test` entries changed in place (not added).
- Confirmed on 2026-09-15: B2C config alone (user flow application claims + `Kirill-SSO` identity provider claims
  mapping) does not produce `given_name`/`family_name` in the issued token while this tfvars step is outstanding -
  decoded token had `name: "Kirill SSO"` (from `display_name`, already set) but no `given_name`/`family_name` at
  all, because the underlying Entra test user has nothing set for those fields yet. B2C can only forward a claim
  the identity provider actually sends; it can't be tested end to end until the tfvars step above is done and a
  fresh token is issued (old tokens predate the user having these fields).
- Configure Loady B2C per "Loady B2C configuration" below, for every environment/customer this ships to.
- Whether other SSO customers besides BASF/tomorrowops are live and would need the same two B2C settings is still open
  per the plan's own "Assumptions" section - not verifiable from this repo; check with Nelia/Heinz which environments
  already have `IsSsoEnabled = true` companies.

## Loady B2C configuration (manual, per environment/customer - self-contained, no other doc needed)

This feature needs two settings turned on in the Azure AD B2C portal. Until both are set for a given
environment/customer, behavior is unchanged - the code path in `GetCurrentUserProfileQueryHandler` just never finds the
claims and does nothing.

### 1. User flow application claims (once per environment - shared by every identity provider using that flow)

1. Azure Portal → your B2C tenant → **User flows** (left nav, under "Policies")
2. Click **B2C_1_sso_sign_up_sign_in**
3. Left nav of that flow → **Application claims**
4. Tick **Given Name** and **Surname** (leave **Email Addresses** and **Identity Provider** checked too)
5. **Save**

This is a pass-through gate, not a mapping - it just allows `given_name`/`family_name` to appear in the issued token
when the active identity provider supplied them. It doesn't know or care what the identity provider's own claim was
called - that translation happens in step 2. Skipping this step means the claims never reach the token even if step 2 is
done correctly for every provider - both are required, and this one only needs doing once per environment (not once per
customer).

### 2. Identity provider claims mapping (once per customer, i.e. once per identity provider entry)

Portal path for any provider: **Identity providers** (left nav) → click the provider → **Identity provider claims
mapping** section. This is the full set of rows on that screen - the first three (User ID, Display name, Email)
are the pre-existing setup and stay as they are; **Given name** and **Surname** are the two this task adds/fixes. Same
values for every provider on this feature, since B2C's target claim names are fixed and both `tomorrowops` and BASF
happen to emit the source claims under their standard OIDC names already:

| B2C portal field | Value to enter       |
|------------------|----------------------|
| User ID          | `sub`                |
| Display name     | `name`               |
| Given name       | `given_name`         |
| Surname          | `family_name`        |
| Email            | `preferred_username` |

Applies to both providers:

- **Tomorrowops** (the `Kirill-SSO` entry, domain hint `tomorrowops`): **Given name** is already correct (`given_name`).
  **Surname** currently reads `Surnamefamily_name` - clear the field completely and retype just
  `family_name`. Then **Save**.
- **BASF** (`basf-idp` or however it's named): set **Given name** → `given_name`, **Surname** → `family_name`, same as
  above; leave User ID/Display name/Email as already configured. Then **Save**. BASF's tenant already sends these under
  exactly these names (confirmed by Dennis), so nothing else needs to change on BASF's side. 0 Do step 1 and step 2 in
  the same environment before testing a given provider - if only one is done, the claim still won't reach the token.

### 3. Verify end to end

- Sign in through the SSO flow, decode the issued id token on jwt.ms: confirm `given_name` and `family_name` are now
  present (in addition to the existing `emails`, `tfp`, `idp`).
- As an already-invited, nameless SSO user on that domain, call `GET members/profiles/my` (or just load the frontend):
  the response should already have non-empty `FirstName`/`LastName`, and the "Update user" modal should not appear.
- If a customer's IdP token carries the name claims but under different types than a standard OIDC token (rare), double
  check the mapping's source-claim spelling against a decoded raw token from that specific provider, not assumptions
  from another customer's setup.

## Notes

- Confirmed `UserService.UpdateUserProfileAsync` does **not** validate internally: `UserProfile.cs`'s
  `UserUpdateProfileAsync` endpoint calls `validator.ThrowIfInvalidAsync(payload)` before calling the service, and the
  service itself has no validator call. The query handler therefore injects
  `IValidator<UpdateUserProfileDto>` and validates explicitly, skipping the update (not throwing) when invalid - simpler
  than the plan's original try/catch sketch, since there is nothing for that catch to ever catch on this path
  (confirmed: the plan's own "Assumptions" section flagged this as unverified before implementation).
- `NSubstitute` 2.0.3 is the version actually resolved in this repo (via `AutoFixture.AutoNSubstitute`) and does not
  support the `out Arg.Any<T>()` shorthand for setting up an out-parameter method here; the new integration tests use
  plain local `out` variables instead.

## Verification

- `dotnet build Loady.slnx` - succeeded, 0 warnings, 0 errors.
- `dotnet test src/Shared/Loady.Azure.Functions.UnitTests/Loady.Azure.Functions.UnitTests.csproj` - 101/101 passed.
-
`dotnet test src/Shared/Loady.Services.IntegrationTests/Loady.Services.IntegrationTests.csproj --filter "FullyQualifiedName~Domains.Users"` -
21/21 passed (against the local SQL Server/Cosmos emulator/Azurite on this VM), including the 3 new tests.
- Not run: `Loady.Services.UnitTests`, `Loady.Common.UnitTests`, and the rest of `Loady.Services.IntegrationTests`
  outside the Users domain - out of blast radius for this change (only `ICurrentUserAccessor` implementations and one
  query handler touched), but not exercised in this session.
