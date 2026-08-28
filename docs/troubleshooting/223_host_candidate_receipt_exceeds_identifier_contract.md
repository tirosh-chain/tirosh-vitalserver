# Host Candidate Receipt Exceeds the Identifier Contract

> ID: TS-223
> Category: Update / Host installation manager
> Owner: macOS runtime
> Status: active

## Symptoms

Host Platform archive staging creates the immutable target slot, but the layer
receipt reports only that `manager-operation.json` is missing. The installation
operation remains in `requested`.

## Cause

The candidate receipt ID concatenated the full operation ID, `.archive.`, and a
64-character SHA-256. A valid update ID produced a 129-character receipt ID,
exceeding the Domain identifier limit of 128. Staging finished before the
candidate transition was rejected.

The layer executor did not capture the manager stderr, so the identifier error
was hidden behind the missing operation document.

## Fix Direction

- Derive the receipt ID as `host-platform-candidate.<artifact-sha256>`, whose
  length is fixed and within the Domain contract.
- Capture manager stderr and include it in the typed owner-operation failure
  when no operation document is produced.
- Keep target slots immutable; do not infer success from an existing directory.

## Prevention

Identifiers composed from caller input must have a proven maximum length.
Process-boundary failures must preserve the owner process diagnostic together
with the missing output state.

## Related Cases

- [TS-203: Update settlement outlives its installation or lease](203_update_settlement_outlives_its_installation_or_lease.md)
