# Golden rootfs compose build cannot find a local package

> ID: TS-172
> Category: Packaging / Local development / Guest bootstrap
> Owner: Guest deploy compile contract
> Status: implemented

## Symptoms

Golden rootfs preparation reaches `compose-build` and fails with a BuildKit
checksum error:

```text
COPY packages/vitalserver-vitalfile /opt/vitalserver-vitalfile
failed to calculate checksum: "/packages/vitalserver-vitalfile": not found
```

The same Dockerfile builds successfully on the Host before the VM starts.

## Cause

Host Docker image compilation uses the repository root as its build context.
The rootfs smoke build uses `/mnt/tirosh/deploy` as an air-gapped build context.

The recorder recovery and Lab Dockerfiles began copying
`packages/vitalserver-vitalfile`, but that package was not listed in
`guest.deploy.include`. It was therefore available to the Host build and absent
from the Guest build context. It was also absent from
`VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS`, so later source changes would not have
invalidated an existing golden rootfs cache.

## Checks

```sh
test -f .tmp/vitalserver-vm-golden/data/deploy/packages/vitalserver-vitalfile/pyproject.toml
rg -n 'packages/vitalserver-vitalfile' config/vm-build.toml make/vm/package.mk
sed -n '1,80p' apps/vitalserver-recorder-recovery/Dockerfile
sed -n '1,80p' apps/vitalserver-lab/Dockerfile
```

The package must be present in both the staged Guest deploy and the rootfs
fingerprint input list.

## Fix

- Add `packages/vitalserver-vitalfile` to `guest.deploy.include`.
- Add the same package to `VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS`.
- Keep a repository contract test that requires both declarations.

## Prevention

- Every workspace path copied by a Guest-built Dockerfile must be an explicit
  Guest deploy input.
- Every Guest deploy source that affects the compiled disk must also be a
  golden rootfs fingerprint input.
- A successful Host Docker build does not prove that the air-gapped Guest build
  context is complete.
- Missing build material must fail as a compile-contract error and must not be
  replaced by a fallback image or an inferred path.

## Related Cases

- TS-069
- TS-107
- TS-118
- TS-120
- TS-154

## Follow-up

- 2026-07-21: The first post-timeout golden rootfs retry reached compose build
  and exposed the missing `vitalserver-vitalfile` deploy input. Added it to the
  deploy and fingerprint contracts with a focused regression test.
