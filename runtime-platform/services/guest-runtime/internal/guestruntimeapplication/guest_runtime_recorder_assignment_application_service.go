package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type GuestRuntimeRecorderAssignmentApplicationService struct {
	repository GuestRuntimeRecorderAssignmentRepository
	clock      GuestRuntimeClock
	workflow   sync.Mutex
}

func NewGuestRuntimeRecorderAssignmentApplicationService(
	repository GuestRuntimeRecorderAssignmentRepository,
	clock GuestRuntimeClock,
) (*GuestRuntimeRecorderAssignmentApplicationService, error) {
	if repository == nil || clock == nil {
		return nil, fmt.Errorf("Recorder assignment repository and clock are required")
	}
	return &GuestRuntimeRecorderAssignmentApplicationService{
		repository: repository,
		clock:      clock,
	}, nil
}

func (service *GuestRuntimeRecorderAssignmentApplicationService) AdmitRecorderAssignmentEvidence(
	ctx context.Context,
	command guestruntimedomain.RecorderAssignmentEvidenceCommand,
) (
	guestruntimedomain.RecorderAssignmentEvidenceReceipt,
	*guestruntimedomain.CommandRejection,
	*guestruntimedomain.CommandAdmissionFailure,
) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if err := guestruntimedomain.ValidateRecorderAssignmentEvidenceCommand(command); err != nil {
		return guestruntimedomain.RecorderAssignmentEvidenceReceipt{},
			recorderAssignmentRejection(
				command.RequestID,
				now,
				"recorder-assignment-command-invalid",
				err.Error(),
			),
			nil
	}
	commandDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.RecorderAssignmentEvidenceReceipt{},
			nil,
			recorderAssignmentAdmissionFailure(
				command.RequestID,
				now,
				"not-admitted",
				"recorder-assignment-command-digest-failed",
				err.Error(),
			)
	}
	stored, err := service.repository.ReadRecorderAssignmentEvidenceByRequestID(
		ctx,
		command.RequestID,
	)
	switch {
	case err == nil && stored.CommandDigest == commandDigest:
		return recorderAssignmentReceipt(command.RequestID, "duplicate", stored.Evidence), nil, nil
	case err == nil:
		return guestruntimedomain.RecorderAssignmentEvidenceReceipt{},
			recorderAssignmentRejection(
				command.RequestID,
				now,
				"recorder-assignment-request-id-conflict",
				"requestId is already bound to different Recorder assignment evidence",
			),
			nil
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.RecorderAssignmentEvidenceReceipt{},
			nil,
			recorderAssignmentAdmissionFailure(
				command.RequestID,
				now,
				"not-admitted",
				"recorder-assignment-request-read-failed",
				err.Error(),
			)
	}
	evidence := guestruntimedomain.RecorderAssignmentEvidenceFromCommand(command, now)
	if err := service.repository.CommitRecorderAssignmentEvidence(
		ctx,
		command.RequestID,
		commandDigest,
		evidence,
	); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			stored, readErr := service.repository.ReadRecorderAssignmentEvidenceByRequestID(
				ctx,
				command.RequestID,
			)
			if readErr == nil && stored.CommandDigest == commandDigest {
				return recorderAssignmentReceipt(command.RequestID, "duplicate", stored.Evidence), nil, nil
			}
		}
		return guestruntimedomain.RecorderAssignmentEvidenceReceipt{},
			nil,
			recorderAssignmentAdmissionFailure(
				command.RequestID,
				now,
				"unknown",
				"recorder-assignment-write-outcome-unknown",
				err.Error(),
			)
	}
	return recorderAssignmentReceipt(command.RequestID, "accepted", evidence), nil, nil
}

func (service *GuestRuntimeRecorderAssignmentApplicationService) ResolveRecorderAssignment(
	ctx context.Context,
	bedName string,
	effectiveAt string,
) (guestruntimedomain.RecorderAssignmentResolution, error) {
	evidences, err := service.repository.ListEffectiveRecorderAssignmentEvidence(
		ctx,
		bedName,
		effectiveAt,
		guestruntimedomain.MaximumRecorderAssignmentCandidates+1,
	)
	if err != nil {
		return guestruntimedomain.RecorderAssignmentResolution{},
			fmt.Errorf("read effective Recorder assignment evidence: %w", err)
	}
	resolution, err := guestruntimedomain.ResolveRecorderAssignment(
		bedName,
		effectiveAt,
		evidences,
		guestruntimedomain.Timestamp(service.clock.Now()),
	)
	if err != nil {
		return guestruntimedomain.RecorderAssignmentResolution{}, err
	}
	stored, err := service.repository.ReadRecorderAssignmentResolution(
		ctx,
		resolution.ResolutionID,
	)
	switch {
	case err == nil:
		if validationErr := guestruntimedomain.ValidateRecorderAssignmentResolution(stored); validationErr != nil {
			return guestruntimedomain.RecorderAssignmentResolution{},
				fmt.Errorf("validate stored Recorder assignment resolution: %w", validationErr)
		}
		return stored, nil
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.RecorderAssignmentResolution{},
			fmt.Errorf("read Recorder assignment resolution: %w", err)
	}
	if err := service.repository.CommitRecorderAssignmentResolution(ctx, resolution); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			stored, readErr := service.repository.ReadRecorderAssignmentResolution(
				ctx,
				resolution.ResolutionID,
			)
			if readErr == nil {
				if validationErr := guestruntimedomain.ValidateRecorderAssignmentResolution(stored); validationErr != nil {
					return guestruntimedomain.RecorderAssignmentResolution{},
						fmt.Errorf("validate conflicting Recorder assignment resolution: %w", validationErr)
				}
				return stored, nil
			}
		}
		return guestruntimedomain.RecorderAssignmentResolution{},
			fmt.Errorf("commit Recorder assignment resolution: %w", err)
	}
	return resolution, nil
}

func recorderAssignmentReceipt(
	requestID string,
	outcome string,
	evidence guestruntimedomain.RecorderAssignmentEvidence,
) guestruntimedomain.RecorderAssignmentEvidenceReceipt {
	return guestruntimedomain.RecorderAssignmentEvidenceReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     requestID,
		Outcome:       outcome,
		EvidenceReference: guestruntimedomain.EvidenceReference{
			Kind: "recorder-assignment-evidence",
			ID:   evidence.EvidenceID,
		},
		PersistedAt: evidence.PersistedAt,
	}
}

func recorderAssignmentRejection(
	requestID string,
	observedAt string,
	code string,
	message string,
) *guestruntimedomain.CommandRejection {
	return &guestruntimedomain.CommandRejection{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "rejected",
		RequestID:     requestID,
		RejectedAt:    observedAt,
		Issue: guestruntimedomain.Issue{
			Code:       code,
			Message:    message,
			Dependency: "recorder-assignment-owner",
		},
	}
}

func recorderAssignmentAdmissionFailure(
	requestID string,
	observedAt string,
	admissionState string,
	code string,
	message string,
) *guestruntimedomain.CommandAdmissionFailure {
	retryable := true
	return &guestruntimedomain.CommandAdmissionFailure{
		SchemaVersion:  guestruntimedomain.SchemaVersion,
		State:          "failed",
		RequestID:      requestID,
		ObservedAt:     observedAt,
		AdmissionState: admissionState,
		Issue: guestruntimedomain.Issue{
			Code:       code,
			Message:    message,
			Retryable:  &retryable,
			Dependency: "recorder-assignment-postgresql",
		},
	}
}
