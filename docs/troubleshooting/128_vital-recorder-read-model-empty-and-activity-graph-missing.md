# Vital Recorder is connected but the recorder list or packet graph does not update

## Metadata

- ID: TS-128
- Category: Runtime health / Recorder streaming / Observability
- Owner: Guest VitalDB observation pipeline / macOS Helper presentation
- Status: package verification pending

## Symptom

VitalDB Web Monitoring shows a physical Vital Recorder and its signals, while the
Helper or PWA Recorders view reports all of the following:

- `Known recorders: 0`
- `Data updated: Unknown`
- `No Vital Recorder data`
- no packet/activity graph after selecting a recorder

At the same time, `GET /runtime/recorder-ingress/status` can report one active
connection and increasing `sendDataEventsObserved` and `sendDataBytesObserved`.
Product Lab recorders can still appear because they have a separate read model.

Another form of the same user-visible failure is that the recorder row and graph
load correctly once, but the graph stops at the first displayed bucket even
though Web Monitoring continues to receive signals.

## Cause

Three independent defects have produced this symptom:

1. Packaged macOS Guest Tools and the Linux/Windows Platform Agent guest configs
   requested `http://127.0.0.1:18084/api/runtime/observations`. The Observer owns
   `GET /api/v1/observations`, so the writer received HTTP 404 and never wrote a
   `vitaldb_observation_snapshots` row to Postgres. Recorder ingress counters are
   diagnostics and must not be promoted into recorder domain state as a fallback.
2. The Observer exposed packet buckets only under `recorders[].activity.buckets`,
   while the Postgres history and chart contract consumes the explicit top-level
   `activityBuckets` collection. Recorder rows could load after fixing the URL,
   but the chart still had no canonical bucket input.
3. The macOS Helper selected-recorder chart used a query-keyed SwiftUI task that
   performed only one read. The five-second Recorders section polling refreshed
   recorder summaries but did not refresh the selected activity window. nginx
   HTTP 101 responses, recorder-ingress `send_data`, and Postgres activity
   buckets therefore continued while only the presentation snapshot stayed old.

## Checks

Compare the three owner boundaries. Do not interpret ingress counters as the
recorder read model:

```sh
curl http://127.0.0.1:18084/api/v1/observations
curl http://127.0.0.1:18330/runtime/vitaldb/recorders
curl http://127.0.0.1:18330/runtime/recorder-ingress/status
```

For an installed macOS runtime, read the same activity window twice and compare
the explicit owner values instead of treating the chart as ingress evidence:

```sh
VITALSERVER_VM_HOME='/Library/Application Support/VitalServerHelper/vm' \
  /usr/local/bin/vitalserver-vm runtime vitaldb-recorder-activity 06311eba \
  --guest-control-url http://192.168.64.2:18330
```

If `lastObservedAt` or the latest bucket count advances between reads, the Host
proxy, recorder-ingress, and Guest read model are live. A frozen chart in that
case is a presentation refresh defect.

Inside the Guest, verify the installed writer contract and service log:

```sh
grep vitaldbObserverUrl /etc/tirosh/guest-tools.toml
grep -A4 vitalDBObservation /mnt/tirosh/run/runtime-observation.json
journalctl -u tirosh-runtime-observation.service -n 200 --no-pager
```

An empty Postgres read model is reported as `VitalDB observation read model is
empty.` It is not a successful observation of zero recorders.

## Actions

- Build and install a package containing the corrected
  `/api/v1/observations` Guest configuration.
- Verify that the Observer response contains the physical recorder in `recorders`
  and canonical packet buckets in top-level `activityBuckets`.
- Wait for the periodic Guest writer to append a Postgres snapshot, then refresh
  the Recorders view and select the recorder to load its chart window.
- Install a Helper build whose selected-recorder activity task polls the same
  explicit query every five seconds and cancels when the recorder/window/bucket
  query changes or the view disappears.
- Do not manually synthesize Postgres recorder rows from ingress connection data.

## Prevention

- Packaging tests assert the exact Observer URL for macOS, Windows, and Linux
  guest configurations; suffix-only URL checks are insufficient.
- The Guest writer preserves an Observer read failure as a
  `probeErrors[source=vitalDBObservation]` diagnostic in
  `runtime-observation.json` instead of silently leaving an empty Postgres read
  model. The periodic writer retries the explicit owner read on its next cycle.
- The Observer owns and emits both recorder live activity and the explicit
  top-level chart bucket projection, including `vrcode`, bucket identity, counts,
  and first/last timestamps.
- Repository tests persist multiple snapshots and verify chronological,
  identity-based bucket deduplication.
- Missing Observer snapshots, malformed buckets, and empty loaded collections
  remain separate read states.
- Presentation tests verify that activity polling performs repeated owner reads
  and exits on task cancellation. Recorder summary polling is not considered a
  substitute for activity-window polling.

## Operational Notes

Existing installations retain the old `/etc/tirosh/guest-tools.toml` until an
updated package or Guest update installs the corrected contract. Rebuilding only
the Host UI does not repair the Guest writer configuration.

## Related Cases

- `TS-094`: Watchdog recovery was coupled to missing VitalDB observation state
- `TS-107`: a clean install can reuse stale Guest Tools rootfs content
- `TS-122`: the Postgres read-model schema can race Guest startup
- `TS-124`: schema migration can run before Postgres readiness
