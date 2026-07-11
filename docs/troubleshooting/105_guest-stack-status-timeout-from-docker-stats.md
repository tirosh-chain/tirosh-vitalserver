# Guest stack status times out on docker stats

## Metadata

- ID: TS-105
- Category: Runtime health / Guest containers / macOS Helper UI
- Owner: Guest Control stack status observation
- Status: active

## Symptom

The Helper shows product HTTP endpoints as reachable, but `Guest product services` reports:

```text
guest control API request failed url=http://<vm-ip>:18330/runtime/stack reason=The request timed out.
```

Diagnostics can show:

```text
Runtime state: Degraded
Failure reasons: guest-service-observation-read-failed-guest_control_API_request_failed_url_http_<vm-ip>_18330_v1_stack_status
```

Direct probes can show `/ready` responding while `/runtime/stack` takes longer than the Host read timeout.

## Cause

`/runtime/stack` includes product service states and optional resource metrics. Container memory metrics were collected with:

```text
docker stats --no-stream --format '{{json .}}'
```

That optional probe had a 5 second timeout, matching the Host Guest Control read timeout. When Docker stats was slow, the entire stack status request could exceed the Host timeout even though product services were healthy.

## Fix Direction

Keep product service state explicit, but bound optional resource metrics to a shorter budget.

Container memory should not wait for `docker stats --no-stream`. Guest Control now reads Docker inspect metadata for the container PID and then reads the container memory cgroup files. If Docker inspect itself fails, times out, or returns invalid JSON, return stack status without container memory and include a `probeErrors` entry such as `docker inspect memory`.

If a specific container has no readable memory cgroup, keep that container's
`memory` field missing without adding a probe warning. In that case Docker and
the product service state were observed; only the optional memory metric was not
available.

The Host must continue to surface failed Guest Control reads, but Guest Control should avoid letting optional metrics consume the whole status endpoint budget.

When `/runtime/stack` returns `state=loaded`, Host `RuntimeStatus` preserves optional stack probe failures in `guestStackProbeErrors`. UI can show that evidence as a warning row without turning healthy product services into a service-read failure.

## Prevention

- Do not infer product service state from HTTP reachability.
- Do not hide Guest Control read failures in the UI.
- Keep optional resource probes shorter than the Host endpoint timeout.
- Preserve probe failures as explicit `probeErrors` instead of converting them into empty success.
- Preserve Host-facing optional probe evidence as `guestStackProbeErrors`; do not promote it to `guestServicesReadError` or a runtime failure reason.

## Follow-up

- 2026-07-11: Linux installed acceptance on a TCG-emulated x86_64 machine
  exceeded a 60-second `/runtime/stack` request budget while preserving explicit
  failure. The Linux installer now supplies a 120-second timeout for this
  expensive acceptance read; the Runtime Provider's separate lifecycle
  deadline remains 180 seconds.
