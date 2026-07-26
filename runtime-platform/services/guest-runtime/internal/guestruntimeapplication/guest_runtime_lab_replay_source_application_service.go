package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type LabReplaySourceAdmissionRejectedError struct {
	Issue guestruntimedomain.Issue
}

func (failure LabReplaySourceAdmissionRejectedError) Error() string {
	return failure.Issue.Message
}

type LabReplaySourceAdmissionUnknownError struct {
	Issue guestruntimedomain.Issue
}

func (failure LabReplaySourceAdmissionUnknownError) Error() string {
	return failure.Issue.Message
}

type GuestRuntimeLabReplaySourceApplicationService struct {
	repository      GuestRuntimeLabReplaySourceRepository
	objectStore     GuestRuntimeLabReplaySourceObjectStore
	clock           GuestRuntimeClock
	maximumByteSize int64
	workflow        sync.Mutex
}

func NewGuestRuntimeLabReplaySourceApplicationService(
	repository GuestRuntimeLabReplaySourceRepository,
	objectStore GuestRuntimeLabReplaySourceObjectStore,
	clock GuestRuntimeClock,
	maximumByteSize int64,
) (*GuestRuntimeLabReplaySourceApplicationService, error) {
	if repository == nil || objectStore == nil || clock == nil ||
		maximumByteSize < 1 ||
		maximumByteSize > guestruntimedomain.MaximumLabReplaySourceByteSize {
		return nil, fmt.Errorf("Lab replay source dependencies and maximum byte size are required")
	}
	return &GuestRuntimeLabReplaySourceApplicationService{
		repository:      repository,
		objectStore:     objectStore,
		clock:           clock,
		maximumByteSize: maximumByteSize,
	}, nil
}

func (service *GuestRuntimeLabReplaySourceApplicationService) AdmitLabReplaySource(
	ctx context.Context,
	command guestruntimedomain.LabReplaySourceAdmissionCommand,
	content io.Reader,
) (guestruntimedomain.LabReplaySourceAdmissionReceipt, error) {
	service.workflow.Lock()
	defer service.workflow.Unlock()
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		service.maximumByteSize,
	); err != nil || content == nil {
		message := "Lab replay source command and content are required"
		if err != nil {
			message = err.Error()
		}
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			rejectedLabReplaySourceAdmission(
				"lab-replay-source-command-invalid",
				message,
			)
	}
	commandDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			unknownLabReplaySourceAdmission(
				"lab-replay-source-command-digest-failed",
				err.Error(),
			)
	}
	stored, err := service.repository.ReadLabReplaySourceAdmission(
		ctx,
		command.RequestID,
	)
	switch {
	case err == nil && stored.CommandDigest == commandDigest:
		if verifyErr := service.verifyStoredLabReplaySourceObject(
			ctx,
			stored.Receipt,
		); verifyErr != nil {
			return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
				unknownLabReplaySourceAdmission(
					"lab-replay-source-object-verification-failed",
					verifyErr.Error(),
				)
		}
		duplicate := stored.Receipt
		duplicate.Outcome = "duplicate"
		if validationErr := guestruntimedomain.ValidateLabReplaySourceAdmissionReceipt(
			duplicate,
		); validationErr != nil {
			return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
				unknownLabReplaySourceAdmission(
					"lab-replay-source-stored-receipt-invalid",
					validationErr.Error(),
				)
		}
		return duplicate, nil
	case err == nil:
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			rejectedLabReplaySourceAdmission(
				"lab-replay-source-request-id-conflict",
				"requestId already belongs to different Lab replay source evidence",
			)
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			unknownLabReplaySourceAdmission(
				"lab-replay-source-request-read-failed",
				err.Error(),
			)
	}
	persistedAt := guestruntimedomain.Timestamp(service.clock.Now())
	objectReceipt, err := service.objectStore.CommitLabReplaySourceObject(
		ctx,
		LabReplaySourceObjectCommit{
			Command:     command,
			Content:     content,
			PersistedAt: persistedAt,
		},
	)
	if errors.Is(err, ErrLabReplaySourceObjectContentMismatch) {
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			rejectedLabReplaySourceAdmission(
				"lab-replay-source-content-mismatch",
				"uploaded bytes do not match declared byteSize and sha256",
			)
	}
	if err != nil {
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			unknownLabReplaySourceAdmission(
				"lab-replay-source-object-write-failed",
				err.Error(),
			)
	}
	receipt := guestruntimedomain.LabReplaySourceAdmissionReceipt{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		RequestID:        command.RequestID,
		Outcome:          "accepted",
		SourceReference:  objectReceipt.SourceReference,
		OriginalFileName: command.OriginalFileName,
		MediaType:        command.MediaType,
		ByteSize:         command.ByteSize,
		SHA256:           command.SHA256,
		ObjectReceipt:    objectReceipt,
		PersistedAt:      objectReceipt.PersistedAt,
	}
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionReceipt(receipt); err != nil {
		return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
			unknownLabReplaySourceAdmission(
				"lab-replay-source-receipt-invalid",
				err.Error(),
			)
	}
	if err := service.repository.CommitLabReplaySourceAdmission(
		ctx,
		commandDigest,
		command,
		receipt,
	); err != nil {
		return service.resolveLabReplaySourceCommit(
			ctx,
			commandDigest,
			command.RequestID,
			err,
		)
	}
	return receipt, nil
}

func (service *GuestRuntimeLabReplaySourceApplicationService) verifyStoredLabReplaySourceObject(
	ctx context.Context,
	receipt guestruntimedomain.LabReplaySourceAdmissionReceipt,
) error {
	content, err := service.objectStore.OpenLabReplaySourceObject(
		ctx,
		receipt.SourceReference,
		receipt.SHA256,
	)
	if err != nil {
		return err
	}
	if err := content.Close(); err != nil {
		return fmt.Errorf("close verified Lab replay source object: %w", err)
	}
	return nil
}

func (service *GuestRuntimeLabReplaySourceApplicationService) resolveLabReplaySourceCommit(
	ctx context.Context,
	commandDigest string,
	requestID string,
	commitError error,
) (guestruntimedomain.LabReplaySourceAdmissionReceipt, error) {
	stored, readErr := service.repository.ReadLabReplaySourceAdmission(ctx, requestID)
	if readErr == nil && stored.CommandDigest == commandDigest {
		duplicate := stored.Receipt
		duplicate.Outcome = "duplicate"
		if validationErr := guestruntimedomain.ValidateLabReplaySourceAdmissionReceipt(
			duplicate,
		); validationErr == nil {
			return duplicate, nil
		}
	}
	return guestruntimedomain.LabReplaySourceAdmissionReceipt{},
		unknownLabReplaySourceAdmission(
			"lab-replay-source-write-outcome-unknown",
			commitError.Error(),
		)
}

func rejectedLabReplaySourceAdmission(
	code string,
	message string,
) LabReplaySourceAdmissionRejectedError {
	return LabReplaySourceAdmissionRejectedError{
		Issue: guestruntimedomain.Issue{
			Code:       code,
			Message:    message,
			Dependency: "lab-replay-source-owner",
		},
	}
}

func unknownLabReplaySourceAdmission(
	code string,
	message string,
) LabReplaySourceAdmissionUnknownError {
	retryable := true
	return LabReplaySourceAdmissionUnknownError{
		Issue: guestruntimedomain.Issue{
			Code:       code,
			Message:    message,
			Retryable:  &retryable,
			Dependency: "lab-replay-source-owner",
		},
	}
}
