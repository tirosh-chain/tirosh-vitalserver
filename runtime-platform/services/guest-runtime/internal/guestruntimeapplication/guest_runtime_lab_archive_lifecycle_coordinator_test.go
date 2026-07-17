package guestruntimeapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type fixedLabArchiveLifecycleCoordinationClock struct{ at time.Time }

func (clock fixedLabArchiveLifecycleCoordinationClock) Now() time.Time { return clock.at }

type recordingLabResourceCommandWorkflow struct{ calls int }

func (workflow *recordingLabResourceCommandWorkflow) ExecuteLabResourceCommand(context.Context, guestruntimedomain.LabResourceCommand, []guestruntimedomain.ResourceReference) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	workflow.calls++
	return guestruntimedomain.Operation{}, nil, nil
}

type failingArchiveRetentionAndExportWorkflow struct{ retentionReads int }

func (workflow *failingArchiveRetentionAndExportWorkflow) ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error) {
	workflow.retentionReads++
	return nil, errors.New("archive storage is unavailable")
}

func (workflow *failingArchiveRetentionAndExportWorkflow) ExecuteArtifactExportCommand(context.Context, guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, nil
}

func TestLabArchiveLifecycleCoordinatorDoesNotAdmitDeleteWithoutArchiveRetentionEvidence(t *testing.T) {
	labWorkflow := &recordingLabResourceCommandWorkflow{}
	archiveWorkflow := &failingArchiveRetentionAndExportWorkflow{}
	coordinationClock := fixedLabArchiveLifecycleCoordinationClock{at: time.Date(2026, 7, 18, 9, 30, 0, 0, time.UTC)}
	coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(labWorkflow, archiveWorkflow, coordinationClock)
	if coordinator == nil {
		t.Fatal("expected explicit Lab/Archive workflows and coordination clock to compose")
	}

	operation, rejection, admissionFailure := coordinator.ExecuteLabResourceCommand(context.Background(), guestruntimedomain.LabResourceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "delete-lab-session-1",
		ResourceType:  guestruntimedomain.LabSessionResourceType,
		ResourceID:    "lab-session-1",
		Action:        "delete",
	})
	if rejection != nil || operation.ID != "" || admissionFailure == nil {
		t.Fatalf("expected archive-retention admission failure, operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if admissionFailure.Issue.Code != "archive-retention-read-failed" || admissionFailure.ObservedAt != "2026-07-18T09:30:00Z" {
		t.Fatalf("expected coordinator-owned failure evidence, got %+v", admissionFailure)
	}
	if archiveWorkflow.retentionReads != 1 || labWorkflow.calls != 0 {
		t.Fatalf("delete must stop at the explicit Archive retention boundary, archive reads=%d lab command calls=%d", archiveWorkflow.retentionReads, labWorkflow.calls)
	}
}

func TestLabArchiveLifecycleCoordinatorRequiresEveryExplicitWorkflowDependency(t *testing.T) {
	labWorkflow := &recordingLabResourceCommandWorkflow{}
	archiveWorkflow := &failingArchiveRetentionAndExportWorkflow{}
	clock := fixedLabArchiveLifecycleCoordinationClock{at: time.Now().UTC()}
	if coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(nil, archiveWorkflow, clock); coordinator != nil {
		t.Fatal("missing Lab workflow must not create a coordinator")
	}
	if coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(labWorkflow, nil, clock); coordinator != nil {
		t.Fatal("missing Archive workflow must not create a coordinator")
	}
	if coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(labWorkflow, archiveWorkflow, nil); coordinator != nil {
		t.Fatal("missing coordination clock must not create a coordinator")
	}
}
