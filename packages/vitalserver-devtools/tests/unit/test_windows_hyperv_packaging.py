from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
WINDOWS_PACKAGING = (
    ROOT / "apps/vitalserver-platform-agent/packaging/windows"
)


def test_hyperv_provisioning_is_idempotent_and_non_destructive() -> None:
    script = (WINDOWS_PACKAGING / "provision-hyperv.ps1").read_text(
        encoding="utf-8"
    )

    for required in (
        "Get-WindowsOptionalFeature",
        "CurrentBuildNumber",
        "ProfessionalEducation",
        "Get-FileHash",
        "Get-VMSwitch",
        "New-VMSwitch",
        "Get-NetNat",
        "New-NetNat",
        "Get-VM",
        "New-VM",
        "MicrosoftUEFICertificateAuthority",
        'state = "provisioned"',
        "systemVHDXSHA256 = $systemVHDXSHA256",
        "Install-PreservedRuntimeDataArtifact",
        'state = "preserved-existing"',
        "runtimeDataVHDXProvisioningState = $runtimeDataVHDX.state",
        "runtimeDataVHDXSourceSHA256 = $runtimeDataVHDX.sourceSHA256",
        "runtimeDataVHDXObservedSHA256 = $runtimeDataVHDX.observedSHA256",
        "seedISOSHA256 = $seedISOSHA256",
        "readError = $null",
    ):
        assert required in script
    for forbidden in ("Remove-VM", "Remove-VMSwitch", "Remove-NetNat", "Stop-VM"):
        assert forbidden not in script
    assert "destinationHash -ne $sourceHash" not in script.split("function Install-PreservedRuntimeDataArtifact", 1)[1].split("$systemVHDXSHA256", 1)[0].split("if (Test-Path", 1)[1].split("}", 1)[0]


def test_windows_service_install_requires_matching_provision_owner() -> None:
    script = (WINDOWS_PACKAGING / "install-service.ps1").read_text(
        encoding="utf-8"
    )

    assert '$provisionState.state -ne "provisioned"' in script
    assert "$provisionState.vmName -ne $hyperVConfig.vmName" in script
    assert (
        "$provisionState.guestAddress -ne $hyperVConfig.runtimeEndpointAddress"
        in script
    )
    assert "Get-CimInstance -ClassName Win32_Service" in script
    assert "Stop-ServiceIfRunning" in script
    assert "Start-Service -Name $providerServiceName" in script
    assert "Start-Service -Name $agentServiceName" in script
    assert "& $acceptanceScript" in script
    assert '$acceptance.status -ne "passed"' in script
    assert 'state = "installed"' in script
    assert "installedAcceptanceRunId = $acceptance.runId" in script
    assert "installedBootSessionId = $acceptance.hostBootSessionId" in script
    assert "releasePath = [IO.Path]::GetFullPath($ReleasePath)" in script
    assert "previousReleasePath = if ($PreviousReleasePath)" in script
    assert "previousSystemVHDXPath = if ($PreviousSystemVHDXPath)" in script
    assert "[Text.UTF8Encoding]::new($false)" in script
    assert "$platformConfig.installDocument" in script
    assert "$platformConfig.runtimeProviderDocument" in script
    assert "$platformConfig.apiToken -ne $apiToken" in script
    assert "-ReleaseManifestPath $ReleaseManifestPath" in script
    assert "-SupportExportMode $SupportExportMode" in script


def test_windows_offline_install_is_owner_driven_and_checksum_gated() -> None:
    script = (WINDOWS_PACKAGING / "install-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "Assert-SafeBundle",
        "Get-FileHash -LiteralPath $candidate -Algorithm SHA256",
        "checksum inventory differs",
        "unsupported reparse points",
        'target.os -ne "windows"',
        'target.architecture -ne "amd64"',
        'target.provider -ne "hyperv"',
        'Join-Path $ProgramFilesRoot "releases"',
        'Join-Path $ProgramDataRoot "install.json"',
        '"runtime-provider" = "VitalServerHyperVRuntime"',
        '"public-proxy" = $null',
        "Protect-OwnerFile -Path $tokenPath",
        "& $provisionScript",
        "& $serviceInstaller",
        "-AcceptanceManifestPath",
        "-InstallDocumentPath $installDocument",
        'schedulerKind = "windows-scheduled-task"',
        'applyPolicy = "verify-only"',
        "trustedBundleInbox = $inboxRoot",
        "Protect-OwnerDirectory -Path $inboxRoot",
    ):
        assert required in script
    assert "Remove-VM" not in script
    assert "Remove-VMSwitch" not in script
    assert "Remove-NetNat" not in script


