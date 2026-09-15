# PR 9819 review comments: fixes for "Implement SSO"

- **Source:** `https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819`, read via `ld-pr 9819` on
  2026-09-15.
- **Base plan/result:** `plans/2026_08_27_sso_v5_no_user_creation.md` / `..._result.md` (backend, already implemented)
  and
  `plans/sso-docs.md` (operator docs). This plan does not redo that work; it resolves the review feedback left on top of
  it.

## Goal

Every open comment on PR 9819 is either fixed in the working tree, or explicitly deferred here with the decision that is
needed before it can be. Observable success: re-reading the PR thread against the diff, each comment maps to a concrete
change (or a documented "needs your call" entry in this plan), and `dotnet build` / `vue-cli-service lint`
still pass.

## Non-goals

- Re-litigating the "no user creation on login" design from the base plan.
- Any change to Azure B2C tenant configuration, user flows, or identity provider registration (that's operator setup in
  `sso-docs.md`, not code in this repo).
- Fixing comments already marked `[fixed]` in ADO (listed below for completeness only).

## Comment inventory and status

Thread links go to the PR's Files tab for that file (comments render alongside the diff there); general threads with no
file link to the PR Overview tab, where non-file comments show. ADO doesn't expose a per-comment `discussionId`
through `ld-pr`, so these are file-level, not scroll-to-that-exact-comment links.

`PR_BASE = https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819`

