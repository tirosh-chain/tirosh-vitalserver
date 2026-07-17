package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeArchiveApplicationService owns source finalization evidence, immutable manifests, and
// ExportReceipt state. It asks Lab only through GuestRuntimeLabRecorderSourceReader and never reads
// Lab persistence or changes Lab execution state.
type GuestRuntimeArchiveApplicationService struct {
	repository   GuestRuntimeArchiveStateRepository
	sourceReader GuestRuntimeLabRecorderSourceReader
	provider     GuestRuntimeArchiveExportProvider
	clock        GuestRuntimeClock
	identifiers  GuestRuntimeRequestCorrelationIdentifierGenerator
	workflowMu   sync.Mutex
}

func NewGuestRuntimeArchiveApplicationService(repository GuestRuntimeArchiveStateRepository, sourceReader GuestRuntimeLabRecorderSourceReader, provider GuestRuntimeArchiveExportProvider, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeArchiveApplicationService, error) {
	if repository == nil || sourceReader == nil || provider == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Archive repository, Lab source reader, provider, clock, and identifier generator are required")
	}
	return &GuestRuntimeArchiveApplicationService{repository: repository, sourceReader: sourceReader, provider: provider, clock: clock, identifiers: identifiers}, nil
}

func (service *GuestRuntimeArchiveApplicationService) ReadArtifactManifest(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-artifact-manifest-id", "artifactId must be a v1 identifier")
	}
	manifest, err := service.repository.ReadArtifactManifest(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "artifact-manifest-missing", "the requested ArtifactManifest does not exist")
	}
	if err != nil {
		return failedRead(now, "archive-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: manifest}
}

func (service *GuestRuntimeArchiveApplicationService) ReadArtifactExportReceipt(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-export-receipt-id", "receiptId must be a v1 identifier")
	}
	receipt, err := service.repository.ReadArtifactExportReceipt(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "export-receipt-missing", "the requested ExportReceipt does not exist")
	}
	if err != nil {
		return failedRead(now, "archive-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: receipt}
}

// ListArtifactsRetainedForResource is the explicit Archive-to-Lab deletion port. An empty
// slice is a successful Archive answer; a non-nil error means the caller must
// not attempt the Lab delete because retention evidence is unavailable.
func (service *GuestRuntimeArchiveApplicationService) ListArtifactsRetainedForResource(ctx context.Context, target guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error) {
	return service.repository.ListArtifactsRetainedForResource(ctx, target)
}

func (service *GuestRuntimeArchiveApplicationService) ExecuteArtifactExportCommand(ctx context.Context, command guestruntimedomain.ArtifactExportCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateArtifactExportCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if configured := service.provider.ArchiveExportProviderReference(); configured != command.Provider {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "archive-provider-reference-mismatch", Message: "command provider does not match the configured Archive Export provider"})
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "archive-command-digest-failed", Message: "Archive Export could not calculate the command digest", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	existing, err := service.repository.ReadArtifactExportOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.ArtifactExportOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", archiveStoreReadIssue("Archive request id ownership", err))
	}

	source, err := service.sourceReader.ReadStoppedLabVirtualRecorderArchiveSource(ctx, command.VirtualRecorderID, command.ExpectedResourceRevision)
	if err != nil {
		var eligibility SourceEligibilityError
		if errors.As(err, &eligibility) {
			return service.commandRejection(command.RequestID, eligibility.Issue)
		}
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-source-read-failed", Message: "Archive Export could not read stopped Lab source: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-runtime-lab"})
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", archiveIdentifierIssue("Archive Export operation"))
	}
	manifestID, err := service.identifiers.NewRequestCorrelationIdentifier("artifact-manifest")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", archiveIdentifierIssue("ArtifactManifest"))
	}
	artifactID, err := service.identifiers.NewRequestCorrelationIdentifier("artifact")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", archiveIdentifierIssue("artifact"))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, failure := service.newRunningOperation(operationID, command, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	payload, err := guestruntimedomain.FinalizeLabVitalPayload(source)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-source-finalization-failed", Message: "Archive Export could not finalize the Lab source: " + err.Error(), Retryable: boolPointer(false), Dependency: "archive-export"})
	}
	manifest, err := guestruntimedomain.NewArtifactManifest(manifestID, artifactID, operation.ID, source, at, payload)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "artifact-manifest-construction-failed", Message: "Archive Export could not construct an immutable manifest", Retryable: boolPointer(false), Dependency: "archive-export"})
	}
	operation.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: "artifact-manifest", ID: manifest.ID}}
	if err := service.repository.AdmitArtifactExport(ctx, manifest, payload, source.SessionID, operation); err != nil {
		return service.handleAdmissionCommitFailure(ctx, command.RequestID, digest, err)
	}

	uploadedAt := guestruntimedomain.Timestamp(service.clock.Now())
	upload, providerErr := service.provider.UploadArtifactExportPayload(ctx, manifest, payload, uploadedAt)
	if providerErr != nil {
		// The durable operation is already running. The provider outcome is now
		// unknown, so no receipt is written and no terminal state is invented.
		return operation, nil, nil
	}
	indexing := guestruntimedomain.NotRequestedExportStep()
	if upload.State == "succeeded" {
		indexing, providerErr = service.provider.VerifyUploadedArtifactIndex(ctx, manifest, upload, guestruntimedomain.Timestamp(service.clock.Now()))
		if providerErr != nil {
			return operation, nil, nil
		}
	}
	receiptID, err := service.identifiers.NewRequestCorrelationIdentifier("export-receipt")
	if err != nil {
		// The artifact and running operation are durable. Do not overwrite them
		// with a guessed terminal receipt when receipt allocation failed.
		return operation, nil, nil
	}
	completedAt := guestruntimedomain.Timestamp(service.clock.Now())
	receipt, err := guestruntimedomain.NewExportReceipt(receiptID, operation, manifest, command.Provider, upload, indexing, completedAt)
	if err != nil {
		return operation, nil, nil
	}
	terminal := operation
	if receipt.Outcome == "succeeded" {
		terminal, err = guestruntimedomain.TransitionOperation(operation, "succeeded", completedAt, nil)
	} else {
		terminal, err = guestruntimedomain.TransitionOperation(operation, "failed", completedAt, receipt.Issue)
	}
	if err != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = append(terminal.EvidenceReferences, guestruntimedomain.EvidenceReference{Kind: "export-receipt", ID: receipt.ID})
	if err := service.repository.CommitArtifactExportOutcome(ctx, receipt, terminal); err != nil {
		// A terminal receipt/operation commit cannot be inferred after failure.
		// The previously durable running operation remains the public truth.
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeArchiveApplicationService) newRunningOperation(id string, command guestruntimedomain.ArtifactExportCommand, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandAdmissionFailure) {
	operation := guestruntimedomain.NewOperation(id, guestruntimedomain.ArtifactExportOperationKind, command.RequestID, guestruntimedomain.VirtualRecorderResourceType, command.VirtualRecorderID, command.ExpectedResourceRevision, at, digest)
	var err error
	operation, err = guestruntimedomain.TransitionOperation(operation, "accepted", at, nil)
	if err == nil {
		operation, err = guestruntimedomain.TransitionOperation(operation, "running", at, nil)
	}
	if err != nil {
		return guestruntimedomain.Operation{}, service.newAdmissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "archive-operation-transition-failed", Message: "Archive Export could not construct an operation transition", Retryable: boolPointer(false), Dependency: "archive-export"})
	}
	return operation, nil
}

func (service *GuestRuntimeArchiveApplicationService) handleAdmissionCommitFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, revisionConflictIssue())
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadArtifactExportOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.ArtifactExportOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "archive-state-store-write-outcome-unknown", Message: "Archive Export could not determine whether the export operation was durably admitted", Retryable: boolPointer(true), Dependency: "guest-state-store"})
}

func (service *GuestRuntimeArchiveApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "archive-rejection-correlation-unavailable", Message: "Archive Export could not allocate a rejection correlation identifier", Retryable: boolPointer(true), Dependency: "guest-runtime"})
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeArchiveApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeArchiveApplicationService) newAdmissionFailure(requestID string, admissionState string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func archiveStoreReadIssue(subject string, err error) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "archive-state-store-read-failed", Message: subject + " read failed: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"}
}

func archiveIdentifierIssue(subject string) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "archive-identifier-unavailable", Message: subject + " identifier could not be allocated", Retryable: boolPointer(true), Dependency: "guest-runtime"}
}
