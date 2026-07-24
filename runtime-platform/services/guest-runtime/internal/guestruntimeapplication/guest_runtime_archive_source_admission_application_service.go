package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type ArchiveSourceAdmissionRejectedError struct {
	Issue guestruntimedomain.Issue
}

func (err ArchiveSourceAdmissionRejectedError) Error() string {
	return err.Issue.Code + ": " + err.Issue.Message
}

type ArchiveSourceAdmissionUnknownError struct {
	Issue guestruntimedomain.Issue
}

func (err ArchiveSourceAdmissionUnknownError) Error() string {
	return err.Issue.Code + ": " + err.Issue.Message
}

type GuestRuntimeArchiveSourceAdmissionApplicationService struct {
	repository          GuestRuntimeArchiveSourceAdmissionRepository
	objectStore         GuestRuntimeArchiveArtifactObjectStore
	attributionResolver GuestRuntimeRecorderArtifactAttributionResolver
	clock               GuestRuntimeClock
}

func NewGuestRuntimeArchiveSourceAdmissionApplicationService(
	repository GuestRuntimeArchiveSourceAdmissionRepository,
	objectStore GuestRuntimeArchiveArtifactObjectStore,
	attributionResolver GuestRuntimeRecorderArtifactAttributionResolver,
	clock GuestRuntimeClock,
) (*GuestRuntimeArchiveSourceAdmissionApplicationService, error) {
	if repository == nil ||
		objectStore == nil ||
		attributionResolver == nil ||
		clock == nil {
		return nil, fmt.Errorf(
			"Archive source repository, object store, attribution resolver, and clock are required",
		)
	}
	return &GuestRuntimeArchiveSourceAdmissionApplicationService{
		repository:          repository,
		objectStore:         objectStore,
		attributionResolver: attributionResolver,
		clock:               clock,
	}, nil
}

func (service *GuestRuntimeArchiveSourceAdmissionApplicationService) AdmitRecorderVitalUpload(
	ctx context.Context,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	content io.Reader,
) (guestruntimedomain.ArchiveSourceAdmissionReceipt, error) {
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionCommand(command); err != nil ||
		content == nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			rejectedArchiveSourceAdmission(
				"archive-source-command-invalid",
				"Archive source admission command and content must be complete and valid",
			)
	}
	commandDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-command-digest-failed",
				err.Error(),
				"archive-export",
			)
	}
	stored, err := service.repository.ReadArchiveSourceAdmission(
		ctx,
		command.RequestID,
	)
	switch {
	case err == nil:
		if stored.CommandDigest != commandDigest {
			return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
				rejectedArchiveSourceAdmission(
					"archive-source-request-id-conflict",
					"requestId is already bound to a different Archive source command",
				)
		}
		return stored.Receipt, nil
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-admission-read-failed",
				err.Error(),
				"archive-export-postgresql",
			)
	}

	existing, err := service.repository.ReadArchiveArtifactDetailBySourceReceipt(
		ctx,
		command.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		command.Source.ID,
	)
	switch {
	case err == nil:
		return service.commitDuplicateSourceAdmission(
			ctx,
			commandDigest,
			command,
			existing,
		)
	case !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound):
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-lineage-read-failed",
				err.Error(),
				"archive-export-postgresql",
			)
	}

	now := guestruntimedomain.Timestamp(service.clock.Now())
	artifactID, err := guestruntimedomain.ArchiveArtifactIDForSourceReceipt(
		command.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		command.Source.ID,
	)
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			rejectedArchiveSourceAdmission(
				"archive-source-identity-invalid",
				err.Error(),
			)
	}
	objectReceipt, err := service.objectStore.CommitArchiveArtifactObject(
		ctx,
		ArchiveArtifactObjectCommit{
			ArtifactID:  artifactID,
			Source:      command.Source,
			Content:     content,
			PersistedAt: now,
		},
	)
	if errors.Is(err, ErrArchiveArtifactObjectContentMismatch) {
		return service.commitQuarantinedSourceAdmission(
			ctx,
			commandDigest,
			command,
			now,
			guestruntimedomain.Issue{
				Code:    "archive-source-content-mismatch",
				Message: "source bytes do not match the Gateway source receipt",
			},
		)
	}
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-artifact-object-commit-unknown",
				err.Error(),
				"guest-archive-object-store",
			)
	}

	resolution, err := service.attributionResolver.ResolveRecorderArtifactAttribution(
		ctx,
		command.Source,
		artifactID,
		now,
	)
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-recorder-attribution-read-failed",
				err.Error(),
				"recorder-assignment-owner",
			)
	}
	attribution, err := guestruntimedomain.ResolveRecorderArtifactAttribution(resolution)
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-recorder-attribution-invalid",
				err.Error(),
				"recorder-assignment-owner",
			)
	}
	artifact := archiveArtifactFromRecorderUpload(
		command.Source,
		objectReceipt,
		now,
	)
	receipt := guestruntimedomain.ArchiveSourceAdmissionReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     command.RequestID,
		Outcome:       "accepted",
		ArtifactReference: &guestruntimedomain.ResourceReference{
			ResourceType: "archive-artifact",
			ResourceID:   artifact.ArtifactID,
		},
		ReceivedAt:  command.Source.ReceivedAt,
		PersistedAt: now,
	}
	err = service.repository.CommitAcceptedArchiveSourceAdmission(
		ctx,
		commandDigest,
		command,
		receipt,
		artifact,
		attribution,
	)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		return service.resolveArchiveSourceAdmissionConflict(
			ctx,
			commandDigest,
			command,
		)
	}
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-admission-commit-unknown",
				err.Error(),
				"archive-export-postgresql",
			)
	}
	return receipt, nil
}

