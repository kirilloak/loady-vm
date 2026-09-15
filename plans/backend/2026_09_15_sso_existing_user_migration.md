# Existing local B2C users migrating to SSO: what actually happens

## Source questions

**Heinz Liewald, PR 9819, general thread, 2026-09-11** (extracted from
`plans/2026_09_15_sso_pr9819_review_comments.md`, comment M — this plan now owns that investigation, see "Superseded"
below):

> We should check what happens when users already exist in our B2C as local-accounts. Can they log in? Could the
> inactivity background job accidentally delete these users because their local-accounts don't generate new login
> activity?

**Kirill, 2026-09-15**, the concrete case this is really about:

> Main questions I have: company BASF, user logged in normally with B2C + email/password. Then we enabled SSO for
> this company. Same user will now use SSO flow — does B2C create shadow users, or link with the existing user in
> Loady B2C? Also this user is already in Loady DB, with company assignments and roles — will they be relinked after
> SSO login?

## Goal

Every question above has a direct answer, backed by either a code citation (for what this repo controls) or an
explicit "unverified, needs a DEV test" flag (for what only Azure AD B2C itself controls) — not a guess either way.
Where an answer depends on a live B2C behavior this repo can't prove, there's a concrete, runnable checklist to
confirm it before BASF's real users go through this.

## Non-goals

- Redesigning how Loady resolves users at login. The investigation below concludes the existing design (lookup by
  email, not by any B2C id) already handles this scenario correctly — this is a verification exercise, not a
  redesign.
- Deciding whether to clean up dormant local B2C accounts after a domain switches to SSO (see "Open question 3") —
  flagged for your call, not decided here.

## Answers

### 1. Can existing local-account users still log in? (Heinz, part 1)

Yes for users **outside** an SSO-enabled domain — unaffected, unchanged (already covered in
`plans/2026_09_15_sso_pr9819_review_comments.md`, comment M).

For a user **on** a domain that later gets SSO enabled: no, not with their old password, by design. Once
`IsSsoEnabled = true` for their domain, the frontend's `login()` (`frontend/src/app/auth/utils/auth.utils.ts`) always
routes them through the SSO flow once `identityProviderService.resolve(email)` returns a domain hint — there's no
UI path back to the password flow for that email. Even if someone bypassed the frontend and authenticated directly
against the old local B2C flow with a still-valid password, `AuthenticateADB2CPrivateApiPolicy.IsExpectedAuthenticationFlow`
(`src/Shared/Loady.Azure.Functions/AuthenticationPolicies/AuthenticateADB2CPrivateApiPolicy.cs`) rejects it at the
backend: it compares the token's `tfp` claim against the policy expected for that domain (`SsoPolicy` when
`ssoDomain is not null`) and returns `null` — a 401 — on a mismatch. So the old local credential stops working
against Loady the moment the domain is switched, enforced server-side, not just by frontend routing convention. This
is a deliberate consequence, not a bug, and it's the one part of this that's genuinely new behavior for an existing
user — worth a one-line heads-up to the customer/Company Admin when a domain is switched, since their old bookmarked
password login will start failing.

### 2. Could the inactivity job accidentally delete these users? (Heinz, part 2)

Already answered directly in `plans/2026_09_15_sso_pr9819_review_comments.md` (comment M) — not repeated in full
here, only the conclusion: this is a real but pre-existing Microsoft Graph/B2C limitation
(`signInActivity` requiring Premium P1/P2 + `AuditLog.Read.All`, documented as unreliable for B2C specifically), not
introduced or fixed by SSO. `UserService.InactivateUsersAsync` already excludes every user on an SSO-configured
domain from the Graph-based inactivation check before doing anything (`src/Shared/Loady.Services/Domains/Shared/Services/UserService.cs:123-129`),
so once BASF's domain is `IsSsoEnabled = true`, none of their users — old local-account holders included — can be
touched by this job at all, regardless of whether Graph's sign-in tracking is reliable for them. The remaining
licensing/reliability question is orthogonal to this specific BASF scenario.

