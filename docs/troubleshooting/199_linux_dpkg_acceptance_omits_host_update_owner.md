# TS-199: Linux dpkg acceptance omits the Host update owner

## Symptom

The selected Linux product package installs successfully in the Docker dpkg
acceptance test, but `dpkg --remove` fails while reading
`host-agent.local.json`.

## Cause

The acceptance environment intentionally replaces systemd with an explicit
test port, so the installed Host Agent is never launched. The test nevertheless
attempted removal without providing the C80 Host Update Operation Ownership
contract that every removal admission requires.

## Fix direction

Keep product removal fail-closed. The acceptance test launches a dedicated
test-only Unix-domain-socket fixture that publishes the declared descriptor and
returns one explicit, identity-matched `available/idle` ownership observation.

## Prevention

When an acceptance environment substitutes a native service manager, it must
also provide every owner contract that the omitted service would expose.
Missing state must never be interpreted as idle merely to make packaging tests
pass.
