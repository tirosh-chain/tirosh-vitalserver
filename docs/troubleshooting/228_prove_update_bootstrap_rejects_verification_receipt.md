# prove-update-bootstrap Rejects verify-update-bootstrap Receipt

> ID: TS-228
> Category: Update / Field proof
> Owner: macOS runtime
> Status: active

## Symptoms

`prove-update-bootstrap` reaches a terminal Host update journal, then fails
before printing `update bootstrap lifecycle proof verified`. The error names
one of:

- `verificationReceiptMissing`
- `verificationReceiptInspectionFailed`
- `verificationReceiptPermissionDenied`
- `verificationReceiptReadFailed`
- `verificationReceiptDecodeFailed`
- `verificationReceiptUnexpectedPathState`
- `verificationReceiptInvalid`
- `verificationReceiptIdentityMismatch`
- `verificationReceiptRuntimeHomeMismatch`
- `verificationReceiptTrustStorePathMismatch`
- `verificationReceiptUidMismatch`
- `verificationReceiptEuidMismatch`

The Host update journal and execution report may already look terminal.

## Impact

Field apply/rollback smoke cannot close. A completed journal is not enough to
prove that a root `verify-update-bootstrap` ran against the installed VM home
for this bundle identity.

## Cause

Proof now reads the verifier-owned receipt at:

```text
/Library/Application Support/VitalServerHelper/update-bootstrap-verification/<update-id>.json
```

`verify-update-bootstrap` writes that document only after successful
verification, using the `InstalledRuntimePaths` it actually resolved. Proof reads the receipt from `InstalledRuntimePaths.defaultInstalled` and
requires that product-installed VM home, product-installed trust store,
canonical `observedAt`, and explicit root `uid=0`/`euid=0`. The proof
process `VITALSERVER_VM_HOME` cannot redefine those expectations. That is
root verifier evidence at the product-installed path, not MacPlatformAgent
caller evidence.

The receipt is keyed by `updateId` and also binds `canonicalPayloadSHA256`. A
global receipt, a receipt for another update, a replaced bundle with the same
id, a non-root verifier, or a root-home path such as
`/var/root/.tirosh/vitalserver-vm` cannot satisfy the current proof. A prior
root verify of the same digest still can; proof does not claim a fresh
invocation for this apply.

Proof does not reconstruct the home from source defaults, the current process
environment after verify exited, logs, or file absence.

## Checks

```sh
VITALSERVER_VM_HOME="/Library/Application Support/VitalServerHelper/vm" \
  /usr/local/bin/vitalserver-vm runtime prove-update-bootstrap \
  <update-id> --expect succeeded \
  --timeout-seconds 30 --poll-interval-milliseconds 250
```

Inspect the persisted owner directly. Do not infer from process tables.

```sh
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))' \
  "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/<update-id>.json"
```

Required fields are `schemaVersion`, `command=verify-update-bootstrap`,
`updateId`, `canonicalPayloadSHA256`, `resolvedRuntimeHome`, `trustStorePath`,
canonical UTC `observedAt`, `uid`, and `euid`. Installed proof expects
`uid=0` and `euid=0`. Missing, unreadable, permission-denied, decode-failed,
uid mismatch, and euid mismatch stay distinct.

## Actions

- Missing receipt: run installed `runtime verify-update-bootstrap` with
  the product-installed `VITALSERVER_VM_HOME=/Library/Application Support/VitalServerHelper/vm`
  as root for this update. apply-smoke includes that step so prove has the
  mandatory receipt; `VM_UPDATE_INSTALLED_RUNTIME_HOME` must be that exact
  path. It is root installed-CLI evidence, not Platform Agent evidence. Do
  not copy a receipt from another updateId. Do not retarget proof to a
  caller-named home.
- Runtime home mismatch: the verifier recorded a home other than
  `InstalledRuntimePaths.defaultInstalled.runtimeHome`. Fix the verify
  process so it uses the product-installed VM home; do not edit the receipt
  and do not point prove at a different `VITALSERVER_VM_HOME`.
- uid/euid mismatch: the verifier was not the required root identity. A
  non-root CLI verify cannot satisfy installed proof.
- Identity/digest mismatch: the receipt is for another update or an older
  bundle payload. Re-run verify for the current bundle. Same digest from an
  earlier root verify is accepted; that is not a fresh-apply invocation proof.
- Permission or inspection failure: the proof process cannot read the
  verifier-owned path. Repair permissions; do not treat absence as empty
  success.
- Decode/invalid contract: the document is not the current schema, or
  `observedAt` is not canonical UTC `yyyy-MM-ddTHH:mm:ssZ`. Do not add a
  compatibility fallback.

Distinguishing MacPlatformAgent from operator-run root CLI requires a future
caller-owned correlation contract. See TS-220.

## Prevention

Keep verify runtime home as an explicit persisted owner. Field proof must
consume the receipt; it must not reconstruct `VITALSERVER_VM_HOME` from
source defaults, logs, or the current service environment.

## Related Cases

- [TS-220: Platform Agent update verifier uses root home](220_platform-agent-update-verifier-uses-root-home.md)
- [TS-227: prove-update-bootstrap rejects persisted layer evidence](227_prove_update_bootstrap_rejects_persisted_layer_evidence.md)
