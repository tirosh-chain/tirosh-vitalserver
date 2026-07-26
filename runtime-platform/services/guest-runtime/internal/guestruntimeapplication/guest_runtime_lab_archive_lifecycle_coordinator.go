package guestruntimeapplication

import (
	"context"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeLabResourceCommandWorkflow is the Lab aggregate command boundary
// used by cross-aggregate coordination. The coordinator never accesses Lab
// application-service internals or Lab persistence.
type GuestRuntimeLabResourceCommandWorkflow interface {
	ExecuteLabResourceCommand(context.Context, guestruntimedomain.LabResourceCommand, []guestruntimedomain.ResourceReference) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure)
	ListPendingTerminalArchiveExportCandidates(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.TerminalArchiveExportCandidate, error)
	ListAllPendingTerminalArchiveExportCandidates(context.Context) ([]guestruntimedomain.TerminalArchiveExportCandidate, error)
	RecordTerminalArchiveDispatch(context.Context, guestruntimedomain.TerminalArchiveExportCandidate, string, *guestruntimedomain.ResourceReference, *guestruntimedomain.Issue) error
}

// GuestRuntimeArchiveRetentionAndExportWorkflow is the Archive Export boundary
// used by cross-aggregate coordination. It supplies explicit retention facts
// and owns export execution; it does not expose Archive persistence.
type GuestRuntimeArchiveRetentionAndExportWorkflow interface {
	ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error)
	ExecuteArtifactExportCommand(context.Context, guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure)
	ExecuteTerminalLabArtifactExport(context.Context, guestruntimedomain.TerminalArchiveExportCandidate) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure)
}

// GuestRuntimeLabArchiveLifecycleCoordinator owns only cross-aggregate ordering. It does not own Lab
// or Archive state: it serializes the explicit Lab-source / Archive-retention
// workflow calls so an export cannot enter between retention evidence and a delete.
type GuestRuntimeLabArchiveLifecycleCoordinator struct {
	labResourceCommandWorkflow        GuestRuntimeLabResourceCommandWorkflow
	archiveRetentionAndExportWorkflow GuestRuntimeArchiveRetentionAndExportWorkflow
	coordinationClock                 GuestRuntimeClock
	mu                                sync.Mutex
}

// NewGuestRuntimeLabArchiveLifecycleCoordinator requires every workflow and
// the coordinator's own time source explicitly. A nil result means the
// product composition did not provide this cross-aggregate use case.
func NewGuestRuntimeLabArchiveLifecycleCoordinator(
	labResourceCommandWorkflow GuestRuntimeLabResourceCommandWorkflow,
	archiveRetentionAndExportWorkflow GuestRuntimeArchiveRetentionAndExportWorkflow,
	coordinationClock GuestRuntimeClock,
) *GuestRuntimeLabArchiveLifecycleCoordinator {
	if labResourceCommandWorkflow == nil || archiveRetentionAndExportWorkflow == nil || coordinationClock == nil {
		return nil
	}
	return &GuestRuntimeLabArchiveLifecycleCoordinator{
		labResourceCommandWorkflow:        labResourceCommandWorkflow,
		archiveRetentionAndExportWorkflow: archiveRetentionAndExportWorkflow,
		coordinationClock:                 coordinationClock,
	}
}

