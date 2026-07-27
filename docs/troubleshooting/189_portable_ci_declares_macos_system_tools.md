# Portable CI declares macOS system tools as test fixtures

> ID: TS-189
> Category: Packaging / Local development
> Owner: Runtime Platform test adapters
> Status: resolved

## Symptoms

- `make -C runtime-platform check` passes the earlier portable tests on macOS
  but fails on an Ubuntu runner.
- The macOS clean-Host or development-installation evidence tests report:

  ```text
  macOS clean-Host pkgutil executable is missing or not an absolute file
  ```

- The failure appears before the test's mocked command observations run.

## Impact

- The portable source and acceptance gate cannot complete on Linux.
- A valid product change cannot be merged even though the affected tests do not
  execute a native macOS command.
- This is a test-contract failure; it does not establish an installed-product
  or package failure.

## Cause

The evidence-runner tests declared `/usr/sbin/pkgutil`, `installer`,
`launchctl`, `codesign`, and `sysctl` as command-contract inputs. Production
validation correctly requires every declared executable to be an existing
absolute file. Ubuntu therefore rejected the test input before the mocked
command boundary could provide its observations.

The tests had mixed up two responsibilities:

- the test owns explicit command identities and mocked observations;
- a native acceptance environment owns real macOS command effects.

## Checks

Run the affected modules with Python 3.12 on Linux:

```sh
python -m unittest \
  tooling.tests.test_macos_clean_host_release_evidence_runner \
  tooling.tests.test_macos_development_installation_evidence_runner
```

The clean-Host module must run 13 tests and the development-installation module
must run 5 tests without a platform skip.

## Actions

1. Give each mocked command a distinct absolute executable fixture inside the
   test's temporary directory.
2. Make the fixture fail closed with a non-zero exit if it is accidentally
   executed.
3. Keep command observations at the existing mocked adapter boundary.
4. Do not weaken production executable validation or treat a missing native
   tool as an empty/default observation.

## Prevention

- Portable policy tests provide their own complete command-contract inputs.
- Tests that truly execute `pkgbuild` or `pkgutil` are explicitly Darwin-gated
  and are also required by the macOS native CI aggregate.
- A missing-tool probe must not decide whether a policy test succeeds or create
  a fallback state.

## Operational Notes

- Passing these portable tests is not clean-Host installation evidence.
- Real macOS package, service, signature, and reboot effects still require the
  matching native acceptance workflow.

## Related Cases

- [TS-082](082_distribution_verification_phase_gaps.md)
- [TS-099](099_runtime-acceptance-environment-blockers.md)

## Follow-up

- 2026-07-27: Replaced host filesystem paths with fail-closed temporary command
  fixtures and verified both evidence-runner modules on Python 3.12 Linux.
