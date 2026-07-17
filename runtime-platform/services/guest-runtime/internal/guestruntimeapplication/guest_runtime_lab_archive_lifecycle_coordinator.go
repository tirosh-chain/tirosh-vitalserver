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
}

// GuestRuntimeArchiveRetentionAndExportWorkflow is the Archive Export boundary
// used by cross-aggregate coordination. It supplies explicit retention facts
// and owns export execution; it does not expose Archive persistence.
type GuestRuntimeArchiveRetentionAndExportWorkflow interface {
	ListArtifactsRetainedForResource(context.Context, guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error)
	ExecuteArtifactExportCommand(context.Context, guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure)
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
	return coordinator.labResourceCommandWorkflow.ExecuteLabResourceCommand(ctx, command, retained)
}

func (coordinator *GuestRuntimeLabArchiveLifecycleCoordinator) ExecuteArtifactExportCommand(ctx context.Context, command guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	coordinator.mu.Lock()
	defer coordinator.mu.Unlock()
	return coordinator.archiveRetentionAndExportWorkflow.ExecuteArtifactExportCommand(ctx, command)
}