func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) ExecuteLabResourceCommand(ctx context.Context, command guestruntimedomain.LabResourceCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	retained := []guestruntimedomain.ResourceReference(nil)
	if command.Action == "delete" && guestruntimedomain.ValidIdentifier(command.ResourceID) {
		var err error
		retained, err = coordinator.archiveRetentionAndExportWorkflow.ListArtifactsRetainedForResource(ctx, guestruntimedomain.ResourceReference{ResourceType: command.ResourceType, ResourceID: command.ResourceID})
		if err != nil {
			return guestruntimedomain.Operation{}, nil, &guestruntimedomain.CommandAdmissionFailure{
				SchemaVersion:  guestruntimedomain.SchemaVersion,
				State:          "failed",
				RequestID:      command.RequestID,
				ObservedAt:     guestruntimedomain.Timestamp(coordinator.coordinationClock.Now()),
				AdmissionState: "not-admitted",
				Issue: guestruntimedomain.Issue{
					Code:       "archive-retention-read-failed",
					Message:    "Lab delete was not admitted because Archive retention evidence could not be read: " + err.Error(),
					Retryable:  boolPointer(true),
					Dependency: "archive-export",
				},
			}
		}
	}
	operation, rejection, admissionFailure := coordinator.labResourceCommandWorkflow.ExecuteLabResourceCommand(ctx, command, retained)
	if rejection != nil || admissionFailure != nil || command.Action != "stop" || operation.State != "succeeded" {
		return operation, rejection, admissionFailure
	}
	// Archive dispatch is deliberately after a durable Lab stop. Its result is
	// recorded on each recorder's terminal intent; it never changes a Lab stop
	// into an upload success or failure.
	coordinator.dispatchTerminalArchiveIntents(ctx, guestruntimedomain.ResourceReference{ResourceType: command.ResourceType, ResourceID: command.ResourceID})
	return operation, nil, nil
}

func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) ExecuteArtifactExportCommand(ctx context.Context, command guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	return coordinator.archiveRetentionAndExportWorkflow.ExecuteArtifactExportCommand(ctx, command)
}

// ReconcilePendingTerminalArchiveExports repeats only durable, still
// dispatchable Lab archive intents. It is safe after a process restart: every
// candidate supplies its original deterministic Archive request ID and the
// exact completed Lab stop operation that owns the dispatch observation.
//
// A reconciliation error is not translated into a stopped-session success.
// The caller must report the error and leave the persisted intent visible for
// another explicit reconciliation attempt.
func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) ReconcilePendingTerminalArchiveExports(ctx context.Context) error {
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	candidates, err := coordinator.labResourceCommandWorkflow.ListAllPendingTerminalArchiveExportCandidates(ctx)
	if err != nil {
		return err
	}
	for _, candidate := range candidates {
		if err := coordinator.dispatchTerminalArchiveCandidate(ctx, candidate); err != nil {
			return err
		}
	}
	return nil
}

func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) dispatchTerminalArchiveIntents(ctx context.Context, target guestruntimedomain.ResourceReference) {
	candidates, err := coordinator.labResourceCommandWorkflow.ListPendingTerminalArchiveExportCandidates(ctx, target)
	if err != nil {
		// The durable intent remains pending and is visible on the recorder.
		// Do not fabricate a dispatch outcome when candidate selection failed.
		return
	}
	for _, candidate := range candidates {
		// A normal stop has already completed. Keep its result distinct from a
		// later Archive dispatch persistence failure; the durable pending intent
		// will be retried by explicit reconciliation.
		_ = coordinator.dispatchTerminalArchiveCandidate(ctx, candidate)
	}
}

func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) dispatchTerminalArchiveCandidate(ctx context.Context, candidate guestruntimedomain.TerminalArchiveExportCandidate) error {
	archiveOperation, rejection, admissionFailure := coordinator.archiveRetentionAndExportWorkflow.ExecuteTerminalLabArtifactExport(ctx, candidate)
	if rejection != nil {
		return coordinator.labResourceCommandWorkflow.RecordTerminalArchiveDispatch(ctx, candidate, "rejected", nil, &rejection.Issue)
	}
	if admissionFailure != nil {
		return coordinator.labResourceCommandWorkflow.RecordTerminalArchiveDispatch(ctx, candidate, "unavailable", nil, &admissionFailure.Issue)
	}
	return coordinator.labResourceCommandWorkflow.RecordTerminalArchiveDispatch(ctx, candidate, "submitted", &guestruntimedomain.ResourceReference{ResourceType: "operation", ResourceID: archiveOperation.ID}, nil)
}
