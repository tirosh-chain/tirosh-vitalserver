package hostplatformreleaseeffectexecutorapplication

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

type testClock struct{}

func (testClock) Now() string { return "2026-07-20T00:00:00Z" }

type testInspector struct{}

func (testInspector) Inspect(path, sha string) (hostplatformreleaseeffectexecutordomain.ReleaseArtifact, error) {
	return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{Path: path, SHA256: sha, SizeBytes: 42}, nil
}

type testClient struct{}

func (testClient) ExecuteHostPlatformStagedReleaseUpdate(_ context.Context, _ hostplatformreleaseeffectexecutordomain.HostInstallationManagerEndpoint, command hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateCommand, _ hostplatformreleaseeffectexecutordomain.ReleaseArtifact) (hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation, error) {
	return hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation{SchemaVersion: "v1", OperationID: command.OperationID, UpdateID: command.UpdateID, Operation: command.Operation, Transition: command.Transition, Artifact: command.Artifact, State: "succeeded", ObservedAt: "2026-07-20T00:00:01Z"}, nil
}

func TestEffectOnlySucceedsFromC68Success(t *testing.T) {
	application, err := ComposeHostPlatformReleaseEffectApplication(testInspector{}, testClock{})
	if err != nil {
		t.Fatal(err)
	}
	invocation := hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation{ProtocolVersion: "v1", EffectExecutorID: "host-platform-effect-030", EffectConfigurationPath: "/updates/configuration.json", ReceiptPath: "/updates/receipt.json", UpdateID: "update-030", Layer: "host-platform", Operation: "apply", ArtifactPath: "/updates/host-platform.tar.gz", ArtifactSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
	configuration := hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{SchemaVersion: "v1", EffectExecutorID: invocation.EffectExecutorID, HostInstallationManager: hostplatformreleaseeffectexecutordomain.HostInstallationManagerEndpoint{Platform: "macos", ExecutablePath: "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager", ActiveReleaseManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json", RequestTimeoutMilliseconds: 1000}, Apply: hostplatformreleaseeffectexecutordomain.ReleaseTransitionIntent{ExpectedActiveReleaseID: "release-020", TargetReleaseID: "release-030"}}
	receipt, err := application.ExecuteHostPlatformReleaseEffect(context.Background(), configuration, invocation, testClient{})
	if err != nil || receipt.State != "succeeded" {
		t.Fatalf("receipt=%+v error=%v", receipt, err)
	}
}
