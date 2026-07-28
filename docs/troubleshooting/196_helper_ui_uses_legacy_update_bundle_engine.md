# TS-196: Helper UI uses the legacy update bundle engine

## Symptom

The Helper can select an update bootstrap archive, but summary, verification, or
apply either rejects it as an old manifest bundle or invokes `apply-bundle`.

## Cause

The stable bootstrap CLI was implemented without changing the macOS control
client. The UI and Runtime Control API therefore continued to enter the legacy
`verify-bundle` and `apply-bundle` commands.

## Fix direction

Keep the public user action stable, but route its Host command adapter to:

- `verify-update-bootstrap <bundle>`
- `apply-update-bootstrap <bundle> --request-id <explicit-id>`

Read directory summaries from `bootstrap-envelope.json`. Verification and apply
must use the same stable envelope, publisher trust store, target, and complete
payload-closure checks.

## Prevention

An updater contract is not integrated until every production entry point uses
it. Tests must prove the GUI/API command adapter cannot invoke the legacy apply
command for a stable bootstrap update.
