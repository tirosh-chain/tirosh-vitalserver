package guestproductreleasemanagerdomain_test

import (
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

func TestReleaseOperationRequiresHealthGatedRollbackEvidence(t *testing.T) {
	configuration := managerConfiguration()
	command := updateCommand()
	operation := guestproductreleasemanagerdomain.NewReleaseOperation(command, "2026-07-20T00:00:00Z")
	var err error
	if operation, err = guestproductreleasemanagerdomain.MarkReleaseStaged(operation, "2026-07-20T00:00:01Z"); err != nil {
		t.Fatal(err)
	}
	if operation, err = guestproductreleasemanagerdomain.BeginReleaseActivation(operation, "2026-07-20T00:00:02Z"); err != nil {
		t.Fatal(err)
	}
	issue := guestproductreleasemanagerdomain.Issue{Code: "target-health-check-failed", Message: "new Guest Product did not become ready", Dependency: "guest-product"}
	if operation, err = guestproductreleasemanagerdomain.BeginReleaseRollback(operation, "2026-07-20T00:00:03Z", issue); err != nil {
		t.Fatal(err)
	}
	if operation, err = guestproductreleasemanagerdomain.CompleteReleaseRollback(operation, "2026-07-20T00:00:04Z"); err != nil {
		t.Fatal(err)
	}
	if operation.State != guestproductreleasemanagerdomain.OperationStateRolledBack || operation.ActiveReleaseID != command.ExpectedActiveReleaseID || operation.Issue == nil {
		t.Fatalf("operation=%#v", operation)
	}
	if err := guestproductreleasemanagerdomain.ValidateReleaseOperation(configuration, operation); err != nil {
		t.Fatalf("validate C59 rollback evidence: %v", err)
	}
}

func TestReleaseOperationCannotClaimTargetSuccessBeforeActivation(t *testing.T) {
	operation := guestproductreleasemanagerdomain.NewReleaseOperation(updateCommand(), "2026-07-20T00:00:00Z")
	if _, err := guestproductreleasemanagerdomain.CompleteReleaseActivation(operation, "2026-07-20T00:00:01Z"); err == nil || !strings.Contains(err.Error(), "invalid release operation transition") {
		t.Fatalf("success before activation error=%v", err)
	}
}

func TestReleaseCommandRequiresDeclaredReleaseRootAndExactArtifactIdentity(t *testing.T) {
	configuration := managerConfiguration()
	command := updateCommand()
	if err := guestproductreleasemanagerdomain.ValidateReleaseUpdateCommand(configuration, command); err != nil {
		t.Fatal(err)
	}
	command.TargetRelease.ReleaseDirectory = "/opt/vitalserver/other/vitalserver-guest-product-0.2.1"
	if err := guestproductreleasemanagerdomain.ValidateReleaseUpdateCommand(configuration, command); err == nil || !strings.Contains(err.Error(), "release update command is invalid") {
		t.Fatalf("undeclared root error=%v", err)
	}
}

func managerConfiguration() guestproductreleasemanagerdomain.ManagerConfiguration {
	return guestproductreleasemanagerdomain.ManagerConfiguration{ManagerID: "guest-product-release-manager-primary", ReleaseDirectoryRoot: "/opt/vitalserver/releases", CurrentReleaseLinkPath: "/opt/vitalserver/current", StagingDirectory: "/var/lib/vitalserver/guest-product-releases/staging", StateDirectory: "/var/lib/vitalserver/guest-product-releases", StateDirectoryMode: "0700", MaximumReleaseArtifactBytes: 1 << 30, SystemctlExecutablePath: "/usr/bin/systemctl", ManagedServiceUnitName: "vitalserver-guest-product.service", RestartTimeoutMilliseconds: 60000, HealthCheckURL: "http://127.0.0.1:18443/v1/runtime/readiness", HealthCheckTimeoutMilliseconds: 30000, HealthCheckAcceptedStatusCodes: []int{200}}
}

func updateCommand() guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand {
	return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{SchemaVersion: "v1", UpdateID: "guest-release-update-020", ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0-dev", TargetRelease: guestproductreleasemanagerdomain.ReleaseTarget{ReleaseID: "vitalserver-guest-product-0.2.1", ReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.1", Artifact: guestproductreleasemanagerdomain.ReleaseArtifact{SHA256: strings.Repeat("a", 64), SizeBytes: 1024, MediaType: "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"}}, RequestedAt: "2026-07-20T00:00:00Z"}
}
