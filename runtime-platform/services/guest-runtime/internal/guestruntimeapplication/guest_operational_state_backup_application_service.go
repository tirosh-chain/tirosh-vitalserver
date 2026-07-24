package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	GuestStateBackupStageOutcomeSucceeded = "succeeded"
	GuestStateBackupStageOutcomeRejected  = "rejected"
)

type PendingGuestOperationalStateBackupEffect struct {
	Operation guestruntimedomain.GuestOperationalStateBackupOperation
	Effect    string
}

type GuestOperationalStateBackupOperationRepository interface {
	ReadOperation(context.Context, string) (guestruntimedomain.GuestOperationalStateBackupOperation, error)
	ReadOperationByRequestID(context.Context, string) (guestruntimedomain.GuestOperationalStateBackupOperation, error)
	AdmitOperation(context.Context, string, guestruntimedomain.GuestOperationalStateBackupOperation, string) error
	ListPendingEffects(context.Context, int) ([]PendingGuestOperationalStateBackupEffect, error)
	CommitTransition(context.Context, guestruntimedomain.GuestOperationalStateBackupOperation, guestruntimedomain.GuestOperationalStateBackupOperation, string, string) error
}

type GuestOperationalStateBackupStageResult struct {
	Outcome           string
	Receipt           *guestruntimedomain.GuestOperationalStateBackupStageReceipt
	FailureCode       string
	FailureMessage    string
	ManifestReference *guestruntimedomain.ResourceReference
	ManifestSHA256    string
}

// GuestOperationalStateBackupStageExecutor owns external stage effects. A Go
// error means outcome unknown and leaves the durable effect pending. A known
// rejection must use Outcome=rejected with an explicit code and message.
type GuestOperationalStateBackupStageExecutor interface {
	ExecuteStage(
		context.Context,
		guestruntimedomain.GuestOperationalStateBackupOperation,
		string,
	) (GuestOperationalStateBackupStageResult, error)
}

// GuestOperationalStateArtifactInventoryOwner streams the complete,
// deterministic Archive-owner inventory. Streaming is required so backup size
// does not become Guest Runtime heap usage.
type GuestOperationalStateArtifactInventoryOwner interface {
	WriteGuestOperationalStateArtifactInventory(
		context.Context,
		string,
		string,
		io.Writer,
	) (int, error)
}

type GuestOperationalStateBackupApplicationService struct {
	repository GuestOperationalStateBackupOperationRepository
	executor   GuestOperationalStateBackupStageExecutor
	clock      GuestRuntimeClock
	workflow   sync.Mutex
}

func NewGuestOperationalStateBackupApplicationService(
	repository GuestOperationalStateBackupOperationRepository,
	executor GuestOperationalStateBackupStageExecutor,
	clock GuestRuntimeClock,
) (*GuestOperationalStateBackupApplicationService, error) {
	if repository == nil || executor == nil || clock == nil {
		return nil, fmt.Errorf("Guest operational-state backup repository, stage executor, and clock are required")
	}
	return &GuestOperationalStateBackupApplicationService{
		repository: repository,
		executor:   executor,
		clock:      clock,
	}, nil
}

func (service *GuestOperationalStateBackupApplicationService) AdmitBackup(
	ctx context.Context,
	command guestruntimedomain.GuestOperationalStateBackupCommand,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	decision, err := guestruntimedomain.NewGuestOperationalStateBackupOperation(command)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, err
	}
	return service.admit(
		ctx,
		command.RequestID,
		command,
		decision.Next,
		func(stored guestruntimedomain.GuestOperationalStateBackupOperation) bool {
			return stored.Kind == guestruntimedomain.GuestStateBackupKind &&
				stored.ID == command.OperationID &&
				stored.DestinationReference != nil &&
				*stored.DestinationReference == command.DestinationReference &&
				stored.CreatedAt == command.RequestedAt
		},
	)
}

func (service *GuestOperationalStateBackupApplicationService) AdmitRestore(
	ctx context.Context,
	command guestruntimedomain.GuestOperationalStateRestoreCommand,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	decision, err := guestruntimedomain.NewGuestOperationalStateRestoreOperation(command)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, err
	}
	return service.admit(
		ctx,
		command.RequestID,
		command,
		decision.Next,
		func(stored guestruntimedomain.GuestOperationalStateBackupOperation) bool {
			return stored.Kind == guestruntimedomain.GuestStateRestoreKind &&
				stored.ID == command.OperationID &&
				stored.ManifestReference != nil &&
				*stored.ManifestReference == command.ManifestReference &&
				stored.ManifestSHA256 == command.ManifestSHA256 &&
				stored.TargetReference != nil &&
				*stored.TargetReference == command.TargetReference &&
				stored.CreatedAt == command.RequestedAt
		},
	)
}

