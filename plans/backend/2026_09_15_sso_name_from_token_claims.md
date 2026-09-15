# Populate first/last name from the SSO token, skip the manual "Update user" popup

## Goal

An SSO user who has been invited and whose identity provider's token carries `given_name`/`family_name` sees their
profile with First/Last name already filled in on first login — no "Update user" modal, no manual typing. Observable
success: with BASF's confirmed claims (or the DEV test IDP once configured the same way), an invited SSO user's
`GET members/profiles/my` response already has non-empty `FirstName`/`LastName` on the very first call after login, so
`current-user.service.ts`'s `isUserIncomplete()` is `false` and the modal never opens.

This directly fixes the reported case: `kirill@tomorrowops.com`, already invited, currently lands on "Update user"
after SSO login.

## Non-goals

- Reversing the "no user creation at login" decision (`plans/2026_08_27_sso_v5_no_user_creation.md`) — this still only
  touches an **already-invited, already-existing** user's name fields, never creates anyone.
- Syncing name for local (password) users — B2C's local sign-up/sign-in flow doesn't have this problem the same way,
  and BASF's ask is SSO-specific. Local users keep typing their own name, unchanged.
- Re-syncing name on every login once it's set, or overwriting a name the user edited manually afterward — see
  "Design" for why this is a one-time, presence-gated backfill, not an ongoing sync.
- Configuring B2C itself (identity provider claims mapping, user flow application claims) in Terraform. Per
  `sso-docs.md`, B2C stays manual; this plan only prepares the DEV test IDP's Terraform-managed side and documents the
  exact manual B2C steps.

## Blockers