func (service *GuestRuntimeArchiveSourceAdmissionApplicationService) commitDuplicateSourceAdmission(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	existing guestruntimedomain.ArchiveArtifactDetail,
) (guestruntimedomain.ArchiveSourceAdmissionReceipt, error) {
	if existing.Artifact.OriginalFileName != command.Source.OriginalFileName ||
		existing.Artifact.MediaType != command.Source.MediaType ||
		existing.Artifact.ByteSize != command.Source.ByteSize ||
		existing.Artifact.SHA256 != command.Source.SHA256 {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			rejectedArchiveSourceAdmission(
				"archive-source-receipt-conflict",
				"source receipt identity is already bound to different artifact evidence",
			)
	}
	receipt := guestruntimedomain.ArchiveSourceAdmissionReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     command.RequestID,
		Outcome:       "duplicate",
		ArtifactReference: &guestruntimedomain.ResourceReference{
			ResourceType: "archive-artifact",
			ResourceID:   existing.Artifact.ArtifactID,
		},
		ReceivedAt:  command.Source.ReceivedAt,
		PersistedAt: guestruntimedomain.Timestamp(service.clock.Now()),
	}
	if err := service.repository.CommitTerminalArchiveSourceAdmission(
		ctx,
		commandDigest,
		command,
		receipt,
	); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			stored, readErr := service.repository.ReadArchiveSourceAdmission(
				ctx,
				command.RequestID,
			)
			if readErr == nil && stored.CommandDigest == commandDigest {
				return stored.Receipt, nil
			}
		}
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-duplicate-commit-unknown",
				err.Error(),
				"archive-export-postgresql",
			)
	}
	return receipt, nil
}

func (service *GuestRuntimeArchiveSourceAdmissionApplicationService) commitQuarantinedSourceAdmission(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	persistedAt string,
	issue guestruntimedomain.Issue,
) (guestruntimedomain.ArchiveSourceAdmissionReceipt, error) {
	receipt := guestruntimedomain.ArchiveSourceAdmissionReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     command.RequestID,
		Outcome:       "quarantined",
		ReceivedAt:    command.Source.ReceivedAt,
		PersistedAt:   persistedAt,
		Issue:         &issue,
	}
	if err := service.repository.CommitTerminalArchiveSourceAdmission(
		ctx,
		commandDigest,
		command,
		receipt,
	); err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-quarantine-commit-unknown",
				err.Error(),
				"archive-export-postgresql",
			)
	}
	return receipt, nil
}

