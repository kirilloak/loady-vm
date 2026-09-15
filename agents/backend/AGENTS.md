# Loady Backend

.NET 10 Azure Functions (isolated worker) | CosmosDB + SQL Server | CQRS + MediatR + FluentValidation

## Commands

```bash
dotnet build Loady.slnx                                    # Build
dotnet test Loady.slnx                                     # Test all
dotnet test <project> --filter "FullyQualifiedName~Name"   # Test specific
```

## Formatting

- Add a blank line before and after large code blocks, and separate adjacent large code blocks with a blank line for readability.

## Repository Layout

This backend lives in the `loady-one/backend` subfolder. Terraform infrastructure lives in the sibling
`loady-one/infra` subfolder (`../infra` from backend). Infra pipelines and scripts should run from
`$(Build.SourcesDirectory)/infra`, not from the backend folder or the repository root.

## Azure Pipelines

- Use standard `job` entries. Do not use `deployment` jobs or add Azure DevOps `environment`, `strategy`, `runOnce`,
  or `deploy` wrappers unless environment-specific Azure DevOps features are explicitly required.

---

## Project Map

### `src/Domains/` - Azure Function Apps

| Project                             | Role                                                                                                                                                                                                                                                                            |
|-------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Loady.Backend.Api`                 | **Main internal API.** Feature folders at root: Companies, Sites, Products, LoadingPoints, UnloadingPoints, Lanes, Tenders, RequirementProfiles, ProductClusters, PreProducts, Factsheets, Webhooks, Users, Dictionaries, PreLoadRestrictions, AppConfigurations |
| `Loady.Backoffice.Api`              | Admin: dictionaries, subscriptions, admin users, translation indexing                                                                                                                                                                                                           |
| `Loady.DriverView.Api`              | Read-only driver view                                                                                                                                                                                                                                                           |
| `Loady.Events.Api`                  | CosmosDB change feed processor                                                                                                                                                                                                                                                  |
| `Loady.Imports.Api`                 | CSV imports: products, sites, lanes, loading points, requirement profiles, business partners, pre-loading restrictions, product assignments, logistics requirements                                                                                                             |
| `Loady.Loady2Share.Api`             | External sharing of loading/unloading data                                                                                                                                                                                                                                      |
| `Loady.Reports.Api`                 | Scheduled reports (timer trigger)                                                                                                                                                                                                                                               |
| `Loady.Public.Api`                  | Public: logistics requirements, yard                                                                                                                                                                                                                                            |
| `Loady.Public.BusinessPartners.Api` | Public: business partner CRUD                                                                                                                                                                                                                                                   |
| `Loady.Public.Lanes.Api`            | Public: lane CRUD                                                                                                                                                                                                                                                               |
| `Loady.Public.LoadingPoints.Api`    | Public: loading point CRUD                                                                                                                                                                                                                                                      |
| `Loady.Public.Products.Api`         | Public: product CRUD (versioned V1)                                                                                                                                                                                                                                             |
| `Loady.Public.UnloadingPoints.Api`  | Public: unloading point CRUD                                                                                                                                                                                                                                                    |

### `src/Shared/` - Core Libraries

| Project                           | Role                                                                                                                                       |
|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `Loady.Common`                    | Shared kernel: entities, DTOs, enums, consts, interfaces, helpers, extensions, validators, serializers, mappers, exceptions, search models |
| `Loady.Services`                  | **All business logic.** MediatR handlers + validators in `Domains/{Scope}/{Feature}/`                                                      |
| `Loady.Infrastructure`            | CosmosDB repos, ADB2C auth, Azure Blob, SendGrid, API Management, authorization                                                            |
| `Loady.Azure.Functions`           | Shared function base classes, middleware, auth/authz policies, health checks, host config                                                  |
| `Loady.Relational.Domain`         | SQL entities (`Sql{Name}.cs`), repository interfaces                                                                                       |
| `Loady.Relational.Infrastructure` | EF Core DbContext, entity configs, migrations, SQL search                                                                                  |
| `Loady.Relational.Application`    | SQL application services (Companies, Webhooks)                                                                                             |
| `Loady.BaseTesting`               | Test builders (`A.Lane`, `A.Product`...), fakers, test doubles, helpers                                                                    |
| `Loady.Services.IntegrationTests` | Integration tests for handlers                                                                                                             |
| `Loady.Services.UnitTests`        | Unit tests for services                                                                                                                    |
| `Loady.Common.UnitTests`          | Unit tests for common                                                                                                                      |
| `Loady.Azure.Functions.UnitTests` | Unit tests for shared function code                                                                                                        |

### `src/Packages/` - Infrastructure

`Loady.Infrastructure.AzureQueue` | `Loady.Infrastructure.AzureSearch` | `Loady.Infrastructure.MsGraph`

### `src/Seeder/` - Data Seeding

`Loady.Seeder` (Cosmos setup + migrations) | `Loady.TestDataSeeder` | `Loady.AzureSearchBuilder` |
`Loady.DictionaryTranslationGenerator`

### `Loady.Tools/` - Standalone utilities (solution: `Loady.Tools.slnx`)

`Loady.Tools.CopyData` | `Loady.Tools.MetricsReader` | `Loady.Tools.TranslationsCleaner`

---

## Request Flow

```
Azure Function
  -> req.DeserializeRequestBody<Command>()
  -> mediator.Send(command)
  -> CommandHandler
  -> validator.ThrowIfInvalidAsync(command)
  -> Repository / Provider
  -> DB
  -> req.CreateResponseAsync(result, statusCode)
