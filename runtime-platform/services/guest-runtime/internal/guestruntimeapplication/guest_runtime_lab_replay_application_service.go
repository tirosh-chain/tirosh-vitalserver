package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type GuestRuntimeLabReplayApplicationService struct {
	repository     GuestRuntimeLabReplayRepository
	objectStore    GuestRuntimeLabReplaySourceObjectStore
	parser         GuestRuntimeVitalFileReplayParser
	spoolFactory   GuestRuntimeVitalFileReplaySpoolFactory
	effectRunner   GuestRuntimeLabReplayEffectRunner
	frameBatchSize int
	gapPolicy      string
	clock          GuestRuntimeClock
	workflow       sync.Mutex
}

func NewGuestRuntimeLabReplayApplicationService(
	repository GuestRuntimeLabReplayRepository,
	objectStore GuestRuntimeLabReplaySourceObjectStore,
	parser GuestRuntimeVitalFileReplayParser,
	spoolFactory GuestRuntimeVitalFileReplaySpoolFactory,
	effectRunner GuestRuntimeLabReplayEffectRunner,
	frameBatchSize int,
	gapPolicy string,
	clock GuestRuntimeClock,
) (*GuestRuntimeLabReplayApplicationService, error) {
	if repository == nil ||
		objectStore == nil ||
		parser == nil ||
		spoolFactory == nil ||
		effectRunner == nil ||
		frameBatchSize < 1 ||
		frameBatchSize > 60 ||
		!guestruntimedomain.ValidVitalFileReplayGapPolicy(gapPolicy) ||
		clock == nil {
		return nil, fmt.Errorf("Lab replay repository, source, parser, spool, effect runner, bounded frame batch, gap policy, and clock are required")
	}
	return &GuestRuntimeLabReplayApplicationService{
		repository:     repository,
		objectStore:    objectStore,
		parser:         parser,
		spoolFactory:   spoolFactory,
		effectRunner:   effectRunner,
		frameBatchSize: frameBatchSize,
		gapPolicy:      gapPolicy,
		clock:          clock,
	}, nil
}

func (service *GuestRuntimeLabReplayApplicationService) ReadLabReplay(
	ctx context.Context,
	replayID string,
) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(replayID) {
		return invalidRead(
			now,
			"invalid-lab-replay-id",
			"replayId must be a v1 identifier",
		)
	}
	operation, err := service.repository.ReadLabReplayOperation(ctx, replayID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(
			now,
			"lab-replay-missing",
			"the requested Lab replay operation does not exist",
		)
	}
	if err != nil {
		return failedRead(
			now,
			"lab-replay-state-read-failed",
			err.Error(),
			"guest-state-store",
		)
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value:         operation,
	}
}

func (service *GuestRuntimeLabReplayApplicationService) AdmitLabReplay(
	ctx context.Context,
	command guestruntimedomain.LabReplayCommand,
) (guestruntimedomain.LabReplayOperation, error) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	decision, err := guestruntimedomain.NewLabReplayOperation(command)
	if err != nil {
		return guestruntimedomain.LabReplayOperation{}, err
	}
	commandDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("digest Lab replay command: %w", err)
	}
	stored, err := service.repository.ReadLabReplayOperationByRequestID(
		ctx,
		command.RequestID,
	)
	switch {
	case err == nil && labReplayOperationMatchesCommand(stored, command):
		return stored, nil
	case err == nil:
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("%w: Lab replay requestId conflict", ErrGuestRuntimeOwnedResourceConflict)
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("read Lab replay request: %w", err)
	}
	if err := guestruntimedomain.ValidateLabReplayAdmissionClock(
		command,
		guestruntimedomain.Timestamp(service.clock.Now()),
	); err != nil {
		return guestruntimedomain.LabReplayOperation{}, err
	}
	if err := service.repository.AdmitLabReplayOperation(
		ctx,
		commandDigest,
		decision.Next,
		decision.Command,
	); err != nil {
		resolved, readErr := service.repository.ReadLabReplayOperationByRequestID(
			ctx,
			command.RequestID,
		)
		if readErr == nil && labReplayOperationMatchesCommand(resolved, command) {
			return resolved, nil
		}
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("Lab replay admission outcome is unknown: %w", err)
	}
	return decision.Next, nil
}

