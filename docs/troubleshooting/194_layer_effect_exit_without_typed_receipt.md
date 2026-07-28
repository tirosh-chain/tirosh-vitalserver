# Layer effect process exits without a typed receipt

## Symptom

- A bundle-owned layer effect process exits, but the next updater cannot read a
  correlated layer effect receipt.
- The update stops with `layer-effect-receipt-unavailable` or
  `layer-effect-receipt-invalid`.
- Later layers do not start. Previously successful layers may enter reverse
  rollback.

## Cause

A process exit code proves only that a process returned. It does not prove
which update, layer, executor, operation, or immutable artifact produced the
result. Likewise, a receipt with a different update ID, executor ID, operation,
or artifact digest is not evidence for the requested effect.

Treating exit code zero or an absent receipt as success would allow stale or
unrelated processes to advance the update.

## Fix direction

1. Require every release-owned effect executor to write one strict typed
   receipt.
2. Correlate the receipt with the requested update, layer, executor, apply or
   rollback operation, and artifact SHA-256.
3. Require successful receipts to contain evidence and no issue.
4. Require failed, unavailable, or unsupported receipts to contain a typed
   issue.
5. Convert an explicit adapter unavailability or invalid receipt into a
   non-successful layer outcome.
6. Stop later apply effects and roll back already successful layers in reverse
   order using only declared rollback artifacts.

Do not infer a receipt from process output, logs, filenames, or exit status.

## Prevention

Effect execution and effect evidence are separate contracts. The process
adapter owns invocation and receipt reading. Pure policy owns correlation and
outcome validity. The workflow sequences only validated outcomes and never
repairs missing evidence with a default state.
