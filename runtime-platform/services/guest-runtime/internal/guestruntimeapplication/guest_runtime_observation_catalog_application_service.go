package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeObservationCatalogApplicationService owns immutable query projections of Recorder
// self-observations. It does not interpret a report as a Gateway connection or
// overwrite the Recorder-owned occurredAt timestamp.
type GuestRuntimeObservationCatalogApplicationService struct {
	repository  GuestRuntimeObservationCatalogStateRepository
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	freshness   guestruntimedomain.RecorderObservationFreshnessPolicy
	workflowMu  sync.Mutex
}

func NewGuestRuntimeObservationCatalogApplicationService(repository GuestRuntimeObservationCatalogStateRepository, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator, freshness guestruntimedomain.RecorderObservationFreshnessPolicy) (*GuestRuntimeObservationCatalogApplicationService, error) {
	if repository == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Observation Catalog repository, clock, and identifier generator are required")
	}
	if err := guestruntimedomain.ValidateRecorderObservationFreshnessPolicy(freshness); err != nil {
		return nil, err
	}
	return &GuestRuntimeObservationCatalogApplicationService{repository: repository, clock: clock, identifiers: identifiers, freshness: freshness}, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) ReadCatalogObservation(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-catalog-observation-id", "observationId must be a v1 identifier")
	}
	observation, err := service.repository.ReadCatalogObservation(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "catalog-observation-missing", "the requested CatalogObservation does not exist")
	}
	if err != nil {
		return failedRead(now, "observation-catalog-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: observation}
}

func (service *GuestRuntimeObservationCatalogApplicationService) ReadRecorderObservabilitySummary(ctx context.Context, recorderID string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(recorderID) {
		return invalidRead(now, "invalid-recorder-id", "recorderId must be a v1 identifier")
	}
	summary, err := service.repository.ReadRecorderObservabilitySummary(ctx, recorderID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "recorder-observability-summary-missing", "the requested Recorder has no Catalog-owned current projection")
	}
	if err != nil {
		return failedRead(now, "observation-catalog-state-store-read-failed", err.Error(), "observation-catalog")
	}
	projected, err := guestruntimedomain.ProjectRecorderReportFreshness(summary, service.freshness, service.clock.Now())
	if err != nil {
		return failedRead(now, "recorder-observation-freshness-projection-failed", err.Error(), "observation-catalog")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: projected}
}