```

## File Locations

| What                         | Path                                                                              |
|------------------------------|-----------------------------------------------------------------------------------|
| Function endpoints (Backend) | `src/Domains/Loady.Backend.Api/{Feature}/{Action}.cs`                             |
| Function endpoints (others)  | `src/Domains/Loady.{Domain}.Api/Functions/{Feature}.cs`                           |
| Commands/Queries             | `Loady.Services/Domains/{Scope}/{Feature}/Commands/{Action}Command.cs`            |
| Handlers                     | `Loady.Services/Domains/{Scope}/{Feature}/{Action}CommandHandler.cs`              |
| Validators                   | `Loady.Services/Domains/{Scope}/{Feature}/Validators/{Action}CommandValidator.cs` |
| DTOs                         | `Loady.Common/Dtos/{Feature}/`                                                    |
| Cosmos entities              | `Loady.Common/Entities/{Feature}/{Name}.cs`                                       |
| SQL entities                 | `Loady.Relational.Domain/AggregateModels/{Name}Aggregate/Sql{Name}.cs`            |
| SQL EF configs               | `Loady.Relational.Infrastructure/EntityConfigurations/{Name}Configuration.cs`     |
| Enums                        | `Loady.Common/Enums/`                                                             |
| Consts                       | `Loady.Common/Consts/DomainConsts.cs`                                             |
| Exceptions                   | `Loady.Common/Exceptions/` (T4-generated from `Exceptions.tt`)                    |
| Test builders                | `Loady.BaseTesting/Builders/`                                                     |
| Integration tests            | `Loady.Services.IntegrationTests/Domains/{Feature}/`                              |
| Event handlers               | `Loady.Services/Domains/Shared/EventHandlers/`                                    |
| Shared readers               | `Loady.Services/Domains/Shared/Readers/`                                          |
| Shared providers             | `Loady.Services/Domains/Shared/Providers/`                                        |
| Company mappers              | `Loady.Services/Domains/Shared/Mappers/CompanyMapper.cs`                          |

All paths under `src/Shared/` unless noted otherwise.

**Scopes:** `Private` (internal APIs) | `Public` (external/partner APIs) | `Shared` (cross-cutting: event handlers,
readers, providers, mappers, services)

## Generated OpenAPI Files

Never modify generated OpenAPI documents under `apim/apis/`, including `apim/apis/backend/Backend.API.openapi.json`.
The developer always regenerates these files. Change only the source contracts and report that OpenAPI regeneration is
required; agents must not edit or regenerate the generated documents.

---

## Data Layer

### Entity Storage

| Entity                       | DB      | Access                                                                                  |
|------------------------------|---------|-----------------------------------------------------------------------------------------|
| Company                      | **SQL** | `ICompanyReader` (reads), `ICompanyProvider` (writes). **Never `IRepository<Company>`** |
| Submodules                   | **SQL** | `IUnitOfWork.Submodule*` repos                                                          |
| Site, Product, Lane, Tender  | Cosmos  | `IRepository<T>`                                                                        |
| LoadingPoint, UnloadingPoint | Cosmos  | `IRepository<T>`                                                                        |
| RequirementProfile           | Cosmos  | `IRepository<T>`                                                                        |

### SQL Server

**Aggregates:** Company, Site, Product, ProductCluster, LoadingPoint, UnloadingPoint, LoadingPointProduct,
UnloadingPointProduct, LoadingPointProductCluster, UnloadingPointProductCluster, Submodule, Webhook

**`IUnitOfWork` repos:** `Companies`, `CarrierAssignments`, `Products`, `Sites`, `Webhooks`, `LoadingPoints`, `UnloadingPoints`,
`ProductClusters`, `LoadingPointProducts`, `UnloadingPointProducts`, `LoadingPointProductClusters`,
`UnloadingPointProductClusters`, `SubmoduleProducts`, `SubmoduleSites`, `SubmoduleLoadingPoints`,
`SubmoduleUnloadingPoints`, `SubmoduleProductClusters`, `SubmoduleLoadingPointProducts`,
`SubmoduleUnloadingPointProducts`, `SubmoduleLoadingPointProductClusters`, `SubmoduleUnloadingPointProductClusters`,
`PreLoadRestrictionsChecks`, `PreLoadRestrictionsRequests`

**Rules:**

- `SaveChangesAsync()` must be called explicitly (auto-populates `CreatedBy`/`UpdatedBy` from `IHttpRequestService`)
- Use `GetAll()` for read-only queries; it returns entities with `AsNoTracking()`
- Use `GetAllWriteable()` when entities will be modified; it returns tracked entities
- Do not call repository `Update()` for entities loaded by tracked queries (`GetAllWriteable()`, `GetByIdAsync()`,
  `GetByLoadyIdAsync()`). Modify them and call `SaveChangesAsync()`; use `Update()` only when intentionally attaching a
  detached entity
- New entity configs must call `builder.ConfigureTrackedEntity()` and `builder.ToTable("PluralName")`
- Do not create/modify/run EF migration files. Edit entities and configs only. User runs `dotnet ef migrations add`

### CosmosDB

`IRepository<T>` from IEvangelist.Azure.CosmosRepository NuGet.

**Active containers:** Events, Indexers, Sites, Products, PreProducts, LoadingPoints, UnloadingPoints,
LoadingPointProducts, UnloadingPointProducts, RequirementProfiles, Lanes, Tenders, Users, CompanyMembers, Notifications,
AppConfigurations, Dictionaries, HistoricalData, Leases, Migrations, ProductPreLoadingRestrictions

**Deprecated containers:** Companies (migrated to SQL), Webhooks (migrated to SQL)

**CosmosDB migrations:** `src/Shared/Loady.Infrastructure/CosmosDb/Migrations/`, executed by seeder.

---

## Company (SQL)

**Never use `IRepository<Company>`.** Use `ICompanyReader` (reads) and `ICompanyProvider` (writes).

**SqlCompany fields:** `Id` (long, SQL identity) | `LoadyId` (string, business ID) | `CountryCode`, `City`, `Street`,
`PostalCode`, `AdditionalAddress` | `Phone` (not `Telephone`), `Email`, `Fax` | `Type` (enum) | `ReportNumberOf*`

**Id vs LoadyId:** Use `LoadyId` for most operations. Use `Id` only for SQL FKs (e.g.,
`WebhookBuilder.WithCompanyId(company.Id)`).

**Mappers** (`using Loady.Services.Domains.Shared.Mappers`): `GetCompanyContactAddressInformationDto()`,
`ToBusinessPartnerAddressDto()`, `GetMainInformation()`

**Business Partner:** Company with `ManagedById` set. `ManagedByName` via SQL JOIN, not stored. Always filter by
`ManagedById` to exclude from company queries.

## Submodules (SQL)

Via `IUnitOfWork.Submodule*` repos. **Company-level:** entity ID is null. **Entity-level:** entity ID is set.

### Submodule Levels

Each company-level submodule row has a `SubmoduleLevel`:

- `Company` - template for entities created by the company itself
- `BusinessPartner` - template for entities created by the company's business partners
- `Entity` - actual submodule on a specific entity instance

**Both Company and BusinessPartner level rows live on the Company** (where `ShouldHaveSubmodules() == true`). Business
Partners do NOT get their own submodule rows - they inherit from the Company's BusinessPartner-level template.

### Who Gets Submodules

`ShouldHaveSubmodules()` (on Cosmos `Company` and on `SqlCompany` via `CompanyMapper`) = non-BP AND
`Type != CompanyType.Carrier` (Carrier only). This is the create/sync path.

The `EnsureSubmoduleExistsForAllCompaniesAsync` backfill uses a narrower filter: `ManagedById == null` AND `Type`
not in `SqlCompany.CarrierCompanyTypes` (Carrier + LogisticsServiceProviderCompany). LSP companies therefore get
submodules on create/sync but are skipped by the all-companies backfill.

### EntityType.AssignedProduct is Virtual

There is no `SubmoduleAssignedProduct` table. `AssignedProduct` is a virtual entity type that fans out to **both**
`SubmoduleLoadingPointProducts` AND `SubmoduleUnloadingPointProducts` tables. All AssignedProduct submodules are
duplicated into both tables regardless of their `SubmoduleContext`. The context (`ForLoadingPoints`/
`ForUnloadingPoints`) is stored as metadata on the row, not used for routing.

Similarly, `EntityType.ProductCluster` fans out to three tables: `SubmoduleProductClusters`,
`SubmoduleLoadingPointProductClusters`, `SubmoduleUnloadingPointProductClusters`.

### Submodule Templates (Static)

System-level submodule definitions live in `Loady.Common/Consts/SubmoduleTemplates.cs` as static `SubmodulePolicy`
lists per entity type (Site, LoadingPoint, UnloadingPoint, Product, AssignedProduct).
`SubmoduleTemplateMapper` (in `Loady.Services`) converts these to `CompanyModuleConfiguration` for use in
`ModuleConfigurationService`.

These lists are also the authoritative set of legal module/submodule pairs per entity type. `SubmoduleTemplates`
exposes `IsSupported`, `TryParse` and `ThrowIfUnsupported` over them, used by `SiteProvider` and
`SqlSiteModuleConfigurationMapper` to reject unknown pairs. Adding a `SubmodulePolicy` entry therefore widens
validation as well as the defaults. `IsSupported` matches on `(ModuleId, SubmoduleId)` only and ignores `Subtype` and
`Context`.

### Adding New Submodules

1. Add enum value to `SubmoduleId.cs`
2. Add const info to `SubmoduleConsts.cs`
3. Add `SubmodulePolicy` entry to `SubmoduleTemplates.cs` (with correct subtype/context)
4. Add case to `SubmoduleTemplates.GetSubmoduleConstInfo()` (and `GetModuleConstInfo()` for a new module)
5. Create a migration (`BaseMigration` subclass in `Loady.Infrastructure/CosmosDb/Migrations/`) to backfill existing
   companies using `ISqlSyncService.EnsureSubmoduleExistsForAllCompaniesAsync()`
6. New companies get the submodule automatically via `CreateCompanyCommand` -> `SqlCompanyProvider` ->
   `SyncCompanyLevelSubmodulesAsync`

---

## Cosmos Migrations (Mandatory Rules)

`BaseMigration` subclasses in `Loady.Infrastructure/CosmosDb/Migrations/` are auto-discovered via assembly scan (
`AddMigrations`). No manual registration needed. They run via `Loady.Seeder` and track execution in a CosmosDB
`Migrations` container (idempotent by class name). Despite the name "CosmosDb Migrations", they can also modify SQL via
`IUnitOfWork`.

### Class Structure

```csharp
// Naming: M{YYYY}_{MM}_{DD}_{HHMM}_{Description}.cs
// Namespace: Loady.Infrastructure.CosmosDb.Migrations (active) or .Archive (completed)
public sealed class M2026_04_08_1000_MigrateTankStateToGeneralCleaningInfo(
    IRepositoryService repositoryService,
    IRepository<Migration> migrationRepository)
    : BaseMigration(migrationRepository)
{
    protected override async Task UpOperation() { /* ... */ }
}
```

- Primary constructor with DI. `IRepository<Migration> migrationRepository` is always required (base class param).
- New or touched migrations use `public sealed class`. Single `protected override async Task UpOperation()` entry point.
- Summary XML doc with Jira link: `/// <summary>https://loady-venture.atlassian.net/browse/LOADY-XXXXX</summary>`
- Existing violations are not precedent. Follow this section for new or modified migrations.