| # | File                                                                | Status   | Author        | Thread                                                                                                                                                                                                     |
|---|---------------------------------------------------------------------|----------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A | `backend/apim/products/private/policy.xml`                          | Done     | Kirill        | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Fbackend%2Fapim%2Fproducts%2Fprivate%2Fpolicy.xml&_a=files)                                                      |
| B | general, 2026-08-28                                                 | Not done | Heinz         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?_a=overview)                                                                                                            |
| C | `frontend/src/app/auth/utils/auth.utils.ts`                         | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Futils%2Fauth.utils.ts&_a=files)                                                   |
| D | `login.component.vue` — ErrorMessage reuse                          | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| E | `login.component.vue` — spacing/gap                                 | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| F | `login.component.vue` — dedupe welcome/login title                  | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| G | `login.component.vue` — Options API → `<script setup>`              | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| H | `login.component.vue` — `data-qa-id`                                | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| I | `login.component.vue` — `isWelcome` via `route.query`               | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| J | `login.component.vue` — description text color                      | Done     | Anton         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Ffrontend%2Fsrc%2Fapp%2Fauth%2Fcomponents%2Flogin.component.vue&_a=files)                                        |
| K | `SsoResolve.cs` — GET with query param, not body-deserialized query | Done     | Nelia         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Fbackend%2Fsrc%2FDomains%2FLoady.Backend.Api%2FAuthentication%2FSsoResolve.cs&_a=files)                          |
| L | `SqlCompany.cs` — SSO columns vs. separate table                    | Done     | Nelia + Heinz | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?path=%2Fbackend%2Fsrc%2FShared%2FLoady.Relational.Domain%2FAggregateModels%2FCompanyAggregate%2FSqlCompany.cs&_a=files) |
| M | general, 2026-09-11 — existing B2C local accounts + inactivity job  | Not done | Heinz         | [link](https://dev.azure.com/Loady-Logistics/loady/_git/loady-one/pullrequest/9819?_a=overview)                                                                                                            |

Since D, E, F, G, H, I and J all land on the same `login.component.vue` thread link, use the PR's own file comment list
to tell them apart — Anton posted them as separate comments a few minutes apart on 2026-09-01.

### Reply comments (copy-paste into each thread)

- **A:** Already fixed before this pass, per the `[fixed]` marker on the thread — no reply needed.
- **B:** `ld-pr` returned this thread with no comment text (possibly attachment-only). Could you repost what you'd like
  addressed here?
- **C:** Fixed — `handleAuthRedirectPromise` now skips `getAllAccounts().find(...)` entirely when there's no stored
  `accountId`, instead of calling `.find()` against `undefined`.
- **D:** Fixed — the validation and error spans are now the shared `ErrorMessage` component; the now-unused
  `.validation-error`/`.login-error` CSS was removed.
- **E:** Fixed — removed the uniform `gap: 1rem` from `.login-form`; label-to-input spacing now comes from
  `InputLabel`'s own `margin-bottom: var(--spacing-2)`, and `.button { margin-top: var(--spacing-6) }` widens the gap
  before the submit button. Not checked against the attached screenshots or the live B2C form in a browser (no
  browser/screenshot tool available in this session) — worth a quick visual pass next time you're testing SSO
  end-to-end.
- **F:** Fixed — `Logo`/`<h1>` now render once outside the `isWelcome` branch, both states share `login.title`, and the
  now-duplicate `login.welcome-title` key was removed from `en.yml`.
- **G:** Fixed — rewritten as `<script setup lang="ts">`: `data()`/`computed`/`methods`/`setup()` collapsed into
  `ref`/`computed`/plain functions, `defineComponent`/`name`/`components` dropped (no longer needed). No template or
  logic changes; same behavior as the Options API version.
- **H:** Fixed — added `data-qa-id` on the email input and both buttons, matching the convention used elsewhere (e.g.
  `edit-company-account.component.vue`).
- **I:** Fixed — `isWelcome` now reads `route.query.reason` reactively instead of `window.location.search`.
- **J:** Fixed — description `<p>` now uses `var(--color-blue-gray-100)` per your confirmation, applied as the
  provisional value pending final design sign-off if Vladi has other feedback.
- **K:** Fixed — `sso/resolve` is now `GET /sso/resolve?email=...`, built via `GetRequiredQueryParameter` instead of
  deserializing the body into the MediatR query directly (matches the `DictionaryGetByIds` pattern). Frontend
  `identity-provider.service.ts` updated to call it as a GET.
- **L:** Fixed — SSO domain configuration is now a standalone `SqlSsoIdentityProvider` table (`Domain` unique-indexed,
  `DomainHint`, `Issuer`, `IsEnabled`), decoupled from `Company` entirely, per
  `plans/2026_09_15_sso_domain_storage_option.md`. `SqlCompany` no longer has any SSO fields. Migration
  `20260827141726_AddSsoConfiguration.cs` was intentionally left untouched — you're recreating it by hand.
- **M:** Investigated in full in `plans/2026_09_15_sso_existing_user_migration.md` — that plan now owns this
  question (it also folds in a related, more concrete scenario Kirill raised: an existing BASF user with company
  assignments/roles switching from local password login to SSO). Summary for the thread reply:
  1. Login: existing local-account users are unaffected — routing to SSO only happens when their email domain has
     `IsSsoEnabled = true`. The one real edge case is a local account whose domain gets SSO turned on *after* the
     account was created — that account can't use its password afterward (enforced server-side, not just frontend
     routing: `AuthenticateADB2CPrivateApiPolicy` rejects a mismatched `tfp` claim with 401). Not documented anywhere
     yet.
  2. Inactivity job: not actually SSO-specific — a known Microsoft Graph/B2C `signInActivity` reliability limitation
     that affects every account type. `UserService.InactivateUsersAsync` already excludes every user on an
     SSO-configured domain outright, so this is moot for SSO users specifically once their domain is enabled;
     whether the underlying Graph signal is trustworthy at all for anyone else needs checking against the tenant's
     actual license/permissions, not something this repo can confirm.
  3. Full existing-user migration analysis (does B2C create a shadow account, do company assignments/roles survive)
     is in the new plan, including a DEV verification checklist for the one part only Azure AD B2C itself can
     confirm.

## Investigation notes (so the "needs your call" items have evidence, not just questions)

**L — domain uniqueness.** `SqlCompany.SsoEmailDomains`
(`src/Shared/Loady.Relational.Domain/AggregateModels/CompanyAggregate/SqlCompany.cs:83-87`)
is a JSON array column (`CompanyConfiguration.cs`: `HasMaxLength(2000)`), no DB constraint. Uniqueness is enforced only
at read time in `SqlCompanyReader.TryGetBySsoEmailDomainAsync`
(`src/Shared/Loady.Services/Domains/Shared/Readers/SqlCompanyReader.cs:82-102`):
it fetches up to 2 matches and throws `InvalidOperationException` if both hit, which surfaces as a bare 401 to every
user on that domain, not just the misconfigured company's. Heinz's point is sharper than Nelia's: a domain isn't
naturally 1:1 with a Company at all (BASF SE vs. BASF NA can share `basf.com`), so the fix isn't just "move columns to a
table with a unique index on domain" — that still assumes one domain -> one company. There's no existing analogue in
this codebase of a shared lookup table keyed by something other than a company (closest pattern is a plain FK +
unique-index child table, e.g. `WebhookConfiguration.cs`, `SiteConfiguration.cs`).

