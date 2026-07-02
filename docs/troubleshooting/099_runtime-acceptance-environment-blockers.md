# 099 Runtime v2 acceptance is blocked by local environment restrictions

> ID: TS-099
> Category: Runtime v2 acceptance / Local development
> Owner: macOS runtime
> Status: active

## Symptoms

Runtime v2 review proof can pass, but full acceptance cannot complete in a restricted development sandbox.

The Swift-focused gate can fail before tests run.

```text
sandbox-exec: sandbox_apply: Operation not permitted
```

The VM smoke or acceptance gate can also fail before Runtime v2 behavior is exercised.

```text
PermissionError: [Errno 1] Operation not permitted: 'ps'
```

Docker image preparation can fail at Docker credential or network access before the VM smoke proof starts.

`make -n runtime/proof/acceptance` is not a reliable pure dry-run for this target. Recursive `$(MAKE)` entries can still enter environment-sensitive VM proof paths.

## Impact

These failures leave Runtime v2 final acceptance incomplete. A restricted-environment blocker does not prove a Runtime v2 code failure by itself because the failing boundary is the local execution environment.

The valid partial proof in a restricted sandbox is `make runtime/proof/review`. That gate covers static v1-removal proof, focused Python Runtime v2 tests, and PWA check/test/build.

## Cause

The full Runtime v2 acceptance gate depends on host capabilities that are intentionally unavailable in the restricted sandbox.

- SwiftPM package evaluation can require macOS `sandbox-exec` support.
- VM smoke can require host process inspection through `ps`.
- VM packaging/smoke can require Docker credential helper access and image pulls.
- Runtime HTTP E2E uses the same local Swift/runtime process boundary as `runtime/e2e/smoke`.

The acceptance gate is therefore environment-sensitive by design. It verifies a product runtime boundary, not only repository source code.

## Checks

Run the sandbox-safe review gate first.

```sh
make runtime/proof/review
```

Run the full acceptance gate only from a local macOS shell that has SwiftPM sandbox support, Docker credential helper access, network image pull access, and VM/process inspection permission.

```sh
make runtime/proof/acceptance
```

If the failure is one of the environment errors above, record it as an acceptance environment blocker, not as successful Runtime v2 acceptance.

## Actions

1. Use `make runtime/proof/review` as the current sandbox proof.
2. Run `make runtime/proof/swift-focused` on a non-restricted macOS host to verify focused Host-side Swift contracts and HTTP gateway behavior.
3. Run `make runtime/proof/http-e2e` on the same host to verify the Runtime Control HTTP E2E path. This target aliases `runtime/e2e/smoke`.
4. Run `make runtime/proof/smoke` with Docker credential and VM permissions available.
5. Run `make runtime/proof/acceptance` as the final gate after the focused gates pass.

Runtime v2 is not complete until the final acceptance gate passes in an environment that can actually execute the Swift, Docker, HTTP E2E, and VM smoke boundaries.

## Prevention

Keep environment blockers visible and typed. Do not replace the full acceptance gate with a narrower proof, and do not convert environment failures into success.

Keep `runtime/proof/review`, `runtime/proof/swift-focused`, `runtime/proof/http-e2e`, `runtime/proof/smoke`, and `runtime/proof/acceptance` as explicit targets so each proof boundary is clear.

## Related Cases

- `TS-070`: Golden disk가 실제 Runtime boot proof를 제공하지 않음
- `TS-082`: 배포 target이 phase별 검증 완료를 명확히 증명하지 못함
- `TS-093`: Golden runtime smoke가 `runtime-settings.json` 누락으로 manifest를 만들지 못함

## Follow-up

- 2026-07-02: Restricted sandbox에서 SwiftPM manifest evaluation이 `sandbox-exec: sandbox_apply: Operation not permitted`로 실패하는 것을 확인했습니다.
- 2026-07-02: Restricted sandbox에서 VM smoke/acceptance path가 `PermissionError: [Errno 1] Operation not permitted: 'ps'` 또는 Docker credential/network access 전 단계에서 막히는 것을 확인했습니다.