### Common DI Dependencies

| Dependency                                                             | When to use                                                                                                |
|------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| `IRepositoryService repositoryService`                                 | Paginated Cosmos queries (most migrations)                                                                 |
| `IRepository<T>`                                                       | Full entity CRUD (`UpdateAsync`, `CreateAsync`, `DeleteAsync`)                                             |
| `ISqlSyncService sqlSyncService`                                       | Submodule backfill, company sync                                                                           |
| `IUnitOfWork unitOfWork` (from `Loady.Relational.Domain.Repositories`) | Direct SQL operations. Import as `using SqlUnitOfWork = Loady.Relational.Domain.Repositories.IUnitOfWork;` |
| `IDeleteService deleteService`                                         | Cascading entity deletion                                                                                  |
| `IRepository<Event> eventsRepository`                                  | Trigger downstream processing via events                                                                   |
| `ISearchable<T>`                                                       | Search index cleanup                                                                                       |

### Data Access

Always use `IRepositoryService` methods for reading Cosmos data. Never use direct container API for reads (
`container.GetItemQueryIterator`, `container.ReadItemAsync`, etc.) or `IRepository<T>` for paginated reads in
migrations. Patches still use the callback `container` passed by `IRepositoryService`.

- `repositoryService.PaginateAsync<T>()` - iterate entities with deserialization. Use `select` to load only needed
  fields. Use `where` with `QueryDefinition` to filter at Cosmos level. Never load all entities and filter in-memory.