### 3. Does B2C create a shadow/duplicate user, or link accounts, when the same email switches from local to SSO?

**This is genuine Azure AD B2C platform behavior — not something this repository's code determines, and not
something I can confirm without a live test against Loady's own DEV B2C tenant.** Documented as researched-default,
flagged for verification, per your instruction.

What the public Azure AD B2C documentation says, consistently: local accounts and federated (social/enterprise OIDC)
accounts are **separate directory objects** by default, matched only by their own identifier type — a local account
by `objectId`, a federated account by `alternativeSecurityId` (issuer + subject from the external IdP) — and B2C does
**not** automatically merge or link them just because they share an email address. Merging requires an explicit
"account linking" custom policy (Identity Experience Framework), which lets a user go through a deliberate
link-my-accounts journey. Loady doesn't use this: `sso-docs.md` describes configuring the SSO flow as a **built-in**
"Sign up and sign in" user flow ("+ Recommended" checkbox), and built-in user flows don't support account linking at
all — that's a custom-policy-only capability.

So the researched default for Loady's actual setup: the first time a BASF user authenticates through the new SSO
user flow, B2C most likely creates a **new, separate B2C directory object** for that federated identity — distinct
from their pre-existing local-password B2C object, both carrying the same email. This is the "shadow user" you asked
about, and it is expected/normal B2C behavior for this configuration, not a misconfiguration.

**Why it doesn't matter to Loady:** confirmed from code, not inferred. Loady's own user lookup at authentication
(`AuthenticateADB2CPrivateApiPolicy.GetUserFromValidationResultAsync`) reads only the token's `emails` claim
(`claimsIdentity.GetEmails()`, line 61) and calls `getUserService.GetUserDtoByMailAsync(email, ...)` /
`GetUserDataByMailAsync(email, ...)` (lines 86, 95) — **never** any B2C object id, `oid`, or `sub` claim. Commit
`7fb1a9a19d` ("LOADY-14682: Switch from b2c Id to Email as Users Identity Key") deliberately removed that dependency
in preparation for SSO — its own commit message says so: *"user id is still equal to b2c user id when 'create in
b2c' is enabled. This will be changed in future when enabling SSO."* Whichever B2C directory object issued the
token, Loady only ever asks "what's the email, and do I have a user with that email" — so a second B2C object for the
same person is invisible to Loady. It neither creates a second Loady user nor requires any relinking action.

### 4. Will the existing Loady user (company assignments, roles) be relinked after SSO login?

No relinking needed or performed, because nothing was ever unlinked. Confirmed from code:

- `UserData.Id` (`src/Shared/Loady.Common/Entities/Users/UserData.cs`) is a Loady-generated Cosmos document id, not
  a B2C identifier for SSO users (per the same LOADY-14682 change above) — it is never regenerated or reassigned by
  which authentication flow the user comes through.
- Company roles live directly on that same `UserData` document (`Roles`, embedded), and `CompanyMembers` documents
  reference the user by that same `Id` (mirrored, denormalized alongside `Mail`/`FirstName`/`LastName`). Both are
  Cosmos-only — unaffected by the separate Company/Webhooks-to-SQL migration.
- Since the SSO login resolves to the exact same `UserData` document via the email lookup (point 3), every reference
  keyed on that document's `Id` — roles, company memberships — is already correct and unchanged. There is no write,
  no migration, no "relink" step, because the identity that assignments are keyed to (the Loady document) was never
  in question; only the login mechanism changed.

