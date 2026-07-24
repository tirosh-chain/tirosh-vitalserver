package guestruntimedomain

import (
	"crypto/sha256"
	"fmt"
	"math"
	"time"
)

const (
	LabReplaySourceResourceType = "lab-replay-source"

	LabReplayPendingFileValidationState    = "pending-file-validation"
	LabReplayPendingTrackDecodeState       = "pending-track-decode"
	LabReplayPendingPreparationState       = "pending-replay-preparation"
	LabReplaySendingState                  = "sending"
	LabReplayAwaitingUpstreamDeliveryState = "awaiting-upstream-delivery"
	LabReplaySucceededState                = "succeeded"
	LabReplayFailedState                   = "failed"
	LabReplayStoppedState                  = "stopped"

	LabReplayFileValidatedEvent                = "file-validated"
	LabReplayTracksDecodedEvent                = "tracks-decoded"
	LabReplayPreparedEvent                     = "replay-prepared"
	LabReplayMessagesSentEvent                 = "messages-sent"
	LabReplayUpstreamDeliveryConfirmedEvent    = "upstream-delivery-confirmed"
	LabReplayExecutionFailedEvent              = "execution-failed"
	LabReplayStopRequestedEvent                = "stop-requested"
	LabReplayValidateFileCommand               = "validate-file"
	LabReplayDecodeTracksCommand               = "decode-tracks"
	LabReplayPrepareCommand                    = "prepare-replay"
	LabReplaySendMessagesCommand               = "send-messages"
	LabReplayConfirmUpstreamDeliveryCommand    = "confirm-upstream-delivery"
	LabReplayFileValidationFailureStage        = "file-validation"
	LabReplayTrackDecodeFailureStage           = "track-decode"
	LabReplayPreparationFailureStage           = "replay-preparation"
	LabReplayMessageSendFailureStage           = "message-send"
	LabReplayUpstreamDeliveryFailureStage      = "upstream-delivery"
	LabReplayLastSendNotAttemptedState         = "not-attempted"
	LabReplayLastSendSentState                 = "sent"
	LabReplayLastSendFailedState               = "failed"
	LabReplayVitalParserContractVersion        = "v1"
	LabReplayMaximumGraphCompatibleSignalCount = 65535
	LabReplayRequestedAtFutureRejectionCode    = "lab-replay-requested-at-in-future"
)

type LabReplayCommand struct {
	SchemaVersion               string            `json:"schemaVersion"`
	RequestID                   string            `json:"requestId"`
	ReplayID                    string            `json:"replayId"`
	SourceReference             ResourceReference `json:"sourceReference"`
	SourceSHA256                string            `json:"sourceSha256"`
	RecorderGatewayRecorderCode string            `json:"recorderGatewayRecorderCode"`
	RequestedAt                 string            `json:"requestedAt"`
}

// LabReplayAdmissionRejectedError is a known command rejection decided before
// durable admission. It is distinct from an unknown repository outcome and
// from a terminal replay execution failure.
type LabReplayAdmissionRejectedError struct {
	RejectedAt string `json:"rejectedAt"`
	Issue      Issue  `json:"issue"`
}

func (rejection LabReplayAdmissionRejectedError) Error() string {
	return rejection.Issue.Message
}

type LabReplayValidationReceipt struct {
	SchemaVersion              string                      `json:"schemaVersion"`
	ParserContractVersion      string                      `json:"parserContractVersion"`
	SourceReference            ResourceReference           `json:"sourceReference"`
	SourceSHA256               string                      `json:"sourceSha256"`
	FileFormatVersion          string                      `json:"fileFormatVersion"`
	GraphCompatibleSignalCount int                         `json:"graphCompatibleSignalCount"`
	SpoolReceipt               VitalFileReplaySpoolReceipt `json:"spoolReceipt"`
	ValidatedAt                string                      `json:"validatedAt"`
}

type LabReplayFailure struct {
	Stage    string `json:"stage"`
	Code     string `json:"code"`
	Message  string `json:"message"`
	FailedAt string `json:"failedAt"`
}