func (service *GuestRuntimeLabReplayApplicationService) RunNextPendingLabReplayEffect(
	ctx context.Context,
) (guestruntimedomain.LabReplayOperation, bool, error) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	effects, err := service.repository.ListPendingLabReplayEffects(ctx, 1)
	if err != nil {
		return guestruntimedomain.LabReplayOperation{}, false, err
	}
	if len(effects) == 0 {
		return guestruntimedomain.LabReplayOperation{}, false, nil
	}
	effect := effects[0]
	switch effect.Command {
	case guestruntimedomain.LabReplayValidateFileCommand:
		operation, err := service.validateLabReplayFile(ctx, effect)
		return operation, true, err
	case guestruntimedomain.LabReplayDecodeTracksCommand:
		operation, err := service.decodeLabReplayTracks(ctx, effect)
		return operation, true, err
	case guestruntimedomain.LabReplayPrepareCommand:
		operation, err := service.prepareLabReplay(ctx, effect)
		return operation, true, err
	case guestruntimedomain.LabReplaySendMessagesCommand:
		operation, err := service.sendLabReplayMessages(ctx, effect)
		return operation, true, err
	case guestruntimedomain.LabReplayConfirmUpstreamDeliveryCommand:
		operation, err := service.confirmLabReplayUpstreamDelivery(ctx, effect)
		return operation, true, err
	default:
		return effect.Operation, true, fmt.Errorf(
			"Lab replay effect adapter is unavailable for command %s",
			effect.Command,
		)
	}
}

func (service *GuestRuntimeLabReplayApplicationService) validateLabReplayFile(
	ctx context.Context,
	effect PendingLabReplayEffect,
) (guestruntimedomain.LabReplayOperation, error) {
	content, err := service.openLabReplaySource(ctx, effect.Operation)
	if err != nil {
		return service.failLabReplayEffect(
			ctx,
			effect,
			"lab-replay-source-open-failed",
			err,
		)
	}
	_, probeErr := service.parser.Probe(content)
	closeErr := content.Close()
	if probeErr != nil {
		return service.failLabReplayEffect(
			ctx,
			effect,
			replayFailureCode(probeErr, "vital-file-validation-failed"),
			probeErr,
		)
	}
	if closeErr != nil {
		return service.failLabReplayEffect(
			ctx,
			effect,
			"lab-replay-source-close-failed",
			closeErr,
		)
	}
	decision, err := guestruntimedomain.DecideLabReplayTransition(
		effect.Operation,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayFileValidatedEvent,
			OccurredAt: guestruntimedomain.Timestamp(service.clock.Now()),
		},
	)
	if err != nil {
		return effect.Operation, err
	}
	if err := service.repository.CommitLabReplayTransition(
		ctx,
		effect.Operation,
		decision.Next,
		effect.Command,
		decision.Command,
	); err != nil {
		return effect.Operation, fmt.Errorf("commit Lab replay file validation: %w", err)
	}
	return decision.Next, nil
}

