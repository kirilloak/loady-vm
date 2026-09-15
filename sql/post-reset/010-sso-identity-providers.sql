-- Local SSO identity providers.
--
-- The seeders do not write this table, so every ld-reset leaves it empty and the SSO sign-in flow
-- has nothing to match a domain against. Applied by scripts/ld-sql.sh, which ld-reset calls.
--
-- Re-runnable, as every file here must be: ld-reset drops the databases first, but `ld-sql` against
-- a live one is the normal case and a plain INSERT would duplicate the row.

MERGE SsoIdentityProviders AS target
USING (VALUES
    ('tomorrowops.com',
     'tomorrowops',
     'https://login.microsoftonline.com/385bd049-aaa0-4d85-9bd8-d777e354c0a7/v2.0',
     1)
) AS source (Domain, DomainHint, Issuer, IsEnabled)
ON target.Domain = source.Domain
WHEN MATCHED THEN UPDATE SET
    DomainHint            = source.DomainHint,
    Issuer                = source.Issuer,
    IsEnabled             = source.IsEnabled,
    UpdatedBy             = 'dev-seed',
    UpdatedByUserName     = 'Dev Seed',
    UpdatedTime           = SYSUTCDATETIME(),
    TrueUpdatedBy         = 'dev-seed',
    TrueUpdatedByUserName = 'Dev Seed',
    TrueUpdatedTime       = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT
    (Domain, DomainHint, Issuer, IsEnabled,
     CreatedBy, CreatedByUserName, CreatedTime,
     UpdatedBy, UpdatedByUserName, UpdatedTime,
     TrueUpdatedBy, TrueUpdatedByUserName, TrueUpdatedTime)
VALUES
    (source.Domain, source.DomainHint, source.Issuer, source.IsEnabled,
     'dev-seed', 'Dev Seed', SYSUTCDATETIME(),
     'dev-seed', 'Dev Seed', SYSUTCDATETIME(),
     'dev-seed', 'Dev Seed', SYSUTCDATETIME());
GO
