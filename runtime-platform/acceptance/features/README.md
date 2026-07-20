# Acceptance Features

Executable scenario specifications belong here. They describe externally observable behavior and use stable domain vocabulary.

Feature files are contracts for the new platform, not copies of legacy implementation details.

- `operator-control-surface.feature` defines the Console/CLI consumer boundary. Its executable Host/Guest public-facade counterpart is `harness/test_host_guest_control.py`; `interfaces/platformctl` has focused parser/transport tests as well.

- `external-time-observability.feature` defines the externally visible C16–C20 owner boundaries. Its executable counterpart is `harness/test_external_time_observability.py`.
- `lab-archive-deletion.feature` defines the Lab, Runner, Gateway, Archive, and deletion boundaries. Its real Runner↔Gateway process counterpart is `harness/test_lab_recorder_runner_gateway.py`; `harness/test_lab_archive_deletion.py` separately proves Guest Runtime Lab/Archive lifecycle behavior.
- `cross-platform-delivery.feature` defines C33 startup configuration, C21–C24 provider selection/lifecycle correlation, and explicit clean-host release-proof behavior. Its portable executable counterpart is `harness/test_cross_platform_delivery.py`.
- `macos-clean-host-release-evidence.feature` defines the C23/C24 macOS clean-Host evidence vocabulary. Its deterministic command-contract counterpart is `../tooling/tests/test_macos_clean_host_release_evidence_runner.py`; real native clean-Host proof remains a C24 release-runner operation.
- `windows-clean-host-release-evidence.feature` defines the C23/C24 Windows MSI, SCM, and reboot evidence vocabulary. Its deterministic command-contract counterpart is `../tooling/tests/test_windows_clean_host_release_evidence_runner.py`; it cannot turn the portable test or a WiX compile into Windows clean-Host proof.
- `linux-clean-host-release-evidence.feature` defines the C23/C24 Linux DEB, systemd, retained-root, and reboot evidence vocabulary. Its deterministic command-contract counterpart is `../tooling/tests/test_linux_clean_host_release_evidence_runner.py`; it cannot turn a DEB composition into Linux clean-Host proof.
- `macos-development-installation.feature` defines the separate unsigned-PKG/ad-hoc-Supervisor local development evidence vocabulary and the all-or-nothing C42/C43 Guest boot input boundary. Its deterministic command-contract counterparts are `../tooling/tests/test_macos_development_installation_evidence_runner.py` and `../tooling/tests/test_macos_development_guest_boot_input_assembly.py`; neither emits C24 release proof.
- `installation-update-foundation.feature` defines C25–C31 composition, bootstrap, handoff, recovery, and layer-evidence behavior. Its executable counterpart is `harness/test_installation_update_foundation.py`.
