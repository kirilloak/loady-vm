# Comment L: SSO domain storage — decoupled `SsoIdentityProvider` table

- **Source:** PR 9819 review comment L (`SqlCompany.cs`, Nelia + Heinz), tracked as "needs your call" in
  `plans/2026_09_15_sso_pr9819_review_comments.md`.
- **Constraint that changes the cost calculus:** the SSO EF migration (`20260827141726_AddSsoConfiguration`) has not
  shipped — the branch isn't merged, so you can delete/regenerate it. That removes the two costs that normally make a
  schema rework expensive (a backfill migration, a live-data compatibility window), which is why this plan proposes a
  bigger change than "just add a unique index" — the cheap fix and the correct fix now cost about the same.

## The two review points, restated

- **Nelia:** `SqlCompany.SsoEmailDomains` is a JSON array column with `HasMaxLength(2000)` and no DB constraint.
  Uniqueness is enforced only by `SqlCompanyReader.TryGetBySsoEmailDomainAsync` fetching up to 2 matches and throwing
  `InvalidOperationException` if both hit — which surfaces as a bare 401 to every user on that domain the moment a
  second company accidentally claims it, not just the misconfigured one.
- **Heinz:** a domain isn't naturally 1:1 with a Company at all — BASF SE and BASF NA can share `basf.com`. Moving the
  JSON column to a real table with a unique index on `(CompanyId, Domain)` or even a bare unique index on `Domain`
  still assumes one domain maps to at most one company, which doesn't hold for that case.

## What the code actually needs (traced, not assumed)

I read the three places that consume SSO domain configuration end-to-end:

1. `ResolveIdentityProviderQueryHandler` (pre-login `GET sso/resolve?email=`) calls
   `ISsoConfigurationService.GetEnabledSsoDomainAsync(email)`, which calls
   `ICompanyReader.TryGetBySsoEmailDomainAsync(domain)` — looked up **by domain only**, no company in scope yet.
2. `AuthenticateADB2CPrivateApiPolicy.IssuerMatches` (post-login token validation) again resolves configuration by
   email domain only, to check the token's `identityProvider` claim against the configured issuer.
3. `UserService.InactivateUsersAsync` calls `ISsoConfigurationService.GetConfiguredSsoDomainsAsync(emails)` — again
   domain-keyed, to exclude SSO users from inactivation regardless of company.

**None of the three call sites use the company at all.** Which company a user belongs to is resolved separately
(post-authentication, via the existing invitation/`CompanyMembers` mechanism — see the base SSO plan). The SSO
domain-to-provider mapping is only ever consulted as "given this email domain, which B2C provider (domain hint +
issuer) do I route/validate against" — a question that has nothing to do with company ownership. Company is the
storage location today only because that's where the base SSO plan put it, not because the check needs it.

This means Heinz's point isn't just valid, it's structural: the domain match has to resolve to exactly one provider
regardless of how many companies use that domain, because pre-login routing can't know which company the user
belongs to yet. A `(CompanyId, Domain)`-scoped unique index doesn't fix that — it just changes where the ambiguity
error is thrown.

## Recommended option: decouple `SsoIdentityProvider` from `Company` entirely

New aggregate, own table, no FK to `Companies`:

```csharp
// src/Shared/Loady.Relational.Domain/AggregateModels/SsoIdentityProviderAggregate/SqlSsoIdentityProvider.cs
public sealed class SqlSsoIdentityProvider : TrackedEntity, IAggregateRoot
{
    public const int DomainMaxLength = DomainConsts.MaxStringLength;
    public const int DomainHintMaxLength = DomainConsts.MaxStringLength;
    public const int IssuerMaxLength = DomainConsts.MaxStringLength;

    public string Domain { get; private set; }          // normalized lowercase, no leading '@'
    public string DomainHint { get; private set; }
    public string Issuer { get; private set; }
    public bool IsEnabled { get; private set; }

    // constructor + Set(...)/Enable()/Disable() mutators, same validation SqlCompany.SetSsoConfiguration has today
    // (domain hint + issuer required together, domain required, normalization rules unchanged)
}
```

`Domain` gets a unique index in `SsoIdentityProviderConfiguration : IEntityTypeConfiguration<SqlSsoIdentityProvider>`
— the database now makes a second company (or the same company twice) claiming a domain **impossible**, not just
detected at read time.

### Files touched

