# Platform provider profiles

Each file is a deployment-time selection, not Host OS auto-detection. The deployment chooses exactly one profile and names the corresponding Platform Provider process in C33 `HostAgentDeploymentConfiguration`.

All three profiles use the same C21 → C10 lifecycle protocol. Host Agent owns request-ID plus endpoint-revision idempotency in its SQLite operation ledger. The provider validates those fields and returns only an OS-owned observation. It must not select a different provider, start a native profile, or transform a missing OS dependency into success. C33 `HostAgentDeploymentConfiguration` names exactly one Platform Provider process and the inputs it may receive: macOS names a persistent supervisor; Windows/Linux name a native provider bridge. The macOS C33 profile separately uses C32 `MacOSVirtualMachineConfiguration` to declare the Guest’s deployment resources and its `GuestBootConsoleCapture`; C32 is not a lifecycle command and is never synthesized from Host paths or a VM name. The capture is Host-owned append-only diagnostic output, not Guest Runtime state or a success signal.

For Windows/Linux, C33 also makes the Guest ownership choice explicit. An
`externally-provisioned` machine is outside Runtime Platform installation and
the bridge can only control the declared VM name. A
`runtime-platform-provisioned` machine must name C62. The selected bridge's
separate `--mode provision` effect verifies the C65 manifest and its declared
bootable amd64 source images, creates the configured native VM definition without starting it, and
writes C63 only after all effects succeed. C63 permits exactly one reuse case:
the complete existing native resources still match the exact C62 bytes and
release-artifact and C65 identities. It never proves Guest boot or readiness.

`C22 ProviderInstallationEvidence` is emitted by the selected Platform Provider process in `--mode evidence`. It keeps installation, VM, service, and two capabilities as separate facts. A product install is release-ready only when its C24 delivery proof records clean-host evidence for every required stage; the profile file itself is not proof of installation.