**M — inactivity job.** `UserService.InactivateUsersAsync`
(`src/Shared/Loady.Services/Domains/Shared/Services/UserService.cs:102-155`)
already excludes SSO-configured domains before inactivating anyone (lines 123-129, added as part of the base SSO work):
it cross-references B2C's `signInActivity/lastSignInDateTime` via Graph against
`ssoConfigurationService.GetConfiguredSsoDomainsAsync(...)` and drops matches. `DisableInactiveUsersAsync` and
`DeleteDisabledUsersAsync` only ever process users already `ActivityStatus == Inactive`/`Disabled`
(`UserService.cs:157-196`), so a user can only reach them by first surviving `InactivateUsersAsync` — meaning the delete
pipeline is already structurally shielded for domains that were SSO-enabled *before* the user went inactive. The gap is
the reverse order: a user already `Inactive`/`Disabled` when their domain later gets `IsSsoEnabled = 1`
stays on the deletion clock, nothing re-checks it. That's a narrow edge case, not a rewrite.

**M, re-checked 2026-09-15 against Heinz's comment text directly.** Two separate questions, both now answered as far
as this repo and public docs allow:

1. *"Can they log in?"* — Yes, unaffected. The SSO routing in `auth.utils.ts`'s `login()` only kicks in when
   `identityProviderService.resolve(email)` returns a `domainHint`, which only happens for a domain with
   `IsSsoEnabled = true` on its `SqlSsoIdentityProvider` row (`SsoConfigurationService.GetEnabledSsoDomainAsync`).
   Every other email, i.e. the entire existing local-account (password) user base, resolves `domainHint: null` and
   keeps going through the unchanged `LocalFlow`/`B2C_1_sign_in_flow` exactly as before this PR. No regression here,
   confirmed by reading the routing code, not just asserted.

   The one narrower case that *is* real: a local (password) account whose email domain later gets
   `IsSsoEnabled = true` gets force-routed into the SSO flow afterward (per `sso-docs.md`: `Local accounts: all
   unchecked` on that B2C user flow), so that specific account can no longer sign in with its old password. That's a
   DEV B2C fact, not something a code read alone proves, and it isn't written down anywhere as expected behavior yet.

2. *"Could the inactivity job accidentally delete these users because local-accounts don't generate new login
   activity?"* — This is the sharper of the two, and it is **not specific to SSO or to local accounts either** — it's
   a known Microsoft Graph/Azure AD B2C limitation on the exact API `GetUserIdsAsync` depends on
   (`src/Packages/Loady.Infrastructure.MsGraph/Services/GraphService.cs:299-333`, filtering on
   `signInActivity/lastSignInDateTime`):
   - `signInActivity` requires an Azure AD Premium P1/P2 license and `AuditLog.Read.All` permission on the tenant; a
     B2C tenant without that gets `"Neither tenant is B2C or tenant doesn't have premium license"` from Graph.
   - Even when it *is* available, Microsoft's own docs describe it as "not consistently returned for some users...
     even though the Azure portal shows successful sign-in events for those same accounts" in B2C tenants
     specifically, and eventually-consistent with up to 24-72h lag.
   - `GraphService.GetUserIdsAsync` catches every exception from that call and returns an **empty set**
     (`GraphService.cs:324-332`), logging an error but not surfacing it anywhere else — so if the whole call fails
     (e.g. missing license/permission), the job silently no-ops rather than wrongly deleting anyone; the real risk is
     the *partial*, per-user flakiness Microsoft documents, where a genuinely active local-account user's sign-ins
     just aren't recorded and they eventually get swept up.
   - The blast radius is slow, not immediate: `UserSettings` (`src/Shared/Loady.Common/Settings/UserSettings.cs`)
     gates this at `InactivateUserMonthsThreshold = 36` months of apparent inactivity before `Inactive`, then
     `DisableInactiveUserMonthsThreshold = 2` more before `Disabled`, then `DeleteDisabledUserMonthsThreshold = 1`
     more before deletion — about 39 months end to end, so a licensing/tracking gap has a long window to be caught
     before it deletes anyone.
   - Whether *this tenant* actually has the P1/P2 license and `AuditLog.Read.All` grant, and whether
     `signInActivity` reliably returns for Loady's own local accounts, is not something this repo or its Terraform
     answers (the B2C app registration's Graph permissions aren't provisioned here) — it needs checking directly
     against the DEV/PROD B2C tenant (Azure Portal API permissions blade, or a manual Graph query against a
     known-active local test account).

