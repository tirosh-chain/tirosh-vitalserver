# Host Update Handoff Supervisor boundary

## Purpose

The Host Agent owns update admission and settlement, but it must not execute a
future C26 specification. The `host-update-handoff-supervisor` is therefore a
separate deployment process that bridges a durable C31 handoff to the staged
next updater selected by C25.

```text
Host Agent
  C29 handoff-pending
    └─ C30 original invocation + C31 queue reference
         └─ Host Update Handoff Supervisor (C56)
              ├─ verifies C31 → C30 correlation
              ├─ verifies only C25-selected next-updater bytes
              ├─ executes next updater with fixed C28/C55/C52 paths
              └─ writes C57 dispatch attempt receipt
                   └─ completion-submitted means C27 was delivered, not update success

Staged next updater
  └─ reads C26, obtains C55, creates C28, submits C27 over C52
       └─ Host Agent atomically settles C29 and installation release
```

## Ownership

| State or effect | Owner | Boundary rule |
| --- | --- | --- |
| C29 admission, update settlement, installed release | Host Agent | C29 is the sole update-success/failure fact. |
| C31 queue and C30 path | Host bootstrapper | Publishes immutable staging/handoff references; does not run C26. |
| C56 process configuration and C57 attempt evidence | Host update handoff supervisor | In service mode scans only the declared queue at C56's explicit interval; each dispatch still names exactly one C31 and preserves missing/invalid inputs. |
| C26 planning, C55 correlation, C28 report, C27 composition | staged next updater | Owns layer ordering and never writes Host SQLite directly. |
| C55 effect result | release-declared layer effect executor | Owns just one apply/rollback result, not orchestration or Host operation state. |

## Dispatch rules

- C56 names every Host directory, C52 descriptor, bounded timeout, and the
  service poll interval. The supervisor never derives a staging root,
  loopback endpoint, report path, timeout, or retry cadence.
- A C31 must be a direct entry in the configured queue and must point to its
  own `updates/<updateId>/invocation.json`. Traversal, symlinks, stale paths,
  or an unreadable document remain C57 `failed` or `unavailable`.
- The supervisor reads C25 only to verify the selected updater identity and
  digest. It intentionally does not decode C26.
- The next updater receives no caller-provided command string or shell
  expression. Its arguments are the C30 path, C28 path, C55 directory, C52
  descriptor, and two bounded timeouts declared by C56.
- A pre-existing C28 chooses the updater's `complete` recovery command. A
  missing C28 chooses `execute`; neither case means an inferred layer state.
- C57 `completion-submitted` is not an update success label. It says only that
  the next updater returned a correlated C27 after C52 accepted the request.
  Operators read C29 for final success or failure.
- The OS-managed process uses only service mode. It maps an unchanged queue
  entry to its stable digest-derived C57 attempt ID; a retained failed or
  unavailable C57 is evidence, not permission to retry after a poll or
  process restart.

## Evidence

`test_installation_update_foundation.py` composes a signed release bundle,
lets Host Agent publish C31, then runs the separate supervisor. The test proves
C31→C30→C25 selection, fixed updater execution, C55→C28→C27, C57 publication,
and C29 settlement without reading Host SQLite. It intentionally uses fixture
layer executors; concrete container, Guest Runtime, and Host platform artifact
replacement remains a separate product delivery proof.