None for the code change. The feature is inert (byte-for-byte today's behavior) until the two B2C portal settings
below are turned on per environment/customer — see "Rollout".

## Investigation summary

- The "Update user" modal is driven entirely by presence, not a flag: `current-user.service.ts`'s
  `isUserIncomplete()` returns `!firstName || !lastName` from the `GET members/profiles/my` response
  (`CurrentUserProfileResponse`, mapped straight from `UserDto.FirstName/LastName`). There is no separate
  "needs-completion" flag to also update — filling the two fields is the whole fix.
- `GetCurrentUserProfileQueryHandler` (`src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs`)
  already has exactly this shape of one-time, condition-gated write-on-read: `if (!user.InvitationAccepted) await
  userService.AcceptInvitationAsync(user, cancellationToken);` before building the response. This plan adds a second,
  analogous block right next to it — reusing an established pattern in this exact handler, not inventing a new one.
- The write path already exists and is already SSO-aware: `UserService.UpdateUserProfileAsync` (`src/Shared/Loady.Services/Domains/Shared/Services/UserService.cs:61-100`)
  — the same method the manual modal calls via `POST members/updateUserProfile` — already skips the B2C Graph update
  for SSO domains (`isSsoDomain` check, line 63-64), fires the `UpdateUserFullNameInEntities` event, invalidates the
  user cache, and tracks telemetry. Reusing it means no new persistence code at all.
- `UpdateUserProfileDtoValidator` only requires non-empty `FirstName`/`LastName` — no length/character restriction —
  so a claim-derived name has low odds of failing validation, but the plan still treats a validator failure as
  "fall back to manual", not a hard error, since this runs inside the profile *read* endpoint.
- `AuthenticateADB2CPrivateApiPolicy` (`src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs`)
  already parses the `ClaimsIdentity` and already knows `ssoDomain` per request (line ~76-77) — it's the only place in
  the request pipeline that sees the raw token. It is deliberately read-only today (base plan's "no writes at all
  during authentication" decision, taken after two bugs surfaced in testing the old creation/name-sync code — those
  bugs aren't recoverable from git history, the removal wasn't committed as a discrete diff). This plan keeps that
  invariant: the policy only *stashes* the two claim strings into the per-request `FunctionContext`, exactly like it
  already does for `UserDto` via `SetUser`/`GetUser` — no Cosmos write happens inside the policy.
- `ClaimsIdentityExtensions.cs` currently has `GetPolicy`/`GetIdentityProvider`, each checking a raw claim type then
  its ASP.NET Core-mapped WS-* fallback (`JwtSecurityTokenHandler`'s `DefaultInboundClaimTypeMap` renames some claims
  before they reach `ClaimsIdentity`). `given_name`/`family_name` need the same dual-check, using
  `System.Security.Claims.ClaimTypes.GivenName`/`ClaimTypes.Surname` as the mapped fallback.
- `ICurrentUserAccessor` (`Loady.Common`) is the existing, deliberate seam between the Functions runtime and
  `Loady.Services`: `Loady.Services` handlers never touch `FunctionContext`/`Items` directly for the current user,
  they go through this interface, implemented by `CurrentUserAccessor` in `Loady.Azure.Functions`. The plan extends
  this same interface with one more read method rather than giving `Loady.Services` a second, parallel way to reach
  into `FunctionContext`.
- `SimpleUserDto.IsRegistrationComplete` (`Loady.Common/Dtos/Users/SimpleUserDto.cs:27`) already exists —
  `!string.IsNullOrEmpty(FirstName) && !string.IsNullOrEmpty(LastName)` — this is the exact "does this user need a
  name" check, already used by nothing in production today but ready to reuse. `FirstName`/`LastName` on
  `SimpleUserDto`/`UserDto` are plain `{ get; set; }`, not `init`, so the handler can just assign them after a
  successful sync instead of rebuilding the record.
- Terraform for the DEV test IDP (`~/loady-vm/integrations/sso-idp-tomorrowops/outputs.tf:32-41`) already documents a
  `claims_mapping` output including `given_name`/`surname` → `given_name`/`family_name` — this was apparently already
  anticipated. What it does **not** yet do: set `given_name`/`surname` on the Terraform-managed `azuread_user.test`
  resources (`main.tf`), so today those test users have no given/family name for Entra to actually return even once
  the B2C-side mapping exists.

## Design

**Chosen approach:** claim-driven, one-time, presence-gated backfill inside the existing profile-read handler, using
the existing update path. Concretely:

1. Read `given_name`/`family_name` off the validated token during authentication (already-parsed `ClaimsIdentity`,
   already known to be an SSO login) and stash them in the per-request `FunctionContext` — no different in kind from
   the `UserDto` that's already stashed there for every authenticated request.
2. On the next `GET members/profiles/my` (which the frontend calls immediately after login, before it would ever show
   the modal), if the user has no name yet and the stashed claims have both values, call the existing
   `UpdateUserProfileAsync` with them, then return the now-complete profile.
3. If either the claims are missing (customer's IdP doesn't map them yet, or B2C's user flow doesn't emit them
   yet) or the update fails validation for any reason, do nothing extra — today's manual-modal behavior is the
   fallback, unconditionally.

**Alternatives considered:**

- *Sync inside `AuthenticateADB2CPrivateApiPolicy` itself* (closest to the old, removed `EnsureNameFromTokenAsync`).
  Rejected: reintroduces a Cosmos write into the one code path the base plan deliberately made read-only after it
  caused two testing bugs, and it would run on *every* authenticated request for the affected user's session, not
  once — more surface for the exact class of problem that was removed, for no benefit over doing it once from the
  profile-read handler that already runs right after login.
- *Add a "needs completion" flag to `UserData`/`UserDto` instead of relying on presence.* Rejected: the frontend
  already derives "incomplete" from field presence in two independent places (`current-user.service.ts` and
  `manage-members-table.component.vue`'s `isMemberRegistered`), and a new flag would have to be kept in sync with
  both without adding anything presence doesn't already tell you.
- *Sync on every login, always trusting the IdP as source of truth.* Rejected: would silently overwrite a name a
  user (or a Company Admin) corrected manually inside Loady after the fact, e.g. because BASF's directory had a
  typo or a preferred-name mismatch. Presence-gating (only when Loady has no name yet) makes this a one-time
  backfill, matching how `InvitationAccepted` is synced once in the same handler.
- *New parallel `IFunctionContextAccessor` injection into `Loady.Services`* instead of extending
  `ICurrentUserAccessor`. Rejected: `Loady.Services` handlers never touch `FunctionContext` directly today; extending
  the one sanctioned seam keeps that invariant instead of adding a second way to reach the same ambient state.

## Steps

### 1. Read the name claims off the token

**File:** `src/Shared/Loady.Azure.Functions/Extensions/ClaimsIdentityExtensions.cs`

Add, following the exact shape of `GetPolicy`/`GetIdentityProvider`:

```csharp
private const string GivenNameClaim = "given_name";
private const string FamilyNameClaim = "family_name";

public static string? GetGivenName(this ClaimsIdentity claimsIdentity)
{
    return GetFirstClaimValue(claimsIdentity, GivenNameClaim)
        ?? GetFirstClaimValue(claimsIdentity, ClaimTypes.GivenName);
}

public static string? GetSurname(this ClaimsIdentity claimsIdentity)
{
    return GetFirstClaimValue(claimsIdentity, FamilyNameClaim)
        ?? GetFirstClaimValue(claimsIdentity, ClaimTypes.Surname);
}
```

`System.Security.Claims` is already imported by this file's consumers; add the `using` if needed.

**Verify:** unit test in `ClaimsIdentityExtensionsTests` for both the raw and WS-*-mapped claim type, mirroring the
existing `idp`/`acr` cases.

### 2. Carry the claims from the policy to the rest of the request

**Files:**
- `src/Shared/Loady.Azure.Functions/Extensions/FunctionContextExtensions.cs` — add, next to `SetUser`/`GetUser`/`TryGetUser`:
  ```csharp
  private const string SsoGivenNameKey = "Authentication.SsoGivenName";
  private const string SsoSurnameKey = "Authentication.SsoSurname";

  public static void SetSsoNameClaims(this FunctionContext context, string? givenName, string? surname)
  {
      context.Items[SsoGivenNameKey] = givenName;
      context.Items[SsoSurnameKey] = surname;
  }

  public static bool TryGetSsoNameClaims(this FunctionContext context, out string? givenName, out string? surname)
  {
      givenName = context.Items.TryGetValue(SsoGivenNameKey, out var g) ? g as string : null;
      surname = context.Items.TryGetValue(SsoSurnameKey, out var s) ? s as string : null;
      return !givenName.IsNullOrWhiteSpace() && !surname.IsNullOrWhiteSpace();
  }
  ```
- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs` —
  in `GetUserFromValidationResultAsync`, right before the final `return user;`, when `ssoDomain is not null`:
  ```csharp
  if (ssoDomain is not null)
  {
      functionContext.SetSsoNameClaims(claimsIdentity.GetGivenName(), claimsIdentity.GetSurname());
  }
  ```
  Only for SSO logins — a local/password login never has these claims and shouldn't pay even the `Items` write.
  Nothing else in this method changes; this stays additive to the existing read-only checks.

**Why here:** this is the only place the validated `ClaimsIdentity` exists; storing two strings in per-request
`Items` is the same operation the policy already performs for `UserDto`, not a new kind of side effect.

**Verify:** extend `AuthenticateADB2CPrivateApiPolicyTests` with a case that an SSO login with `given_name`/
`family_name` claims leaves them retrievable via `TryGetSsoNameClaims`, and that a local-flow login does not set
them.

### 3. Expose the claims to `Loady.Services` through the existing seam

**Files:**
- `src/Shared/Loady.Common/Interfaces/ICurrentUserAccessor.cs` — add:
  ```csharp
  bool TryGetSsoNameClaims(out string? givenName, out string? surname);
  ```
- `src/Shared/Loady.Azure.Functions/Services/CurrentUserAccessor.cs` — implement by delegating to
  `functionContextAccessor.FunctionContext`:
  ```csharp
  public bool TryGetSsoNameClaims(out string? givenName, out string? surname)
  {
      if (functionContextAccessor.FunctionContext is not null)
      {
          return functionContextAccessor.FunctionContext.TryGetSsoNameClaims(out givenName, out surname);
      }

      givenName = null;
      surname = null;
      return false;
  }
  ```

**Verify:** no existing test covers `CurrentUserAccessor` directly (checked); add one alongside the existing class if
one doesn't already exist, or fold into the `GetCurrentUserProfileQueryHandlerTests` integration coverage in step 4.

### 4. Backfill the name in the profile-read handler

**File:** `src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs`

Next to the existing `if (!user.InvitationAccepted) { await userService.AcceptInvitationAsync(...); }` block, add:

```csharp
if (!user.IsRegistrationComplete
    && currentUserAccessor.TryGetSsoNameClaims(out var givenName, out var surname))
{
    var profileUpdate = new UpdateUserProfileDto { FirstName = givenName!.Trim(), LastName = surname!.Trim() };

    try
    {
        await userService.UpdateUserProfileAsync(user, profileUpdate, cancellationToken);
        user.FirstName = profileUpdate.FirstName;
        user.LastName = profileUpdate.LastName;
    }
    catch (Exception ex) when (ex is BadRequestException or BadRequestAggregateException)
    {
        // Claim-derived name failed validation (or some other business rule the manual form also enforces).
        // Leave the user nameless; the "Update user" modal is still the fallback.
    }
}
```

Confirm the exact exception type(s) `UpdateUserProfileAsync` -> `validator.ThrowIfInvalidAsync` actually throws
before finalizing this catch clause (the codebase's convention per `backend/AGENTS.md` is `BadRequestException` from
`ThrowIfInvalidAsync`, but this handler doesn't currently call a validator itself — confirm whether
`UpdateUserProfileAsync` validates internally or relies on the caller, since `UserProfile.cs`'s function endpoint
validates before calling the service; calling the service directly here may need to run
`UpdateUserProfileDtoValidator` explicitly first, or accept that this path is trusted (claims, not user input) and
skip validation, catching only unexpected failures).

**Why this exception handling:** this runs inside the endpoint the frontend calls to render the whole app shell after
login — throwing here breaks the entire session, not just the name field. Silently falling back to "no name yet" is
strictly better than a broken profile fetch.

**Verify:** extend `GetCurrentUserProfileQueryHandlerTests` (integration): an invited SSO user with no name, claims
present → response has the names, `UserData` in Cosmos is updated, event fired. An invited SSO user with no name,
claims absent → unchanged (still needs the modal). A user who already has a name → claims are ignored even if
present (no overwrite).

### 5. Terraform: give the DEV test IDP's users a given/family name to return

**File:** `~/loady-vm/integrations/sso-idp-tomorrowops/variables.tf` and `main.tf`

Add `given_name`/`surname` to the `test_users` object type and pass them into `azuread_user.test`:

```hcl
# variables.tf
variable "test_users" {
  type = map(object({
    display_name          = string
    given_name             = string
    surname                = string
    password              = string
    force_password_change = optional(bool, false)
  }))
  ...
}

# main.tf
resource "azuread_user" "test" {
  for_each = nonsensitive(toset(keys(var.test_users)))

  user_principal_name   = each.key
  display_name          = var.test_users[each.key].display_name
  given_name            = var.test_users[each.key].given_name
  surname               = var.test_users[each.key].surname
  password              = var.test_users[each.key].password
  force_password_change = var.test_users[each.key].force_password_change
}
```

Confirm `given_name`/`surname` are valid arguments on the `azuread_user` resource for the pinned provider version
(`.terraform.lock.hcl`) before applying — not verified from this repo, check the provider docs at apply time.

This is the one Terraform-managed piece; the tfvars file supplying actual `test_users` values is untracked
(`variables.tf`'s own comment: "supplied from an untracked tfvars file"), so no secret/PII lands in either repo.

**Why:** without this, the DEV round-trip has nothing to prove the feature with — Entra returns `given_name`/
`family_name` from the `profile` scope based on the user object's actual given name/surname fields, which are
currently unset for the Terraform-managed test users.

### 6. Manual B2C configuration (per environment/customer, outside any repo)

Not code — a checklist for you to run once per environment this ships to, per `sso-docs.md`'s existing "each
environment is configured separately" model:

1. **Identity Provider claims mapping** (Azure AD B2C → Identity Providers → the customer's/test provider's OIDC
   entry): add two more mapped claims — Given Name → `given_name`, Surname → `family_name` — alongside the existing
   User ID/Display name/Email mapping. For the tomorrowops test provider, this is exactly the `claims_mapping`
   Terraform output already prepared in `outputs.tf`.
2. **SSO user flow Application claims** (`B2C_1_sso_sign_up_sign_in`): check "Given Name" and "Surname" alongside
   the existing "Email Addresses" and "Identity Provider".
3. Confirm with a decoded token (jwt.ms, per `sso-docs.md`'s "Verify" section) that `given_name`/`family_name` are
   now present before relying on it.

For BASF specifically: Dennis already confirmed their tenant's default token includes `family_name`/`given_name`
(no BASF-side app registration change needed, since `profile` scope already requests them per the existing setup) —
only the two Loady B2C settings above are needed in whichever environment BASF's production SSO runs.

### 7. Update `sso-docs.md`

**File:** `backend/plans/sso-docs.md`

- "Loady setup: user flow" (line 88): change `Application claims: **Email Addresses** and **Identity Provider**
  only` to include Given Name and Surname, and note they're optional — their absence doesn't break login, it just
  means the user types their name manually.
- "Loady setup: identity provider" (line 101): add Given Name → `given_name`, Surname → `family_name` to the claims
  mapping list.
- Add a short note near "Good to know": if the customer's IdP token carries `given_name`/`family_name` and B2C is
  configured to pass them through, an invited user's name is filled in automatically on first login instead of the
  manual popup; otherwise nothing changes from today.

## Files this work will own

- `src/Shared/Loady.Azure.Functions/Extensions/ClaimsIdentityExtensions.cs`
- `src/Shared/Loady.Azure.Functions/Extensions/FunctionContextExtensions.cs`
- `src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs`
- `src/Shared/Loady.Common/Interfaces/ICurrentUserAccessor.cs`
- `src/Shared/Loady.Azure.Functions/Services/CurrentUserAccessor.cs`
- `src/Shared/Loady.Services/Domains/Private/Users/Queries/GetCurrentUserProfileQueryHandler.cs`
- Their corresponding test files (`ClaimsIdentityExtensionsTests`, `AuthenticateADB2CPrivateApiPolicyTests`,
  `GetCurrentUserProfileQueryHandlerTests`).
- `~/loady-vm/integrations/sso-idp-tomorrowops/variables.tf`, `main.tf` (private repo, separate apply/commit flow).
- `backend/plans/sso-docs.md`.

No SQL/Cosmos schema change: `UserData.FirstName`/`LastName` already exist and already accept this write via the
existing `UpdateUserProfileAsync` path.

## Rollout

Fully additive and backward compatible:

- With no B2C config change, behavior is identical to today — claims are absent, the `if` in step 4 never fires, the
  manual modal is exactly as it is now. Safe to merge and deploy ahead of any B2C portal change.
- Once B2C is configured for a given environment/customer (step 6), the *next* profile fetch for any already-invited,
  still-nameless SSO user on that domain (including `kirill@tomorrowops.com` right now) picks up their name
  automatically — no backfill migration needed, since the check is presence-based and runs on every profile fetch
  until a name exists.
- No versioned contract change: `CurrentUserProfileResponse`'s shape is unchanged, only when its fields are already
  populated changes.
- Nothing to undo in code if a customer's B2C claims mapping turns out wrong — worst case, a wrong name lands from a
  bad claim; that's exactly as fixable as it is today (Company Admin/the user edits it via the existing manual "edit
  profile" path), and it isn't overwritten again automatically because of the presence gate.

## Assumptions / what I could not verify

- The exact exception type `UserService.UpdateUserProfileAsync` throws on invalid input (step 4) — this method is
  called directly here, not through the endpoint's own `validator.ThrowIfInvalidAsync` call in `UserProfile.cs`.
  Confirm at implementation time whether the service validates internally.
- Whether the `azuread_user` Terraform resource, at the version pinned in
  `sso-idp-tomorrowops/.terraform.lock.hcl`, accepts `given_name`/`surname` arguments — highly likely (standard
  AzureAD provider fields) but not verified against the actual provider schema from this session.
- Whether BASF's production Entra app registration needs any change beyond what Dennis already confirmed. Taking his
  message at face value: no change needed there, only the two Loady B2C settings.
- Whether other already-configured SSO customers besides BASF/tomorrowops exist today and would need the same two
  B2C settings applied before this has any visible effect for them. Not visible from this repo (B2C config is
  manual, per-environment, and this repo has no inventory of live customers) — check with Nelia/Heinz which
  environments already have `IsSsoEnabled = true` companies before assuming this is BASF-only.

## Risks

- If a customer's IdP maps `given_name`/`family_name` to something unexpected (e.g. a full display name in
  `given_name`, empty `family_name`), the claim-derived name could be wrong instead of missing — the user or a
  Company Admin has to notice and correct it manually, same as any other data-quality issue from an external
  source. No repo-side validation can catch a semantically wrong-but-well-formed claim.
- Confirm the profile-read endpoint's overall latency/error budget tolerates one extra conditional write on a cold
  path (first login only, only while nameless) — low risk given `UpdateUserProfileAsync` is already a normal,
  exercised write path, but worth a quick check in a DEV round-trip before calling this done.
