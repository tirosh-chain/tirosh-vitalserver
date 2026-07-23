# Distribution review rejects the PostgreSQL migration service seccomp contract

> ID: TS-180
> Category: Packaging / Guest containers
> Owner: macOS distribution review
> Status: resolved

## Symptoms

`make internal/vm/dmg/dev` reaches `internal/vm/distribution/review` and the
selected Swift suite reports one failure:

```text
GuestCommandDispatcherSupportTests
testRuntimeComposeDisablesContainerSeccompForAppleVirtualizationGuestKernel
XCTAssertEqual failed: ("12") is not equal to ("11")
```

## Cause

The Guest Compose stack added the explicit one-shot `postgres-migrate` service.
Like every other container running under the Apple Virtualization Guest kernel,
it declares `seccomp=unconfined`. The distribution-review test still expected
the previous eleven declarations and rejected the correct twelve-service
contract.

## Fix direction

Keep `security_opt: [seccomp=unconfined]` on `postgres-migrate` and update the
review contract to cover all twelve declarations. Do not remove the security
setting or bypass the selected Swift suite to make packaging continue.

## Prevention

When a Guest Compose service is added or removed, update the service inventory,
image bundle contract, ordered-start tests, and kernel security-option contract
in the same change. Run `internal/vm/distribution/review` before starting the
expensive rootfs and DMG compile stages.
