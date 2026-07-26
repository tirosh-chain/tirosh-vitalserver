# Guest Runtime Disk Provisioning Boundary

## Problem and decision

C35/C34 outputs identify immutable release bytes. `guest-root` has a writable
Guest storage role, so a VM that attaches that file will normally modify it
while Linux boots. Treating the same path as both a release artifact and a
long-lived VM disk mixes two owners and makes a release digest cease to be
true after ordinary runtime activity.

C32 already declares the Host-owned provisioning boundary that must run before
an installed VM is constructed:

```text
C34 GuestRootStorageReleaseArtifact (immutable release input)
  → GuestRuntimeDiskProvisioner (Host effect adapter)
  → GuestRuntimeDiskWorkspace (Host-persistent runtime location)
  → C32 MacOSVirtualMachineConfiguration attaches only the runtime disk
  → Linux Guest owns post-boot filesystem writes
```

`GuestRootStorageReleaseArtifact` is an identity-verified input. It is not a
runtime disk, a state store, or a mutable volume. `GuestRuntimeDiskWorkspace`
is Host-owned deployment state: it records the explicit path, the release
artifact identity used to create it, and its provisioning outcome. It is not
Guest Runtime SQLite state and it must not infer a usable disk from a filename
or an existing directory.

## Responsibilities

| Component | Owns | Must do | Must not do |
| --- | --- | --- | --- |
| C35/C34 release build | `GuestRootStorageReleaseArtifact` identity | publish immutable bytes and digest | boot or mutate the root artifact |
| `GuestRuntimeDiskProvisioner` | copy/provision effect | verify source identity; create one runtime disk atomically when a guard permits | overwrite an existing runtime disk as an implicit update/retry action |
| `ProvisionedMacOSVirtualMachineFactory` | Host provisioning/composition boundary | provision from C32, then construct the VZ controller from the declared runtime attachment | construct a VM from an unprovisioned or unverified runtime disk |
| Host Agent application workflow | VM lifecycle command/result | request a supervisor start and surface its typed outcome | infer workspace readiness from a path or from a boot log |
| C32 author | VM attachment and provisioning configuration | name immutable release input and provisioned runtime disk explicitly | name the release artifact as a writable attachment |
| Linux Guest | guest root bytes after boot | write its own filesystem through the attached runtime disk | write release artifact bytes |
| package/update workflow | migration policy | choose explicit keep, replace, migrate, or reject decision | let installer payload overwrite runtime state implicitly |

## Required rules

1. The release source digest is verified before a provision effect. A missing,
   changed, unreadable, or non-regular source is a typed failed/unavailable
   outcome; it is never copied as a best effort.
2. Provisioning writes a new temporary disk and publishes it atomically. A
   partial copy cannot become a C32 attachment.
3. An existing workspace is not implicitly replaced. The caller must issue an
   explicit lifecycle/update decision that states whether its disk is retained,
   migrated, replaced, or the operation is rejected.
4. Boot smoke uses a run-scoped workspace with the same provisioner rules. It
   does not attach a C35/C34 release file directly.
5. Package verification still verifies immutable payload correspondence. C24
   installation/update evidence additionally proves provisioning and the chosen
   persistent-disk policy.

## Local diagnostic evidence

The 2026-07-18 macOS ARM64 diagnostic smoke used an ad-hoc-entitled copy of
`macos-virtual-machine-supervisor`, a C32 document whose immutable release
paths and `GuestRuntimeDiskWorkspace` paths were distinct, and an otherwise
unchanged C35/C34 artifact set. It observed the following facts in order:

1. `GuestRuntimeDiskProvisioner` verified the C34 `guest-root` identity and
   published a separate 2,062,548,992-byte runtime disk plus its matching
   receipt.
2. A second Supervisor construction retained that workspace only after receipt
   verification, then returned C21 `start` with `observedState=running`.
3. The Host-owned boot console reached `cloud-init.target`,
   `multi-user.target`, `serial-getty@hvc0`, and the Ubuntu login prompt.
4. The immutable C34 source SHA-256 remained unchanged while the runtime disk
   SHA-256 changed after Guest boot, which is the intended ownership split.

This is local diagnostic proof of the C32 → provisioner → VZ boot path. It is
not a signed-PKG installation, launchd retention, Guest Runtime Control
transport/readiness, update migration, or C24 clean-host proof.

## Contract direction

C32 `guestRuntimeDiskProvisioning` is the versioned Host deployment contract:
it names the immutable C34 manifest/root source, the Host-persistent runtime
target, its receipt, and the only admitted existing-disk policy. C32
`storageDevices[].diskImagePath` for `guest-root` must equal the declared
`runtimeDiskImagePath`; it never names the release artifact.

`GuestRuntimeDiskProvisioner` returns the explicit outcomes `provisioned` or
`retained-existing-runtime-disk`, and reports invalid, unreadable, incomplete,
or identity-mismatched input as a typed failed/unavailable result. A generic
`StorageManager`, `ImageCopier`, or boolean `diskReady` would hide the owner,
the release/runtime distinction, and update guard that this boundary exists to
preserve.

The package composer and verifier prove that the PKG carries only the immutable
release root and the read-only bootstrap volume. The macOS supervisor creates
the runtime disk at first construction and retains it only when its receipt
matches the configured release identity. C24 clean-host installation and
update evidence must still prove the installed behavior and an explicit
replacement/migration decision for a changed release artifact.