- `repositoryService.PaginateIdsOnlyAsync<T>()` - iterate IDs only, for patch-only operations where entity data is not
  needed.
- When migrating module/submodule configuration from Cosmos to SQL, preserve both levels of state. Cosmos can store
  visibility on the module even when every child submodule has default/false visibility; SQL module visibility may be
  derived only from child `Submodule*` rows. Add an explicit fallback/mapping so a visible Cosmos module does not become
  hidden in SQL.

### Migration Patterns (Pick the Right One)

### Rename / Move Migrations

- For real Cosmos JSON renames, prefer `PatchOperation.Move(oldPath, newPath)` over copy/set+remove. It preserves the
  existing value exactly and avoids leaving stale duplicate fields.
- If a branch-only migration has not been deployed or recorded in the `Migrations` container, merge related fixes into
  that same migration instead of adding follow-up part files. Add a new migration only after the previous one may have
  run outside the branch.
- Before moving fields, preflight collisions with `IS_DEFINED(oldPath) AND IS_DEFINED(newPath)` and throw
  `InvalidOperationException`; do not silently overwrite one side.
- When renaming nested fields together with a parent object, check collisions for both legacy-parent and new-parent
  paths, then move the parent first and nested fields second.
- For high-volume renames, combine all patch operations for the same document in one request where possible. Avoid
  separate full-container passes for parent rename, nested rename, and related config rename when one projected pass can
  build conditional operations.
- Do not rely on current domain models to inspect removed JSON properties. Use lightweight migration projection entities
  with computed `IS_DEFINED(...) AS propertyName` selects, and pass the original discriminator with `type: "Product"` /
  `type: "PreProduct"` etc. when the projection class name differs from stored `c.type`.
- Keep reruns idempotent with `IS_DEFINED(oldPath) AND NOT IS_DEFINED(newPath)` filters. A canceled migration usually
  reruns from the class start, so every operation must skip already-migrated documents instead of assuming progress
  state.
- Bind parameters on every `QueryDefinition` that contains placeholders. This is easy to miss when query strings move
  into helper methods.
