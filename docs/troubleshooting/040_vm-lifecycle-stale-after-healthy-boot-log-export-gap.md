# 040 VM lifecycle stale after healthy boot and log export gap

> ID: TS-040  
> Category: Runtime health / Observability  
> Owner: macOS runtime / HostCLI / MacHostRuntimeAdapter  
> Status: implemented

## Symptoms

- Runtime status becomes `critical` with message `watchdog recovery failed: vm-lifecycle-document-stale`.
- `runtime-status.json` reports `failureReasons=["vm-lifecycle-document-stale"]` and `vmState="starting"` even though `guestHTTP`, `hostProxyHTTP`, Redis UI, and Swagger UI are `200`.
- `watchdog.out.log` shows repeated recovery plans with `vm=false proxy=false hostProxyHealth=204 hostProxyReady=200 guestReady=200`.
- Log export manifest may report permission failures such as `runtime-config.json` not copied, while the exported bundle lacks `diagnostics/runtime/vm-lifecycle.json`.

Observed field log bundle:

- Export generated at `2026-06-01T01:50:21Z`.
- Watchdog passed from `2026-06-01T01:33:59Z` through `2026-06-01T01:42:17Z`.
- Starting at `2026-06-01T01:43:20Z`, watchdog repeatedly reported only `vm-lifecycle-document-stale`.
- Guest runtime state remained fresh at `2026-06-01T01:50:17Z`, with `guestHTTP="200"` and `vmIP="192.168.64.2"`.

## Impact

- The VM and containers can be healthy while the Host reports critical runtime status.
- Watchdog does not restart VM or proxy because probes are healthy, so the user sees repeated failed recovery messages without an actionable recovery plan.
- Missing lifecycle document in log exports makes it harder to distinguish a real boot stall from an uncleared Host lifecycle state.
- Permission-denied supplemental files can make exports incomplete; the manifest must preserve source, destination, status, and error for each missing diagnostic artifact.

## Cause

HostCLI writes VM lifecycle as `.starting` before VM launch and `.bootstrapping` after the Virtualization framework starts the VM process. The lifecycle document has a boot deadline. When the guest becomes healthy, the watchdog used the healthy snapshot to write healthy runtime status but did not close the Host-owned lifecycle document as `.running`.

After the boot deadline, `RuntimeHealthChecker` correctly reports the stale lifecycle document as `vm-lifecycle-document-stale`. Because guest and host proxy checks are healthy, recovery planning produces `restartVM=false` and `restartProxy=false`, then the unchanged stale lifecycle document makes the recovered snapshot critical again.

The log export gap is separate but related operationally: the export did include runtime status and guest runtime state, but did not include the Host lifecycle document needed to confirm the stale state directly.

## Checks

```sh
jq '{status,message,updatedAt,failureReasons,vmState,guestHTTP,hostProxyHTTP}' \
  diagnostics/status/runtime-status.json

jq '{updatedAt,guestHTTP,vmIP,ready:.vitalDBObservation.ready}' \
  diagnostics/guest/runtime-state.json

rg -n 'vm-lifecycle-document-stale|runtime watchdog passed|watchdog recovery plan' \
  runtime/watchdog.out.log helper-message.log

jq '.supplementalItems[] | select(.included == false)' \
  diagnostics/export-manifest.json
```

## Actions

- If `guestHTTP=200`, `hostProxyHTTP=200`, and guest runtime-state is fresh, do not treat this as VM/container outage.
- Restarting VM/proxy is not expected to help if watchdog plan shows `vm=false proxy=false`.
- Check whether `diagnostics/runtime/vm-lifecycle.json` is present in newer exports. If present, confirm whether state stayed `starting` or `bootstrapping` past `deadlineAt`.
- For older exports without the lifecycle document, use watchdog timing: a transition from healthy watchdog passes to repeated stale lifecycle roughly 10 minutes after boot indicates this case.

## Prevention

- Watchdog must explicitly mark the Host VM lifecycle `.running` after a healthy runtime observation when the lifecycle is still `starting` or `bootstrapping`.
- Log export must include `diagnostics/runtime/vm-lifecycle.json`.
- Log export manifest supplemental entries must expose `source`, `relativeDestination`, `sourcePresent`, `included`, `status`, and `error` so permission failures remain visible.

## Operational Notes

- This case does not by itself indicate data loss or guest storage corruption.
- A concurrent VitalDB `duplicate-ip` warning can appear in the same bundle for TestKit recorders sharing a container IP. That warning is separate from the runtime critical status unless its severity is critical.
- If `guestHTTP` or `hostProxyHTTP` is not successful, use the relevant host proxy or guest bootstrap TS instead of this case.

## Related Cases

- [TS-030 runtime state inference](030_runtime-state-inference.md)
- [TS-032 macOS runtime explicit responsibility review](032_macos-runtime-explicit-responsibility-review.md)
- [TS-039 AGENTS.md fallback audit](039_agents-compliance-fallback-audit.md)

## Follow-up

- 2026-06-01: hotfix에서 healthy runtime 관측 후 Host VM lifecycle을 `.running`으로 명시 전환하고, log export에 `diagnostics/runtime/vm-lifecycle.json`과 supplemental item `status`를 추가했습니다. Focused Swift tests와 build를 통과해 문서 상태를 `implemented`로 갱신했습니다.
