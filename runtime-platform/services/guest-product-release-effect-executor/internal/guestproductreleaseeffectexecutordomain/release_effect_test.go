package guestproductreleaseeffectexecutordomain

import "testing"

func TestValidateConfigurationRequiresRollbackToReverseApplyTransition(t *testing.T) {
	configuration := validConfiguration()
	configuration.Rollback.ExpectedActiveReleaseID = "vitalserver-guest-product-0.2.0"
	if err := ValidateConfiguration(configuration); err == nil {
		t.Fatal("expected non-reversing rollback declaration to be rejected")
	}
}

func TestOutcomeForGuestProductReleaseOperationMapsGuestSuccessToC55Success(t *testing.T) {
	invocation := validInvocation()
	configuration := validConfiguration()
	intent, err := SelectIntent(configuration, invocation)
	if err != nil {
		t.Fatal(err)
	}
	command, err := NewGuestProductReleaseUpdateCommand(invocation, intent, ReleaseArtifact{Path: "/host/staging/payload/release.tar.gz", SHA256: invocation.ArtifactSHA256, SizeBytes: 10}, "2026-07-20T00:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := OutcomeForGuestProductReleaseOperation(invocation, command, GuestProductReleaseOperation{SchemaVersion: SchemaVersion, UpdateID: command.UpdateID, ExpectedActiveReleaseID: command.ExpectedActiveReleaseID, TargetRelease: command.TargetRelease, State: "succeeded", ActiveReleaseID: command.TargetRelease.ReleaseID, ObservedAt: "2026-07-20T00:00:02Z"}, "2026-07-20T00:00:03Z")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != ReceiptStateSucceeded || receipt.Issue != nil || receipt.Evidence.Kind != "guest-product-release-operation" {
		t.Fatalf("unexpected C55 receipt: %+v", receipt)
	}
}

func TestOutcomeForGuestProductReleaseOperationKeepsNonTerminalC59StateUnavailable(t *testing.T) {
	invocation := validInvocation()
	configuration := validConfiguration()
	intent, err := SelectIntent(configuration, invocation)
	if err != nil {
		t.Fatal(err)
	}
	command, err := NewGuestProductReleaseUpdateCommand(invocation, intent, ReleaseArtifact{Path: "/host/staging/payload/release.tar.gz", SHA256: invocation.ArtifactSHA256, SizeBytes: 10}, "2026-07-20T00:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := OutcomeForGuestProductReleaseOperation(invocation, command, GuestProductReleaseOperation{SchemaVersion: SchemaVersion, UpdateID: command.UpdateID, ExpectedActiveReleaseID: command.ExpectedActiveReleaseID, TargetRelease: command.TargetRelease, State: "applying", ObservedAt: "2026-07-20T00:00:02Z"}, "2026-07-20T00:00:03Z")
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != ReceiptStateUnavailable || receipt.Issue == nil || receipt.Issue.Code != "guest-product-release-operation-not-terminal" {
		t.Fatalf("unexpected C55 receipt: %+v", receipt)
	}
}

func validConfiguration() GuestProductReleaseEffectExecutorConfiguration {
	return GuestProductReleaseEffectExecutorConfiguration{
		SchemaVersion:                      SchemaVersion,
		EffectExecutorID:                   "guest-product-release-effect-executor-020",
		GuestProductReleaseManagerEndpoint: GuestProductReleaseManagerEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18444, Path: GuestProductReleaseManagerPath, RequestTimeoutMilliseconds: 60000},
		Apply:                              GuestProductReleaseOperationIntent{ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0"},
		Rollback:                           &GuestProductReleaseOperationIntent{ExpectedActiveReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0"},
	}
}

func validInvocation() FixedProtocolInvocation {
	return FixedProtocolInvocation{ProtocolVersion: SchemaVersion, EffectExecutorID: "guest-product-release-effect-executor-020", EffectConfigurationPath: "/host/staging/payload/executors/guest-product-release.json", ReceiptPath: "/host/receipts/receipt.json", UpdateID: "update-020", Layer: "guest-runtime", Operation: UpdateOperationApply, ArtifactPath: "/host/staging/payload/release.tar.gz", ArtifactSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
}