type LabReplayPreparationReceipt struct {
	SchemaVersion       string  `json:"schemaVersion"`
	ReplayID            string  `json:"replayId"`
	RunnerSessionID     string  `json:"runnerSessionId"`
	SpoolDatabaseSHA256 string  `json:"spoolDatabaseSha256"`
	FrameCount          int     `json:"frameCount"`
	OutputStartedAt     float64 `json:"outputStartedAt"`
	PreparedAt          string  `json:"preparedAt"`
}

type LabReplayMessageBatchReceipt struct {
	SchemaVersion     string `json:"schemaVersion"`
	ReplayID          string `json:"replayId"`
	RunnerSessionID   string `json:"runnerSessionId"`
	BatchID           string `json:"batchId"`
	StartOffsetSecond int    `json:"startOffsetSecond"`
	FrameCount        int    `json:"frameCount"`
	FinalBatch        bool   `json:"finalBatch"`
	AcceptedAt        string `json:"acceptedAt"`
}

type LabReplayUpstreamDeliveryReceipt struct {
	SchemaVersion       string `json:"schemaVersion"`
	ReplayID            string `json:"replayId"`
	RunnerSessionID     string `json:"runnerSessionId"`
	DeliveryReceiptID   string `json:"deliveryReceiptId"`
	DeliveredFrameCount int    `json:"deliveredFrameCount"`
	DeliveryConfirmedAt string `json:"deliveryConfirmedAt"`
}

type LabReplayOperation struct {
	SchemaVersion               string                            `json:"schemaVersion"`
	ID                          string                            `json:"id"`
	RequestID                   string                            `json:"requestId"`
	ResourceRevision            int                               `json:"resourceRevision"`
	State                       string                            `json:"state"`
	SourceReference             ResourceReference                 `json:"sourceReference"`
	SourceSHA256                string                            `json:"sourceSha256"`
	RecorderGatewayRecorderCode string                            `json:"recorderGatewayRecorderCode"`
	MessagesSent                int                               `json:"messagesSent"`
	NextFrameOffsetSecond       int                               `json:"nextFrameOffsetSecond"`
	LastSendState               string                            `json:"lastSendState"`
	ValidationReceipt           *LabReplayValidationReceipt       `json:"validationReceipt,omitempty"`
	PreparationReceipt          *LabReplayPreparationReceipt      `json:"preparationReceipt,omitempty"`
	UpstreamDeliveryReceipt     *LabReplayUpstreamDeliveryReceipt `json:"upstreamDeliveryReceipt,omitempty"`
	Failure                     *LabReplayFailure                 `json:"failure,omitempty"`
	StoppedFromState            string                            `json:"stoppedFromState,omitempty"`
	CreatedAt                   string                            `json:"createdAt"`
	UpdatedAt                   string                            `json:"updatedAt"`
}

type LabReplayEvent struct {
	Kind                    string
	OccurredAt              string
	ValidationReceipt       *LabReplayValidationReceipt
	PreparationReceipt      *LabReplayPreparationReceipt
	MessageBatchReceipt     *LabReplayMessageBatchReceipt
	UpstreamDeliveryReceipt *LabReplayUpstreamDeliveryReceipt
	Failure                 *LabReplayFailure
}

type LabReplayTransitionDecision struct {
	Next    LabReplayOperation
	Command string
}

