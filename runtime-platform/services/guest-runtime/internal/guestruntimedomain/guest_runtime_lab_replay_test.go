package guestruntimedomain_test

import (
	"errors"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestLabReplayStateMachineCompletesOnlyAfterUpstreamDelivery(t *testing.T) {
	decision, err := guestruntimedomain.NewLabReplayOperation(labReplayCommand())
	if err != nil {
		t.Fatal(err)
	}
	if decision.Next.State != guestruntimedomain.LabReplayPendingFileValidationState ||
		decision.Command != guestruntimedomain.LabReplayValidateFileCommand {
		t.Fatalf("admission=%#v", decision)
	}
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayFileValidatedEvent,
			OccurredAt: "2026-07-24T15:00:01Z",
		},
	)
	validationReceipt := labReplayValidationReceipt()
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:              guestruntimedomain.LabReplayTracksDecodedEvent,
			OccurredAt:        "2026-07-24T15:00:02Z",
			ValidationReceipt: &validationReceipt,
		},
	)
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:               guestruntimedomain.LabReplayPreparedEvent,
			OccurredAt:         "2026-07-24T15:00:03Z",
			PreparationReceipt: labReplayPreparationReceipt(),
		},
	)
	batchReceipt := labReplayMessageBatchReceipt(t, decision.Next, 0, 2)
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:                guestruntimedomain.LabReplayMessagesSentEvent,
			OccurredAt:          batchReceipt.AcceptedAt,
			MessageBatchReceipt: &batchReceipt,
		},
	)
	if decision.Next.State != guestruntimedomain.LabReplayAwaitingUpstreamDeliveryState ||
		decision.Next.MessagesSent != 2 ||
		decision.Command != guestruntimedomain.LabReplayConfirmUpstreamDeliveryCommand {
		t.Fatalf("sent=%#v", decision)
	}
	upstreamReceipt := labReplayUpstreamReceipt(decision.Next)
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:                    guestruntimedomain.LabReplayUpstreamDeliveryConfirmedEvent,
			OccurredAt:              upstreamReceipt.DeliveryConfirmedAt,
			UpstreamDeliveryReceipt: &upstreamReceipt,
		},
	)
	if decision.Next.State != guestruntimedomain.LabReplaySucceededState ||
		decision.Command != "" {
		t.Fatalf("completed=%#v", decision)
	}
}

func TestLabReplayRejectsNonDeterministicOrSkippedMessageBatch(t *testing.T) {
	operation := labReplaySendingOperation(t)
	batch := labReplayMessageBatchReceipt(t, operation, 0, 1)
	batch.BatchID = "caller-invented-batch"
	if _, err := guestruntimedomain.DecideLabReplayTransition(
		operation,
		guestruntimedomain.LabReplayEvent{
			Kind:                guestruntimedomain.LabReplayMessagesSentEvent,
			OccurredAt:          batch.AcceptedAt,
			MessageBatchReceipt: &batch,
		},
	); err == nil {
		t.Fatal("non-deterministic replay batch identity must be rejected")
	}
	batch = labReplayMessageBatchReceipt(t, operation, 1, 1)
	if _, err := guestruntimedomain.DecideLabReplayTransition(
		operation,
		guestruntimedomain.LabReplayEvent{
			Kind:                guestruntimedomain.LabReplayMessagesSentEvent,
			OccurredAt:          batch.AcceptedAt,
			MessageBatchReceipt: &batch,
		},
	); err == nil {
		t.Fatal("a replay batch cannot skip the durable frame cursor")
	}
}

func TestLabReplayTrackDecodeRequiresGraphCompatibleSignal(t *testing.T) {
	decision, err := guestruntimedomain.NewLabReplayOperation(labReplayCommand())
	if err != nil {
		t.Fatal(err)
	}
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayFileValidatedEvent,
			OccurredAt: "2026-07-24T15:00:01Z",
		},
	)
	receipt := labReplayValidationReceipt()
	receipt.GraphCompatibleSignalCount = 0
	if _, err := guestruntimedomain.DecideLabReplayTransition(
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:              guestruntimedomain.LabReplayTracksDecodedEvent,
			OccurredAt:        "2026-07-24T15:00:02Z",
			ValidationReceipt: &receipt,
		},
	); err == nil {
		t.Fatal("track decode without a graph-compatible signal must not advance")
	}
}

