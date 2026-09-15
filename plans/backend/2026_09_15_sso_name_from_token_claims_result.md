# Result: Populate first/last name from the SSO token

Plan: `plans/2026_09_15_sso_name_from_token_claims.md`
Status: IN PROGRESS

## Files changed

(updated as work proceeds)

## Manual actions for the founder

- B2C portal configuration (per plan step 6) — not part of this change, must be done per environment/customer.
- Terraform apply for `~/loady-vm/integrations/sso-idp-tomorrowops` (private repo, separate commit/apply flow) — out of
  scope for this backend checkout.

## Notes

- Confirmed `UserService.UpdateUserProfileAsync` does **not** validate internally — `UserProfile.cs`'s
  `UserUpdateProfileAsync` endpoint calls `validator.ThrowIfInvalidAsync(payload)` before calling the service. The
  query handler added in step 4 therefore injects `IValidator<UpdateUserProfileDto>` and calls
  `ThrowIfInvalidAsync` itself before calling the service, catching only `BadRequestException` (the type
  `ThrowIfInvalidAsync` actually throws) rather than `BadRequestAggregateException`, which this path never produces.
- `ICurrentUserAccessor.TryGetSsoNameClaims` mirrors `FunctionContextExtensions.TryGetSsoNameClaims`'s non-blank
  contract exactly.

## Verification

(updated as work proceeds)