func (service *GuestRuntimeLabReplayApplicationService) decodeLabReplayTracks(
	ctx context.Context,
	effect PendingLabReplayEffect,
) (guestruntimedomain.LabReplayOperation, error) {
	spoolReceipt, err := service.spoolFactory.ReadFinalizedSpoolReceipt(
		effect.Operation.ID,
	)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		spoolReceipt, err = service.createLabReplaySpool(ctx, effect.Operation)
	}
	if err != nil {
		return service.failLabReplayEffect(
			ctx,
			effect,
			replayFailureCode(err, "vital-track-decode-failed"),
			err,
		)
	}
	validatedAt := spoolReceipt.FinalizedAt
	validationReceipt := guestruntimedomain.LabReplayValidationReceipt{
		SchemaVersion:              guestruntimedomain.SchemaVersion,
		ParserContractVersion:      guestruntimedomain.LabReplayVitalParserContractVersion,
		SourceReference:            effect.Operation.SourceReference,
		SourceSHA256:               effect.Operation.SourceSHA256,
		FileFormatVersion:          spoolReceipt.FileFormatVersion,
		GraphCompatibleSignalCount: spoolReceipt.GraphCompatibleSignalCount,
		SpoolReceipt:               spoolReceipt,
		ValidatedAt:                validatedAt,
	}
	decision, err := guestruntimedomain.DecideLabReplayTransition(
		effect.Operation,
		guestruntimedomain.LabReplayEvent{
			Kind:              guestruntimedomain.LabReplayTracksDecodedEvent,
			OccurredAt:        validatedAt,
			ValidationReceipt: &validationReceipt,
		},
	)
	if err != nil {
		return effect.Operation, err
	}
	if err := service.repository.CommitLabReplayTransition(
		ctx,
		effect.Operation,
		decision.Next,
		effect.Command,
		decision.Command,
	); err != nil {
		return effect.Operation, fmt.Errorf("commit Lab replay track decode: %w", err)
	}
	return decision.Next, nil
}

func (service *GuestRuntimeLabReplayApplicationService) prepareLabReplay(
	ctx context.Context,
	effect PendingLabReplayEffect,
) (guestruntimedomain.LabReplayOperation, error) {
	if effect.Operation.ValidationReceipt == nil {
		return effect.Operation, fmt.Errorf("Lab replay preparation has no validation receipt")
	}
	receipt, err := service.effectRunner.PrepareLabReplay(
		ctx,
		LabReplayPrepareEffect{
			ReplayID:                    effect.Operation.ID,
			RecorderGatewayRecorderCode: effect.Operation.RecorderGatewayRecorderCode,
			SpoolReceipt:                effect.Operation.ValidationReceipt.SpoolReceipt,
		},
	)
	if err != nil {
		return service.handleLabReplayEffectError(ctx, effect, err)
	}
	return service.commitLabReplayEvent(
		ctx,
		effect,
		guestruntimedomain.LabReplayEvent{
			Kind:               guestruntimedomain.LabReplayPreparedEvent,
			OccurredAt:         receipt.PreparedAt,
			PreparationReceipt: &receipt,
		},
	)
}

func (service *GuestRuntimeLabReplayApplicationService) sendLabReplayMessages(
	ctx context.Context,
	effect PendingLabReplayEffect,
) (guestruntimedomain.LabReplayOperation, error) {
	operation := effect.Operation
	if operation.ValidationReceipt == nil || operation.PreparationReceipt == nil {
		return operation, fmt.Errorf("Lab replay send has no validation or preparation receipt")
	}
	remaining := operation.PreparationReceipt.FrameCount - operation.NextFrameOffsetSecond
	if remaining < 1 {
		return operation, fmt.Errorf("Lab replay send cursor has no remaining frame")
	}
	frameCount := min(service.frameBatchSize, remaining)
	batchID, err := guestruntimedomain.LabReplayMessageBatchID(
		operation.ID,
		operation.NextFrameOffsetSecond,
		frameCount,
	)
	if err != nil {
		return operation, err
	}
	reader, err := service.spoolFactory.OpenSpoolReader(
		operation.ID,
		operation.ValidationReceipt.SpoolReceipt,
		service.gapPolicy,
	)
	if err != nil {
		return service.handleLabReplayEffectError(ctx, effect, err)
	}
	frames := make([]guestruntimedomain.VitalFileReplayFrame, 0, frameCount)
	for offset := operation.NextFrameOffsetSecond; offset < operation.NextFrameOffsetSecond+frameCount; offset++ {
		frame, frameErr := reader.Frame(
			offset,
			operation.PreparationReceipt.OutputStartedAt+float64(offset),
		)
		if frameErr != nil {
			return service.handleLabReplayEffectError(
				ctx,
				effect,
				errors.Join(frameErr, reader.Close()),
			)
		}
		frames = append(frames, frame)
	}
	if err := reader.Close(); err != nil {
		return service.handleLabReplayEffectError(ctx, effect, err)
	}
	receipt, err := service.effectRunner.SendLabReplayMessageBatch(
		ctx,
		LabReplayMessageBatchEffect{
			ReplayID:          operation.ID,
			RunnerSessionID:   operation.PreparationReceipt.RunnerSessionID,
			BatchID:           batchID,
			StartOffsetSecond: operation.NextFrameOffsetSecond,
			Frames:            frames,
			FinalBatch:        frameCount == remaining,
		},
	)
	if err != nil {
		return service.handleLabReplayEffectError(ctx, effect, err)
	}
	return service.commitLabReplayEvent(
		ctx,
		effect,
		guestruntimedomain.LabReplayEvent{
			Kind:                guestruntimedomain.LabReplayMessagesSentEvent,
			OccurredAt:          receipt.AcceptedAt,
			MessageBatchReceipt: &receipt,
		},
	)
}