func (service *GuestRuntimeArchiveSourceAdmissionApplicationService) resolveArchiveSourceAdmissionConflict(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
) (guestruntimedomain.ArchiveSourceAdmissionReceipt, error) {
	stored, err := service.repository.ReadArchiveSourceAdmission(ctx, command.RequestID)
	if err == nil {
		if stored.CommandDigest != commandDigest {
			return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
				rejectedArchiveSourceAdmission(
					"archive-source-request-id-conflict",
					"requestId is already bound to a different Archive source command",
				)
		}
		return stored.Receipt, nil
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-conflict-read-failed",
				err.Error(),
				"archive-export-postgresql",
			)
	}
	existing, err := service.repository.ReadArchiveArtifactDetailBySourceReceipt(
		ctx,
		command.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		command.Source.ID,
	)
	if err != nil {
		return guestruntimedomain.ArchiveSourceAdmissionReceipt{},
			unknownArchiveSourceAdmission(
				"archive-source-conflict-unresolved",
				err.Error(),
				"archive-export-postgresql",
			)
	}
	return service.commitDuplicateSourceAdmission(ctx, commandDigest, command, existing)
}

func archiveArtifactFromRecorderUpload(
	source guestruntimedomain.RecorderVitalUploadSourceReceipt,
	object guestruntimedomain.ArchiveArtifactObjectReceipt,
	createdAt string,
) guestruntimedomain.ArchiveArtifact {
	manifestID := "archive-manifest-" +
		strings.TrimPrefix(object.ArtifactID, "archive-artifact-")
	manifest := guestruntimedomain.ArchiveLineageManifest{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ID:            manifestID,
		Source: guestruntimedomain.ArchiveLineageManifestSource{
			Kind:        source.SourceKind,
			ReceiptType: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
			ReceiptID:   source.ID,
			FinalizedAt: source.FinalizedAt,
			EvidenceReference: guestruntimedomain.EvidenceReference{
				Kind: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
				ID:   source.ID,
			},
		},
		Artifact: guestruntimedomain.ArchiveLineageArtifactIdentity{
			ArtifactID:       object.ArtifactID,
			SHA256:           object.SHA256,
			ByteSize:         object.ByteSize,
			MediaType:        source.MediaType,
			StorageReference: object.StorageReference,
		},
		CreatedAt: createdAt,
	}
	return guestruntimedomain.ArchiveArtifact{
		SchemaVersion:     guestruntimedomain.SchemaVersion,
		ArtifactID:        object.ArtifactID,
		SourceKind:        source.SourceKind,
		SourceReceiptType: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		SourceReceiptID:   source.ID,
		Manifest:          manifest,
		OriginalFileName:  source.OriginalFileName,
		MediaType:         source.MediaType,
		ByteSize:          object.ByteSize,
		SHA256:            object.SHA256,
		FinalizationState: "finalized",
		CreatedAt:         createdAt,
		FinalizedAt:       &source.FinalizedAt,
	}
}

func rejectedArchiveSourceAdmission(
	code string,
	message string,
) ArchiveSourceAdmissionRejectedError {
	return ArchiveSourceAdmissionRejectedError{
		Issue: guestruntimedomain.Issue{Code: code, Message: message},
	}
}

func unknownArchiveSourceAdmission(
	code string,
	message string,
	dependency string,
) ArchiveSourceAdmissionUnknownError {
	retryable := true
	return ArchiveSourceAdmissionUnknownError{
		Issue: guestruntimedomain.Issue{
			Code:       code,
			Message:    message,
			Retryable:  &retryable,
			Dependency: dependency,
		},
	}
}
