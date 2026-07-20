package guestproductreleasemanagerapplication_test

import (
	"bytes"
	"context"
	"io"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

func TestApplyReleaseUpdateRestoresExpectedReleaseWhenTargetHealthFails(t *testing.T) {
	repository := &memoryRepository{}
	current := &currentRelease{active: "vitalserver-guest-product-0.2.0-dev"}
	service := &managedService{}
	health := &healthProbe{failFirst: true}
	application := newApplication(t, repository, &stager{}, current, service, health)
	operation, err := application.ApplyReleaseUpdate(context.Background(), command(), bytes.NewReader([]byte("release")))
	if err != nil {
		t.Fatal(err)
	}
	if operation.State != guestproductreleasemanagerdomain.OperationStateRolledBack || operation.ActiveReleaseID != "vitalserver-guest-product-0.2.0-dev" || operation.Issue == nil {
		t.Fatalf("operation=%#v", operation)
	}
	if current.active != "vitalserver-guest-product-0.2.0-dev" || service.restarts != 2 || health.calls != 2 {
		t.Fatalf("current=%q restarts=%d health=%d", current.active, service.restarts, health.calls)
	}
}

func TestApplyReleaseUpdateReturnsExistingOperationOnlyForSameCommand(t *testing.T) {
	repository := &memoryRepository{operation: guestproductreleasemanagerdomain.GuestProductReleaseOperation{SchemaVersion: "v1", UpdateID: "guest-release-update-020", ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0-dev", TargetRelease: command().TargetRelease, State: guestproductreleasemanagerdomain.OperationStateSucceeded, ActiveReleaseID: "vitalserver-guest-product-0.2.1", ObservedAt: "2026-07-20T00:00:00Z"}, found: true}
	application := newApplication(t, repository, &stager{}, &currentRelease{}, &managedService{}, &healthProbe{})
	operation, err := application.ApplyReleaseUpdate(context.Background(), command(), bytes.NewReader([]byte("ignored")))
	if err != nil || operation.State != guestproductreleasemanagerdomain.OperationStateSucceeded {
		t.Fatalf("operation=%#v err=%v", operation, err)
	}
	different := command()
	different.ExpectedActiveReleaseID = "different-release"
	if _, err := application.ApplyReleaseUpdate(context.Background(), different, bytes.NewReader([]byte("ignored"))); err == nil || !strings.Contains(err.Error(), "different release command") {
		t.Fatalf("different request error=%v", err)
	}
}

func newApplication(t *testing.T, repository *memoryRepository, staged guestproductreleasemanagerapplication.ReleaseArchiveStager, current guestproductreleasemanagerapplication.CurrentReleaseLinkManager, service guestproductreleasemanagerapplication.ManagedGuestProductService, health guestproductreleasemanagerapplication.GuestProductHealthProbe) *guestproductreleasemanagerapplication.GuestProductReleaseManagerApplicationService {
	t.Helper()
	application, err := guestproductreleasemanagerapplication.NewGuestProductReleaseManagerApplicationService(configuration(), repository, staged, current, service, health, fixedClock{})
	if err != nil {
		t.Fatal(err)
	}
	return application
}

type memoryRepository struct {
	operation guestproductreleasemanagerdomain.GuestProductReleaseOperation
	found     bool
}

func (repository *memoryRepository) ReadReleaseOperation(context.Context, string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error) {
	return repository.operation, repository.found, nil
}
func (repository *memoryRepository) WriteReleaseOperation(_ context.Context, operation guestproductreleasemanagerdomain.GuestProductReleaseOperation) error {
	repository.operation, repository.found = operation, true
	return nil
}

type stager struct{}

func (*stager) StageReleaseArchive(context.Context, guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, io.Reader) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	return nil
}

type currentRelease struct{ active string }

func (release *currentRelease) ReadActiveReleaseID(context.Context) (string, *guestproductreleasemanagerapplication.ReleaseManagementFailure) {
	return release.active, nil
}
func (release *currentRelease) ActivateRelease(_ context.Context, target guestproductreleasemanagerdomain.ReleaseReference) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	release.active = target.ReleaseID
	return nil
}

type managedService struct{ restarts int }

func (service *managedService) RestartManagedGuestProduct(context.Context) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	service.restarts++
	return nil
}

type healthProbe struct {
	failFirst bool
	calls     int
}

func (probe *healthProbe) WaitForGuestProductHealth(context.Context) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	probe.calls++
	if probe.failFirst && probe.calls == 1 {
		return &guestproductreleasemanagerapplication.ReleaseManagementFailure{State: "failed", Issue: guestproductreleasemanagerdomain.Issue{Code: "target-health-check-failed", Message: "target failed", Dependency: "guest-product"}}
	}
	return nil
}

type fixedClock struct{}

func (fixedClock) Now() string { return "2026-07-20T00:00:00Z" }

func configuration() guestproductreleasemanagerdomain.ManagerConfiguration {
	return guestproductreleasemanagerdomain.ManagerConfiguration{ManagerID: "guest-product-release-manager-primary", ReleaseDirectoryRoot: "/opt/vitalserver/releases", CurrentReleaseLinkPath: "/opt/vitalserver/current", StagingDirectory: "/var/lib/vitalserver/guest-product-releases/staging", StateDirectory: "/var/lib/vitalserver/guest-product-releases", StateDirectoryMode: "0700", MaximumReleaseArtifactBytes: 1 << 30, SystemctlExecutablePath: "/usr/bin/systemctl", ManagedServiceUnitName: "vitalserver-guest-product.service", RestartTimeoutMilliseconds: 60000, HealthCheckURL: "http://127.0.0.1:18443/v1/runtime/readiness", HealthCheckTimeoutMilliseconds: 30000, HealthCheckAcceptedStatusCodes: []int{200}}
}
func command() guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand {
	return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{SchemaVersion: "v1", UpdateID: "guest-release-update-020", ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0-dev", TargetRelease: guestproductreleasemanagerdomain.ReleaseTarget{ReleaseID: "vitalserver-guest-product-0.2.1", ReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.1", Artifact: guestproductreleasemanagerdomain.ReleaseArtifact{SHA256: strings.Repeat("a", 64), SizeBytes: 1024, MediaType: "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"}}, RequestedAt: "2026-07-20T00:00:00Z"}
}