Sources: [signInActivity resource type - Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/resources/signinactivity?view=graph-rest-1.0),
[SignInActivity property missing in Graph API despite visible sign-in logs](https://learn.microsoft.com/en-us/answers/questions/2237331/signinactivity-property-missing-in-graph-api-despi),
[Receiving error 'Neither tenant is B2C or tenant doesn't have premium license'](https://blogs.aaddevsup.xyz/2021/03/receiving-error-neither-tenant-is-b2c-or-tenant-doesnt-have-premium-license-from-microsoft-graph/).

## Steps

### Step 1 — `auth.utils.ts`: null-safe account lookup (comment C)

- **File:** `frontend/src/app/auth/utils/auth.utils.ts`, `handleAuthRedirectPromise` (around line 46).
- **What:** apply Anton's suggested change verbatim — skip `msalInstance.getAllAccounts().find(...)` when
  `sessionStorage.getItem(AccountIdKey)` is `null`, instead of calling `.find()` against `undefined` and relying on
  `candidate.homeAccountId === null` never matching.
- **Why:** same outcome today (no candidate matches `null`), but this makes the "no stored account" case explicit
  instead of accidental, per the review comment.
- **Verify:** `vue-cli-service lint` on the file; no behavior change to assert in a test.

### Step 2 — `login.component.vue`: structure and API style (comments F, G, I)

Do these three together since they all touch the same template/script restructuring and Anton's own comment F sketches
the shape:

- **F:** hoist `<Logo />` and `<h1>{{ translate("title") }}</h1>` outside the `isWelcome` conditional, drop
  `welcome-title` from `frontend/src/assets/i18n/en.yml` (currently identical to `title`), keep only the description/
  form content behind `v-if="isWelcome"` / `v-else`.
- **I:** replace the `isWelcome` computed's `isWelcomeReason(window.location.search)` with
  `route.query[ReasonKey] === WelcomeReason` (or `isWelcomeReason` reworked to take `route.query` — pick whichever keeps
  `isWelcomeReason` usable from its one other caller; check `frontend/src/app/router.ts` and
  `api-error-interceptor.service.ts` for other callers before changing its signature, since the base-plan result notes
  it's shared vocabulary now). Using `route.query` makes the check reactive, matching Anton's rationale.
- **G:** rewrite the component from Options API (`defineComponent` + `data()`/`computed`/`methods`) to
  `<script setup lang="ts">`, consistent with the FE team's stated direction (per Anton's comment; no repo-wide
  precedent conflict — mixed Options/`<script setup>` components already coexist, e.g.
  `edit-company-account.component.vue` uses `<script setup>`).
- **Why order matters:** rewriting to `<script setup>` (G) is the largest mechanical change to this file: do the logic
  changes (F, I) first against the Options API version so each is reviewable as a small diff, then let the
  `<script setup>` rewrite (G) be the last, purely mechanical pass — easier to review as "no logic change, just syntax."
- **Verify:** `vue-cli-service lint`; manually exercise both `/login` and `/login?reason=welcome` in the dev server (per
  repo convention for frontend changes) to confirm both states still render and `signOut`/`submit` still work.

### Step 3 — `login.component.vue`: presentation cleanup (comments D, E, H, J)

- **D:** replace `<span v-if="..." class="validation-error">` and `<span v-if="error" class="login-error">` with
  `<ErrorMessage>` from `frontend/src/app/shared/components/error-message.component.vue`, exactly as Anton's snippet
  shows. Drop `.validation-error`/`.login-error` from the `<style>` block once nothing references them.
- **H:** add `data-qa-id` on the email `InputText` (already has `id="login-email"` but no `data-qa-id`) and the submit
  `Button`, matching the convention in `edit-company-account.component.vue` (`data-qa-id="<field>"`).
- **E:** remove `gap: 1rem` from `.login-card` and rely on each child's own `margin`, matching the two screenshots in
  the comment. This is a visual-diff change — implement it, then compare against the attached design screenshot in a
  running dev server rather than guessing spacing values from code alone.
- **J:** **needs your call.** Anton flagged the description `<p>` color (currently `var(--color-blue-gray-60)`, an
  input-placeholder color) as low-contrast and suggested `--color-blue-gray-100`, but asked to confirm with the designer
  (Vladi) first — that confirmation hasn't happened in the thread. Options: (1) apply
  `--color-blue-gray-100` now and treat it as provisional pending design sign-off, (2) leave it and open a separate
  design-confirmation task, (3) get Vladi's answer before touching this file at all. Recommend (1): it's a one-line,
  easily-revertable CSS change and blocking the rest of Step 3 on a Slack thread costs more than getting it wrong once.
- **Verify:** `vue-cli-service lint`; visual check against both attached screenshots in the dev server.

### Step 4 — `SsoResolve.cs`: GET with query parameter, not body-deserialized query (comment K)

- **Files:**
    - `backend/src/Domains/Loady.Backend.Api/Authentication/SsoResolve.cs`
    - `backend/src/Shared/Loady.Services/Domains/Private/Authentication/Queries/ResolveIdentityProviderQuery.cs`
    -
  `backend/src/Shared/Loady.Services/Domains/Private/Authentication/Validators/ResolveIdentityProviderQueryValidator.cs`
  (and its unit test) — unaffected in content, just now validating a query built from a query-string param
    - `backend/apim/apis/backend/Backend.API.openapi.json` — **do not touch**; regeneration required, out of scope per
      `backend/AGENTS.md`
    - Frontend caller: `frontend/src/app/auth/services/identity-provider.service.ts` (confirm exact name/path before
      editing) — must switch its `resolve(email)` call from POST+JSON-body to GET+query string.
- **What:** change the route from `POST sso/resolve` (body-deserialized straight into `ResolveIdentityProviderQuery`)
  to `GET sso/resolve?email=...`, following the existing pattern in
  `backend/src/Domains/Loady.Backend.Api/Dictionaries/DictionaryGetByIds.cs:38-63` (`req.Query["ids"]`) or the
  stronger-typed `req.GetRequiredQueryParameter<T>(...)` /`GetQueryParameterOrDefault<T>(...)` helpers in
  `Loady.Azure.Functions/Extensions/QueryStringExtensions.cs`, used by the Search-style GET endpoints. Build the
  `ResolveIdentityProviderQuery` from the query parameter instead of `req.DeserializeRequestBody<...>()`. Add an
  `[OpenApiParameter("email", In = ParameterLocation.Query, Required = true, ...)]` attribute matching the
  `DictionaryGetByIds` precedent.
- **Why:** matches Nelia's stated concern (deserializing request bodies directly into Command/Query types leads to
  nullable/JsonIgnored properties, as happened with `ConnectEntityCommand`) and her concrete suggestion (`GET` with a
  query param) — this endpoint has exactly one primitive input, which is the textbook case for a query param over a JSON
  body.
- **Rollout:** this is a public-facing anonymous endpoint contract change (method + param location). Since the feature
  is not yet released (branch not merged to `dev`), there's no live client to break — no versioning or dual-support
  needed, just update backend + frontend together in this branch.
- **Verify:** `dotnet build Loady.slnx`;
  `dotnet test src/Shared/Loady.Services.UnitTests --filter "ResolveIdentityProviderQueryValidatorTests"`;
  `vue-cli-service lint` on the frontend service; manual round trip against local func host if time allows.

### Step 5 — SSO domain configuration storage (comment L) — done, see `plans/2026_09_15_sso_domain_storage_option.md`

Superseded by that plan: implemented as a standalone `SqlSsoIdentityProvider` table, decoupled from `Company`. Kept
below for the historical record of the tradeoff.

This is the one comment that changes a decision already made and implemented, not just a code-quality nit, so it needs a
decision before a step can be written concretely. Options, with what each costs:

1. **Minimal fix — keep 1 domain : 1 company, move to a real table.** Add a `CompanySsoEmailDomains` (or similar)
   table: `Id`, `CompanyId` (FK to `Companies`), `Domain` (unique index), replacing the JSON array column. Closest
   existing pattern: child tables like `WebhookConfiguration`/`SiteConfiguration` (FK + unique index). Cost: one EF
   migration (you run `dotnet ef migrations add`, not me, per `backend/AGENTS.md`), a data backfill from the existing
   JSON column, and every `SqlCompanyReader`/`ISsoConfigurationService` call site touching `SsoEmailDomains` updated.
   Does **not** address Heinz's BASF SE/NA point — a domain is still tied to exactly one company.
2. **Address Heinz's point — decouple domain-to-provider mapping from Company entirely.** A `SsoIdentityProvider`-like
   table (domain unique, hint, issuer) that companies opt into by reference, rather than each company owning its own
   domain list. Bigger: changes the mental model in `sso-docs.md`'s "Loady setup: company row" section, the
   `SetSsoConfiguration`/`ClearSsoConfiguration` API on `SqlCompany`, and every consumer. No existing precedent in this
   codebase for shared-lookup-not-owned-by-an-aggregate-root; would be new infrastructure.
3. **Leave as-is, document the operational constraint.** Cheapest: no code, just make `sso-docs.md`'s existing "One
   domain belongs to one company only" line louder, and rely on the existing throw-on-conflict as the safety net (it
   already fails closed, per `SqlCompanyReader.TryGetBySsoEmailDomainAsync`). Doesn't fix the "any company can
   accidentally break another company's SSO" risk Nelia raised, since it's still a hand-edited SQL column with no DB
   constraint — but no BASF-style multi-company-per-domain support was ever a stated requirement.

