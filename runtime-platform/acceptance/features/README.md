# Acceptance Features

Executable scenario specifications belong here. They describe externally observable behavior and use stable domain vocabulary.

Feature files are contracts for the new platform, not copies of legacy implementation details.

- `external-time-observability.feature` defines the externally visible C16–C20 owner boundaries. Its executable counterpart is `harness/test_external_time_observability.py`.
- `cross-platform-delivery.feature` defines C33 startup configuration, C21–C24 provider selection/lifecycle correlation, and explicit clean-host release-proof behavior. Its portable executable counterpart is `harness/test_cross_platform_delivery.py`.
- `macos-clean-host-release-evidence.feature` defines the C23/C24 macOS clean-Host evidence vocabulary. Its deterministic command-contract counterpart is `../tooling/tests/test_macos_clean_host_release_evidence_runner.py`; real native clean-Host proof remains a C24 release-runner operation.
- `macos-development-installation.feature` defines the separate unsigned-PKG/ad-hoc-Supervisor local development evidence vocabulary. Its deterministic command-contract counterpart is `../tooling/tests/test_macos_development_installation_evidence_runner.py`; it never emits C24 release proof.
- `installation-update-foundation.feature` defines C25–C31 composition, bootstrap, handoff, recovery, and layer-evidence behavior. Its executable counterpart is `harness/test_installation_update_foundation.py`.