func TestLabReplayFailureStageMustMatchOwnedStateAndRemainTerminal(t *testing.T) {
	decision, err := guestruntimedomain.NewLabReplayOperation(labReplayCommand())
	if err != nil {
		t.Fatal(err)
	}
	wrongStageFailure := labReplayFailure(
		guestruntimedomain.LabReplayMessageSendFailureStage,
		"2026-07-24T15:00:01Z",
	)
	if _, err := guestruntimedomain.DecideLabReplayTransition(
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayExecutionFailedEvent,
			OccurredAt: wrongStageFailure.FailedAt,
			Failure:    &wrongStageFailure,
		},
	); err == nil {
		t.Fatal("message-send failure cannot be attached during file validation")
	}
	fileFailure := labReplayFailure(
		guestruntimedomain.LabReplayFileValidationFailureStage,
		"2026-07-24T15:00:01Z",
	)
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayExecutionFailedEvent,
			OccurredAt: fileFailure.FailedAt,
			Failure:    &fileFailure,
		},
	)
	if decision.Next.State != guestruntimedomain.LabReplayFailedState ||
		decision.Next.Failure == nil ||
		decision.Next.Failure.Stage != guestruntimedomain.LabReplayFileValidationFailureStage ||
		decision.Next.LastSendState != guestruntimedomain.LabReplayLastSendNotAttemptedState {
		t.Fatalf("failed=%#v", decision.Next)
	}
	if _, err := guestruntimedomain.DecideLabReplayTransition(
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayStopRequestedEvent,
			OccurredAt: "2026-07-24T15:00:02Z",
		},
	); err == nil {
		t.Fatal("terminal failure must not be replaced by stopped")
	}
}

func TestLabReplayUserStopIsNotSystemFailure(t *testing.T) {
	decision, err := guestruntimedomain.NewLabReplayOperation(labReplayCommand())
	if err != nil {
		t.Fatal(err)
	}
	decision = labReplayTransition(
		t,
		decision.Next,
		guestruntimedomain.LabReplayEvent{
			Kind:       guestruntimedomain.LabReplayStopRequestedEvent,
			OccurredAt: "2026-07-24T15:00:01Z",
		},
	)
	if decision.Next.State != guestruntimedomain.LabReplayStoppedState ||
		decision.Next.Failure != nil {
		t.Fatalf("stopped=%#v", decision.Next)
	}
}

func TestLabReplayAdmissionClockRejectsFutureRequestedAt(t *testing.T) {
	command := labReplayCommand()
	command.RequestedAt = "2026-07-24T15:00:01Z"

	err := guestruntimedomain.ValidateLabReplayAdmissionClock(
		command,
		"2026-07-24T15:00:00Z",
	)
	var rejection guestruntimedomain.LabReplayAdmissionRejectedError
	if !errors.As(err, &rejection) ||
		rejection.Issue.Code != "lab-replay-requested-at-in-future" {
		t.Fatalf("future requestedAt rejection=%#v", err)
	}
	if err := guestruntimedomain.ValidateLabReplayAdmissionClock(
		command,
		command.RequestedAt,
	); err != nil {
		t.Fatalf("equal Guest time must be admissible: %v", err)
	}
}

func labReplayTransition(
	t *testing.T,
	current guestruntimedomain.LabReplayOperation,
	event guestruntimedomain.LabReplayEvent,
) guestruntimedomain.LabReplayTransitionDecision {
	t.Helper()
	decision, err := guestruntimedomain.DecideLabReplayTransition(current, event)
	if err != nil {
		t.Fatal(err)
	}
	if err := guestruntimedomain.ValidateLabReplayOperation(decision.Next); err != nil {
		t.Fatal(err)
	}
	return decision
}

func labReplayCommand() guestruntimedomain.LabReplayCommand {
	return guestruntimedomain.LabReplayCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "lab-replay-request-1",
		ReplayID:      "lab-replay-1",
		SourceReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceResourceType,
			ResourceID:   "lab-replay-source-1",
		},
		SourceSHA256:                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		RecorderGatewayRecorderCode: "LAB-01",
		RequestedAt:                 "2026-07-24T15:00:00Z",
	}
}