Recommend option 1 as the concrete next step (it directly answers Nelia's ask and is a bounded migration), and raising
option 2 with Heinz separately as a product question (does Loady actually need multiple companies sharing one email
domain, or was that a hypothetical illustrating the coupling problem?) before building for it. I have not written a Step
5 implementation because which of these you want changes the migration shape.

### Step 6 — inactivity-job edge case + B2C local-account continuity (comment M) — **needs your call**

- **Code fix, if wanted:** re-check `IsSsoEnabled`/domain configuration inside `DisableInactiveUsersAsync` (and/or
  `DeleteDisabledUsersAsync`) in `UserService.cs`, not just `InactivateUsersAsync`, so a user who went `Inactive`
  before their domain got SSO-enabled doesn't get disabled/deleted afterward. Small, same helper
  (`ssoConfigurationService`) already injected into `UserService`. Only worth doing if you consider this edge case live
  risk rather than theoretical (a domain has to go Inactive-eligible, then get SSO turned on, before this matters).
- **Not a code fix — needs a DEV B2C test:** whether a pre-existing B2C **local** (password) account on a domain keeps
  working once that domain is switched to SSO. Current reading of `sso-docs.md` plus the frontend routing in
  `auth.utils.ts` says no — the user gets routed into the SSO flow, which doesn't offer password login. If that's the
  intended behavior, it belongs in `sso-docs.md`'s "Good to know" section (there isn't a line for it yet). If it's not
  intended, that's a product conversation, not a code fix I can write from here.

