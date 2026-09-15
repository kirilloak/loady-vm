# SSO v5: no user creation, friendly 403 instead

## Goal

An SSO login by someone who has not been invited creates nothing in Loady and lands on a friendly "you are signed in
but not set up yet" page, with no toast, no broken shell and no unhandled rejection.

## What this means in practice

Without a Loady user, **no** private endpoint can answer: the authentication policy rejects the token before any
function runs, so `companies/search` and `members/profiles/my` both fail. "Let the app work with only a valid JWT"
therefore means: one rejected request, then a deliberate page that explains the situation and offers sign-out. It does
not mean rendering the application shell, which needs a profile that cannot exist yet.

Most of this already works: the policy marks the caller not-provisioned, the middleware answers 403 `A1145`, and the
frontend interceptor routes to `/login?reason=no-access` where `login.component.vue` renders the card. What is left is
removing every write from the login path, wording the card, and making sure nothing throws on the way.

Two rejections must stay distinguishable, and they already are:

| Situation                                  | Backend        | Frontend                        |
|--------------------------------------------|----------------|---------------------------------|
| Token missing, invalid or expired          | 401            | Redirect to `/login` to sign in |
| Token valid, no Loady user (or disabled)   | 403 `A1145`    | The welcome page                |

Most expiries never reach the backend: MSAL refreshes silently, and `getAuthToken()` routes to `/login` when it
cannot.

## Blockers

None. The migration was already regenerated without `SsoAutoProvision` (`20260827141726_AddSsoConfiguration`, commit
`969ee8863f`), so the model and snapshot agree and the integration suite runs again.

## Steps

### 1. Revert the uncommitted company-optional profile work

**What:** `git checkout` these four files, which are the only uncommitted changes:
`src/Domains/Loady.Backend.Api/Users/UserProfile.cs`,
`src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs`,
`src/Shared/Loady.Services/Domains/Private/Users/Responses/CurrentUserProfileResponse.cs`,
`src/Shared/Loady.Services.IntegrationTests/Domains/Users/GetCurrentUserProfileQueryHandlerTests.cs`.

**Why:** they exist to serve a user who has a Loady record but no company. With no record created, that caller is
rejected at authentication and never reaches the handler.

**Dependencies:** none, do this first so the diff starts clean.

### 2. Remove the user creation from the authentication policy

**What:** in `AuthenticateADB2CPrivateApiPolicy` delete `CreateSsoUserAsync` and the branch that calls it, so an
unknown email always goes through `LogAndTrackMissingUser` plus `MarkNotProvisioned` and gets the existing 403. With
the create gone, also remove `IDistributedLockService`, and `RedisKeys.LockForSsoUserProvisioning` from
`Loady.Common/Consts/RedisKeys.cs`.

`LogAndTrackMissingUser` currently states "not configured for SSO" in its message; widen it, since it now also logs
uninvited SSO users, which is the common case.

**Why:** the decision from the thread: an account is created by a Company Admin invitation, never by a login.

**Dependencies:** step 1.

### 3. Make the login path read-only

**What:** delete the name sync and everything that existed to support writing during authentication:

- `EnsureNameFromTokenAsync` and `GetNameFromToken` (with its claim-types diagnostic) in the policy.
- `WithProvisioningAuthorAsync`, the `SsoProvisioningAuthor` user and the `SsoProvisioningActor` constant.
- `FunctionContextExtensions.ClearUser` (the policy is its only caller; `SetUser` stays, the authentication
  middleware uses it).
- The `IFunctionContextAccessor` and `IUserService` constructor dependencies, which have no remaining use.

After this the policy only reads: validate the token, resolve the SSO domain, run the trust check, look the user up,
check the disabled flag.

**Why:** simplest possible path, as requested. Nothing is created or updated at login, so the author plumbing that
caused two bugs during testing disappears with it.

**Consequence to accept:** an invited SSO user still has no name in Loady until they type one, so they meet the
mandatory "Update user" modal on first login and their company member row reads "Waiting for user registration" until
then. That modal works without a company, since `members/updateUserProfile` takes the user from
`ICurrentUserAccessor` rather than the company header.

**Dependencies:** step 2.

### 4. The welcome page

**What:** keep `login.component.vue`'s `hasNoAccess` branch as the page, reduced to the minimum: logo, one heading,
one sentence, sign-out. Nothing else renders there today either, since `app.component` shows only the router view on
the login route and hides `ModalsContainer`.

Copy for the `login.no-access-*` keys, replacing the current invitation-flavoured text:

- Heading: "Welcome to Loady GmbH"
- Body: "You are signed in, but your account is not set up in Loady yet. A company administrator has to invite you
  before you can start working."
- Button: "Sign out"

Sign-out stays because it is the only way out of the page for someone who signed in with the wrong account; without it
a live identity-provider session puts them straight back here.

**Why:** it is the page Dennis asked for. It already renders outside the app shell, is already exempt from the
`/login` route guard, and already keeps the identity-provider session so sign-out works.

**Alternative considered:** a dedicated `/welcome` route. Rejected: it duplicates the guard exemption, the layout and
the sign-out handling that the card already has, for a cosmetically nicer URL.

**Dependencies:** none.

### 5. No unhandled rejection during app init

**What:** `app.component.mounted()` calls `load()`, which awaits `Promise.all` over the init services. The first
request (`companies/search`) rejects with the 403, so `load()` rejects and nothing catches it. Swallow it in `load()`:
every request-level failure is already handled by the HTTP error interceptors, and once the interceptor has navigated
to the card, finishing initialisation is pointless.