def test_windows_acceptance_writes_stage_and_failure_proof() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-hyperv.ps1").read_text(
        encoding="utf-8"
    )

    for required in (
        'platform = "windows-hyperv-amd64"',
        "platformVersion = $PlatformVersion",
        "runtimeBundleVersion = $RuntimeBundleVersion",
        '"runtime-provider-running"',
        '"platform-contract"',
        '"runtime-capabilities"',
        '"runtime-services"',
        '"runtime-stack"',
        '"runtime-settings"',
        '"redis-relay-settings"',
        '"runtime-events"',
        '"product-pwa"',
        '"runtime-provider-stop"',
        '"runtime-provider-start"',
        '"runtime-after-provider-restart"',
        'Wait-RuntimeProviderState -ExpectedState "stopped"',
        'Wait-RuntimeProviderState -ExpectedState "running"',
        'Write-AcceptanceManifest -Status "passed"',
        'Write-AcceptanceManifest -Status "failed"',
        "failureStage = if ($FailureStage)",
        "failureReason = if ($FailureReason)",
        "hyperVImageManifestSHA256 = $imageManifestSHA256",
        "imageCompileRunId = $imageCompileRunId",
        "releaseInputs = $releaseInputs",
        "$installedRelease.inputs.platformAgentSHA256",
        "hostBootSessionId = $hostBootSessionId",
        "Get-CimInstance -ClassName Win32_OperatingSystem",
        "$imageCompileRunId = $imageManifest.runId",
    ):
        assert required in script
    assert "/runtime/stack/status" not in script


def test_windows_reboot_acceptance_requires_new_boot_session_and_full_runtime_proof() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-reboot-hyperv.ps1").read_text(encoding="utf-8")

    for required in (
        'kind = "reboot"',
        'installedBootSessionId = $installedBootSessionId',
        'currentBootSessionId = $currentBootSessionId',
        '"boot-session-changed"',
        '$currentBootSessionId -eq $installedBootSessionId',
        '& $acceptanceScript',
        '-ReleaseManifestPath $ReleaseManifestPath',
        '$acceptance.hostBootSessionId -ne $currentBootSessionId',
        'runtimeAcceptanceRunId = $runtimeAcceptanceRunId',
        '[Text.UTF8Encoding]::new($false)',
    ):
        assert required in script


def test_windows_workflow_scheduler_survives_agent_restart_and_reports_launch_failure() -> None:
    script = (WINDOWS_PACKAGING / "schedule-workflow-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "Register-ScheduledTask",
        "Start-ScheduledTask",
        'New-ScheduledTaskPrincipal -UserId "SYSTEM"',
        "-RunTask",
        "Decode-Arguments",
        "Write-TaskFailure",
        'kind = "workflowTaskFailed"',
        "Unregister-ScheduledTask",
        '[Text.UTF8Encoding]::new($false)',
    ):
        assert required in script


def test_windows_update_verification_rejects_unsafe_zip_before_apply() -> None:
    module = (WINDOWS_PACKAGING / "windows-delivery.psm1").read_text(encoding="utf-8")
    update = (WINDOWS_PACKAGING / "update-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "ZipFile]::OpenRead",
        "entry path is unsafe",
        "entry is duplicated",
        "entry type is unsupported",
        "expanded size exceeds 100 GiB",
        "checksum inventory differs",
        "checksum mismatch",
    ):
        assert required in module
    assert "Expand-VitalServerWindowsBundle" in update
    assert "Assert-VitalServerWindowsBundle" in update
    assert "Read-VitalServerWindowsRelease" in update
    assert "apply-update-windows.ps1" in update


