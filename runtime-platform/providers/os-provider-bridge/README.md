# Windows/Linux platform provider bridges

This module contains two separately built, selected-provider executables:

- `linux-kvm-libvirt-systemd-bridge` controls only the explicitly configured libvirt VM and systemd service.
- `windows-hyperv-scm-bridge` controls only the explicitly configured Hyper-V VM and Windows SCM service.

Both consume C21 `PlatformProviderLifecycleInvocation` on standard input in `--mode lifecycle` and emit C10 `ProviderLifecycleResult`. `--mode evidence` emits C22 `ProviderInstallationEvidence`. A Host Agent deployment must pass all three explicit values: `--provider-id`, `--vm-name`, and `--service-name`.

Host Agent owns the durable request-ID and expected Guest-endpoint-revision ledger. The bridge validates that correlation and uses an explicit pre-effect VM observation to make a same-state command safe, but it does not create a competing lifecycle database or infer a revision from process output.

The selected bridge never tries another platform provider. Missing native commands, wrong Host OS, missing configuration, unknown native output, and command errors are emitted as typed `unavailable` or `failed` results. Actual live Hyper-V/libvirt proof belongs to the OS clean-host release runner; portable unit tests only verify the mapping through explicit executor outcomes.