func labReplayValidationReceipt() guestruntimedomain.LabReplayValidationReceipt {
	command := labReplayCommand()
	return guestruntimedomain.LabReplayValidationReceipt{
		SchemaVersion:              guestruntimedomain.SchemaVersion,
		ParserContractVersion:      guestruntimedomain.LabReplayVitalParserContractVersion,
		SourceReference:            command.SourceReference,
		SourceSHA256:               command.SourceSHA256,
		FileFormatVersion:          "vital-v3",
		GraphCompatibleSignalCount: 3,
		SpoolReceipt: guestruntimedomain.VitalFileReplaySpoolReceipt{
			SchemaVersion:              guestruntimedomain.SchemaVersion,
			ReplayID:                   "lab-replay-1",
			FileFormatVersion:          "vital-v3",
			DatabaseSHA256:             "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			DatabaseByteSize:           4096,
			StartedAt:                  100,
			EndedAt:                    102,
			DurationSeconds:            2,
			TrackCount:                 3,
			RecordCount:                4,
			GraphCompatibleSignalCount: 3,
			FinalizedAt:                "2026-07-24T15:00:02Z",
		},
		ValidatedAt: "2026-07-24T15:00:02Z",
	}
}

func labReplayFailure(
	stage string,
	at string,
) guestruntimedomain.LabReplayFailure {
	return guestruntimedomain.LabReplayFailure{
		Stage:    stage,
		Code:     "replay-effect-failed",
		Message:  "explicit replay effect failed",
		FailedAt: at,
	}
}

func labReplayPreparationReceipt() *guestruntimedomain.LabReplayPreparationReceipt {
	validation := labReplayValidationReceipt()
	return &guestruntimedomain.LabReplayPreparationReceipt{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		ReplayID:            "lab-replay-1",
		RunnerSessionID:     "runner-replay-1",
		SpoolDatabaseSHA256: validation.SpoolReceipt.DatabaseSHA256,
		FrameCount:          validation.SpoolReceipt.DurationSeconds,
		OutputStartedAt:     200,
		PreparedAt:          "2026-07-24T15:00:03Z",
	}
}

func labReplaySendingOperation(t *testing.T) guestruntimedomain.LabReplayOperation {
	t.Helper()
	decision, err := guestruntimedomain.NewLabReplayOperation(labReplayCommand())
	if err != nil {
		t.Fatal(err)
	}
	decision = labReplayTransition(t, decision.Next, guestruntimedomain.LabReplayEvent{
		Kind:       guestruntimedomain.LabReplayFileValidatedEvent,
		OccurredAt: "2026-07-24T15:00:01Z",
	})
	validation := labReplayValidationReceipt()
	decision = labReplayTransition(t, decision.Next, guestruntimedomain.LabReplayEvent{
		Kind:              guestruntimedomain.LabReplayTracksDecodedEvent,
		OccurredAt:        validation.ValidatedAt,
		ValidationReceipt: &validation,
	})
	decision = labReplayTransition(t, decision.Next, guestruntimedomain.LabReplayEvent{
		Kind:               guestruntimedomain.LabReplayPreparedEvent,
		OccurredAt:         "2026-07-24T15:00:03Z",
		PreparationReceipt: labReplayPreparationReceipt(),
	})
	return decision.Next
}

func labReplayMessageBatchReceipt(
	t *testing.T,
	operation guestruntimedomain.LabReplayOperation,
	start int,
	count int,
) guestruntimedomain.LabReplayMessageBatchReceipt {
	t.Helper()
	batchID, err := guestruntimedomain.LabReplayMessageBatchID(
		operation.ID,
		start,
		count,
	)
	if err != nil {
		t.Fatal(err)
	}
	return guestruntimedomain.LabReplayMessageBatchReceipt{
		SchemaVersion:     guestruntimedomain.SchemaVersion,
		ReplayID:          operation.ID,
		RunnerSessionID:   operation.PreparationReceipt.RunnerSessionID,
		BatchID:           batchID,
		StartOffsetSecond: start,
		FrameCount:        count,
		FinalBatch:        start+count == operation.PreparationReceipt.FrameCount,
		AcceptedAt:        "2026-07-24T15:00:04Z",
	}
}

func labReplayUpstreamReceipt(
	operation guestruntimedomain.LabReplayOperation,
) guestruntimedomain.LabReplayUpstreamDeliveryReceipt {
	return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		ReplayID:            operation.ID,
		RunnerSessionID:     operation.PreparationReceipt.RunnerSessionID,
		DeliveryReceiptID:   "runner-delivery-1",
		DeliveredFrameCount: operation.MessagesSent,
		DeliveryConfirmedAt: "2026-07-24T15:00:05Z",
	}
}
