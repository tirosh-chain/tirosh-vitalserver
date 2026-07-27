# Host Update Handoff Supervisor

host-update-handoff-supervisor is the separate Host process that consumes
durable C31 queue entries. It bridges Host bootstrap staging to the staged next
updater without importing the updater's C26 domain package.

It starts only with all three explicit inputs:

```text
host-update-handoff-supervisor \
  --configuration <absolute C56 configuration> \
  --handoff <absolute C31 queue entry> \
  --attempt-id <C57 immutable attempt id>
```

For that C31 entry it verifies the C30 path and update identity, reads C25 only
to locate and byte-verify the selected next updater, then invokes it with
fixed C28/C55/C52 arguments. It does not parse C26 or replace an absent C31,
C30, C25, binary, descriptor, or report with a default.

The process writes C57 below C56 `executionEvidenceDirectory`. A
`completion-submitted` receipt means only that the staged updater returned a
correlated C27 after its Host-local C52 request was accepted. It does not mean
the update succeeded: C29 remains the Host Agent-owned terminal fact and can
contain either a succeeded or failed C28 settlement.

If C28 already exists at the configured per-update evidence path, the
supervisor selects the updater's recovery-only `complete` command. Otherwise
it selects `execute`. Both paths remain explicit and C55/C28 idempotency is
enforced by the staged updater; the supervisor never invents layer state from
a process exit or log.

While one staged next updater is running, the supervisor reads Host Update
Operation Ownership through the C52 OS-local endpoint at the explicit C56
service poll interval. An unavailable, invalid, or mismatched ownership read
is a dispatch failure; it is never treated as “no cancellation”.

When the exact active owner reports an accepted interruption request, the
supervisor terminates the staged next-updater process tree and waits for the
direct process to terminate. macOS and Linux place the updater and every
inherited layer-effect executor in a dedicated process group. Windows creates
the updater inside a dedicated Job Object with
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; the Job is attached at process creation,
so a fast child cannot escape between start and assignment. It then submits
Host Update Interruption Confirmation
(contract C82) with the exact installation identity/revision, Update Journal
revision, interruption request ID, and typed termination evidence. Host Agent,
not the supervisor, atomically changes the Update Journal and Operation to
`interrupted`. A process error caused by a completion/interruption race is
followed by one final ownership read so the confirmation is not lost.

A direct-process-only cancellation is not valid termination evidence. The
staged updater launches release-owned layer-effect executors, so killing only
that parent can leave a Host, Guest, or container mutation running after C29
has released ownership.

An OS service starts the distinct long-running service mode with only its
absolute C56 configuration. C56 supplies servicePollIntervalMilliseconds, so
there is no hidden retry interval. Each unchanged queue entry maps to the same
automatic C57 attempt ID. A retained failed or unavailable C57 is read as
evidence and is not dispatched again merely because the service polls or
restarts.
