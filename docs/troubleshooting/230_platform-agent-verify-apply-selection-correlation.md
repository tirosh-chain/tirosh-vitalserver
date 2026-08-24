# Platform Agent Apply Does Not Share The Verified Bundle Selection

> ID: TS-230
> Category: Update / Field proof
> Owner: macOS runtime
> Status: active

## Symptoms

`prove-update-bootstrap --require-platform-agent-verification` accepts the
three verification owners (receipt, verifier binding, MacPlatformAgent
evidence) but the later apply used a different bundle, a reselected path, or a
newly minted `--request-id` with no Host selection identity. Ordinary
apply-smoke still proves the root CLI receipt only and must not pass the
Platform Agent flag.

Typed Host failures for this contract include:

- `platform-agent verified selection missing`
- `platform-agent verified selection stale`
- `platform-agent verified selection conflict`
- `platform-agent verified selection invalid`
- `platform-agent verified selection inspection failed`
- `platform-agent verified selection permission denied`
- `platform-agent verified selection read failed`
- `platform-agent verified selection decode failed`
- `platform-agent verified selection unexpected path state`
- `platform-agent verified selection persist failed`
- `platformAgentApplySelectionMissing`
- `platformAgentApplySelectionInvalid`
- `platformAgentApplySelectionIdentityMismatch`
- `platformAgentApplyCorrelationInspectionFailed`
- `platformAgentApplyCorrelationPermissionDenied`
- `platformAgentApplyCorrelationReadFailed`
- `platformAgentApplyCorrelationDecodeFailed`
- `platformAgentApplyCorrelationUnexpectedPathState`
- `platformAgentApplyCorrelationInvalid`
- `platformAgentSelectionUpdateMismatch`
- `platformAgentSelectionDigestMismatch`

## Impact

Field proof can close a MacPlatformAgent verify run and still not prove that
the applied bundle was that verified selection. PWA UI memory of a path, native
Control Panel `selectedBundleVerified`, same digest, clocks, and file absence
are not freshness.

## Cause

PWA `POST /platform/update-bundles/verify` and `POST /platform/update-bundles/apply`
send only a host file path. Native Control Panel stores verification in view
model memory and later apply mints an unrelated request ID. MacPlatformAgent is
the owner that accepts the PWA-selected path and receives privileged
verification success. Native Control Panel constructs
`MacRuntimeControlCommandWorker` without the Platform Agent invoker or
selection owner, so that route does not produce this correlation. Public
`apply-update-bootstrap --request-id` does not take a selection identity
argument and must not invent one.

After MacPlatformAgent verify success the owner persists one atomically
replaced store at:

```text
/Library/Application Support/VitalServerHelper/platform-agent-update-bootstrap-selection/current.json
```

The document binds `selectionId`, `verificationInvocationId`, `updateId`,
`canonicalPayloadSHA256`, and `observedBundlePath` as observation only. Domain
states are `verified`, `applyCommitted`, and `spent`. A later successful verify
replaces `verified` or `spent`. It cannot replace `applyCommitted`: that is the
in-flight/retryable apply. Bind/commit is one atomic replace of this store.
Before that persist succeeds the selection stays `verified` and retryable.
After commit the same `requestId` is resumed; a different request is stale.
Path is never identity.

MacPlatformAgent apply spawns:

```text
apply-update-bootstrap <bundle> --request-id <id> --require-platform-agent-selection
```

When the flag is set, missing store is a distinct fatal admission error.
Ordinary CLI/native omit the flag and keep nil journal correlation even if a
store file exists. Setting the flag without a valid committed Host store cannot
claim a selection. The apply child does not spend the store at journal
admission; `applyCommitted` remains until the Platform Agent worker observes
apply completion and spends, or a later same-request retry finds the journal
already admitted and spends as recovery. That keeps verify from replacing the
store while a child apply is still running after a service restart. Same
request ID after spawn/auth failure stays `applyCommitted` and is retried
through the owner.

The Platform Agent worker holds a distinct in-process guard across `await`:
`verifyInFlight` rejects apply before bind/spawn, and `applyInFlight` rejects
verify before invoke/record. Native workers without the invoker/owner do not
take this guard. It is not persisted; restart recovery is the disk
`applyCommitted` bound request ID.

## Checks

Ordinary root CLI receipt proof (apply-smoke) is unchanged and must not pass
the Platform Agent flag.

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250
```

Platform Agent verify-plus-apply proof is explicit:

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250 \
  --require-platform-agent-verification
```

Inspect the Host-owned selection store and journal field. Do not infer from
the current path, digest alone, UI memory, timestamps, or latest file.

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/platform-agent-update-bootstrap-selection/current.json"
```

## Actions

- Selection missing on PWA apply: verify through the installed MacPlatformAgent
  API/PWA path first. Native Control Panel verify/apply is a different route
  and is not this proof.
- Stale: the store is `spent` or committed to another request. Verify again
  for a new selection. Retry the same request ID only while state is
  `applyCommitted`.
- Conflict: the apply path does not match the selection's observed path. The
  path is observation, not identity. Re-verify the intended bundle.
- In flight: live Platform Agent verify rejects apply before bind (`verify in
  flight`); live apply rejects verify before invoke (`apply in flight`). Disk
  `applyCommitted` still refuses a new verify after a service restart until
  spend. Wait for the in-flight operation or inspect `boundRequestId`.
- Required selection missing on prove/apply with the Platform Agent flags:
  this apply was CLI or native, or commit did not persist. Re-run
  PWA/MacPlatformAgent verify then apply.
- Identity mismatch: journal selection, receipt, binding, and evidence do not
  share invocation ID, updateId, or digest. Re-run the Platform Agent path.
- Permission/read/decode: repair access; do not treat absence as empty success.
- Do not pass a selection ID to public CLI. The MacPlatformAgent owner produces
  and validates the correlation.

An installed MacPlatformAgent verify-then-apply field run remains unproven
until an operator records that run. This contract does not mark that run
complete.

## Prevention

MacPlatformAgent is the only producer of verified-selection and apply
correlation documents. The shared command worker must not invent that identity
when hosted by Control Panel. Public CLI must not accept a selection argument.
`prove-update-bootstrap` requires journal selection correlation only when the
command claims Platform Agent proof. Ordinary apply-smoke stays receipt-only.

## Related Cases

- [TS-229: Platform Agent verify correlation distinguishes MacPlatformAgent from root CLI](229_platform-agent-verify-correlation.md)
- [TS-228: prove-update-bootstrap rejects verify-update-bootstrap receipt](228_prove_update_bootstrap_rejects_verification_receipt.md)