func NewLabReplayOperation(command LabReplayCommand) (LabReplayTransitionDecision, error) {
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) ||
		!ValidIdentifier(command.ReplayID) ||
		command.SourceReference.ResourceType != LabReplaySourceResourceType ||
		!ValidIdentifier(command.SourceReference.ResourceID) ||
		!validSHA256(command.SourceSHA256) ||
		!ValidIdentifier(command.RecorderGatewayRecorderCode) ||
		!validTimestamp(command.RequestedAt) {
		return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay command is incomplete or invalid")
	}
	operation := LabReplayOperation{
		SchemaVersion:               SchemaVersion,
		ID:                          command.ReplayID,
		RequestID:                   command.RequestID,
		ResourceRevision:            1,
		State:                       LabReplayPendingFileValidationState,
		SourceReference:             command.SourceReference,
		SourceSHA256:                command.SourceSHA256,
		RecorderGatewayRecorderCode: command.RecorderGatewayRecorderCode,
		MessagesSent:                0,
		NextFrameOffsetSecond:       0,
		LastSendState:               LabReplayLastSendNotAttemptedState,
		CreatedAt:                   command.RequestedAt,
		UpdatedAt:                   command.RequestedAt,
	}
	return LabReplayTransitionDecision{
		Next:    operation,
		Command: LabReplayValidateFileCommand,
	}, nil
}

// ValidateLabReplayAdmissionClock rejects a caller timestamp that is later
// than the explicit Guest-owned admission observation. Admission does not wait
// for or infer clock convergence from a future caller timestamp.
func ValidateLabReplayAdmissionClock(
	command LabReplayCommand,
	guestObservedAt string,
) error {
	if !validTimestamp(command.RequestedAt) ||
		!validTimestamp(guestObservedAt) {
		return fmt.Errorf("Lab replay admission clock input is invalid")
	}
	requestedAt, _ := time.Parse(time.RFC3339Nano, command.RequestedAt)
	observedAt, _ := time.Parse(time.RFC3339Nano, guestObservedAt)
	if requestedAt.After(observedAt) {
		return LabReplayAdmissionRejectedError{
			RejectedAt: guestObservedAt,
			Issue: Issue{
				Code: LabReplayRequestedAtFutureRejectionCode,
				Message: "Lab replay requestedAt is later than the Guest " +
					"admission clock",
			},
		}
	}
	return nil
}

