# Platform Agent Verify Correlation Distinguishes MacPlatformAgent From Root CLI

> ID: TS-229
> Category: Update / Field proof
> Owner: macOS runtime
> Status: active

## Symptoms

`prove-update-bootstrap` without `--require-platform-agent-verification`
accepts a root `verify-update-bootstrap` receipt. That is not proof that
MacPlatformAgent spawned the verifier. Adding the flag fails with one of:

- `platformAgentVerificationInvocationMissing`
- `platformAgentVerificationBindingMissing`
- `platformAgentVerificationBindingInspectionFailed`
- `platformAgentVerificationBindingPermissionDenied`
- `platformAgentVerificationBindingReadFailed`
- `platformAgentVerificationBindingDecodeFailed`
- `platformAgentVerificationBindingUnexpectedPathState`
- `platformAgentVerificationBindingInvalid`
- `platformAgentVerificationBindingIdentityMismatch`
- `platformAgentVerificationEvidenceMissing`
- `platformAgentVerificationEvidenceInspectionFailed`
- `platformAgentVerificationEvidencePermissionDenied`
- `platformAgentVerificationEvidenceReadFailed`
- `platformAgentVerificationEvidenceDecodeFailed`
- `platformAgentVerificationEvidenceUnexpectedPathState`
- `platformAgentVerificationEvidenceInvalid`
- `platformAgentVerificationEvidenceIdentityMismatch`
- `platformAgentVerificationEvidenceInvoked`
- `platformAgentVerificationEvidenceSpawnFailed`
- `platformAgentVerificationEvidenceCommandFailed`
- `platformAgentVerificationEvidenceBindingMissing`
- `platformAgentVerificationEvidenceBindingInspectionFailed`
- `platformAgentVerificationEvidenceBindingPermissionDenied`
- `platformAgentVerificationEvidenceBindingReadFailed`
- `platformAgentVerificationEvidenceBindingDecodeFailed`
- `platformAgentVerificationEvidenceBindingUnexpectedPathState`
- `platformAgentVerificationEvidenceBindingInvalid`
- `platformAgentVerificationEvidenceBindingIdentityMismatch`

Ordinary apply-smoke still uses receipt-only proof and must not pass the
Platform Agent flag.

## Impact

Field proof cannot close a MacPlatformAgent verify run. A root CLI receipt at
the product-installed home is still required, but it is a different owner from
the privileged Platform Agent spawn.

## Cause

MacRuntimeControlCommandWorker is a shared OutboundAdapters actor. Two hosts
construct it:

- `MacPlatformAgentService.live()` injects
  `SystemPlatformAgentUpdateBootstrapVerificationInvoker` and serves PWA
  `POST /platform/update-bundles/verify`.
- `MacRuntimeControlEnvironment.live()` constructs the same worker without that
  invoker, so native Control Panel verify is not MacPlatformAgent-owned.

The public CLI does not invent a Platform Agent identity. When the Platform
Agent invoker is present it creates a unique verification invocation ID before
spawn, passes `--verification-invocation-id`, and persists caller-owned
evidence at:

```text
/Library/Application Support/VitalServerHelper/platform-agent-update-bootstrap-verification/<invocation-id>.json
```

The verifier binds the same ID into the existing receipt (optional field) and
writes a verifier-owned binding at:

```text
/Library/Application Support/VitalServerHelper/update-bootstrap-verification/invocations/<invocation-id>.json
```

Caller-owned states stay distinct: `invoked`, `spawnFailed`, `commandFailed`,
`bindingMissing`, `bindingInspectionFailed`, `bindingPermissionDenied`,
`bindingReadFailed`, `bindingDecodeFailed`, `bindingUnexpectedPathState`,
`bindingInvalid`, `bindingIdentityMismatch`, and `succeeded`. Path and reason
fields are detail, not the discriminator. Prove does not parse prefixes out of
a generic mismatch string. If the current binding is unreadable, that current
read error still fails first. If the binding is readable, persisted caller
evidence still reports the typed observation from the spawn. Evidence persist
failure is not recorded or returned as child-process spawn failure.

Native UI apply still generates a new `--request-id` at apply time. Verify and
apply do not share a selection identity. Same digest, clocks, logs, and file
absence are not freshness. Fresh-for-this-apply remains unproven.

## Checks

Ordinary root CLI receipt proof (apply-smoke) is unchanged:

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250
```

Platform Agent dual-owner proof is explicit:

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250 \
  --require-platform-agent-verification
```

Inspect both owners. Do not infer from process tables or launchd environment.

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/<update-id>.json"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/invocations/<invocation-id>.json"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/platform-agent-update-bootstrap-verification/<invocation-id>.json"
```

## Actions

- Invocation missing on the receipt: this verify was operator CLI, native
  Control Panel, or an older receipt. Run verify through the installed
  MacPlatformAgent API/PWA path. Do not add `--verification-invocation-id` to
  an operator CLI and call that Platform Agent proof.
- Binding missing or mismatched: the CLI did not bind the ID the Platform Agent
  passed. Re-run the Platform Agent verify. Do not copy a binding from another
  invocation.
- Evidence missing, `invoked`, `spawnFailed`, `commandFailed`, or a typed
  binding failure kind: the privileged owner did not complete a successful
  spawn correlation. Repair that state; do not edit the document into
  `succeeded`. Do not treat an evidence persist failure as a child-process
  launch failure. If the child verifier exited 0 but terminal caller evidence
  did not persist, the outer Platform Agent verify is still failed: nonzero
  exit, `executionIssue` absent, and a persist output issue. Native UI must
  not set `isVerified` from that result.
- Identity mismatch: the receipt, binding, and Platform Agent evidence do not
  share the same invocation ID, updateId, or digest.
- Permission/read/decode: repair access; do not treat absence as empty success.
- Native Control Panel verify succeeding is not MacPlatformAgent proof. PWA
  verify through the launchd Platform Agent is the privileged path.

An installed MacPlatformAgent verify field run remains unproven until an
operator records that run. This contract does not mark that run complete.

## Prevention

The MacPlatformAgent composition is the only producer of Platform Agent
verification evidence. The shared command worker must not invent that identity
when hosted by Control Panel. The public CLI must not invent it either.
`prove-update-bootstrap` requires both owners only when the command claims
Platform Agent proof.

## Related Cases

- [TS-220: Platform Agent update verifier uses root home](220_platform-agent-update-verifier-uses-root-home.md)
- [TS-228: prove-update-bootstrap rejects verify-update-bootstrap receipt](228_prove_update_bootstrap_rejects_verification_receipt.md)
