# Helper stays Installing after provisioned install

## Metadata

- ID: TS-104
- Category: Runtime health / macOS Helper UI / Packaging
- Owner: Runtime operation presentation contract
- Status: active

## Symptom

After a fresh Helper install, the runtime is healthy and HTTP probes pass, but the Helper UI continues to show `Installing`.

The Runtime Control API can show this shape:

```json
{
  "runtimeState": "healthy",
  "runtimeInstallationState": "executable",
  "installStateDocument": {
    "state": "provisioned",
    "mode": "provision",
    "message": "runtime install provisioned"
  }
}
```

`/platform/operations` may also report:

```json
{
  "activeOperation": "install",
  "install": {
    "state": "loaded",
    "document": {
      "state": "provisioned"
    }
  }
}
```

## Cause

`provisioned` is an explicit install-state document meaning the host-side runtime payload was provisioned. It is not the same meaning as an install step still running.

The operation-state presentation contract treated any loaded `provisioned` install document as an active install operation. The UI gives active operations priority over runtime readiness, so a healthy runtime could still be formatted as `Installing`.

## Fix Direction

Keep the install-state document as diagnostics/export evidence only; do not promote install-state artifacts to `activeOperation=install` or Runtime Control current operation detail. Active operation must come from the explicit operation lease/API owner.

Runtime readiness and lifecycle state must then drive the UI:

- `runtimeState=initializing` displays `Initializing`
- `runtimeState=healthy` with readiness proofs displays `Healthy`
- active install is reserved for non-terminal install workflow states such as `started`, `settingsLoaded`, `stepStarted`, and `stepCompleted`

## Prevention

- Do not delete or rewrite `provisioned` as `completed` just to repair presentation.
- Do not infer install progress from the mere presence of an install-state document.
- Keep a contract test proving `provisioned` remains loaded while `activeOperation` stays `null`.