func DecideLabReplayTransition(
	current LabReplayOperation,
	event LabReplayEvent,
) (LabReplayTransitionDecision, error) {
	if err := ValidateLabReplayOperation(current); err != nil {
		return LabReplayTransitionDecision{}, err
	}
	if !validTimestamp(event.OccurredAt) {
		return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay event time is invalid")
	}
	if terminalLabReplayState(current.State) {
		return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay terminal state cannot transition")
	}
	if event.Kind == LabReplayExecutionFailedEvent {
		return failLabReplay(current, event)
	}
	if event.Kind == LabReplayStopRequestedEvent {
		next := advanceLabReplay(current, event.OccurredAt)
		next.StoppedFromState = current.State
		next.State = LabReplayStoppedState
		return LabReplayTransitionDecision{Next: next}, nil
	}

	next := advanceLabReplay(current, event.OccurredAt)
	switch {
	case current.State == LabReplayPendingFileValidationState &&
		event.Kind == LabReplayFileValidatedEvent:
		next.State = LabReplayPendingTrackDecodeState
		return LabReplayTransitionDecision{
			Next:    next,
			Command: LabReplayDecodeTracksCommand,
		}, nil
	case current.State == LabReplayPendingTrackDecodeState &&
		event.Kind == LabReplayTracksDecodedEvent:
		if event.ValidationReceipt == nil {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay track decode receipt is required")
		}
		if err := validateLabReplayValidationReceipt(
			*event.ValidationReceipt,
			current,
		); err != nil {
			return LabReplayTransitionDecision{}, err
		}
		next.State = LabReplayPendingPreparationState
		receipt := *event.ValidationReceipt
		next.ValidationReceipt = &receipt
		return LabReplayTransitionDecision{
			Next:    next,
			Command: LabReplayPrepareCommand,
		}, nil
	case current.State == LabReplayPendingPreparationState &&
		event.Kind == LabReplayPreparedEvent:
		if event.PreparationReceipt == nil {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay preparation receipt is required")
		}
		if err := validateLabReplayPreparationReceipt(
			*event.PreparationReceipt,
			current,
		); err != nil {
			return LabReplayTransitionDecision{}, err
		}
		if event.PreparationReceipt.PreparedAt != event.OccurredAt {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay preparation event time does not match its receipt")
		}
		next.State = LabReplaySendingState
		receipt := *event.PreparationReceipt
		next.PreparationReceipt = &receipt
		return LabReplayTransitionDecision{
			Next:    next,
			Command: LabReplaySendMessagesCommand,
		}, nil
	case current.State == LabReplaySendingState &&
		event.Kind == LabReplayMessagesSentEvent:
		if event.MessageBatchReceipt == nil {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay message batch receipt is required")
		}
		if err := validateLabReplayMessageBatchReceipt(
			*event.MessageBatchReceipt,
			current,
		); err != nil {
			return LabReplayTransitionDecision{}, err
		}
		if event.MessageBatchReceipt.AcceptedAt != event.OccurredAt {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay message event time does not match its receipt")
		}
		receipt := *event.MessageBatchReceipt
		next.MessagesSent += receipt.FrameCount
		next.NextFrameOffsetSecond += receipt.FrameCount
		next.LastSendState = LabReplayLastSendSentState
		if receipt.FinalBatch {
			next.State = LabReplayAwaitingUpstreamDeliveryState
			return LabReplayTransitionDecision{
				Next:    next,
				Command: LabReplayConfirmUpstreamDeliveryCommand,
			}, nil
		}
		next.State = LabReplaySendingState
		return LabReplayTransitionDecision{
			Next:    next,
			Command: LabReplaySendMessagesCommand,
		}, nil
	case current.State == LabReplayAwaitingUpstreamDeliveryState &&
		event.Kind == LabReplayUpstreamDeliveryConfirmedEvent:
		if event.UpstreamDeliveryReceipt == nil {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay upstream delivery receipt is required")
		}
		if err := validateLabReplayUpstreamDeliveryReceipt(
			*event.UpstreamDeliveryReceipt,
			current,
		); err != nil {
			return LabReplayTransitionDecision{}, err
		}
		if event.UpstreamDeliveryReceipt.DeliveryConfirmedAt != event.OccurredAt {
			return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay upstream event time does not match its receipt")
		}
		next.State = LabReplaySucceededState
		receipt := *event.UpstreamDeliveryReceipt
		next.UpstreamDeliveryReceipt = &receipt
		return LabReplayTransitionDecision{Next: next}, nil
	default:
		return LabReplayTransitionDecision{}, fmt.Errorf(
			"Lab replay event %s is invalid for state %s",
			event.Kind,
			current.State,
		)
	}
}