func (service *GuestRuntimeObservationCatalogApplicationService) IngestCatalogObservation(ctx context.Context, command guestruntimedomain.CatalogObservationIngestCommand, evidence CatalogObservationAdmissionEvidence) (guestruntimedomain.CatalogObservationAdmission, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if evidence.SourceIdentity == "" || evidence.MediaType == "" || evidence.ReceivedBytes < 0 {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-admission-evidence-invalid", "Observation Catalog admission requires explicit authenticated source, media type, and received byte evidence", false))
	}
	if issue := guestruntimedomain.ValidateCatalogObservationIngestCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-command-digest-failed", "Observation Catalog could not calculate the command digest", true))
	}
	existingRequest, err := service.repository.ReadCatalogObservationAdmissionByRequestID(ctx, command.RequestID)
	if err == nil {
		if existingRequest.CommandDigest == digest {
			return existingRequest.Admission, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Observation Catalog could not read command request ownership", true))
	}
	envelopeDigest, err := guestruntimedomain.CatalogEnvelopeDigest(command.Envelope)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-envelope-digest-failed", "Observation Catalog could not calculate the source envelope digest", false))
	}
	sourceKey := guestruntimedomain.CatalogSourceKey(command.Envelope)
	existingSource, err := service.repository.ReadCatalogObservationBySourceKey(ctx, sourceKey)
	if err == nil {
		if existingSource.EnvelopeDigest == envelopeDigest {
			duplicate, duplicateErr := guestruntimedomain.NewDuplicateCatalogObservationAdmission(
				command.RequestID,
				existingSource.Observation.ID,
				service.clock.Now(),
				service.clock.Now(),
			)
			if duplicateErr != nil {
				return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-duplicate-admission-invalid", "Observation Catalog could not construct the duplicate admission receipt", false))
			}
			if err := service.repository.CommitDuplicateCatalogObservationAdmission(ctx, digest, sourceKey, envelopeDigest, duplicate, evidence); err != nil {
				return service.handleAdmissionFailure(ctx, command, digest, envelopeDigest, sourceKey, evidence, err)
			}
			return duplicate, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "catalog-source-identity-conflict", Message: "Recorder source identity already belongs to a different observation envelope"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Observation Catalog could not read the Recorder source identity", true))
	}
	observation, buildErr := guestruntimedomain.NewCatalogObservation(command, service.clock.Now(), service.clock.Now())
	if buildErr != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-projection-invalid", "Observation Catalog could not construct the validated immutable projection", false))
	}
	admission, admissionErr := guestruntimedomain.NewAcceptedCatalogObservationAdmission(command, service.clock.Now(), service.clock.Now())
	if admissionErr != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-admission-invalid", "Observation Catalog could not construct the accepted admission receipt", false))
	}
	var previousSummary *guestruntimedomain.RecorderObservabilitySummary
	expectedPreviousRevision := 0
	storedSummary, summaryErr := service.repository.ReadRecorderObservabilitySummary(ctx, observation.Envelope.RecorderID)
	if summaryErr == nil {
		previousSummary = &storedSummary
		expectedPreviousRevision = storedSummary.ResourceRevision
	} else if !errors.Is(summaryErr, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Observation Catalog could not read the Recorder current projection", true))
	}
	summary, projectionErr := guestruntimedomain.ProjectRecorderObservabilitySummary(observation, previousSummary)
	if projectionErr != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-current-projection-invalid", "Observation Catalog could not construct the Recorder current projection", false))
	}
	if err := service.repository.CommitAcceptedCatalogObservation(ctx, observation, digest, envelopeDigest, admission, summary, expectedPreviousRevision, evidence); err != nil {
		return service.handleAdmissionFailure(ctx, command, digest, envelopeDigest, sourceKey, evidence, err)
	}
	return admission, nil, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) QuarantineCatalogObservation(
	ctx context.Context,
	requestID string,
	sourceDocument map[string]any,
	issue guestruntimedomain.Issue,
	evidence CatalogObservationAdmissionEvidence,
) (guestruntimedomain.CatalogObservationAdmission, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if !guestruntimedomain.ValidIdentifier(requestID) || sourceDocument == nil || issue.Code == "" || issue.Message == "" || evidence.SourceIdentity == "" || evidence.MediaType == "" || evidence.ReceivedBytes < 0 {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "invalid-catalog-quarantine-evidence", Message: "Catalog quarantine requires explicit request, source document, issue, and transport evidence"})
	}
	digest, err := guestruntimedomain.CommandDigest(sourceDocument)
	if err != nil {
		return service.admissionFailure(requestID, "not-admitted", catalogIssue("catalog-quarantine-digest-failed", "Observation Catalog could not calculate the quarantined source digest", true))
	}
	existing, err := service.repository.ReadCatalogObservationAdmissionByRequestID(ctx, requestID)
	if err == nil {
		if existing.CommandDigest == digest {
			return existing.Admission, nil, nil
		}
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Catalog admission"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(requestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Observation Catalog could not read quarantine request ownership", true))
	}
	admission, err := guestruntimedomain.NewQuarantinedCatalogObservationAdmission(requestID, issue, service.clock.Now(), service.clock.Now())
	if err != nil {
		return service.admissionFailure(requestID, "not-admitted", catalogIssue("catalog-quarantine-receipt-invalid", "Observation Catalog could not construct the quarantine receipt", false))
	}
	if err := service.repository.CommitQuarantinedCatalogObservationAdmission(ctx, digest, admission, sourceDocument, evidence); err != nil {
		if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
			durable, readErr := service.repository.ReadCatalogObservationAdmissionByRequestID(ctx, requestID)
			if readErr == nil && durable.CommandDigest == digest {
				return durable.Admission, nil, nil
			}
		}
		return service.admissionFailure(requestID, "unknown", catalogIssue("catalog-quarantine-write-outcome-unknown", "Observation Catalog could not determine whether quarantine evidence was durably persisted", true))
	}
	return admission, nil, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.CatalogObservationAdmission, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.CatalogObservationAdmission{}, nil, service.newAdmissionFailure(requestID, "not-admitted", catalogIssue("catalog-observation-rejection-correlation-unavailable", "Observation Catalog could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return guestruntimedomain.CatalogObservationAdmission{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.CatalogObservationAdmission, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.CatalogObservationAdmission{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeObservationCatalogApplicationService) newAdmissionFailure(requestID string, state string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *GuestRuntimeObservationCatalogApplicationService) handleAdmissionFailure(ctx context.Context, command guestruntimedomain.CatalogObservationIngestCommand, digest string, envelopeDigest string, sourceKey string, evidence CatalogObservationAdmissionEvidence, err error) (guestruntimedomain.CatalogObservationAdmission, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existingRequest, requestErr := service.repository.ReadCatalogObservationAdmissionByRequestID(ctx, command.RequestID)
		if requestErr == nil && existingRequest.CommandDigest == digest {
			return existingRequest.Admission, nil, nil
		}
		if requestErr == nil {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
		existingSource, sourceErr := service.repository.ReadCatalogObservationBySourceKey(ctx, sourceKey)
		if sourceErr == nil && existingSource.EnvelopeDigest == envelopeDigest {
			duplicate, duplicateErr := guestruntimedomain.NewDuplicateCatalogObservationAdmission(command.RequestID, existingSource.Observation.ID, service.clock.Now(), service.clock.Now())
			if duplicateErr == nil {
				if duplicateCommitErr := service.repository.CommitDuplicateCatalogObservationAdmission(ctx, digest, sourceKey, envelopeDigest, duplicate, evidence); duplicateCommitErr == nil {
					return duplicate, nil, nil
				}
				durableRequest, durableRequestErr := service.repository.ReadCatalogObservationAdmissionByRequestID(ctx, command.RequestID)
				if durableRequestErr == nil && durableRequest.CommandDigest == digest {
					return durableRequest.Admission, nil, nil
				}
			}
		}
		if sourceErr == nil {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "catalog-source-identity-conflict", Message: "Recorder source identity already belongs to a different observation envelope"})
		}
	}
	return guestruntimedomain.CatalogObservationAdmission{}, nil, service.newAdmissionFailure(command.RequestID, "unknown", catalogIssue("observation-catalog-state-store-write-outcome-unknown", "Observation Catalog could not determine whether the observation admission was durably persisted", true))
}

func catalogIssue(code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(retryable), Dependency: "observation-catalog"}
}