def test_windows_update_and_rollback_preserve_runtime_data_disk_and_restore_all_owners() -> None:
    apply = (WINDOWS_PACKAGING / "apply-update-windows.ps1").read_text(encoding="utf-8")
    rollback = (WINDOWS_PACKAGING / "rollback-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "$oldConfigBytes",
        "$oldProvisionBytes",
        "$oldInstallBytes",
        "Set-VMHardDiskDrive",
        "Set-VMDvdDrive",
        "PreviousReleasePath",
        "PreviousSystemVHDXPath",
        "windows-hyperv-update-recovery-acceptance.json",
        "-SupportExportMode 'capability-only'",
        "rollbackState=restored",
    ):
        assert required in apply
    assert "runtimeDataVHDXDestination" not in apply
    assert "Remove-VM" not in apply
    assert "previousReleasePath" in rollback
    assert "apply-update-windows.ps1" in rollback
    assert 'kind = \'rollback\'' in rollback


def test_windows_update_acceptance_uses_runtime_owner_marker_instead_of_vhdx_inference() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-update-rollback-hyperv.ps1").read_text(encoding="utf-8")

    for required in (
        'kind = \'update-rollback-data-preservation\'',
        '"$BaseURL/runtime/settings"',
        '"$BaseURL/platform/update-bundles/apply"',
        '"$BaseURL/platform/releases/rollback"',
        "Wait-PlatformWorkflow",
        "ExpectedUpdatePlatformVersion",
        "ExpectedUpdateRuntimeBundleVersion",
        "update-data-preserved",
        "rollback-data-preserved",
        "runtime-settings-restored",
        "Apply-SettingsDocument -SettingsJSON $originalSettingsJSON",
    ):
        assert required in script
    assert "Mount-VHD" not in script
    assert "Get-Content $RuntimeDataVHDX" not in script


def test_windows_uninstall_reinstall_acceptance_proves_explicit_data_owners() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-uninstall-reinstall-hyperv.ps1").read_text(encoding="utf-8")

    for required in (
        "kind = 'uninstall-reinstall-data-preservation'",
        "state -ne 'releaseCandidate'",
        "installedAcceptanceRunId",
        "Installed immutable release bytes differ from the sealed reinstall bundle",
        "Reinstall did not publish a new host-local installed acceptance identity",
        '"$BaseURL/platform/uninstall"',
        "Wait-LocalUninstall",
        "Assert-OwnerDigests",
        "runtimeDataVHDXProvisioningState -ne 'preserved-existing'",
        "Require-SettingsMarker -Marker $marker -Transition 'standard uninstall and reinstall'",
        "packaging\\install-windows.ps1",
        "runtime-settings-restored",
    ):
        assert required in script
    assert "Mount-VHD" not in script
    assert "Remove-Item -LiteralPath $dataPath" not in script


def test_windows_clean_uninstall_acceptance_is_terminal_and_checks_external_proof() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-clean-uninstall-hyperv.ps1").read_text(encoding="utf-8")

    for required in (
        "kind = 'clean-uninstall'",
        "Clean uninstall acceptance output must be outside managed ProgramData",
        '"$BaseURL/platform/uninstall"',
        "'{\"mode\":\"clean\"}'",
        "VitalServer-UninstallProof",
        "postconditionsPassed -ne $true",
        "Clean uninstall acceptance found managed residue",
        "Get-VM -Name",
        "Get-NetNat -Name",
        "Get-VMSwitch -Name",
    ):
        assert required in script
    assert "install-windows.ps1" not in script


def test_windows_update_trust_requires_out_of_band_digest_and_hardens_owner() -> None:
    script = (WINDOWS_PACKAGING / "trust-update-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "ExpectedSHA256",
        "Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256",
        "$actual -ne $ExpectedSHA256",
        "trusted-bundle-digests.json",
        "sha256-allowlist",
        "trustedBundleDigests",
        "icacls.exe",
        "Restart-Service -Name 'VitalServerPlatformAgent'",
        "trustedBundleInbox",
    ):
        assert required in script
    assert "ExpectedSHA256 = $actual" not in script