- Limit data migrations to the exact containers named by the ticket. Do not include history, ePR/ePLR history,
  Public API contracts, or archived migrations unless explicitly in scope.
- For CSV/header renames, keep tests that prove legacy headers are rejected when backward compatibility is not required;
  old header strings in those tests are intentional and should not be mechanically renamed.

**Pattern 1: Cosmos Patch** (most common - rename, move, add fields)

```csharp
await repositoryService.PaginateAsync<T>(
    select: "c.id, c.fieldNeeded",
    where: new QueryDefinition("ARRAY_LENGTH(c.field) > 0"),
    callback: async (entity, container, cancellationToken) =>
    {
        var operations = new List<PatchOperation>
        {
            PatchOperation.Set("/newPath", entity.OldPath),
        };
        await container.PatchItemAsync<T>(
            entity.Id, new PartitionKey(entity.Id),
            operations, cancellationToken: cancellationToken);
        Console.WriteLine($"{typeof(T).Name} {entity.Id} updated");
    });
```

**Pattern 2: IDs-Only Patch** (when entity data is not needed, only applying static values)

```csharp
var patchOperations = new PatchOperation[]
{
    PatchOperation.Add("/newField", value),
};
await repositoryService.PaginateIdsOnlyAsync<T>(
    where: new QueryDefinition("c.siteId = @SiteId").WithParameter("@SiteId", siteId),
    callback: async (entityId, container, cancellationToken) =>
    {
        await container.PatchItemAsync<T>(
            entityId, new PartitionKey(entityId),
            patchOperations, cancellationToken: cancellationToken);
    });
```

**Pattern 3: Full Entity Update** (when complex in-memory transformations are needed)

```csharp
await repositoryService.PaginateAsync<T>(
    where: new QueryDefinition("filter"),
    callback: async (entity, _, cancellationToken) =>
    {
        entity.Property = newValue;
        await repository.UpdateAsync(entity, changeUpdatedBy: false, cancellationToken);
        Console.WriteLine($"Updated {entity.Id}");
    });
```

Always pass `changeUpdatedBy: false` to avoid modifying audit fields during migration.

**Pattern 4: Submodule Backfill** (adding new submodules to all companies)

```csharp
protected override async Task UpOperation()
{
    var levels = new[] { SubmoduleLevel.Company, SubmoduleLevel.BusinessPartner };
    var rows = levels.Select(level => new DesiredSubmoduleRow(
        Level: level, ModuleId: ModuleId.X, SubmoduleId: SubmoduleId.Y,
        IsSystem: false, IsMandatory: false, IsDefault: true,
        IsPublic: false, IsShared: false,
        Subtype: SubmoduleSubtype.None, Context: null)).ToList();
    var inserted = await sqlSyncService.EnsureSubmoduleExistsForAllCompaniesAsync(
        EntityType.Product, rows, cancellationToken: CancellationToken.None);
    Console.WriteLine($"Inserted {inserted} submodule rows");
}
```

**Pattern 5: SQL-Only** (when migration only touches SQL tables)

```csharp
protected override async Task UpOperation()
{
    var rows = await unitOfWork.SubmoduleProducts.GetAll()
        .Where(x => condition).ToListAsync();
    foreach (var row in rows) unitOfWork.SubmoduleProducts.Delete(row);
    if (rows.Count > 0) await unitOfWork.SaveChangesAsync();
    Console.WriteLine($"Deleted {rows.Count} rows");
}
```

**Pattern 6: Event Trigger** (trigger downstream processing for existing entities)

```csharp
await repositoryService.PaginateAsync<T>(
    select: "c.id, c.relevantField",
    where: new QueryDefinition("filter"),
    callback: async (entity, container, cancellationToken) =>
    {
        await eventsRepository.CreateAsync(new Event
        {
            EventType = EventType.SomeEvent,
            EntityId = entity.Id,
            NewValue = value,
        }, cancellationToken);
        Console.WriteLine($"Event created for {entity.Id}");
        await Task.Delay(100, cancellationToken);
    });
```

**Pattern 7: Delete Entities** (via `IDeleteService` for cascading or `IRepository.DeleteAsync` for direct)

```csharp
// Cascading delete (deletes related entities, search index entries, etc.)
await deleteService.DeleteLaneAsync(laneId);

// Direct delete + search index cleanup
await repository.DeleteAsync(entity);
await searchable.DeleteDocumentsAsync(idsToDelete);
```

### Multi-Entity Type Processing

For multiple entity types, use a generic method with type constraints (`where T : BaseEntity, IRelevantInterface`).
**Factsheet requires separate handling** - it embeds Site, UnloadingPoint, and UnloadingPointProduct with prefixed patch
paths: `/unloadingPointProduct/...`, `/site/...`, `/unloadingPoint/...`.

### Stand-in Entities for Deleted/Renamed Properties

When a C# property has been removed from the model but still exists in Cosmos JSON, define a lightweight stand-in entity
class inside the migration file. The stand-in must have `[Container(DomainConsts.XxxContainerName)]` and extend
`BaseEntity` so `PaginateAsync<T>` resolves the correct Cosmos container. Add only the properties being read/migrated -
Cosmos silently ignores extra JSON fields. Never use raw JSON parsing (`JObject`, `GetItemQueryIterator<JObject>`).