| File | Change |
|---|---|
| `SqlCompany.cs` | Remove `SsoEmailDomains`, `SsoDomainHint`, `SsoIssuer`, `IsSsoEnabled`, `SetSsoConfiguration`, `NormalizeSsoEmailDomains`, `ClearSsoConfiguration`, the two `SsoXMaxLength` consts, and the `ClearSsoConfiguration()` call in `ApplyDefaultSettingsIfMissing()` |
| `SqlSsoIdentityProvider.cs` (new) | New aggregate, as above |
| `SsoIdentityProviderConfiguration.cs` (new, `Loady.Relational.Infrastructure/EntityConfigurations/`) | `ToTable("SsoIdentityProviders")`, unique index on `Domain`, max-length mappings, `ConfigureTrackedEntity()` |
| `CompanyConfiguration.cs` | Remove the four `Sso*` property mappings (lines 99-111) |
| `ISsoIdentityProviderRepository.cs` (new, `Loady.Relational.Domain/Repositories/`) | `IRepository<SqlSsoIdentityProvider>` plus `Task<SqlSsoIdentityProvider?> TryGetByDomainAsync(string domain, ...)` |
| `SsoIdentityProviderRepository.cs` (new, `Loady.Relational.Infrastructure/Repositories/`) | Implementation, same shape as `WebhookRepository.cs` |
| `IUnitOfWork.cs` | Add `ISsoIdentityProviderRepository SsoIdentityProviders { get; }` |
| `ICompanyReader.cs` / `SqlCompanyReader.cs` | Remove `TryGetBySsoEmailDomainAsync` and `GetConfiguredSsoEmailDomainsAsync` — no longer company concerns |
| `ISsoConfigurationService` impl (`SsoConfigurationService.cs`) | Depend on `IUnitOfWork` (or a new `ISsoIdentityProviderReader` if you want the same reader-abstraction layering `ICompanyReader` uses) instead of `ICompanyReader`. `GetEnabledSsoDomainAsync`/`IsSsoDomainConfiguredAsync`/`GetConfiguredSsoDomainsAsync` logic is otherwise unchanged — same normalization, same "malformed email = false/null, not throw" contract, same "domain claimed twice" test intent (now enforced by the unique index, so that test changes from "seed two companies, expect throw" to "the second insert violates the unique index") |
| `SqlCompanyBuilder.cs` | Remove `WithSsoConfiguration`; add `A.SsoIdentityProvider` builder (new `SqlSsoIdentityProviderBuilder : SimpleSqlBuilder<SqlSsoIdentityProvider>`) |
| `CompanySsoConfigurationModelTests.cs` | Rewrite as `SsoIdentityProviderModelTests.cs` — same shape, asserts on the new entity/config instead of `SqlCompany` |
| `SsoConfigurationServiceTests.cs` | Update `GivenCompanyWithSsoConfiguration` → `GivenSsoIdentityProvider`, built via `A.SsoIdentityProvider`, not `A.Company`. The "domain claimed by two companies" test becomes "domain claimed by two providers" and its assertion changes from `ShouldThrowAsync<InvalidOperationException>` to whatever the unique-index violation surfaces as (EF `DbUpdateException`) — reframe it as a **build-time** rejection when creating the second row, not a **read-time** one |
| Existing migration `20260827141726_AddSsoConfiguration*` + its `Designer.cs` entry in `AppDbContextModelSnapshot.cs` | Deleted, not edited — you regenerate with `dotnet ef migrations add`, per `backend/AGENTS.md` (I don't run this) |

### Open question this plan does not resolve

`ApplyDefaultSettingsIfMissing()` today forbids SSO configuration on a managed business partner
(`ClearSsoConfiguration()` on every `SetManagedBy`/`SetGeneralSettings` call, and `SetSsoConfiguration` throws if
`IsBusinessPartner`). That rule doesn't have anywhere to live once SSO configuration isn't a `Company` property at
all — nothing in the new model prevents a domain match from working for a business partner's users, because the
lookup never touches `Company` in the first place. There's no command handler yet that sets `SqlSsoIdentityProvider`
rows (today it's builder/tests only, confirmed by grep — no API endpoint touches these fields), so this doesn't break
anything *today*, but whoever writes that admin/backoffice endpoint later needs to re-decide and re-implement this
rule at that layer (reject configuring a domain that's only ever used by business-partner emails, or don't — that's
a product call, not one this plan can make). Flagging it now so it isn't silently dropped.

## Alternative (not recommended): `CompanySsoEmailDomains` child table, still 1:1 domain:company

Keep `SsoDomainHint`/`SsoIssuer`/`IsSsoEnabled` on `SqlCompany`, replace the JSON `SsoEmailDomains` column with a
child table (`Id`, `CompanyId` FK, `Domain` unique-indexed) — closest existing pattern in this codebase
(`WebhookConfiguration`/`SiteConfiguration`: FK + unique-index child). This fixes Nelia's DB-constraint complaint but
**not** Heinz's: the unique index is still keyed on `Domain` alone (or `(CompanyId, Domain)`, which is weaker and
still lets BASF SE and BASF NA both claim `basf.com` with different, conflicting providers — exactly the ambiguity
Nelia's own bug report is about). I'm not proposing this: given migrations are free to nuke right now, it costs
almost the same as the decoupled option above but leaves the actual bug in place for the next reviewer to reopen.

## Verify

- `dotnet build Loady.slnx`
- `dotnet test src/Shared/Loady.Services.IntegrationTests --filter "FullyQualifiedName~SsoConfigurationServiceTests|FullyQualifiedName~SsoIdentityProviderModelTests"`
- `dotnet test src/Shared/Loady.Services.UnitTests --filter "FullyQualifiedName~ResolveIdentityProviderQueryValidatorTests"` (unaffected, but touches the same feature)
- You run `dotnet ef migrations add AddSsoIdentityProviders` after deleting the old migration + its snapshot entry.

## Recommendation

Implement the decoupled `SsoIdentityProvider` option. It answers both Nelia's and Heinz's comments with one change,
matches what the three real call sites actually need (domain-only lookup), and — because there's no shipped migration
or live data to protect — costs roughly the same in file-touch terms as the narrower fix that leaves Heinz's point
unaddressed.
