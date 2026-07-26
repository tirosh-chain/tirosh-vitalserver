package guestruntimeapplication_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type fixedClock struct{ now time.Time }

func (clock fixedClock) Now() time.Time { return clock.now }

type sequentialIdentifiers struct{ next int }

func (identifiers *sequentialIdentifiers) NewRequestCorrelationIdentifier(prefix string) (string, error) {
	identifiers.next++
	return prefix + "-test-" + string(rune('0'+identifiers.next)), nil
}

type memoryRepository struct {
	topology   *guestruntimedomain.RuntimeTopology
	capability *guestruntimedomain.CapabilityDocument
	operations map[string]guestruntimedomain.Operation
	requests   map[string]string
	healthErr  error
	commitErr  error
}

func newMemoryRepository() *memoryRepository {
	return &memoryRepository{operations: map[string]guestruntimedomain.Operation{}, requests: map[string]string{}}
}

func (repository *memoryRepository) VerifyRuntimeTopologyStateStoreAvailability(context.Context) error {
	return repository.healthErr
}

func (repository *memoryRepository) ReadRuntimeTopology(context.Context) (guestruntimedomain.RuntimeTopology, error) {
	if repository.topology == nil {
		return guestruntimedomain.RuntimeTopology{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return *repository.topology, nil
}

func (repository *memoryRepository) ReadRuntimeTopologyCapabilityDocument(context.Context) (guestruntimedomain.CapabilityDocument, error) {
	if repository.capability == nil {
		return guestruntimedomain.CapabilityDocument{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return *repository.capability, nil
}

func (repository *memoryRepository) ReadRuntimeTopologyOperation(_ context.Context, id string) (guestruntimedomain.Operation, error) {
	operation, found := repository.operations[id]
	if !found {
		return guestruntimedomain.Operation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return operation, nil
}

func (repository *memoryRepository) ReadRuntimeTopologyOperationByRequestID(_ context.Context, requestID string) (guestruntimedomain.Operation, error) {
	id, found := repository.requests[requestID]
	if !found {
		return guestruntimedomain.Operation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return repository.operations[id], nil
}

func (repository *memoryRepository) CommitRuntimeTopologyApplication(_ context.Context, topology guestruntimedomain.RuntimeTopology, capability *guestruntimedomain.CapabilityDocument, operation guestruntimedomain.Operation) error {
	if repository.commitErr != nil {
		return repository.commitErr
	}
	if _, exists := repository.requests[operation.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.topology = &topology
	repository.capability = capability
	repository.operations[operation.ID] = operation
	repository.requests[operation.RequestID] = operation.ID
	return nil
}

func topologyCommand(requestID string, expectedRevision int) guestruntimedomain.TopologyApplyCommand {
	return guestruntimedomain.TopologyApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                requestID,
		TopologyID:               "primary-topology",
		ExpectedResourceRevision: expectedRevision,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:  "external-upstream",
			ProviderKind: "vitalserver",
			EndpointReference: guestruntimedomain.ResourceReference{
				ResourceType: guestruntimedomain.ExternalUpstreamIntegrationResourceType,
				ResourceID:   "primary",
			},
		},
	}
}

func newGuestRuntimeTopologyService(t *testing.T, repository *memoryRepository) *guestruntimeapplication.GuestRuntimeTopologyApplicationService {
	t.Helper()
	service, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationService(
		repository,
		fixedClock{now: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)},
		&sequentialIdentifiers{},
		"test",
		"guest-test",
	)
	if err != nil {
		t.Fatalf("new service: %v", err)
	}
	return service
}

func TestApplyTopologyPersistsExplicitUnsupportedStatus(t *testing.T) {
	repository := newMemoryRepository()
	service := newGuestRuntimeTopologyService(t, repository)
	operation, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), topologyCommand("request-1", 0))
	if admissionFailure != nil || rejection != nil {
		t.Fatalf("apply topology admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if operation.State != "succeeded" {
		t.Fatalf("operation state = %s, want succeeded", operation.State)
	}
	topology := service.ReadRuntimeTopology(context.Background())
	if topology.State != "available" {
		t.Fatalf("topology read state = %s", topology.State)
	}
	value := topology.Value.(guestruntimedomain.RuntimeTopology)
	if value.Status.ReadState != "unsupported" || value.Status.Connection.State != "not-checked" {
		t.Fatalf("topology status must explicitly preserve unsupported upstream: %+v", value.Status)
	}
	if value.Status.Issue == nil || value.Status.Issue.Code != "external-upstream-module-not-configured" {
		t.Fatalf("topology status issue = %+v", value.Status.Issue)
	}
}

func TestApplyBundledTopologyPersistsCapabilityAndDoesNotClaimConnection(t *testing.T) {
	repository := newMemoryRepository()
	service := newGuestRuntimeTopologyService(t, repository)
	command := topologyCommand("request-bundled", 0)
	command.Spec.ProfileKind = "bundled-upstream"
	command.Spec.EndpointReference.ResourceID = "bundled-vitalserver"
	operation, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), command)
	if admissionFailure != nil || rejection != nil {
		t.Fatalf("apply topology admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if operation.State != "succeeded" {
		t.Fatalf("operation state = %s", operation.State)
	}
	topology := service.ReadRuntimeTopology(context.Background())
	if topology.State != "available" {
		t.Fatalf("topology read state = %s", topology.State)
	}
	value := topology.Value.(guestruntimedomain.RuntimeTopology)
	if value.Status.ReadState != "available" || value.Status.Connection.State != "not-checked" || value.Status.CapabilityDocumentReference == nil {
		t.Fatalf("bundled topology status must expose capability without connection claim: %+v", value.Status)
	}
	capabilities := service.ReadRuntimeTopologyCapabilityDocument(context.Background())
	if capabilities.State != "available" {
		t.Fatalf("capability read state = %s issue=%+v", capabilities.State, capabilities.Issue)
	}
	capability := capabilities.Value.(guestruntimedomain.CapabilityDocument)
	if capability.ID != value.Status.CapabilityDocumentReference.ResourceID || capability.CapabilityRevision != value.ResourceRevision {
		t.Fatalf("capability and topology do not match: capability=%+v topology=%+v", capability, value.Status)
	}
	if len(capability.Commands) != 1 || capability.Commands[0].Name != "upstream.recorder.deliver" || capability.Commands[0].State != "supported" {
		t.Fatalf("capability commands = %+v", capability.Commands)
	}
}

func TestApplyTopologyIsIdempotentForTheSameRequestAndRejectsReuse(t *testing.T) {
	repository := newMemoryRepository()
	service := newGuestRuntimeTopologyService(t, repository)
	command := topologyCommand("request-1", 0)
	first, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), command)
	if admissionFailure != nil || rejection != nil {
		t.Fatalf("first apply admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	second, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), command)
	if admissionFailure != nil || rejection != nil {
		t.Fatalf("idempotent apply admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if first.ID != second.ID {
		t.Fatalf("same request created operations %s and %s", first.ID, second.ID)
	}
	changed := command
	changed.Spec.ProfileKind = "bundled-upstream"
	_, rejection, admissionFailure = service.ApplyRuntimeTopology(context.Background(), changed)
	if admissionFailure != nil || rejection == nil {
		t.Fatalf("reused request admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if rejection.Issue.Code != "request-id-reused-with-different-command" {
		t.Fatalf("rejection issue = %s", rejection.Issue.Code)
	}
}

func TestApplyTopologyRejectsRevisionConflictWithoutCreatingOperation(t *testing.T) {
	repository := newMemoryRepository()
	service := newGuestRuntimeTopologyService(t, repository)
	_, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), topologyCommand("request-1", 1))
	if admissionFailure != nil || rejection == nil {
		t.Fatalf("apply admissionFailure=%+v rejection=%+v", admissionFailure, rejection)
	}
	if rejection.Issue.Code != "resource-revision-conflict" {
		t.Fatalf("rejection issue = %s", rejection.Issue.Code)
	}
	if len(repository.operations) != 0 {
		t.Fatalf("revision rejection created %d operation(s)", len(repository.operations))
	}
}

func TestApplyTopologyCommitFailurePreservesUnknownOperationExistence(t *testing.T) {
	repository := newMemoryRepository()
	repository.commitErr = errors.New("simulated commit outcome failure")
	service := newGuestRuntimeTopologyService(t, repository)

	operation, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), topologyCommand("request-1", 0))
	if operation.ID != "" || rejection != nil || admissionFailure == nil {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if admissionFailure.State != "failed" || admissionFailure.AdmissionState != "unknown" || admissionFailure.Issue.Code != "guest-state-store-write-outcome-unknown" {
		t.Fatalf("admissionFailure=%+v", admissionFailure)
	}
	if repository.topology != nil || len(repository.operations) != 0 {
		t.Fatalf("failed atomic commit changed owned documents: topology=%+v operations=%d", repository.topology, len(repository.operations))
	}
}

func TestApplyTopologyAtomicRevisionConflictIsRejectedWithoutOperation(t *testing.T) {
	repository := newMemoryRepository()
	repository.commitErr = guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	service := newGuestRuntimeTopologyService(t, repository)

	operation, rejection, admissionFailure := service.ApplyRuntimeTopology(context.Background(), topologyCommand("request-1", 0))
	if operation.ID != "" || admissionFailure != nil || rejection == nil {
		t.Fatalf("operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if rejection.Issue.Code != "resource-revision-conflict" {
		t.Fatalf("rejection=%+v", rejection)
	}
	if len(repository.operations) != 0 {
		t.Fatalf("revision rejection created %d operation(s)", len(repository.operations))
	}
}

func TestReadinessPreservesStateStoreFailure(t *testing.T) {
	repository := newMemoryRepository()
	repository.healthErr = errors.New("disk is unavailable")
	service := newGuestRuntimeTopologyService(t, repository)
	result := service.ReadGuestRuntimeReadiness(context.Background())
	if result.State != "failed" || result.Issue == nil || result.Issue.Code != "guest-state-store-unavailable" {
		t.Fatalf("readiness result = %+v", result)
	}
}