def test_windows_uninstall_validates_owned_resources_and_preserves_data_by_mode() -> None:
    script = (WINDOWS_PACKAGING / "uninstall-windows.ps1").read_text(encoding="utf-8")

    for required in (
        "ValidateSet('standard', 'clean')",
        "Windows uninstall refuses VM with different owner identity",
        "Compare-Object -ReferenceObject $expectedDisks",
        "Windows uninstall refuses NAT with different owner prefix",
        "Windows uninstall refuses virtual switch with different owner type",
        "Remove-VM -VM $vm -Force",
        "Remove-ServiceOwner -Name 'VitalServerHyperVRuntime'",
        "Remove-ServiceOwner -Name 'VitalServerPlatformAgent'",
        "Remove-NetNat",
        "Remove-VMSwitch",
        "runtimeDataPreserved = ($Mode -eq 'standard')",
        "postconditionsPassed = $true",
        "Windows uninstall postcondition failed",
        "Windows standard uninstall did not preserve its explicit Runtime data/config/token owners",
        "Windows clean uninstall left managed ProgramData or Runtime data VHDX state",
        "VitalServer-UninstallProof",
        "kind = 'uninstallFailed'",
        "Write-Workflow -State 'running'",
        "Write-Workflow -State 'completed'",
        "Write-Workflow -State 'failed'",
    ):
        assert required in script
    assert "Remove-Item -LiteralPath ([string]$provision.runtimeDataVHDXPath)" not in script
    assert script.rindex("Write-Workflow -State 'completed'") > script.index(
        "Windows uninstall postcondition failed"
    )
    assert script.rindex("Write-Workflow -State 'completed'") > script.index(
        "Write-UninstallProof -Path $proofPath -Document $proof"
    )
    assert "Clean uninstall removes its internal workflow owner" in script
    assert "external failure proof is authoritative" in script


def test_windows_clean_uninstall_acceptance_reports_external_failure_immediately() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-clean-uninstall-hyperv.ps1").read_text(
        encoding="utf-8"
    )

    assert "if ($proof.state -eq 'failed')" in script
    assert "Windows clean uninstall workflow failed" in script


def test_windows_support_export_is_owner_driven_and_reports_partial_sources() -> None:
    script = (WINDOWS_PACKAGING / "support-export-windows.ps1").read_text(
        encoding="utf-8"
    )

    for required in (
        "kind = 'support-export'",
        "Write-Workflow -State 'running'",
        "Write-Workflow -State 'completed'",
        "Write-Workflow -State 'failed'",
        "archivePath = $archivePath",
        "state = 'missing'",
        "state = 'invalid'",
        "state = 'read-failed'",
        "$hyperVDiagnosticState = 'command-failed'",
        "sha256 = (Get-FileHash",
        "sizeBytes = [Int64]$file.Length",
        "config\\platform-agent.json",
        "runtime product settings and datastore contents",
    ):
        assert required in script
    assert "apiToken" not in script
    assert "Get-Content -LiteralPath (Join-Path $ProgramDataRoot 'secrets" not in script


def test_windows_installed_acceptance_proves_support_export_artifact() -> None:
    script = (WINDOWS_PACKAGING / "acceptance-hyperv.ps1").read_text(
        encoding="utf-8"
    )

    for required in (
        '"platform-support-export"',
        '"$BaseURL/platform/capabilities"',
        '"$BaseURL/platform/support-exports"',
        '"$BaseURL/platform/workflows/current"',
        "$supportOperation.operationId -ne $support.operationId",
        "$supportOperation.state -eq 'failed'",
        "Join-Path $env:ProgramData 'VitalServer\\support'",
        "Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256",
        "$supportOperation.artifact.sizeBytes",
        '$SupportExportMode -eq "capability-only"',
    ):
        assert required in script
