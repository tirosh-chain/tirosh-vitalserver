# Product deployment profiles

This directory contains named, composable desired deployments. A deployment
profile is not a runtime state store, a release receipt, or a provider
selection shortcut. It brings together only the configuration documents that
one named Host installation must consume together.

`profiles/` remains the owner-neutral capability selection vocabulary. In
contrast, a directory below `deployment-profiles/` states a concrete
combination of Host operating system, virtual-machine provider, upstream
placement, and public-edge intent. The directory name must make that
combination visible before a reader opens any JSON file.

Each profile records desired input only:

- C32 `MacOSVirtualMachineConfiguration` is consumed by the macOS Virtual
  Machine Supervisor;
- C62 `NativeGuestMachineProvisioningConfiguration` is consumed only by the
  selected Windows Hyper-V or Linux KVM/libvirt bridge during its separate
  installer/recovery provision effect;
- C33 `HostAgentDeploymentConfiguration` is consumed by Host Agent;
- C36 `HostEdgeProxyDeploymentConfiguration` is consumed by Host Edge Proxy; and
- C53 `OperatorInterfaceBootstrapConfiguration` is consumed only by a
  packaged Runtime Console launcher.

Those consumers own their own process and runtime facts. A profile never
claims that a VM booted, an endpoint connected, or a public listener became
ready. Those observations belong to the relevant Host/Guest state owner and
the C24 release-evidence workflow.

A Windows/Linux deployment profile must explicitly choose C33
`nativeGuestMachineOwnership`. `runtime-platform-provisioned` includes a C62
document whose immutable Guest source disks and mutable runtime paths are part
of the deployment. `externally-provisioned` intentionally excludes C62 and
does not authorize the Runtime Platform to create or replace the VM.

The first profile is
`macos-virtualization-external-vitalserver-reference/`. Its `reference` name
is intentional: it composes a package-buildable macOS/arm64 configuration with
the checked-in external VitalServer reference configuration. The `.example`
endpoint in that C46 source is not a deployable clinical target. A deployment
administrator must provide a separately identified C46 document for a real
external VitalServer before clean-Host installation and operational evidence
can be recorded.

`macos-virtualization-bundled-vitalserver-reference/` is the matching explicit
macOS/arm64 bundled placement. Its C32 adds the independent C64 control bridge;
the matching C37/C39/C44/C64 inputs live in `product/guest-product/` under
their `bundled-vitalserver` names. It intentionally starts with C64's explicit
`unprovisioned` selection, not a guessed image or an implicitly running
container. A C55 → C66 update must install the first verified image set.

`windows-hyperv-external-guest-external-vitalserver-reference/` is the first
Windows x64 release-input profile. It deliberately selects an externally
provisioned Guest and external VitalServer placement. Its reserved endpoint
is a required deployment-time replacement, not a connection fallback; the
profile README identifies the operational facts that still need C24 evidence.
# Linux KVM/libvirt/systemd external Guest / external VitalServer reference

`linux-kvm-libvirt-systemd-external-guest-external-vitalserver-reference/`
is the Linux C33/C36/C53/C56/C58 release-input profile. It makes each
external dependency and the root-only reference socket authorization explicit;
it is desired deployment input, not a successful libvirt/systemd/Guest proof.
