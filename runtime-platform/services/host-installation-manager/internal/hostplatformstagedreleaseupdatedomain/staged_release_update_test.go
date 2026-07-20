package hostplatformstagedreleaseupdatedomain

import (
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestAdmissionRequiresStableHostServiceTopology(t *testing.T) {
	active := release("release-020")
	candidate := release("release-030")
	candidate.RequiredServices[0].Name = "changed-service"
	command := command("release-020", "release-030")
	if err := DecideAdmission(command, CandidateHostRelease{Manifest: candidate, CandidateDirectory: "/tmp/candidate"}, ActiveHostRelease{Manifest: active}); err == nil {
		t.Fatal("expected changed service topology to be rejected")
	}
}

func TestAdmissionAcceptsLinuxWhenC48TopologyIsStable(t *testing.T) {
	active := release("release-020")
	active.Platform = "linux"
	active.RequiredServices[0].Manager = "systemd"
	active.RequiredServices[1].Manager = "systemd"
	active.RequiredServices[2].Manager = "systemd"
	active.Activation.CurrentReleaseLinkPath = "/opt/vitalserver-runtime-platform/current"
	active.Activation.ExpectedReleaseRootPath = "/opt/vitalserver-runtime-platform/releases/release-020"
	active.ImmutablePayload.ReleaseCatalogPath = "/opt/vitalserver-runtime-platform/releases"
	active.ImmutablePayload.ReleaseRootPath = "/opt/vitalserver-runtime-platform/releases/release-020"
	active.ImmutablePayload.ManifestPath = "/opt/vitalserver-runtime-platform/releases/release-020/installation-manifest.json"
	active.OperatorInterface.BootstrapConfigurationPath = "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json"
	candidate := active
	candidate.Release.ID = "release-030"
	candidate.ImmutablePayload.ReleaseRootPath = "/opt/vitalserver-runtime-platform/releases/release-030"
	candidate.ImmutablePayload.ManifestPath = "/opt/vitalserver-runtime-platform/releases/release-030/installation-manifest.json"
	candidate.Activation.ExpectedReleaseRootPath = "/opt/vitalserver-runtime-platform/releases/release-030"
	if err := DecideAdmission(command("release-020", "release-030"), CandidateHostRelease{Manifest: candidate, CandidateDirectory: "/tmp/candidate"}, ActiveHostRelease{Manifest: active}); err != nil {
		t.Fatalf("expected stable Linux C48 topology to be admitted: %v", err)
	}
}

func TestSucceededOperationCannotCarryIssue(t *testing.T) {
	value := StagedReleaseUpdateOperation{SchemaVersion: "v1", OperationID: "update-030-host-platform-apply", UpdateID: "update-030", Operation: "apply", Transition: ReleaseTransition{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}, Artifact: ArchiveArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MediaType: HostPlatformReleaseArchiveMedia}, State: "succeeded", ObservedAt: "2026-07-20T00:00:00Z", Issue: &Issue{Code: "unexpected", Message: "not allowed"}}
	if err := ValidateOperation(value); err == nil {
		t.Fatal("expected succeeded issue rejection")
	}
}

func TestFailedOperationRequiresLastDurableState(t *testing.T) {
	value := StagedReleaseUpdateOperation{SchemaVersion: "v1", OperationID: "update-030-host-platform-apply", UpdateID: "update-030", Operation: "apply", Transition: ReleaseTransition{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}, Artifact: ArchiveArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MediaType: HostPlatformReleaseArchiveMedia}, State: StateFailed, ObservedAt: "2026-07-20T00:00:00Z", Issue: &Issue{Code: "interrupted", Message: "unknown result"}}
	if err := ValidateOperation(value); err == nil {
		t.Fatal("expected failed operation without last durable state to be rejected")
	}
}

func TestRecoveryAdmissionRequiresExplicitServiceAffectingBoundary(t *testing.T) {
	command := command("release-020", "release-030")
	prior := Failure(command, StateFailed, StateReceived, "archive-invalid", "archive is invalid", "host-update-staging", "2026-07-20T00:00:00Z")
	recovery := StagedReleaseRecoveryCommand{SchemaVersion: "v1", RecoveryID: "update-030-recovery-001", OperationID: command.OperationID, Action: RecoveryActionReconcileCurrentRelease, RequestedAt: "2026-07-20T00:00:00Z"}
	issue := DecideRecoveryAdmission(recovery, prior, ActiveHostRelease{Manifest: release("release-020")})
	if issue == nil || issue.Code != "recovery-not-required" {
		t.Fatalf("issue=%+v", issue)
	}
}

func command(expected, target string) StagedReleaseUpdateCommand {
	return StagedReleaseUpdateCommand{SchemaVersion: "v1", OperationID: "update-030-host-platform-apply", UpdateID: "update-030", Operation: "apply", Transition: ReleaseTransition{ExpectedActiveReleaseID: expected, TargetReleaseID: target}, Artifact: ArchiveArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MediaType: HostPlatformReleaseArchiveMedia}, RequestedAt: "2026-07-20T00:00:00Z"}
}
func release(id string) hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{SchemaVersion: "v1", InstallationID: "installation-001", Platform: "macos", Release: hostinstallationmanagerdomain.HostProductRelease{ID: id, ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"}, Package: hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.3.0"}, ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{ReleaseCatalogPath: "/Library/Application Support/VitalServerRuntimePlatform/releases", ReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id, ManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id + "/installation-manifest.json", Entries: []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Executable: true}}}, Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/" + id}, OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}, RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}, {Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}, {Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", DefinitionSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}}, MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{{ID: hostinstallationmanagerdomain.HostInstallationTransactionStoreID, Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"}}}
}
