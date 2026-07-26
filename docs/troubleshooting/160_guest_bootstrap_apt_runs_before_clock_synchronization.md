# Guest bootstrap runs APT before its clock is synchronized

> ID: TS-160  
> Category: Guest bootstrap / Packaging  
> Owner: Guest Product bootstrap volume (C39/C40)  
> Status: active

## Symptom

A release package can compose and the VZ Guest can reach `multi-user.target`,
but the first cloud-init bootstrap fails before the Guest Product starts. The
serial console contains a message like:

```text
E: Release file for ... InRelease is not valid yet (invalid for another 513d ...)
cloud-init ... scripts_user failed
```

This is distinct from a network failure: the repository is reachable, but the
Guest's source-image clock is older than the repository metadata.

## Cause

The original C40 bootstrap installed Chrony with `apt-get update` followed by
`apt-get install chrony`. A cloud-image snapshot can boot with the date it had
when it was built. In the reproduced Ubuntu Noble image, that date was February
2025 while the selected repository metadata was from July 2026. APT correctly
rejected metadata that appeared to be in the future.

Chrony could not solve this ordering problem because it was installed only
after APT had already rejected the request. Disabling APT's validity checks or
treating the source-image clock as good enough would hide a failed dependency
as a successful bootstrap.

## Checks

Before installation, use the VZ serial-console evidence from the release smoke
to distinguish the failure from boot-disk or repository connectivity issues:

```text
Release file ... is not valid yet
cloud-init ... scripts_user failed
```

Inspect the selected C39 configuration. A time-enabled bootstrap must declare
all three pre-package values in addition to the long-lived Chrony package:

```json
{
  "prePackageSynchronizationServiceName": "systemd-timesyncd.service",
  "prePackageSynchronizationProbeExecutablePath": "/usr/bin/timedatectl",
  "prePackageSynchronizationTimeoutSeconds": 120
}
```

## Fix direction

C40 first restarts the declared source-image `systemd-timesyncd.service` and
waits until `/usr/bin/timedatectl show --property=NTPSynchronized --value`
returns `yes`. Only then does it execute APT and install/start Chrony. The
timeout is part of the C39/C40 contract, so an unavailable initial time source
is a visible bootstrap failure.

Do not reuse a package release workspace built before this change. Recompose a
new C40 artifact and package, then run the VZ first-boot smoke through
cloud-init completion before installing on a clean Host.

## Prevention

- Treat initial source-image clock synchronization and long-lived Guest time
  authority as separate responsibilities.
- Keep the service name, probe executable, and timeout explicit C39/C40
  contract values; do not discover an image daemon from a shell probe.
- Never bypass or relax APT repository-validity checks to work around an
  unsynchronized clock.
- Require actual first-boot cloud-init evidence in addition to VZ controller
  `running` and package-composition receipts.

## Related cases

- [TS-005: golden rootfs APT release-file time error](005_apt-release-file-time-error.md)
- [TS-070: Golden Disk Runtime Boot Proof Gap](070_golden-disk-runtime-boot-proof-gap.md)
- [TS-159: C43 root-only disk assembly drops the boot partitions](159_guest_boot_disk_loses_boot_and_efi_partitions.md)