**Why:** the "no errors" half of the requirement. Today this is a console-level unhandled rejection, not a toast, but
it is exactly the kind of thing that turns into a visible error later.

**Dependencies:** none.

### 6. Audit the whole branch against dev and roll back what v5 does not need

**What:** `git diff origin/dev...HEAD` over the branch and justify every file against the final flow. Anything that
only existed to support auto-provisioning or JIT creation goes. Ignore `apim/apis/**` (generated, the developer
regenerates) and lockfiles.

Recommended rollbacks, each to be confirmed by grep for remaining callers:

- `ClaimsIdentityExtensions.GetGivenName` / `GetSurname` and their constants: only the name sync used them. Their
  cases in `ClaimsIdentityExtensionsTests` go with them; `GetPolicy` and `GetIdentityProvider` stay, the trust check
  needs both.
- `UserOperationTelemetryConsts.Operations.SsoUserProvision` and `AuthenticationReasons.ProvisioningFailed`: nothing
  tracks either once creation is gone.
- `GetUserService`: `FirstOrDefault` was changed to `SingleOrDefault` in `GetUserDataByMailAsync` because JIT creation
  could produce two documents for one email. With no creation, that risk is gone and the change only turns
  pre-existing duplicate data into a hard authentication failure. Roll back to `FirstOrDefault`.
- `RedisKeys.LockForSsoUserProvisioning`: covered by step 2, listed here so the audit is complete.

Recommended keeps, with the reason to record in the result:

- `sso/resolve`, `AnonymousAuthenticationPolicy`, `Error.UserNotProvisioned` (`A1145`) and its frontend handling, the
  SQL columns and their migration, both `ICompanyReader` SSO reads, `EmailHelper.TryGetDomain` / `Mask`, the trust
  check, Graph suppression for SSO domains, the login page with its route guard and redirect-back handling,
  `VUE_APP_AUTH_FLOW_SSO`.
- `apim/products/private/policy.xml` rate-limit key: the resolver is the first anonymous endpoint on the product, and
  the old constant key let one caller exhaust the shared quota for everyone.
- `SqlCompany.SetSsoConfiguration` and `SqlCompanyBuilder.WithSsoConfiguration`: no production caller, configuration is
  raw SQL today. Keep as the invariant holder for tests, and say so in the result rather than leaving it to be
  rediscovered.
- `HostBuilderConfiguration.ClearProvidersUnlessConsoleEnabled` and `frontend.ps1 -UseRealAuthentication`: local
  development conveniences, unrelated to SSO but kept on this branch by decision.
- `infra-sso-example/`: Terraform for a customer-style Entra tenant, kept as a testing aid. B2C itself stays manual.

**Why:** the branch grew through three different access models. Whatever is left unused will be read as intentional by
the next person, and the dead telemetry and claim helpers are the kind of thing that quietly rots.

**Dependencies:** steps 1 to 3, since those removals decide what is unused.

### 7. Confirm the two rejections stay apart

**What:** verification, no code expected. An expired or invalid token must reach `/login`, not the welcome page:
`PerformAuthenticationAsync` returns null without setting the marker, so the middleware answers 401 and
`api-error-interceptor` calls `redirectToLogin()`. The welcome page is reachable only through the `A1145` code. Add a
policy test that a token which fails validation leaves the marker unset, if one does not already cover it.

**Why:** it is the distinction you asked for, and the marker lives in `FunctionContext.Items`, which is easy to set
one branch too early when this code is next touched.

**Dependencies:** step 2.

### 8. Tests

**What:** in `AuthenticateADB2CPrivateApiPolicyTests` drop every creation, name-sync and write-author case along with
the harness pieces that fed them (`LastProvisioningAuthor`, `userHasName`, `tokenHasName`, `provisioningFails`, the
pass-through lock). What remains: an unknown user on an SSO domain is rejected and marked not-provisioned, an existing
user authenticates untouched, plus the trust-check, disabled-user and marker cases. Keep
`InviteSsoMemberToCompanyTests`, invitation is still the only way in.

**Dependencies:** steps 2, 3 and 6.

### 9. Update `docs/sso.md`

**What:** replace the "signing in does not give access" section: logging in creates nothing, an uninvited person sees
the welcome page, a Company Admin invitation creates the Loady user (no B2C account, no password mail) and grants the
role. Note that an invited user types their own name on first login. Fix the troubleshooting rows that promise a
created account.

## Assumptions

- One rejected request per uninvited login is acceptable. It is visible in the network tab and in App Insights as a
  403 with reason `UserNotFound`, which is useful signal rather than noise.
- The Users container only ever holds people an admin invited, which is what Nelia asked for.
- An existing user who was removed from every company still hits the pre-existing 400 on `members/profiles/my`. Not
  caused by SSO, out of scope here; step 1's reverted code is the fix if that state ever matters.
- The identity-provider session stays alive on that page on purpose, so sign-out is the way back to a different
  account.
- A disabled user sees the same welcome page, since both states share the 403 `A1145` code. Accepted for now; giving
  them their own wording means a second error code.
- SSO users type their own first and last name on first login, like invited local users do today.

## Decided

- No user is created at login (Nelia, Dennis).
- No writes at all during authentication: the name-from-token sync goes too.
- The welcome page is the existing no-access card with minimal copy and sign-out.
- Expired or invalid sessions go to `/login`; only a valid token without a Loady user reaches the welcome page.
- A disabled user shares the welcome page.
- The local development conveniences (`Logging__EnableConsole` handling, `frontend.ps1 -UseRealAuthentication`) and
  `infra-sso-example/` stay on this branch.