func ValidateLabReplayOperation(operation LabReplayOperation) error {
	if operation.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(operation.ID) ||
		!ValidIdentifier(operation.RequestID) ||
		operation.ResourceRevision < 1 ||
		!validLabReplayState(operation.State) ||
		operation.SourceReference.ResourceType != LabReplaySourceResourceType ||
		!ValidIdentifier(operation.SourceReference.ResourceID) ||
		!validSHA256(operation.SourceSHA256) ||
		!ValidIdentifier(operation.RecorderGatewayRecorderCode) ||
		operation.MessagesSent < 0 ||
		operation.NextFrameOffsetSecond < 0 ||
		operation.MessagesSent != operation.NextFrameOffsetSecond ||
		!validLabReplayLastSendState(operation.LastSendState) ||
		!validTimestamp(operation.CreatedAt) ||
		!validTimestamp(operation.UpdatedAt) {
		return fmt.Errorf("Lab replay operation is incomplete or invalid")
	}
	if operation.MessagesSent == 0 &&
		operation.LastSendState == LabReplayLastSendSentState {
		return fmt.Errorf("Lab replay operation cannot report sent without messages")
	}
	createdAt, _ := time.Parse(time.RFC3339Nano, operation.CreatedAt)
	updatedAt, _ := time.Parse(time.RFC3339Nano, operation.UpdatedAt)
	if updatedAt.Before(createdAt) {
		return fmt.Errorf("Lab replay operation updatedAt precedes createdAt")
	}
	if operation.ValidationReceipt != nil {
		if err := validateLabReplayValidationReceipt(
			*operation.ValidationReceipt,
			operation,
		); err != nil {
			return err
		}
		validatedAt, _ := time.Parse(
			time.RFC3339Nano,
			operation.ValidationReceipt.ValidatedAt,
		)
		if validatedAt.After(updatedAt) {
			return fmt.Errorf("Lab replay validation receipt is newer than operation")
		}
	}
	if operation.PreparationReceipt != nil {
		if err := validateLabReplayPreparationReceipt(
			*operation.PreparationReceipt,
			operation,
		); err != nil {
			return err
		}
		preparedAt, _ := time.Parse(
			time.RFC3339Nano,
			operation.PreparationReceipt.PreparedAt,
		)
		if preparedAt.After(updatedAt) {
			return fmt.Errorf("Lab replay preparation receipt is newer than operation")
		}
	}
	if operation.UpstreamDeliveryReceipt != nil {
		if err := validateLabReplayUpstreamDeliveryReceipt(
			*operation.UpstreamDeliveryReceipt,
			operation,
		); err != nil {
			return err
		}
		confirmedAt, _ := time.Parse(
			time.RFC3339Nano,
			operation.UpstreamDeliveryReceipt.DeliveryConfirmedAt,
		)
		if confirmedAt.After(updatedAt) {
			return fmt.Errorf("Lab replay upstream receipt is newer than operation")
		}
	}
	if operation.State == LabReplayFailedState {
		if operation.Failure == nil {
			return fmt.Errorf("Failed Lab replay operation requires failure")
		}
		if err := validateLabReplayFailure(*operation.Failure); err != nil {
			return err
		}
	} else if operation.Failure != nil {
		return fmt.Errorf("Non-failed Lab replay operation cannot contain failure")
	}
	if operation.State == LabReplayStoppedState {
		if !validNonTerminalLabReplayState(operation.StoppedFromState) {
			return fmt.Errorf("Stopped Lab replay operation requires its exact prior state")
		}
	} else if operation.StoppedFromState != "" {
		return fmt.Errorf("Non-stopped Lab replay operation cannot contain stoppedFromState")
	}
	if err := validateLabReplayStateEvidence(operation); err != nil {
		return err
	}
	return nil
}

func failLabReplay(
	current LabReplayOperation,
	event LabReplayEvent,
) (LabReplayTransitionDecision, error) {
	if event.Failure == nil {
		return LabReplayTransitionDecision{}, fmt.Errorf("Lab replay failure is required")
	}
	if err := validateLabReplayFailure(*event.Failure); err != nil {
		return LabReplayTransitionDecision{}, err
	}
	expectedStage, ok := labReplayFailureStageForState(current.State)
	if !ok || event.Failure.Stage != expectedStage ||
		event.Failure.FailedAt != event.OccurredAt {
		return LabReplayTransitionDecision{}, fmt.Errorf(
			"Lab replay failure stage does not match the current state",
		)
	}
	next := advanceLabReplay(current, event.OccurredAt)
	next.State = LabReplayFailedState
	failure := *event.Failure
	next.Failure = &failure
	if failure.Stage == LabReplayMessageSendFailureStage {
		next.LastSendState = LabReplayLastSendFailedState
	}
	return LabReplayTransitionDecision{Next: next}, nil
}

