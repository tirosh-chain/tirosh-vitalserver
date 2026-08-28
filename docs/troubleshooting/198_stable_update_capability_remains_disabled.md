# TS-198: Stable update capability remains disabled after integration

## Symptom

The Helper contains the stable bootstrap verify and apply commands, but the
macOS app, Runtime Control API, PWA, or embedded development console still
disables product update apply or describes publisher verification as
unavailable.

## Cause

The command adapter was migrated without updating the explicit presentation
capability and operator-facing contract. The old product limitation remained
hard-coded independently in several clients.

## Fix direction

Expose `canApplyBundle` from the installed Host client as an explicit supported
capability, route verification and apply through the stable bootstrap, and make
every presentation surface describe the same authenticated payload contract.
Keep an unavailable result explicit for builds whose Host client does not
provide that capability.

## Prevention

Treat a capability, its command route, its error contract, and every shipped
presentation as one vertical product slice. Integration tests must prove both
that the adapter can execute the command and that the public capability permits
the operator to reach it.
