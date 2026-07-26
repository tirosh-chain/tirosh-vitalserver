package gueststatesqliterepository

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestCommitRuntimeTopologyApplicationRejectsStaleRevisionBeforeCreatingOperation(t *testing.T) {
	repository, err := OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })

	if err := repository.CommitRuntimeTopologyApplication(context.Background(), topology(1), nil, operation("operation-1", "request-1")); err != nil {
		t.Fatalf("commit initial topology: %v", err)
	}
	if err := repository.CommitRuntimeTopologyApplication(context.Background(), topology(2), nil, operation("operation-2", "request-2")); err != nil {
		t.Fatalf("commit next topology: %v", err)
	}
	if err := repository.CommitRuntimeTopologyApplication(context.Background(), topology(2), nil, operation("operation-3", "request-3")); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict) {
		t.Fatalf("stale revision error = %v", err)
	}
	if _, err := repository.ReadRuntimeTopologyOperation(context.Background(), "operation-3"); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound) {
		t.Fatalf("stale revision created operation: %v", err)
	}
}

func TestCommitRuntimeTopologyApplicationAtomicallyReplacesBundledCapabilityAndRemovesItForExternalProfile(t *testing.T) {
	repository, err := OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	bundled := topology(1)
	bundled.Spec.ProfileKind = "bundled-upstream"
	bundled.Spec.EndpointReference.ResourceID = "bundled-vitalserver"
	capability, err := guestruntimedomain.BundledUpstreamCapability(bundled.ID, bundled.Spec, 1, mustTime(t, "2026-07-17T00:00:00Z"))
	if err != nil {
		t.Fatalf("build capability: %v", err)
	}
	bundled.Status = guestruntimedomain.BundledTopologyStatus(mustTime(t, "2026-07-17T00:00:00Z"), "operation-1", capability)
	if err := repository.CommitRuntimeTopologyApplication(context.Background(), bundled, &capability, operation("operation-1", "request-1")); err != nil {
		t.Fatalf("commit bundled topology: %v", err)
	}
	persisted, err := repository.ReadRuntimeTopologyCapabilityDocument(context.Background())
	if err != nil || persisted.ID != capability.ID {
		t.Fatalf("persisted capability = %+v err=%v", persisted, err)
	}
	external := topology(2)
	if err := repository.CommitRuntimeTopologyApplication(context.Background(), external, nil, operation("operation-2", "request-2")); err != nil {
		t.Fatalf("commit external topology: %v", err)
	}
	if _, err := repository.ReadRuntimeTopologyCapabilityDocument(context.Background()); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound) {
		t.Fatalf("external profile retained a stale capability: %v", err)
	}
}

func TestCommitLabRejectsStaleTargetWithoutPersistingOperation(t *testing.T) {
	repository, err := OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	initial := labSession(1, "prepared")
	if err := repository.CommitLabStateTransition(context.Background(), guestruntimeapplication.LabStateTransitionCommit{
		Operation:     labOperation("lab-operation-1", "lab-request-1", 0),
		UpsertSession: &initial,
	}); err != nil {
		t.Fatalf("commit initial Lab session: %v", err)
	}
	next := labSession(2, "running")
	if err := repository.CommitLabStateTransition(context.Background(), guestruntimeapplication.LabStateTransitionCommit{
		Operation:     labOperation("lab-operation-2", "lab-request-2", 1),
		UpsertSession: &next,
	}); err != nil {
		t.Fatalf("commit next Lab session: %v", err)
	}
	stale := labSession(2, "stopped")
	err = repository.CommitLabStateTransition(context.Background(), guestruntimeapplication.LabStateTransitionCommit{
		Operation:     labOperation("lab-operation-3", "lab-request-3", 1),
		UpsertSession: &stale,
	})
	if !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict) {
		t.Fatalf("stale Lab commit error = %v", err)
	}
	if _, err := repository.ReadLabOperation(context.Background(), "lab-operation-3"); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound) {
		t.Fatalf("stale Lab commit created operation: %v", err)
	}
	persisted, err := repository.ReadLabSession(context.Background(), initial.ID)
	if err != nil || persisted.State != "running" || persisted.ResourceRevision != 2 {
		t.Fatalf("stale Lab commit changed session persisted=%+v err=%v", persisted, err)
	}
}

func mustTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func topology(revision int) guestruntimedomain.RuntimeTopology {
	return guestruntimedomain.RuntimeTopology{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		ID:               "primary-topology",
		ResourceRevision: revision,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:  "external-upstream",
			ProviderKind: "vitalserver",
			EndpointReference: guestruntimedomain.ResourceReference{
				ResourceType: "upstream-endpoint",
				ResourceID:   "primary",
			},
		},
		Status: guestruntimedomain.TopologyStatus{
			ReadState: "unsupported",
			Connection: guestruntimedomain.ConnectionObservation{
				State:      "not-checked",
				ObservedAt: "2026-07-17T00:00:00Z",
			},
			ObservedAt: "2026-07-17T00:00:00Z",
		},
		CreatedAt: "2026-07-17T00:00:00Z",
		UpdatedAt: "2026-07-17T00:00:00Z",
	}
}

func operation(id string, requestID string) guestruntimedomain.Operation {
	acceptedAt := "2026-07-17T00:00:00Z"
	startedAt := "2026-07-17T00:00:01Z"
	finishedAt := "2026-07-17T00:00:02Z"
	return guestruntimedomain.Operation{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ID:            id,
		Kind:          "runtime.topology.apply",
		RequestID:     requestID,
		Target: guestruntimedomain.OperationTarget{
			ResourceType:              "runtime-topology",
			ResourceID:                "primary-topology",
			RequestedResourceRevision: 0,
		},
		RequestedAt:   "2026-07-17T00:00:00Z",
		AcceptedAt:    &acceptedAt,
		StartedAt:     &startedAt,
		FinishedAt:    &finishedAt,
		State:         "succeeded",
		CommandDigest: "test-digest",
	}
}

func labSession(revision int, state string) guestruntimedomain.LabSession {
	return guestruntimedomain.LabSession{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ID:            "lab-session-1", Name: "LAB-test", Origin: "lab", ResourceRevision: revision,
		Scenario: "test", State: state,
		CreatedAt: "2026-07-17T00:00:00Z", UpdatedAt: "2026-07-17T00:00:00Z",
	}
}

func labOperation(id string, requestID string, requestedRevision int) guestruntimedomain.Operation {
	acceptedAt := "2026-07-17T00:00:00Z"
	startedAt := "2026-07-17T00:00:01Z"
	finishedAt := "2026-07-17T00:00:02Z"
	return guestruntimedomain.Operation{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ID:            id, Kind: "lab.resource.start", RequestID: requestID,
		Target:      guestruntimedomain.OperationTarget{ResourceType: guestruntimedomain.LabSessionResourceType, ResourceID: "lab-session-1", RequestedResourceRevision: requestedRevision},
		RequestedAt: "2026-07-17T00:00:00Z", AcceptedAt: &acceptedAt, StartedAt: &startedAt, FinishedAt: &finishedAt,
		State: "succeeded", CommandDigest: "test-digest-" + id,
	}
}