func validateLabReplayValidationReceipt(
	receipt LabReplayValidationReceipt,
	operation LabReplayOperation,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		receipt.ParserContractVersion != LabReplayVitalParserContractVersion ||
		receipt.SourceReference != operation.SourceReference ||
		receipt.SourceSHA256 != operation.SourceSHA256 ||
		!ValidIdentifier(receipt.FileFormatVersion) ||
		receipt.GraphCompatibleSignalCount < 1 ||
		receipt.GraphCompatibleSignalCount > LabReplayMaximumGraphCompatibleSignalCount ||
		!validTimestamp(receipt.ValidatedAt) {
		return fmt.Errorf("Lab replay validation receipt is incomplete or invalid")
	}
	if err := ValidateVitalFileReplaySpoolReceipt(receipt.SpoolReceipt); err != nil ||
		receipt.SpoolReceipt.ReplayID != operation.ID ||
		receipt.SpoolReceipt.FileFormatVersion != receipt.FileFormatVersion ||
		receipt.SpoolReceipt.GraphCompatibleSignalCount != receipt.GraphCompatibleSignalCount ||
		receipt.SpoolReceipt.FinalizedAt != receipt.ValidatedAt {
		return fmt.Errorf("Lab replay validation receipt spool evidence is invalid")
	}
	return nil
}

func validateLabReplayPreparationReceipt(
	receipt LabReplayPreparationReceipt,
	operation LabReplayOperation,
) error {
	if operation.ValidationReceipt == nil ||
		receipt.SchemaVersion != SchemaVersion ||
		receipt.ReplayID != operation.ID ||
		!ValidIdentifier(receipt.RunnerSessionID) ||
		receipt.SpoolDatabaseSHA256 != operation.ValidationReceipt.SpoolReceipt.DatabaseSHA256 ||
		receipt.FrameCount != operation.ValidationReceipt.SpoolReceipt.DurationSeconds ||
		receipt.FrameCount < 1 ||
		math.IsNaN(receipt.OutputStartedAt) ||
		math.IsInf(receipt.OutputStartedAt, 0) ||
		receipt.OutputStartedAt <= 0 ||
		!validTimestamp(receipt.PreparedAt) {
		return fmt.Errorf("Lab replay preparation receipt is incomplete or invalid")
	}
	return nil
}

func validateLabReplayMessageBatchReceipt(
	receipt LabReplayMessageBatchReceipt,
	operation LabReplayOperation,
) error {
	expectedBatchID, batchIDErr := LabReplayMessageBatchID(
		operation.ID,
		receipt.StartOffsetSecond,
		receipt.FrameCount,
	)
	if operation.PreparationReceipt == nil ||
		batchIDErr != nil ||
		receipt.SchemaVersion != SchemaVersion ||
		receipt.ReplayID != operation.ID ||
		receipt.RunnerSessionID != operation.PreparationReceipt.RunnerSessionID ||
		receipt.BatchID != expectedBatchID ||
		receipt.StartOffsetSecond != operation.NextFrameOffsetSecond ||
		receipt.FrameCount < 1 ||
		receipt.StartOffsetSecond+receipt.FrameCount > operation.PreparationReceipt.FrameCount ||
		receipt.FinalBatch != (receipt.StartOffsetSecond+receipt.FrameCount == operation.PreparationReceipt.FrameCount) ||
		!validTimestamp(receipt.AcceptedAt) {
		return fmt.Errorf("Lab replay message batch receipt is incomplete or invalid")
	}
	return nil
}

func LabReplayMessageBatchID(
	replayID string,
	startOffsetSecond int,
	frameCount int,
) (string, error) {
	if !ValidIdentifier(replayID) ||
		startOffsetSecond < 0 ||
		frameCount < 1 {
		return "", fmt.Errorf("Lab replay message batch identity input is invalid")
	}
	sum := sha256.Sum256([]byte(fmt.Sprintf(
		"%s:%d:%d",
		replayID,
		startOffsetSecond,
		frameCount,
	)))
	return fmt.Sprintf("replay-batch-%x", sum), nil
}

func validateLabReplayUpstreamDeliveryReceipt(
	receipt LabReplayUpstreamDeliveryReceipt,
	operation LabReplayOperation,
) error {
	if operation.PreparationReceipt == nil ||
		receipt.SchemaVersion != SchemaVersion ||
		receipt.ReplayID != operation.ID ||
		receipt.RunnerSessionID != operation.PreparationReceipt.RunnerSessionID ||
		!ValidIdentifier(receipt.DeliveryReceiptID) ||
		receipt.DeliveredFrameCount != operation.PreparationReceipt.FrameCount ||
		receipt.DeliveredFrameCount != operation.MessagesSent ||
		!validTimestamp(receipt.DeliveryConfirmedAt) {
		return fmt.Errorf("Lab replay upstream delivery receipt is incomplete or invalid")
	}
	return nil
}