The one thing this *does* depend on, and the one thing worth verifying rather than assuming: that BASF's Entra
tenant, once federated through B2C's SSO flow, asserts the **exact same email string** in the token's `emails` claim
that the user's existing Loady `UserData.Mail` already holds (case differences are tolerated —
`GetUserDataByMailAsync` normalizes and has a case-insensitive fallback query, per `GetUserService.cs`). If BASF's
directory has a different email on file than what Loady has stored (a common real-world drift: old personal-looking
corporate alias vs. current one), the SSO login would resolve to *no* Loady user at all and the person would land on
the welcome/not-provisioned page instead of their existing account — not a duplicate, but a false "you're not set
up" for someone who already is. Worth a spot-check against a couple of real BASF users' stored `Mail` values before
go-live, not just the mapping config.

## Verification checklist (run before BASF's real users switch)

Not code — a DEV test using the existing test IDP (`~/loady-vm/integrations/sso-idp-tomorrowops`) and a seeded local
Loady test user, to turn "researched default" into "confirmed for our tenant":

1. Create/seed a Loady test user (invited normally, has a company + role) whose email matches a `tomorrowops`
   domain test identity, and log in once with the **local** password flow — confirms the baseline account exists
   and works today.
2. Enable SSO for that domain (`IsSsoEnabled = 1`, per `sso-docs.md`'s "Loady setup: company row" SQL) and the two
   B2C settings from `plans/2026_09_15_sso_name_from_token_claims.md` step 6 if testing name sync too, or just the
   existing minimal SSO user-flow/provider config if not.
3. Log in with the same email through the SSO flow. In the Azure Portal (B2C → Users), check whether a **second**
   user object now exists for that email (different object id, `Identities` showing the federated issuer instead of
   `emailAddress`) — confirms or refutes the shadow-object default from point 3 above for Loady's actual tenant.
4. In Loady, confirm: same company, same role, same profile — no new invite needed, nothing to re-accept. This is
   the part code analysis already gives high confidence on; this step is the belt-and-suspenders check.
5. Try logging in again with the old local password directly against the local B2C flow (bypassing the frontend,
   e.g. via a manually-constructed MSAL local-flow authority) — confirm Loady's backend rejects it with 401 per
   point 1, not a silent success.
6. Decode both tokens on jwt.ms and diff the `emails` claim value character-for-character between the local-flow
   token and the SSO-flow token, to rule out the email-drift risk in point 4.

## Superseded

`plans/2026_09_15_sso_pr9819_review_comments.md`, comment M: that plan's "Investigation notes" and reply-comment text
for M are the source material this plan was built from and remain accurate for the narrower question they cover
(inactivity job + generic "can local accounts still log in"). This plan supersedes them for anything about the
specific existing-user-migrates-to-SSO scenario; that plan's M reply comment should link here rather than duplicate
this content when you post it to the PR thread.

## Assumptions / what I could not verify

- The B2C default-behavior conclusion in point 3 is built from Microsoft's public documentation about local vs.
  federated identities and account linking, not from inspecting Loady's actual DEV B2C tenant configuration. Treat it
  as the most likely outcome, not a confirmed fact, until the verification checklist above is run.
- Whether BASF specifically (as opposed to the test IDP) has any existing local-account users who'll be affected by
  this at all — not visible from this repo. If BASF's Loady users were all created fresh for this SSO rollout with no
  prior password-based history, points 3-4 are moot for them specifically, even though they're still correct answers
  to the general question.
- I have not confirmed there are zero duplicate `UserData` documents for the same email already in the DEV/PROD
  Cosmos container today (a pre-existing data-quality risk `GetUserDataByMailAsync`'s `FirstOrDefault` masks
  silently, unrelated to SSO) — out of scope here, flagged because it would compound with point 4 if it existed.

## Risks

- If the verification checklist finds B2C *does* create a second directory object per point 3, the operational
  consequence is B2C tenant clutter (a permanently dormant local account object per migrated user), not a Loady data
  risk — worth a decision later on whether to manually disable/delete those objects, but not urgent given point 1
  already blocks them from authenticating against Loady.
- The email-drift risk in point 4 is the one failure mode that would actually surface as a support ticket ("I can't
  log in / I lost my company") rather than a silent non-issue — prioritize checklist step 6 if you can only run one
  of them before BASF goes live.