**Critical: type discriminator.** `RepositoryService` filters by `c.type = '{typeof(TEntity).Name}'`. When using a
stand-in entity like `MigrationProduct`, the query becomes `c.type = 'MigrationProduct'` which matches nothing. Always
pass the original entity type name explicitly: `type: "Product"`.

**Every auto-property must have an explicit default value** (`= string.Empty;`, `= new();`, `= null;`, `= [];`). The
setter is only invoked by Cosmos deserialization, so Sonar's S3459 ("unassigned auto-property") and S1144 ("unused
private set accessor") fire on any property without an initializer - including nullable value types like `decimal?` and
`TemperatureUnit?`. Assign `= null` explicitly on nullable properties even though it is redundant at runtime.

```csharp
[Container(DomainConsts.ProductContainerName)]
private sealed class MigrationProduct : BaseEntity
{
    public string CompanyId { get; set; } = string.Empty;
    public MigrationCleaningRequirements CleaningRequirements { get; set; } = new();
}

private sealed record MigrationCleaningRequirements
{
    public MigrationOldSubmodule RequiredEquipmentState { get; set; } = new();
    public MigrationNewSubmodule GeneralCleaningInfo { get; set; } = new();
    public decimal? MinValue { get; set; } = null;
    public TemperatureUnit? Unit { get; set; } = null;
}
```

### Patching

- Use `PatchOperation.Set()`, `PatchOperation.Remove()`, `PatchOperation.Add()` etc.
- Call `container.PatchItemAsync<T>()` from the callback (container is passed as 2nd callback arg).
- For >10 operations, use `BaseMigration.PatchAsync<T>(container, id, operations)` which batches in groups of 10.
- PartitionKey is always the entity ID: `new PartitionKey(entity.Id)`.
- Build patch operations conditionally - only patch if changes are actually needed.

### Rate Limiting

Use `await Task.Delay(ms, cancellationToken)` between operations when deliberately protecting production Cosmos from
downstream side effects or RU spikes. Do not add fixed per-document delays to high-volume, time-boxed key-shape
migrations unless the RU budget has been measured and requires throttling:

- `50-200ms` between individual patches (typical)
- `500ms` for event creation (to avoid overwhelming downstream processors)
- `2000ms` between entity type batches (when doing broad updates)

### Logging

Use `Console.WriteLine`, not `ILogger`. For small/manual migrations, log each entity ID processed, skip reasons, and a
summary with counts. For high-volume migrations, do not log per document; log every N processed entities plus final
totals per entity type/pass. Prefixes: `[SKIP]`, `[CREATED]`, `[FAILED]`. Log start/end per entity type in multi-entity
migrations.

---

## SqlSyncService

`ISqlSyncService` (interface in `Loady.Common`) / `SqlSyncService` (impl in `Loady.Services`) handles Cosmos-to-SQL
sync. Key methods:

- `SyncCompanyAsync` - full company sync from Cosmos entity
- `SyncCompanyLevelSubmodulesAsync` - full sync of all company-level submodules from Cosmos config (creates, updates,
  deletes)
- `EnsureCompanyLevelSubmodulesExistAsync` - idempotent insert-only for specific submodules on one SQL company
- `EnsureSubmoduleExistsForAllCompaniesAsync` - idempotent insert-only for specific submodules across all eligible
  companies (used by migrations to backfill new submodules)

## Project Dependency Constraint

`Loady.Infrastructure` references `Loady.Common` but NOT `Loady.Services`. Migrations in `Loady.Infrastructure` can use
`ISqlSyncService`, `SubmodulePolicy` and `SubmoduleTemplates` (all in `Loady.Common`), but not
`SubmoduleTemplateMapper` or `SubmoduleRowReader` (both in `Loady.Services`).

Use `SubmoduleTemplates` in a migration only for validation and parsing (`TryParse`, `IsSupported`,
`ThrowIfUnsupported`), as `M2026_05_28_1000_MigrateSitesToSqlServer` does. Do NOT derive backfill data from
`GetTemplateForEntityType()`. Build `DesiredSubmoduleRow` values explicitly instead, as in Pattern 4 above. A migration
must stay pinned to the intent it had when written; deriving rows from the live template list means a later template
change silently alters what an already-recorded migration does on rerun.

---

## Code Patterns

### Error Handling

On data integrity issues (e.g., missing module/submodule config, broken entity references), always throw (
`InvalidOperationException`) instead of silently returning null or skipping. Fail fast to surface problems early.

### New Azure Function

```csharp
public class ProductCreate(IMediator mediator)
{
    [Function("ProductCreate")]
    public async Task<HttpResponseData> ProductCreateAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "POST", Route = "products")]
        HttpRequestData req, CancellationToken cancellationToken)
    {
        var command = req.DeserializeRequestBody<CreateProductCommand>();
        command.CompanyId = req.GetCompanyIdFromHeader();
        var result = await mediator.Send(command, cancellationToken);
        return await req.CreateResponseAsync(result, HttpStatusCode.Created, cancellationToken);
    }
}
```

### New Command + Handler