func (service *GuestOperationalStateBackupApplicationService) admit(
	ctx context.Context,
	requestID string,
	command any,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	matches func(guestruntimedomain.GuestOperationalStateBackupOperation) bool,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	commandDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, fmt.Errorf("digest Guest operational-state backup command: %w", err)
	}
	stored, err := service.repository.ReadOperationByRequestID(ctx, requestID)
	switch {
	case err == nil && matches(stored):
		return stored, nil
	case err == nil:
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, fmt.Errorf("%w: Guest operational-state backup requestId conflict", ErrGuestRuntimeOwnedResourceConflict)
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, fmt.Errorf("read Guest operational-state backup request: %w", err)
	}
	if err := service.repository.AdmitOperation(
		ctx,
		commandDigest,
		operation,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); err != nil {
		resolved, readErr := service.repository.ReadOperationByRequestID(ctx, requestID)
		if readErr == nil && matches(resolved) {
			return resolved, nil
		}
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, fmt.Errorf("Guest operational-state backup admission outcome is unknown: %w", err)
	}
	return operation, nil
}

func (service *GuestOperationalStateBackupApplicationService) ReadOperation(
	ctx context.Context,
	operationID string,
) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(operationID) {
		return invalidRead(now, "invalid-guest-state-backup-operation-id", "operationId must be a v1 identifier")
	}
	operation, err := service.repository.ReadOperation(ctx, operationID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "guest-state-backup-operation-missing", "the requested backup or restore operation does not exist")
	}
	if err != nil {
		return failedRead(now, "guest-state-backup-operation-read-failed", err.Error(), "guest-state-backup-ledger")
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value:         operation,
	}
}

func (service *GuestOperationalStateBackupApplicationService) RunNextPendingEffect(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStateBackupOperation, bool, error) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	effects, err := service.repository.ListPendingEffects(ctx, 1)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, false, err
	}
	if len(effects) == 0 {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, false, nil
	}
	effect := effects[0]
	if effect.Effect == guestruntimedomain.GuestStateBackupStartWorkflowEffect {
		decision, err := guestruntimedomain.DecideGuestOperationalStateBackupTransition(
			effect.Operation,
			guestruntimedomain.GuestOperationalStateBackupEvent{
				Kind:       guestruntimedomain.GuestStateBackupWorkflowStartedEvent,
				OccurredAt: guestruntimedomain.Timestamp(service.clock.Now()),
			},
		)
		if err != nil {
			return effect.Operation, true, err
		}
		return service.commit(ctx, effect, decision)
	}
	result, err := service.executor.ExecuteStage(ctx, effect.Operation, effect.Effect)
	if err != nil {
		return effect.Operation, true, fmt.Errorf("Guest operational-state backup effect outcome is unknown: %w", err)
	}
	occurredAt := guestruntimedomain.Timestamp(service.clock.Now())
	var event guestruntimedomain.GuestOperationalStateBackupEvent
	switch result.Outcome {
	case GuestStateBackupStageOutcomeSucceeded:
		if result.Receipt == nil {
			return effect.Operation, true, fmt.Errorf("Guest operational-state backup succeeded stage omitted receipt")
		}
		occurredAt = result.Receipt.CompletedAt
		event = guestruntimedomain.GuestOperationalStateBackupEvent{
			Kind:              guestruntimedomain.GuestStateBackupStageSucceededEvent,
			OccurredAt:        occurredAt,
			StageReceipt:      result.Receipt,
			ManifestReference: result.ManifestReference,
			ManifestSHA256:    result.ManifestSHA256,
		}
	case GuestStateBackupStageOutcomeRejected:
		failure := guestruntimedomain.GuestOperationalStateBackupFailure{
			Stage:    effect.Effect,
			Code:     result.FailureCode,
			Message:  result.FailureMessage,
			FailedAt: occurredAt,
		}
		event = guestruntimedomain.GuestOperationalStateBackupEvent{
			Kind:       guestruntimedomain.GuestStateBackupStageFailedEvent,
			OccurredAt: occurredAt,
			Failure:    &failure,
		}
	default:
		return effect.Operation, true, fmt.Errorf("Guest operational-state backup stage outcome is invalid")
	}
	decision, err := guestruntimedomain.DecideGuestOperationalStateBackupTransition(
		effect.Operation,
		event,
	)
	if err != nil {
		return effect.Operation, true, err
	}
	return service.commit(ctx, effect, decision)
}

func (service *GuestOperationalStateBackupApplicationService) commit(
	ctx context.Context,
	effect PendingGuestOperationalStateBackupEffect,
	decision guestruntimedomain.GuestOperationalStateBackupDecision,
) (guestruntimedomain.GuestOperationalStateBackupOperation, bool, error) {
	if err := service.repository.CommitTransition(
		ctx,
		effect.Operation,
		decision.Next,
		effect.Effect,
		decision.Effect,
	); err != nil {
		return effect.Operation, true, fmt.Errorf("commit Guest operational-state backup transition: %w", err)
	}
	return decision.Next, true, nil
}