func (service *GuestRuntimeLabReplayApplicationService) confirmLabReplayUpstreamDelivery(
	ctx context.Context,
	effect PendingLabReplayEffect,
) (guestruntimedomain.LabReplayOperation, error) {
	operation := effect.Operation
	if operation.PreparationReceipt == nil {
		return operation, fmt.Errorf("Lab replay delivery confirmation has no preparation receipt")
	}
	receipt, err := service.effectRunner.ConfirmLabReplayUpstreamDelivery(
		ctx,
		LabReplayUpstreamDeliveryEffect{
			ReplayID:           operation.ID,
			RunnerSessionID:    operation.PreparationReceipt.RunnerSessionID,
			ExpectedFrameCount: operation.MessagesSent,
		},
	)
	if err != nil {
		return service.handleLabReplayEffectError(ctx, effect, err)
	}
	return service.commitLabReplayEvent(
		ctx,
		effect,
		guestruntimedomain.LabReplayEvent{
			Kind:                    guestruntimedomain.LabReplayUpstreamDeliveryConfirmedEvent,
			OccurredAt:              receipt.DeliveryConfirmedAt,
			UpstreamDeliveryReceipt: &receipt,
		},
	)
}

func (service *GuestRuntimeLabReplayApplicationService) handleLabReplayEffectError(
	ctx context.Context,
	effect PendingLabReplayEffect,
	cause error,
) (guestruntimedomain.LabReplayOperation, error) {
	var rejected LabReplayEffectRejectedError
	if errors.As(cause, &rejected) {
		return service.failLabReplayEffect(ctx, effect, rejected.Code, rejected)
	}
	var replayFailure interface{ ReplayFailureCode() string }
	if errors.As(cause, &replayFailure) {
		return service.failLabReplayEffect(
			ctx,
			effect,
			replayFailure.ReplayFailureCode(),
			cause,
		)
	}
	return effect.Operation, cause
}

func (service *GuestRuntimeLabReplayApplicationService) commitLabReplayEvent(
	ctx context.Context,
	effect PendingLabReplayEffect,
	event guestruntimedomain.LabReplayEvent,
) (guestruntimedomain.LabReplayOperation, error) {
	decision, err := guestruntimedomain.DecideLabReplayTransition(
		effect.Operation,
		event,
	)
	if err != nil {
		return effect.Operation, err
	}
	if err := service.repository.CommitLabReplayTransition(
		ctx,
		effect.Operation,
		decision.Next,
		effect.Command,
		decision.Command,
	); err != nil {
		return effect.Operation, fmt.Errorf(
			"commit Lab replay %s effect: %w",
			effect.Command,
			err,
		)
	}
	return decision.Next, nil
}

