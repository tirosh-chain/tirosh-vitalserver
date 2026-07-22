# Distribution review proxy readiness test exits with empty stderr

> ID: TS-175
> Category: Packaging / Host proxy / Local development
> Owner: macOS host proxy
> Status: resolved

## Symptoms

`make internal/vm/dmg/dev` reaches `internal/vm/distribution/review` and fails in:

```text
test_proxy_run_does_not_report_started_when_proxy_readiness_fails
AssertionError: assert 'host proxy readiness failed after nginx configuration' in ''
```

The captured proxy stderr is completely empty, while the other distribution review tests pass.

## Impact

DMG review stops even though the compiled VM/rootfs artifact is not the failing boundary. The same
signal handling defect can also keep the installed Host proxy runner alive after `SIGTERM` until an
external supervisor escalates termination.

## Cause

The proxy runner used one handler for `EXIT`, `INT`, and `TERM`:

```sh
trap cleanup EXIT INT TERM
```

For a caught `SIGTERM`, Bash ran `cleanup` and then resumed the infinite proxy loop because the
handler did not exit. The test consequently waited five seconds and escalated to `SIGKILL` on every
run. Its separate three-second startup observation deadline could expire under build load before
the subprocess wrote any diagnostic, producing the empty-stderr assertion.

## Checks

Run the exact Python portion of distribution review:

```sh
uv run --frozen pytest -q \
  packages/vitalserver-devtools/tests/unit/test_delivery_makefile_contract.py \
  packages/vitalserver-devtools/tests/unit/test_docker_image_bundle.py \
  packages/vitalserver-devtools/tests/unit/test_guest_deploy_bundle.py \
  packages/vitalserver-devtools/tests/unit/test_macos_release_plans.py \
  packages/vitalserver-devtools/tests/unit/test_packaging_templates.py \
  packages/vitalserver-devtools/tests/unit/test_release_sync_contract.py \
  packages/vitalserver-devtools/tests/unit/test_upstream_vitalserver_contract.py
```

## Actions

Use separate termination and exit cleanup traps. `INT` and `TERM` must exit; the `EXIT` trap then
owns nginx cleanup exactly once:

```sh
trap cleanup EXIT
trap terminate INT TERM
```

The subprocess tests now allow a ten-second event observation budget for a loaded build host and
assert that the runner exits normally after `SIGTERM`. Re-run the failed DMG target; no rootfs
rebuild or runtime data deletion is required solely because of this review failure.

## Prevention

Packaging template tests verify that the combined non-terminating trap is absent, that termination
and cleanup traps are separate, and that the subprocess return code is zero rather than the result
of `SIGKILL`.

## Operational Notes

An empty captured stderr distinguishes this timing/termination failure from a real proxy readiness
diagnostic. When stderr contains the readiness failure message, inspect upstream and local proxy
health instead of classifying it as this case.

## Related Cases

- `TS-008`: watchdog and Host proxy readiness failures.
- `TS-028`: packaged Host proxy runtime directory dependencies.

## Follow-up

- 2026-07-22: reproduced as a passing standalone test that still took 6.13 seconds because it
  required `SIGKILL`; after the signal-contract fix, all 95 distribution review Python tests passed
  in 2.69 seconds.
