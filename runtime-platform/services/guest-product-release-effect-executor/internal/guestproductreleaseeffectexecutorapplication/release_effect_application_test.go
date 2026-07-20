package guestproductreleaseeffectexecutorapplication

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

type fixedClock struct{}

func (fixedClock) Now() string { return "2026-07-20T00:00:00Z" }

type staticArtifactInspector struct {
	artifact guestproductreleaseeffectexecutordomain.ReleaseArtifact
	err      error
}

func (inspector staticArtifactInspector) Inspect(string, string) (guestproductreleaseeffectexecutordomain.ReleaseArtifact, error) {
	return inspector.artifact, inspector.err
}

type recordingReleaseManagerClient struct {
	operation guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation
	err       error
	command   guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand
}

func (client *recordingReleaseManagerClient) ApplyReleaseUpdate(_ context.Context, _ guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint, command guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand, _ guestproductreleaseeffectexecutordomain.ReleaseArtifact) (guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation, error) {
	client.command = command
	return client.operation, client.err
}

func TestExecuteWritesSucceededC55OnlyFromMatchingC59Success(t *testing.T) {
	configuration := configuration()
	invocation := invocation()
	application, err := ComposeGuestProductReleaseEffectApplication(staticArtifactInspector{artifact: guestproductreleaseeffectexecutordomain.ReleaseArtifact{Path: invocation.ArtifactPath, SHA256: invocation.ArtifactSHA256, SizeBytes: 10}}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	client := &recordingReleaseManagerClient{operation: succeededOperation(invocation)}
	receipt, err := application.ExecuteGuestProductReleaseEffect(context.Background(), configuration, invocation, client)
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != guestproductreleaseeffectexecutordomain.ReceiptStateSucceeded || client.command.TargetRelease.ReleaseID != configuration.Apply.TargetReleaseID {
		t.Fatalf("unexpected receipt=%+v command=%+v", receipt, client.command)
	}
}

func TestExecuteMapsC59TransportFailureToUnavailableC55(t *testing.T) {
	configuration := configuration()
	invocation := invocation()
	application, err := ComposeGuestProductReleaseEffectApplication(staticArtifactInspector{artifact: guestproductreleaseeffectexecutordomain.ReleaseArtifact{Path: invocation.ArtifactPath, SHA256: invocation.ArtifactSHA256, SizeBytes: 10}}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := application.ExecuteGuestProductReleaseEffect(context.Background(), configuration, invocation, &recordingReleaseManagerClient{err: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerRequestFailure{State: guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable, Issue: guestproductreleaseeffectexecutordomain.Issue{Code: "guest-product-release-manager-connection-refused", Message: "bridge connection refused", Dependency: "guest-product-release-manager"}}})
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable || receipt.Issue == nil || receipt.Issue.Code != "guest-product-release-manager-connection-refused" {
		t.Fatalf("unexpected receipt=%+v", receipt)
	}
}

func TestExecuteMapsInvalidC61ConfigurationToFailedC55(t *testing.T) {
	configuration := configuration()
	configuration.GuestProductReleaseManagerEndpoint.Host = "guest-discovered-address"
	invocation := invocation()
	application, err := ComposeGuestProductReleaseEffectApplication(staticArtifactInspector{}, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := application.ExecuteGuestProductReleaseEffect(context.Background(), configuration, invocation, &recordingReleaseManagerClient{})
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != guestproductreleaseeffectexecutordomain.ReceiptStateFailed || receipt.Issue == nil || receipt.Issue.Code != "guest-product-release-configuration-invalid" {
		t.Fatalf("unexpected receipt=%+v", receipt)
	}
}

func configuration() guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration {
	rollback := guestproductreleaseeffectexecutordomain.GuestProductReleaseOperationIntent{ExpectedActiveReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0"}
	return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{SchemaVersion: "v1", EffectExecutorID: "guest-product-release-effect-executor-020", GuestProductReleaseManagerEndpoint: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18444, Path: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerPath, RequestTimeoutMilliseconds: 60000}, Apply: guestproductreleaseeffectexecutordomain.GuestProductReleaseOperationIntent{ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0"}, Rollback: &rollback}
}

func invocation() guestproductreleaseeffectexecutordomain.FixedProtocolInvocation {
	return guestproductreleaseeffectexecutordomain.FixedProtocolInvocation{ProtocolVersion: "v1", EffectExecutorID: "guest-product-release-effect-executor-020", EffectConfigurationPath: "/host/staging/payload/executor-configuration.json", ReceiptPath: "/host/receipts/receipt.json", UpdateID: "update-020", Layer: "guest-runtime", Operation: "apply", ArtifactPath: "/host/staging/payload/guest-product-release.tar.gz", ArtifactSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
}

func succeededOperation(invocation guestproductreleaseeffectexecutordomain.FixedProtocolInvocation) guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation {
	return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{SchemaVersion: "v1", UpdateID: invocation.UpdateID, ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0", TargetRelease: guestproductreleaseeffectexecutordomain.GuestProductReleaseTarget{ReleaseID: "vitalserver-guest-product-0.3.0", ReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0", Artifact: guestproductreleaseeffectexecutordomain.GuestProductReleaseArtifact{SHA256: invocation.ArtifactSHA256, SizeBytes: 10, MediaType: guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerMediaType}}, State: "succeeded", ActiveReleaseID: "vitalserver-guest-product-0.3.0", ObservedAt: "2026-07-20T00:00:01Z"}
}