func (service *GuestRuntimeLabReplayApplicationService) createLabReplaySpool(
	ctx context.Context,
	operation guestruntimedomain.LabReplayOperation,
) (guestruntimedomain.VitalFileReplaySpoolReceipt, error) {
	content, err := service.openLabReplaySource(ctx, operation)
	if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{}, err
	}
	writer, err := service.spoolFactory.NewSpoolWriter(operation.ID)
	if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			errors.Join(err, content.Close())
	}
	result, scanErr := service.parser.Scan(content, writer)
	closeErr := content.Close()
	if scanErr != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			errors.Join(scanErr, closeErr, writer.Abort())
	}
	if closeErr != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			errors.Join(closeErr, writer.Abort())
	}
	receipt, err := writer.Commit(
		result,
		guestruntimedomain.Timestamp(service.clock.Now()),
	)
	if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			errors.Join(err, writer.Abort())
	}
	return receipt, nil
}

func (service *GuestRuntimeLabReplayApplicationService) openLabReplaySource(
	ctx context.Context,
	operation guestruntimedomain.LabReplayOperation,
) (io.ReadCloser, error) {
	return service.objectStore.OpenLabReplaySourceObject(
		ctx,
		operation.SourceReference,
		operation.SourceSHA256,
	)
}

func (service *GuestRuntimeLabReplayApplicationService) failLabReplayEffect(
	ctx context.Context,
	effect PendingLabReplayEffect,
	code string,
	cause error,
) (guestruntimedomain.LabReplayOperation, error) {
	failedAt := guestruntimedomain.Timestamp(service.clock.Now())
	decision, err := guestruntimedomain.DecideLabReplayTransition(
		effect.Operation,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayExecutionFailedEvent,
			OccurredAt: failedAt,
			Failure: &guestruntimedomain.LabReplayFailure{
				Stage:    labReplayFailureStage(effect.Operation.State),
				Code:     code,
				Message:  cause.Error(),
				FailedAt: failedAt,
			},
		},
	)
	if err != nil {
		return effect.Operation, err
	}
	if err := service.repository.CommitLabReplayTransition(
		ctx,
		effect.Operation,
		decision.Next,
		effect.Command,
		"",
	); err != nil {
		return effect.Operation, fmt.Errorf(
			"commit Lab replay typed failure after %v: %w",
			cause,
			err,
		)
	}
	return decision.Next, nil
}

func labReplayFailureStage(state string) string {
	switch state {
	case guestruntimedomain.LabReplayPendingFileValidationState:
		return guestruntimedomain.LabReplayFileValidationFailureStage
	case guestruntimedomain.LabReplayPendingTrackDecodeState:
		return guestruntimedomain.LabReplayTrackDecodeFailureStage
	case guestruntimedomain.LabReplayPendingPreparationState:
		return guestruntimedomain.LabReplayPreparationFailureStage
	case guestruntimedomain.LabReplaySendingState:
		return guestruntimedomain.LabReplayMessageSendFailureStage
	case guestruntimedomain.LabReplayAwaitingUpstreamDeliveryState:
		return guestruntimedomain.LabReplayUpstreamDeliveryFailureStage
	default:
		return "invalid-stage"
	}
}

func labReplayOperationMatchesCommand(
	operation guestruntimedomain.LabReplayOperation,
	command guestruntimedomain.LabReplayCommand,
) bool {
	return operation.ID == command.ReplayID &&
		operation.RequestID == command.RequestID &&
		operation.SourceReference == command.SourceReference &&
		operation.SourceSHA256 == command.SourceSHA256 &&
		operation.RecorderGatewayRecorderCode == command.RecorderGatewayRecorderCode &&
		operation.CreatedAt == command.RequestedAt
}

type replayCodedFailure interface {
	ReplayFailureCode() string
}

func replayFailureCode(err error, fallback string) string {
	var coded replayCodedFailure
	if errors.As(err, &coded) && guestruntimedomain.ValidIdentifier(coded.ReplayFailureCode()) {
		return coded.ReplayFailureCode()
	}
	return fallback
}
