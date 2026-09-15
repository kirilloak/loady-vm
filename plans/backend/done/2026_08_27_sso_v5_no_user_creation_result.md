# Result: SSO v5, no user creation

- **Plan:** `plans/2026_08_27_sso_v5_no_user_creation.md`
- **Status:** complete. Step 9 had no target, `docs/sso.md` does not exist on this branch any more.

## Files

- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs`: login path is read-only; removed `CreateSsoUserAsync`, `EnsureNameFromTokenAsync`, `GetNameFromToken`, `WithProvisioningAuthorAsync`, the SSO author and actor, and the `IUserService`, `IDistributedLockService`, `IFunctionContextAccessor` dependencies; an unknown user is always rejected via `LogAndTrackMissingUser` plus the not-provisioned marker.
- `src/Shared/Loady.Azure.Functions/Extensions/FunctionContextExtensions.cs`: `ClearUser` removed, the policy was its only caller.
- `src/Shared/Loady.Azure.Functions/Extensions/ClaimsIdentityExtensions.cs`: `GetGivenName`, `GetSurname` and their claim constants removed, only the name sync used them.
- `src/Shared/Loady.Common/Consts/RedisKeys.cs`: `LockForSsoUserProvisioning` removed.
- `src/Shared/Loady.Common/Consts/UserOperationTelemetryConsts.cs`: `Operations.SsoUserProvision` and `AuthenticationReasons.ProvisioningFailed` removed, nothing tracks them now.
- `src/Shared/Loady.Services/Domains/Shared/Services/GetUserService.cs`: `GetUserDataByMailAsync` back to `FirstOrDefault` on both lookups, matching dev exactly.
- `src/Shared/Loady.Services.IntegrationTests/Other/GetUserService/GetUserDtoTests.cs`: duplicate-mail-throws test removed with the hardening it covered, file matches dev exactly.
- `src/Shared/Loady.Azure.Functions.UnitTests/Tests/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicyTests.cs`: creation, membership, name-sync and write-author cases replaced by the read-only contract, plus a case that an invalid token leaves the marker unset; harness lost the write-related knobs and gained `tokenIsValid`.
- `frontend/src/app/app.component.vue`: `load()` swallows the app-init rejection, since the HTTP error interceptors already handle and route request failures.
- `frontend/src/assets/i18n/en.yml`: `login.no-access-*` reworded into the welcome message.

Follow-up review pass (leftovers found by re-reviewing the branch against dev):

- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs`: `RunAsync`'s XML doc had been orphaned onto `NotProvisionedItemKey` when the const was inserted on the branch; both are documented correctly again.
- `src/Shared/Loady.Azure.Functions.UnitTests/Tests/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicyTests.cs`: comment no longer claims provisioning is tracked.
- `src/Shared/Loady.Services.IntegrationTests/Other/CompanyMembersService/InviteSsoMemberToCompanyTests.cs`: second test renamed to `InviteMemberToCompany_UserAlreadyExistsInLoady_IsReusedAndKeepsItsIdentity`, since a login no longer creates the user it described.
- `frontend/src/app/auth/utils/auth.utils.ts`, `frontend/src/router.ts`, `frontend/src/app/core/services/api-error-interceptor.service.ts`, `frontend/src/app/auth/components/login.component.vue`, `frontend/src/assets/i18n/en.yml`: the "no access" vocabulary renamed to "welcome" (`isWelcomeReason`, `redirectToWelcome`, `isWelcome`, `login.welcome-*`, and the query value `reason=welcome`).

Reverted to dev (step 1): `UserProfile.cs`, `GetCurrentUserProfileQueryHandler.cs`, `CurrentUserProfileResponse.cs`, `GetCurrentUserProfileQueryHandlerTests.cs`.

## Notes

- `docs/sso.md` is neither in `origin/dev` nor in `HEAD`, so step 9 was skipped rather than recreating a file that was deliberately dropped.
- Step 4 needed no template or component change: the `hasNoAccess` card already renders logo, heading, sentence and sign-out outside the app shell, so only the copy moved.
- Kept `EmailHelper.GetDomain` although production code now only uses `TryGetDomain`: it is a general helper in `Loady.Common` with its own unit tests and two integration-test callers.
- Kept, per the plan's audit, with no production caller: `SqlCompany.SetSsoConfiguration` and `SqlCompanyBuilder.WithSsoConfiguration` (invariant holder for tests, configuration is raw SQL today).
- `ClaimsIdentityExtensionsTests` needed no edit; it only covers `idp`, `acr`, `tfp`, `emails`, `GetIdentityProvider` and `GetPolicy`, never the name claims.
- Behaviour kept from the branch and now the normal path: an unknown user, on any domain, gets 403 `A1145`, which the frontend turns into the welcome page. An expired or invalid token still gets 401 and goes to `/login`, verified by the new policy test.
- Consequence accepted in the plan: an invited SSO user types their own name on first login and their company member row reads "Waiting for user registration" until then.
- `apim/apis/backend/Backend.API.openapi.json` untouched and still accurate, no request or response contract changed.
- The welcome page URL is now `/login?reason=welcome`; the old `reason=no-access` value is not recognised, which only matters for a bookmarked link to a transient state.
- `login.title` and `login.welcome-title` are both "Welcome to Loady" on purpose: the two screens are never shown together, and the login heading was requested that way.
- Audited and confirmed still used: all three `ISsoConfigurationService` methods, every telemetry constant the branch adds, `EmailHelper.Normalize` / `Mask` / `TryGetDomain` in production and `GetDomain` in tests, `AnonymousAuthenticationPolicy`, `A1145` and its frontend code.

## Verification

- `dotnet build Loady.slnx`: pass, 0 warnings.
- `dotnet test src/Shared/Loady.Azure.Functions.UnitTests`: pass, 86/86.
- `dotnet test src/Shared/Loady.Common.UnitTests`: pass, 403/403.
- `dotnet test src/Shared/Loady.Services.UnitTests`: pass, 250/250.
- `dotnet test src/Shared/Loady.Services.IntegrationTests --filter "SsoConfigurationServiceTests|InviteSsoMemberToCompanyTests|CompanySsoConfigurationModelTests|GetUserDtoTests|CreateOrGetCurrentUserTests"`: pass, 41/41.
- `vue-cli-service lint` on all changed frontend files, including the renamed ones: pass.
- `dotnet test src/Shared/Loady.Services.IntegrationTests --filter "InviteSsoMemberToCompanyTests"` after the rename: pass, 2/2.
- Manual SSO round trip not run: needs a DEV B2C login.