```csharp
// Commands/{Action}Command.cs
public sealed class CreateProductCommand : IRequest<ProductDto> { ... }

// {Action}CommandHandler.cs
internal sealed class CreateProductCommandHandler(
    IRepository<Product> productRepository,
    ICompanyReader companyReader,
    IValidator<CreateProductCommand> validator)
    : IRequestHandler<CreateProductCommand, ProductDto>
{
    public async Task<ProductDto> Handle(CreateProductCommand request, CancellationToken cancellationToken)
    {
        await validator.ThrowIfInvalidAsync(request, cancellationToken);
        // ...
    }
}
```

### New Validator

```csharp
// Validators/{Action}CommandValidator.cs
public class CreateProductCommandValidator : BaseDictionaryValidator<CreateProductCommand>
{
    public CreateProductCommandValidator(IDictionaryService dictionaryService) : base(dictionaryService)
    {
        RuleFor(x => x.Name).NotEmptyWithCharacterRestrictionAndCustomCode(min, max);
    }
}
```

**Error codes alias:** `using E = Loady.Common.Errors;` then use `E.Error.UnacceptableValue`, `E.Error.NotFound`, etc.
Custom validation extensions (e.g. `MustWithCustomCode`) accept `ErrorCode` which implicitly converts to `string`.

### Exceptions

Domain-specific exception classes are generated from `Loady.Common/Exceptions/Exceptions.tt` into
`Exceptions.Designer.cs`. Do not add separate `*Exception.cs` files for new `ErrorCode` entries; add the error code and
regenerate the T4 output instead. Key types:

- `NotFoundException.ThrowIf(condition, propertyName)` - for missing entities
- `BadRequestException` - for FluentValidation failures (thrown by `validator.ThrowIfInvalidAsync()`)
- `BadRequestAggregateException` - for aggregated business rule errors (multiple errors collected manually)
- `ConflictException` - for uniqueness violations
- Domain-specific: `CompanyNotExistsException`, `SiteNotExistsException`, `ProductNotExistsException`, etc.

**Public API validation:** handlers call `validator.ThrowIfInvalidAsync(payload)` which throws `BadRequestException`.
Use `Should.ThrowAsync<BadRequestException>(act)` in tests, NOT `BadRequestAggregateException`.

---

## ePRL / PreProduct Fallback

- ePRL checks PLR first; only when no PLR match exists does it search system `PreProduct`.
- PreProduct lookup uses exact name/synonym/trade-name matching after ePRL normalization, plus exact CAS/EC set matching.
- A found PreProduct enriches the second ePRL check with synonyms, trade names, CAS, EC, and group attributes.
- Multiple PreProduct matches rank by `NumberOfWords desc`, `CreatedTime desc`, then `Id asc`.

---

## Testing

After any code change, run the related unit and integration tests that may be affected before considering the task done.
Use `dotnet test <project> --filter "FullyQualifiedName~TestClassName"` to run specific tests. Run integration tests
for handler/domain/persistence behavior. If local SQL/Cosmos/Azurite or another dependency is unavailable, state exactly
what was not verified.

- Do not add tests whose only purpose is to assert that a static dictionary seed contains a newly added constant in
  expected dictionaries. Test consuming behavior or serialization instead.

### Base Classes

| Class                          | Extends  | Use For                                    |
|--------------------------------|----------|--------------------------------------------|
| `SimpleIntegrationTests`       | -        | `CreateCompany()`, repos, `CurrentUser`    |
| `MediatorIntegrationTests`     | Simple   | `SendRequest()` for commands               |
| `WebhookIntegrationTests`      | Mediator | Webhooks with WireMock                     |
| `EventHandlerIntegrationTests` | Simple   | Event handlers with `IEventHandlerService` |

### Integration Test Style

- Command/query handler tests extend `MediatorIntegrationTests`, not `BaseIntegrationTests`
- Service, repository, parser, and infrastructure tests use `SimpleIntegrationTests` or the nearest existing specialized
  base when that matches the local pattern
- Shared setup in `override async Task InitializeAsync()`, not in each test method
- Use `SendRequest()` / `SendRequestThrowException<T>()`, not `SendCommandAsync()`
- Structure test body with `// Given`, `// When`, `// Then` comments
- Inline arrange/act/assert directly in test methods - no private helper methods like `TheRequestIsSent()` or
  `TheResponseContainsTheExpectedProperties()`
- Store shared state (company, entity under test) in `private` fields, not `protected`
- Use builders from `Loady.BaseTesting/Builders/` (`A.Lane`, `A.Tender`, `A.Product`, etc.) to set up entities - prefer
  builder fluent methods (e.g. `A.Lane.WithCompanyFrom(company).WithTenderId(id)`) over setting properties directly
- Before adding test-local data generators, check `Loady.BaseTesting` helpers/fakers first; use
  `SpecialNumberHelper.GenerateRandomCasNumber()` and `GenerateRandomEcNumber()` for valid CAS/EC numbers
- Use `.BuildAndSave(Repository)` to create and persist entities in one step:
  `_tender = await A.Tender.WithCompany(company).BuildAndSave(TenderRepository);`