func validateLabReplayFailure(failure LabReplayFailure) error {
	if !validLabReplayFailureStage(failure.Stage) ||
		!ValidIdentifier(failure.Code) ||
		failure.Message == "" ||
		!validTimestamp(failure.FailedAt) {
		return fmt.Errorf("Lab replay failure is incomplete or invalid")
	}
	return nil
}

func validateLabReplayStateEvidence(operation LabReplayOperation) error {
	switch operation.State {
	case LabReplayPendingFileValidationState, LabReplayPendingTrackDecodeState:
		if operation.ValidationReceipt != nil ||
			operation.PreparationReceipt != nil ||
			operation.UpstreamDeliveryReceipt != nil ||
			operation.MessagesSent != 0 ||
			operation.LastSendState != LabReplayLastSendNotAttemptedState {
			return fmt.Errorf("Lab replay pre-decode state contains later-stage evidence")
		}
	case LabReplayPendingPreparationState:
		if operation.ValidationReceipt == nil ||
			operation.PreparationReceipt != nil ||
			operation.UpstreamDeliveryReceipt != nil ||
			operation.MessagesSent != 0 ||
			operation.LastSendState != LabReplayLastSendNotAttemptedState {
			return fmt.Errorf("Lab replay preparation state evidence is invalid")
		}
	case LabReplaySendingState:
		if operation.ValidationReceipt == nil ||
			operation.PreparationReceipt == nil ||
			operation.UpstreamDeliveryReceipt != nil ||
			operation.MessagesSent >= operation.PreparationReceipt.FrameCount ||
			(operation.MessagesSent == 0 &&
				operation.LastSendState != LabReplayLastSendNotAttemptedState) ||
			(operation.MessagesSent > 0 &&
				operation.LastSendState != LabReplayLastSendSentState) {
			return fmt.Errorf("Lab replay sending state evidence is invalid")
		}
	case LabReplayAwaitingUpstreamDeliveryState, LabReplaySucceededState:
		if operation.ValidationReceipt == nil ||
			operation.PreparationReceipt == nil ||
			operation.MessagesSent != operation.PreparationReceipt.FrameCount ||
			operation.LastSendState != LabReplayLastSendSentState {
			return fmt.Errorf("Lab replay delivery state evidence is invalid")
		}
		if operation.State == LabReplayAwaitingUpstreamDeliveryState &&
			operation.UpstreamDeliveryReceipt != nil {
			return fmt.Errorf("Lab replay awaiting-delivery state contains terminal receipt")
		}
		if operation.State == LabReplaySucceededState &&
			operation.UpstreamDeliveryReceipt == nil {
			return fmt.Errorf("Lab replay succeeded state requires delivery receipt")
		}
	case LabReplayFailedState:
		switch operation.Failure.Stage {
		case LabReplayFileValidationFailureStage, LabReplayTrackDecodeFailureStage:
			if operation.ValidationReceipt != nil ||
				operation.PreparationReceipt != nil ||
				operation.UpstreamDeliveryReceipt != nil ||
				operation.MessagesSent != 0 ||
				operation.LastSendState != LabReplayLastSendNotAttemptedState {
				return fmt.Errorf("Lab replay validation failure evidence is invalid")
			}
		case LabReplayPreparationFailureStage:
			if operation.ValidationReceipt == nil ||
				operation.PreparationReceipt != nil ||
				operation.UpstreamDeliveryReceipt != nil ||
				operation.MessagesSent != 0 ||
				operation.LastSendState != LabReplayLastSendNotAttemptedState {
				return fmt.Errorf("Lab replay preparation failure evidence is invalid")
			}
		case LabReplayMessageSendFailureStage:
			if operation.ValidationReceipt == nil ||
				operation.PreparationReceipt == nil ||
				operation.UpstreamDeliveryReceipt != nil ||
				operation.MessagesSent >= operation.PreparationReceipt.FrameCount ||
				operation.LastSendState != LabReplayLastSendFailedState {
				return fmt.Errorf("Lab replay message-send failure evidence is invalid")
			}
		case LabReplayUpstreamDeliveryFailureStage:
			if operation.ValidationReceipt == nil ||
				operation.PreparationReceipt == nil ||
				operation.UpstreamDeliveryReceipt != nil ||
				operation.MessagesSent != operation.PreparationReceipt.FrameCount ||
				operation.LastSendState != LabReplayLastSendSentState {
				return fmt.Errorf("Lab replay upstream failure evidence is invalid")
			}
		}
	case LabReplayStoppedState:
		prior := operation
		prior.State = operation.StoppedFromState
		prior.StoppedFromState = ""
		if err := validateLabReplayStateEvidence(prior); err != nil {
			return fmt.Errorf("Lab replay stopped-state evidence is invalid: %w", err)
		}
	}
	return nil
}

