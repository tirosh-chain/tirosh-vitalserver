# Update bundle integrity is mistaken for publisher authenticity

> ID: TS-188
> Category: Update / Packaging
> Owner: macOS installed Updater / Runtime Control Platform Agent
> Status: active

## Symptoms

- `verify-update-bundle`, `release-update-bundle-verify`, or
  `vitalserver-vm runtime verify-bundle` succeeds, but the 0.2.1 Helper still
  disables Apply.
- The Platform capability reports `canApplyBundle=false`.
- A direct `POST /platform/update-bundles/apply` returns:

  ```json
  {
    "code": "updateApplyUnavailable",
    "message": "This 0.2.1 build cannot apply updates because trusted publisher verification is unavailable."
  }
  ```

- A default CLI apply fails with
  `reason=trusted-publisher-verification-unavailable`.

These are expected 0.2.1 containment states. A successful integrity check must
not be reported or interpreted as trusted publisher authentication.

## Impact

- Stable 0.2.1 installations cannot apply Product Update or VM Image Update
  bundles through UI, API, or CLI.
- Bundle summary and manifest/size/checksum integrity checks remain available.
- Repeated POST or CLI attempts do not make the bundle trusted and must not
  acquire an operation lease, persist update workflow state, or stage the
  bundle as part of apply.
- Existing runtime and data are unchanged by the rejected apply.

## Cause

The 0.2.1 bundle builder writes the fixed `signature` slot as `unsigned`.
Installed verification checks manifest structure, artifact sizes, and
checksums, but no trusted publisher verification or trust-root/config contract
exists.

Previously, generic “verified” wording and an enabled apply capability could
collapse two different meanings:

- integrity: the selected bytes match the bundle manifest and checksums;
- authenticity: a trusted publisher signed those bytes.

The second state cannot be established in 0.2.1, so production apply is
fail-closed.

## Checks

Read the explicit Platform capability:

```sh
curl -sS \
  -H "X-VitalServer-Token: <token>" \
  http://127.0.0.1:18321/platform/capabilities
```

The 0.2.1 response must contain:

```json
{
  "canApplyBundle": false
}
```

An integrity check may still be run:

```sh
/usr/local/bin/vitalserver-vm runtime verify-bundle \
  /path/to/update-bundle-<channel>-<kind>-<releaseLabel>.tar.gz
```

Expected success wording states both facts:

```text
bundle integrity checked; publisher authenticity unverified
```

Do not use a successful checksum result as evidence that the publisher is
trusted.

## Actions

1. On stable installations, stop after the integrity check. Do not retry apply
   or attempt to bypass the capability with a direct POST.
2. Use a fresh signed PKG/DMG installation workflow for a supported 0.2.1
   release change.
3. For local development only, confirm the installed launcher was compiled
   with `Constants.launcherChannel == dev`, then use the explicit intent:

   ```sh
   sudo /usr/local/bin/vitalserver-vm runtime apply-bundle \
     /path/to/update-bundle-dev-<kind>-<releaseLabel>.tar.gz \
     --allow-unsigned-dev-bundle
   ```

4. Do not use the development flag on a stable or unknown installed launcher;
   it is rejected even when supplied.
5. Do not use an Updater bridge/two-phase bundle as a trust workaround. That
   route remains blocked.

## Prevention

- `RuntimeUpdateApplyTrustPolicy` authorizes apply from the installed launcher
  channel and explicit CLI intent before lease, workflow state, or staging.
- The default intent requires trusted publisher verification, which 0.2.1
  reports as unavailable.
- The development override is accepted only for an installed `dev` launcher.
- Platform capability defaults and the macOS client explicitly report
  `canApplyBundle=false`.
- Both Runtime Control apply handlers reject direct POST with typed
  `501 updateApplyUnavailable` before native command execution.
- Native UI and PWA distinguish integrity checking from publisher
  authenticity.
- Dev apply-smoke supplies the development flag; stable apply-smoke is an
  explicit fail-closed contract test that stops before `sudo`.

## Operational Notes

- Missing, unreadable, or unknown launcher channel is not treated as dev.
- Bundle channel metadata does not establish the installed launcher channel.
- The development override is intentionally unavailable to API and native
  worker composition.
- Publisher trust support requires a separate explicit contract for trusted
  identities, signature decoding/verification, trust-root ownership, failure
  reporting, and release provisioning. Operator configuration alone cannot
  enable it in 0.2.1.

## Related Cases

- [TS-027](027_update-stale-pwa-assets.md)
- [TS-035](035_update-guest-capability-contract-missing.md)
- [TS-185](185_vm-image-update-inferred-two-phase-bridge.md)
- [Update contract](../runtime/macos/update.md)

## Follow-up

- 2026-07-27: Added 0.2.1 fail-closed containment across Domain, CLI, Runtime
  Control API, native/PWA presentation, devtools apply-smoke, and documentation.
