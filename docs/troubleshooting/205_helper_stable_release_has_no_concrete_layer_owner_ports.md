# TS-205: Helper stable release has no concrete layer owner ports

## Symptom

`helper-stable-update-release` can compose and sign a complete three-layer
bootstrap bundle, and the installed next updater can verify and invoke the
declared effect executables. However, the Helper repository cannot yet supply
honest production effect executors for `container`, `guest-runtime`, and
`host-platform`.

Passing wrapper scripts or the old `apply-bundle` command as the three
executors would make the bundle structurally complete while preserving the old
cross-layer mutation. A zero process exit would still not prove which layer
state changed.

## Cause

The stable updater protocol and release composer were implemented before the
current Helper product acquired three explicit state-owner command ports.

### Container owner port is missing

The current Guest update activation loads the Docker image archive from the
shared deploy directory and restarts the Compose stack as part of one broad
activation operation. It does not accept:

- an immutable image-set artifact and expected SHA-256,
- an expected active image-set identity,
- a target image-set identity,
- an `apply` or `rollback` command, and
- a durable terminal operation document identifying the active image set.

Therefore a Host effect executor cannot distinguish “images were loaded”,
“the target image set is active”, and “the previous image set was restored”
without reading Docker output or inferring state from process completion.

### Guest Runtime owner port is missing

The current Host update path replaces the shared Guest deploy tree before it
requests Guest activation. The Guest operation accepts a version and request
identifier, but it does not own immutable release slots, an active-release
identity, atomic activation, or rollback to a declared prior release.

The required Guest Runtime owner must accept a verified release archive plus
explicit expected/target release identities and return a correlated durable
terminal operation. Host-side file replacement cannot substitute for this
contract because the Guest owns Guest filesystem and service state.

### Host Platform owner port is missing

The current Helper installation is not managed by a stable, already-installed
Host Installation Manager that can stage a candidate release, verify the
active installation manifest, atomically activate the candidate, reconcile
services, and persist an update operation. The package installer and legacy
artifact replacer are not such a port.

A Host Platform executor therefore has no explicit installed owner to call and
no terminal installation operation to map into a layer receipt. Package
receipt presence, file hashes observed after copying, launchd state, and
process exit are diagnostic observations, not update success state.

### The executable protocols also differ

The Helper Swift next updater currently launches an effect executable with an
invocation-document protocol:

```text
execute --request <request.json> --receipt <receipt.json>
```

The concrete Runtime Platform layer executors use the fixed C55 argument
protocol:

```text
--protocol-version v1
--effect-executor-id <id>
--effect-configuration-path <path>
--receipt-path <path>
--update-id <id>
--layer <layer>
--operation <apply|rollback>
--artifact-path <path>
--artifact-sha256 <sha256>
```

Adapting that invocation shape alone is insufficient. Those executors depend
on Runtime Platform Guest image-set, Guest product-release, and Host
installation managers that the Helper 0.2.2 installation does not provide.

## Fix direction

Implement the state owners before publishing production Helper stable update
bundles:

1. Add a Guest Container Image Set Manager with an explicit command/read
   contract and durable operation state.
2. Add a Guest Runtime Release Manager with immutable release slots, explicit
   active-release state, apply/rollback transitions, and durable operation
   state.
3. Add an installed Host Installation Manager whose stable executable path and
   active installation manifest survive Host Platform release replacement.
4. Give each release-owned effect executor only one owner client. It must
   re-verify its artifact, send one correlated apply/rollback command, require
   the owner's terminal operation, and atomically write one strict layer
   receipt.
5. Align the Helper next updater with one fixed layer-effect invocation
   protocol, then run apply and rollback acceptance tests against the actual
   three owners.
6. Wire those real artifacts, configurations, rollback artifacts, and
   executables into `helper-stable-update-release`. Until then, the composer is
   a contract/composition tool rather than a production release target.

The Runtime Platform implementations are useful reference owners, but copying
their executables into a Helper bundle without installing their dependent
managers is invalid composition and must fail release validation.

## Prevention

- Do not wrap `apply-bundle`, package installers, shell commands, or broad
  Guest activation in a layer executor.
- Do not derive layer success from exit code, logs, file presence, Docker
  output, launchd state, or an absent error.
- Require each layer configuration to name one fixed owner endpoint and exact
  expected/target identities for both apply and rollback.
- Require an owner-authored terminal operation as the evidence behind every
  `succeeded` layer receipt.
- Keep the stable release publisher blocked until clean-install update and
  reverse-order rollback proofs exercise the production owner ports.