func advanceLabReplay(
	current LabReplayOperation,
	at string,
) LabReplayOperation {
	next := current
	next.ResourceRevision++
	next.UpdatedAt = at
	return next
}

func labReplayFailureStageForState(state string) (string, bool) {
	stages := map[string]string{
		LabReplayPendingFileValidationState:    LabReplayFileValidationFailureStage,
		LabReplayPendingTrackDecodeState:       LabReplayTrackDecodeFailureStage,
		LabReplayPendingPreparationState:       LabReplayPreparationFailureStage,
		LabReplaySendingState:                  LabReplayMessageSendFailureStage,
		LabReplayAwaitingUpstreamDeliveryState: LabReplayUpstreamDeliveryFailureStage,
	}
	stage, ok := stages[state]
	return stage, ok
}

func validLabReplayState(state string) bool {
	switch state {
	case LabReplayPendingFileValidationState,
		LabReplayPendingTrackDecodeState,
		LabReplayPendingPreparationState,
		LabReplaySendingState,
		LabReplayAwaitingUpstreamDeliveryState,
		LabReplaySucceededState,
		LabReplayFailedState,
		LabReplayStoppedState:
		return true
	default:
		return false
	}
}

func validNonTerminalLabReplayState(state string) bool {
	switch state {
	case LabReplayPendingFileValidationState,
		LabReplayPendingTrackDecodeState,
		LabReplayPendingPreparationState,
		LabReplaySendingState,
		LabReplayAwaitingUpstreamDeliveryState:
		return true
	default:
		return false
	}
}

func terminalLabReplayState(state string) bool {
	return state == LabReplaySucceededState ||
		state == LabReplayFailedState ||
		state == LabReplayStoppedState
}

func LabReplayCommandForState(state string) (string, bool) {
	switch state {
	case LabReplayPendingFileValidationState:
		return LabReplayValidateFileCommand, true
	case LabReplayPendingTrackDecodeState:
		return LabReplayDecodeTracksCommand, true
	case LabReplayPendingPreparationState:
		return LabReplayPrepareCommand, true
	case LabReplaySendingState:
		return LabReplaySendMessagesCommand, true
	case LabReplayAwaitingUpstreamDeliveryState:
		return LabReplayConfirmUpstreamDeliveryCommand, true
	default:
		return "", false
	}
}

func validLabReplayFailureStage(stage string) bool {
	switch stage {
	case LabReplayFileValidationFailureStage,
		LabReplayTrackDecodeFailureStage,
		LabReplayPreparationFailureStage,
		LabReplayMessageSendFailureStage,
		LabReplayUpstreamDeliveryFailureStage:
		return true
	default:
		return false
	}
}

func validLabReplayLastSendState(state string) bool {
	return state == LabReplayLastSendNotAttemptedState ||
		state == LabReplayLastSendSentState ||
		state == LabReplayLastSendFailedState
}
