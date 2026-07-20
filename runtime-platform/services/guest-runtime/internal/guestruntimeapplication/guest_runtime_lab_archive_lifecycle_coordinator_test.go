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

func (workflow *recordingLabResourceCommandWorkflow) ListPendingTerminalArchiveExportCandidates(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	return nil, nil
}

func (workflow *recordingLabResourceCommandWorkflow) ListAllPendingTerminalArchiveExportCandidates(context.Context) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	return nil, nil
}

func (workflow *recordingLabResourceCommandWorkflow) RecordTerminalArchiveDispatch(context.Context, guestruntimedomain.TerminalArchiveExportCandidate, string, *guestruntimedomain.ResourceReference, *guestruntimedomain.Issue) error {
	return nil
}

type failingArchiveRetentionAndExportWorkflow struct{ retentionReads int }

func (workflow *failingArchiveRetentionAndExportWorkflow) ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error) {
	workflow.retentionReads++
	return nil, errors.New("archive storage is unavailable")
}

func (workflow *failingArchiveRetentionAndExportWorkflow) ExecuteArtifactExportCommand(context.Context, guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, nil
}

func (workflow *failingArchiveRetentionAndExportWorkflow) ExecuteTerminalLabArtifactExport(context.Context, guestruntimedomain.TerminalArchiveExportCandidate) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
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

type terminalArchiveDispatchLabWorkflow struct {
	candidates []guestruntimedomain.TerminalArchiveExportCandidate
	recorded   []guestruntimedomain.ResourceReference
}

func (workflow *terminalArchiveDispatchLabWorkflow) ExecuteLabResourceCommand(context.Context, guestruntimedomain.LabResourceCommand, []guestruntimedomain.ResourceReference) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{ID: "lab-stop-operation-1", RequestID: "stop-session-1", State: "succeeded"}, nil, nil
}

func (workflow *terminalArchiveDispatchLabWorkflow) ListPendingTerminalArchiveExportCandidates(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	return workflow.candidates, nil
}

func (workflow *terminalArchiveDispatchLabWorkflow) ListAllPendingTerminalArchiveExportCandidates(context.Context) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	return workflow.candidates, nil
}

func (workflow *terminalArchiveDispatchLabWorkflow) RecordTerminalArchiveDispatch(_ context.Context, _ guestruntimedomain.TerminalArchiveExportCandidate, outcome string, reference *guestruntimedomain.ResourceReference, issue *guestruntimedomain.Issue) error {
	if outcome != "submitted" {
		return errors.New("unexpected dispatch outcome: " + outcome)
	}
	if issue != nil {
		return errors.New("unexpected dispatch issue: " + issue.Code)
	}
	workflow.recorded = append(workflow.recorded, *reference)
	return nil
}

type terminalArchiveDispatchArchiveWorkflow struct {
	candidates []guestruntimedomain.TerminalArchiveExportCandidate
}

func (workflow *terminalArchiveDispatchArchiveWorkflow) ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error) {
	return nil, nil
}

func (workflow *terminalArchiveDispatchArchiveWorkflow) ExecuteArtifactExportCommand(context.Context, guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, nil
}

func (workflow *terminalArchiveDispatchArchiveWorkflow) ExecuteTerminalLabArtifactExport(_ context.Context, candidate guestruntimedomain.TerminalArchiveExportCandidate) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	workflow.candidates = append(workflow.candidates, candidate)
	return guestruntimedomain.Operation{ID: "archive-operation-" + candidate.VirtualRecorderID, State: "running"}, nil, nil
}

func TestLabArchiveLifecycleCoordinatorDispatchesTerminalArchiveAfterSuccessfulStop(t *testing.T) {
	labWorkflow := &terminalArchiveDispatchLabWorkflow{candidates: []guestruntimedomain.TerminalArchiveExportCandidate{{RequestID: "terminal-archive-1", VirtualRecorderID: "lab-recorder-1", ExpectedResourceRevision: 5, ColdPathFinalizationReceiptID: "finalization-1", LabOperationReference: guestruntimedomain.ResourceReference{ResourceType: "operation", ResourceID: "lab-stop-operation-1"}}}}
	archiveWorkflow := &terminalArchiveDispatchArchiveWorkflow{}
	coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(labWorkflow, archiveWorkflow, fixedLabArchiveLifecycleCoordinationClock{at: time.Now().UTC()})
	operation, rejection, admissionFailure := coordinator.ExecuteLabResourceCommand(context.Background(), guestruntimedomain.LabResourceCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "stop-session-1", ResourceType: guestruntimedomain.LabSessionResourceType, ResourceID: "lab-session-1", ExpectedResourceRevision: 4, Action: "stop"})
	if rejection != nil || admissionFailure != nil || operation.State != "succeeded" {
		t.Fatalf("stop result operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if len(archiveWorkflow.candidates) != 1 || archiveWorkflow.candidates[0].ColdPathFinalizationReceiptID != "finalization-1" {
		t.Fatalf("archive candidates=%+v", archiveWorkflow.candidates)
	}
	if len(labWorkflow.recorded) != 1 || labWorkflow.recorded[0].ResourceType != "operation" || labWorkflow.recorded[0].ResourceID != "archive-operation-lab-recorder-1" {
		t.Fatalf("dispatch evidence=%+v", labWorkflow.recorded)
	}
}

func TestLabArchiveLifecycleCoordinatorReconcilesPersistedTerminalArchiveIntent(t *testing.T) {
	labWorkflow := &terminalArchiveDispatchLabWorkflow{candidates: []guestruntimedomain.TerminalArchiveExportCandidate{{RequestID: "terminal-archive-reconcile-1", VirtualRecorderID: "lab-recorder-1", ExpectedResourceRevision: 5, ColdPathFinalizationReceiptID: "finalization-1", LabOperationReference: guestruntimedomain.ResourceReference{ResourceType: "operation", ResourceID: "lab-stop-operation-1"}}}}
	archiveWorkflow := &terminalArchiveDispatchArchiveWorkflow{}
	coordinator := NewGuestRuntimeLabArchiveLifecycleCoordinator(labWorkflow, archiveWorkflow, fixedLabArchiveLifecycleCoordinationClock{at: time.Now().UTC()})
	if err := coordinator.ReconcilePendingTerminalArchiveExports(context.Background()); err != nil {
		t.Fatalf("reconcile terminal archive intent: %v", err)
	}
	if len(archiveWorkflow.candidates) != 1 || archiveWorkflow.candidates[0].RequestID != "terminal-archive-reconcile-1" {
		t.Fatalf("reconciled archive candidates=%+v", archiveWorkflow.candidates)
	}
	if len(labWorkflow.recorded) != 1 || labWorkflow.recorded[0].ResourceID != "archive-operation-lab-recorder-1" {
		t.Fatalf("reconciled dispatch evidence=%+v", labWorkflow.recorded)
	}
}