## Files this work will own

- `frontend/src/app/auth/utils/auth.utils.ts`
- `frontend/src/app/auth/components/login.component.vue`
- `frontend/assets/i18n/en.yml` (`login.welcome-title` removal only)
- `backend/src/Domains/Loady.Backend.Api/Authentication/SsoResolve.cs`
- `backend/src/Shared/Loady.Services/Domains/Private/Authentication/Queries/ResolveIdentityProviderQuery.cs`
- `frontend/src/app/auth/services/identity-provider.service.ts` (verify exact path first)
- Step 5/6 files are not touched until you pick an option.

## Assumptions / what I could not verify

- Comment B (general, Heinz, 2026-08-28) came back with an empty body from `ld-pr`. It may be attachment-only or a
  reply-thread artifact `ld-pr` doesn't render. Check it directly in the ADO PR UI before assuming there's nothing
  there.
- `identity-provider.service.ts`'s exact path/name wasn't confirmed by file read, only inferred from the import in
  `login.component.vue` (`@/app/auth/services/identity-provider.service`) — confirm before editing in Step 4.
- Whether `isWelcomeReason` in `auth.utils.ts` has other callers beyond `login.component.vue` wasn't fully traced — Step
  2 says to check before changing its signature.
- Step 5's "needs your call" is the one place this plan doesn't reduce to a checklist; implementing it before you pick
  an option would mean guessing at a schema change to a feature already in review.

## Risks

- Step 4 (GET vs POST) and Step 5 (schema change) both touch the SSO login's critical path; test both against a real
  local func host + B2C dev tenant before considering them done, not just unit tests.
- Step 2's `<script setup>` rewrite is a full-file diff; reviewers may want it as its own commit/PR-comment-reply
  separate from the logic changes for that reason (see step ordering note).
