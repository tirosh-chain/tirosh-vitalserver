# Container update had no explicit image-set owner

> ID: TS-207
> Category: Update / Guest state ownership
> Owner: Guest Container Image Set Manager
> Status: resolved at contract and state-owner boundary

## Symptom

- A container layer update can report that an image archive was loaded or that
  a Compose command exited successfully, but it cannot name the image set that
  is currently active.
- Concurrent or stale update requests can replace container images without
  proving which prior image-set identity they expected.
- Host update code has no typed way to distinguish an accepted command from a
  running, succeeded, failed, or unavailable container mutation.
- Rollback success is inferred from process output instead of being authored by
  the Guest component that owns Docker and Compose state.

## Cause

The old Guest activation operation combined shared-directory replacement,
Docker image loading, and stack restart. It accepted a product version rather
than an immutable image-set identity and digest. No durable Guest state owner
recorded the current image set or compared an update request with that state.

This made the Host depend on external symptoms. A zero exit code could mean
that commands ran, but not that the requested set became current. Missing
output could also be mistaken for an empty or successful state.

## Fix direction

Guest Control now exposes a dedicated Container Image Set Manager boundary:

- every image set has one immutable `identity` and SHA-256 `digest`;
- the Guest SQLite control store owns the explicit current identity;
- reads return `available` with the complete image set or `unavailable` with a
  typed failure;
- `apply` and `rollback` require `expectedCurrentIdentity` and a complete target
  image set;
- command acceptance performs an atomic compare-and-swap and persists a
  `pending` operation;
- durable operation states keep `pending`, `running`, `succeeded`, `failed`,
  and `unavailable` distinct;
- only a valid `running -> succeeded` owner transition changes the current
  image-set identity;
- reusing one identity with another digest is rejected.

The macOS Helper consumes this state only through its
`RuntimeContainerImageSetGateway` application port and Guest Control HTTP
adapter. It does not inspect Docker, Compose, logs, or Guest files.

This slice deliberately does not implement the container effect executor. An
accepted command remains `pending` until a future Guest executor explicitly
records `running` and a terminal outcome. The API does not fabricate
completion from HTTP acceptance or process exit.

Existing control databases are upgraded from schema revision `0001` to `0002`.
The migration creates image-set identity, current-state, and operation tables;
it does not invent a current image set. Installation or an explicit reviewed
migration must provision that initial identity and digest.

## Prevention

- Let the Guest component that mutates Docker/Compose state own the current
  image-set document and terminal operation.
- Require expected and target identities at every apply and rollback boundary.
- Do not derive current image state from loaded archives, container names,
  Compose output, logs, filenames, or absence of errors.
- Do not turn a missing current identity into an empty image set. Report it as
  `unavailable` until installation explicitly provisions it.
- A layer effect receipt may claim success only after it reads the correlated
  owner-authored `succeeded` operation and verifies the target is current.
