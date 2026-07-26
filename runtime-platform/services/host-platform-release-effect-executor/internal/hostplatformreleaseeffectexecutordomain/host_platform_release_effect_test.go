package hostplatformreleaseeffectexecutordomain

import "testing"

func TestC68SucceededOperationCreatesC55Success(t *testing.T) {
	invocation := FixedProtocolInvocation{ProtocolVersion: "v1", EffectExecutorID: "host-platform-effect-030", EffectConfigurationPath: "/updates/configuration.json", ReceiptPath: "/updates/receipt.json", UpdateID: "update-030", Layer: "host-platform", Operation: "apply", ArtifactPath: "/updates/host-platform.tar.gz", ArtifactSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
	command, err := NewHostPlatformStagedReleaseUpdateCommand(invocation, ReleaseTransitionIntent{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}, ReleaseArtifact{Path: invocation.ArtifactPath, SHA256: invocation.ArtifactSHA256, SizeBytes: 42}, "2026-07-20T00:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	operation := HostPlatformStagedReleaseUpdateOperation{SchemaVersion: "v1", OperationID: command.OperationID, UpdateID: command.UpdateID, Operation: command.Operation, Transition: command.Transition, Artifact: command.Artifact, State: "succeeded", ObservedAt: "2026-07-20T00:00:01Z"}
	receipt, err := OutcomeForHostPlatformOperation(invocation, command, operation, "2026-07-20T00:00:02Z")
	if err != nil || receipt.State != ReceiptStateSucceeded {
		t.Fatalf("receipt=%+v error=%v", receipt, err)
	}
}

func TestC67RejectsDifferentRollbackPrecondition(t *testing.T) {
	configuration := EffectExecutorConfiguration{SchemaVersion: "v1", EffectExecutorID: "host-platform-effect-030", HostInstallationManager: HostInstallationManagerEndpoint{Platform: "macos", ExecutablePath: "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager", ActiveReleaseManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json", RequestTimeoutMilliseconds: 1000}, Apply: ReleaseTransitionIntent{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}, Rollback: &ReleaseTransitionIntent{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-010"}}
	if err := ValidateConfiguration(configuration); err == nil {
		t.Fatal("expected rollback precondition rejection")
	}
}

func TestC67WindowsEndpointMatchesWindowsC48ProductRoot(t *testing.T) {
	configuration := EffectExecutorConfiguration{
		SchemaVersion:    "v1",
		EffectExecutorID: "host-platform-effect-030",
		HostInstallationManager: HostInstallationManagerEndpoint{
			Platform:                   "windows",
			ExecutablePath:             `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-installation-manager.exe`,
			ActiveReleaseManifestPath:  `C:\ProgramData\VitalServerRuntimePlatform\current\installation-manifest.json`,
			RequestTimeoutMilliseconds: 1000,
		},
		Apply: ReleaseTransitionIntent{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"},
	}
	if err := ValidateConfiguration(configuration); err != nil {
		t.Fatalf("expected C48-aligned Windows C67 endpoint: %v", err)
	}
	configuration.HostInstallationManager.ExecutablePath = `C:\Program Files\VitalServerRuntimePlatform\current\bin\host-installation-manager.exe`
	if err := ValidateConfiguration(configuration); err == nil {
		t.Fatal("expected divergent Windows product root to be rejected")
	}
}
