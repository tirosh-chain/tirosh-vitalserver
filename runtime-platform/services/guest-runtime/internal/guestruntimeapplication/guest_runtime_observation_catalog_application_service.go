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
	workflowMu  sync.Mutex
}

func NewGuestRuntimeObservationCatalogApplicationService(repository GuestRuntimeObservationCatalogStateRepository, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeObservationCatalogApplicationService, error) {
	if repository == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Observation Catalog repository, clock, and identifier generator are required")
	}
	return &GuestRuntimeObservationCatalogApplicationService{repository: repository, clock: clock, identifiers: identifiers}, nil
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

func (service *GuestRuntimeObservationCatalogApplicationService) ListCatalogObservations(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	observations, err := service.repository.ListCatalogObservations(ctx)
	if err != nil {
		return failedRead(now, "observation-catalog-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(observations) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: observations}
}

func (service *GuestRuntimeObservationCatalogApplicationService) IngestCatalogObservation(ctx context.Context, command guestruntimedomain.CatalogObservationIngestCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateCatalogObservationIngestCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-command-digest-failed", "Observation Catalog could not calculate the command digest", true))
	}
	existingRequest, err := service.repository.ReadCatalogObservationIngestOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existingRequest.Kind == guestruntimedomain.CatalogIngestOperationKind && existingRequest.CommandDigest == digest {
			return existingRequest, nil, nil
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
			return existingSource.Operation, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "catalog-source-identity-conflict", Message: "Recorder source identity already belongs to a different observation envelope"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("observation-catalog-state-store-read-failed", "Observation Catalog could not read the Recorder source identity", true))
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-operation-id-unavailable", "Observation Catalog could not allocate an operation identifier", true))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.CatalogIngestOperationKind, command.RequestID, guestruntimedomain.CatalogObservationResourceType, command.ObservationID, 0, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", catalogIssue("catalog-observation-operation-transition-failed", "Observation Catalog could not construct operation transitions", false))
	}
	if err := service.repository.AdmitCatalogOperation(ctx, sourceKey, operation); err != nil {
		return service.handleAdmissionFailure(ctx, command, digest, envelopeDigest, sourceKey, err)
	}
	observation, buildErr := guestruntimedomain.NewCatalogObservation(command, service.clock.Now(), service.clock.Now())
	if buildErr != nil {
		return operation, nil, nil
	}
	terminal, transitionErr := guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: guestruntimedomain.CatalogObservationResourceType, ID: observation.ID}}
	if err := service.repository.CommitCatalogObservation(ctx, observation, envelopeDigest, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", catalogIssue("catalog-observation-rejection-correlation-unavailable", "Observation Catalog could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeObservationCatalogApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeObservationCatalogApplicationService) newAdmissionFailure(requestID string, state string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *GuestRuntimeObservationCatalogApplicationService) handleAdmissionFailure(ctx context.Context, command guestruntimedomain.CatalogObservationIngestCommand, digest string, envelopeDigest string, sourceKey string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existingRequest, requestErr := service.repository.ReadCatalogObservationIngestOperationByRequestID(ctx, command.RequestID)
		if requestErr == nil && existingRequest.Kind == guestruntimedomain.CatalogIngestOperationKind && existingRequest.CommandDigest == digest {
			return existingRequest, nil, nil
		}
		if requestErr == nil {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
		existingSource, sourceErr := service.repository.ReadCatalogObservationBySourceKey(ctx, sourceKey)
		if sourceErr == nil && existingSource.EnvelopeDigest == envelopeDigest {
			return existingSource.Operation, nil, nil
		}
		if sourceErr == nil {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "catalog-source-identity-conflict", Message: "Recorder source identity already belongs to a different observation envelope"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(command.RequestID, "unknown", catalogIssue("observation-catalog-state-store-write-outcome-unknown", "Observation Catalog could not determine whether the ingest operation was durably admitted", true))
}

func catalogIssue(code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(retryable), Dependency: "observation-catalog"}
}