- Use repositories already resolved in `SimpleIntegrationTests` (e.g. `TenderRepository`, `LaneRepository`,
  `EventRepository`, `SiteRepository`, `ProductRepository`) - do not call `GetService<IRepository<T>>()` or
  `GetRepository<T>()` when a field already exists
- For repository types not pre-resolved in `SimpleIntegrationTests`, resolve once in a private field via
  `GetRepository<T>()` in `InitializeAsync()` or at the top of the test - do not call `GetRepository<T>()` inline
  multiple times in the same test

### Setup Pattern

```csharp
var businessPartner = await CreateCompany(managedById: company.LoadyId);
company.Email = "test@example.com";
company.CountryCode = "DE";
await UnitOfWork.SaveChangesAsync();
```

### EF Change Tracker

Do not use `Fixture.ClearChangeTracker()` unless a test actually fails with an EF tracking conflict. Most read paths use
`AsNoTracking()`, so clearing is rarely needed. Only add it when you have a confirmed `InvalidOperationException` from
duplicate tracking.

### Builders

```csharp
// SqlCompany object:
A.RequirementProfile.WithCompanyFrom(company)
A.Lane.WithCompanyFrom(company)

// String LoadyId:
A.Product.WithCompanyId(company.LoadyId)
A.Site.WithCompanyId(company.LoadyId)

// Long Id (SQL FK):
A.Webhook.WithCompanyId(company.Id)
```

---

## Banned APIs

| Banned                                       | Use Instead                                  |
|----------------------------------------------|----------------------------------------------|
| `DateTime.Now` / `DateTimeOffset.Now`        | `.UtcNow`                                    |
| `StringComparison.InvariantCulture`          | `Ordinal`                                    |
| `Tuple<>`                                    | `ValueTuple`                                 |
| `JsonConvert.DeserializeObject`              | `DeserializerHelper.DeserializeObject`       |
| `Math.Round` without `MidpointRounding`      | Always specify                               |
| `Enum.TryParse` without `ignoreCase`         | Always specify                               |
| `IRepository<Company>`                       | `ICompanyReader` / `ICompanyProvider`        |
| `ArgumentNullException` for missing entities | `NotFoundException.ThrowIf(condition, name)` |

## Terminology

- **Company** = top-level entity (the owner). **Business Partner** = child entity managed by a Company (`ManagedById`
  set).
- Never use "parent company" - use **Company** when referring to the top-level entity that owns Business Partners.

## Style

- Primary constructors: `class Foo(IDep dep)` | `internal sealed class` for handlers
- `_field` | `I` prefix | File-scoped namespaces | `var` | Braces required | 4 spaces
- Always use `var` with explicit `new`: `var x = new Foo(...)` instead of target-typed `Foo x = new(...)`
- Analyzers: Meziantou, SonarAnalyzer, StyleCop
- Human-readable code. No special symbols in comments. Never use em dashes (`—`) - use standard dashes or words instead
- Avoid null-forgiving (`!`) in new production logic. It is allowed for EF navigation properties, options/DTOs
  initialized by the framework, and test fields when matching existing patterns. Use explicit null checks in executable
  code.
- Prefer the project `IsNullOrWhiteSpace()` extension over `string.IsNullOrWhiteSpace(...)`; write negation as
  `!value.IsNullOrWhiteSpace()`.
- `<summary>` XML docs on interfaces and command properties; `//` only in implementations
- CosmosDB: `id` (lowercase) | SQL: `Id` (PascalCase)
- One validator per file. Never combine multiple validator classes in the same file

---

## Local Dev

Auth: `LocalhostAuthenticationMiddleware.cs` with `x-user-id` header

### Process Cleanup

- Stop background processes, servers, and tool sessions started by the agent when they are no longer needed; no user
  confirmation is required.
- Ask before stopping a process that predates the task, belongs to the user, or has uncertain ownership.
- Before stopping anything, resolve the exact process and avoid broad name-based termination commands.

### Local DB Access

Read-only by default. Never run destructive queries without explicit user approval.

**SQL Server** (`sqlcmd` context `loady` pre-configured, local dev credentials only):

```bash
sqlcmd query "SELECT * FROM Companies WHERE LoadyId = 'xxx'" --database loady
```

`Server=localhost,1433;Database=loady;User Id=sa;Password=Passw0rd!;TrustServerCertificate=True;`

**Redis:**

```bash
redis-cli -h 127.0.0.1 -p 6379
```

**CosmosDB emulator** (database: `Loady`, default emulator key):

`AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==`

- Query via REST: `https://localhost:8081/dbs/Loady/colls/{Container}/docs`

**Azurite** (Blob + Queue, default emulator key):

- Blob: `http://127.0.0.1:10000/devstoreaccount1` | Queue: `http://127.0.0.1:10001/devstoreaccount1`
- `UseDevelopmentStorage=true`
- Key: `Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==`

---

## Version Control

Branch: `type/LOADY-123-short-desc` | Commit: `LOADY-123: Description` | PR: `type(LOADY-123): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## Plans

Store in `backend/plans/YYYY_MM_DD_{plan_name}.md`. Get user confirmation before code
modifications.

That directory is invisible to this repository and is never committed here: it is excluded locally
and copied out to the founder's own repository once a minute, so a plan survives the machine. Write
plans there and nowhere else, and do not copy them anywhere.
