package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeExternalUpstreamApplicationService owns external provider configuration, explicit
// observations, and C4 capability projections. It does not own RuntimeTopology
// or delivery receipts.
type GuestRuntimeExternalUpstreamApplicationService struct {
	repository  GuestRuntimeExternalUpstreamStateRepository
	provider    GuestRuntimeExternalUpstreamProvider
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	workflowMu  sync.Mutex
}

func NewGuestRuntimeExternalUpstreamApplicationService(repository GuestRuntimeExternalUpstreamStateRepository, provider GuestRuntimeExternalUpstreamProvider, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeExternalUpstreamApplicationService, error) {
	if repository == nil || provider == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("External Upstream repository, provider, clock, and identifier generator are required")
	}
	return &GuestRuntimeExternalUpstreamApplicationService{repository: repository, provider: provider, clock: clock, identifiers: identifiers}, nil
}

func (service *GuestRuntimeExternalUpstreamApplicationService) ReadExternalUpstreamIntegrationDocument(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-external-upstream-integration-id", "integrationId must be a v1 identifier")
	}
	integration, err := service.repository.ReadExternalUpstreamIntegrationState(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "external-upstream-integration-missing", "the requested ExternalUpstreamIntegration does not exist")
	}
	if err != nil {
		return failedRead(now, "external-upstream-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := integration.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: integration, SourceRevision: &revision}
}

func (service *GuestRuntimeExternalUpstreamApplicationService) ListExternalUpstreamIntegrationDocuments(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	integrations, err := service.repository.ListExternalUpstreamIntegrations(ctx)
	if err != nil {
		return failedRead(now, "external-upstream-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(integrations) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: integrations}
}

// ReadExternalUpstreamIntegrationState is the internal owner boundary used by
// RuntimeTopology. Unlike the presentation read method, it exposes the raw owned
// document and typed repository outcome so the topology workflow can preserve
// missing versus unreadable owner state without treating a UI ReadResult as
// domain input.
func (service *GuestRuntimeExternalUpstreamApplicationService) ReadExternalUpstreamIntegrationState(ctx context.Context, integrationID string) (guestruntimedomain.ExternalUpstreamIntegration, error) {
	return service.repository.ReadExternalUpstreamIntegrationState(ctx, integrationID)
}

// ReadExternalUpstreamCapabilityDocument is the matching internal C4 boundary. The
// caller still validates its stored reference; no bundled document is offered
// as a substitute.
func (service *GuestRuntimeExternalUpstreamApplicationService) ReadExternalUpstreamCapabilityDocument(ctx context.Context, integrationID string) (guestruntimedomain.CapabilityDocument, error) {
	return service.repository.ReadExternalUpstreamCapabilityDocument(ctx, integrationID)
}

func (service *GuestRuntimeExternalUpstreamApplicationService) ApplyExternalUpstreamIntegration(ctx context.Context, command guestruntimedomain.ExternalUpstreamApplyCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateExternalUpstreamApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if !guestruntimedomain.ExternalProviderReferenceEqual(service.provider.ExternalUpstreamObservationProviderReference(), command.Spec.Provider) {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "external-upstream-provider-reference-mismatch", Message: "command provider does not match the configured external upstream provider"})
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-command-digest-failed", Message: "External Upstream could not calculate the command digest", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	existing, err := service.repository.ReadExternalUpstreamIntegrationOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.ExternalUpstreamApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-state-store-read-failed", Message: "External Upstream could not read command request ownership: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"})
	}

	current, err := service.repository.ReadExternalUpstreamIntegrationState(ctx, command.IntegrationID)
	if err != nil && !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-state-store-read-failed", Message: "External Upstream could not read its current integration: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"})
	}
	createdAt := ""
	nextRevision := 1
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "ExternalUpstreamIntegration is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned ExternalUpstreamIntegration"})
		}
		createdAt = current.CreatedAt
		nextRevision = current.ResourceRevision + 1
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", externalIdentifierIssue("operation"))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.ExternalUpstreamApplyOperationKind, command.RequestID, guestruntimedomain.ExternalUpstreamIntegrationResourceType, command.IntegrationID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-operation-transition-failed", Message: "External Upstream could not construct operation transitions", Retryable: boolPointer(false), Dependency: "external-upstream"})
	}
	if err := service.repository.AdmitExternalUpstreamOperation(ctx, command.IntegrationID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleAdmissionFailure(ctx, command.RequestID, digest, err)
	}

	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	observation, observeErr := service.provider.ObserveExternalUpstream(ctx, command.IntegrationID, command.Spec, guestruntimedomain.Timestamp(observedAt))
	if observeErr != nil {
		// The external effect was attempted after durable admission but its
		// result is unknown. Keep the operation running and write no guessed
		// resource/capability state.
		return operation, nil, nil
	}
	integration, capability, buildErr := guestruntimedomain.NewExternalUpstreamIntegration(command, nextRevision, createdAt, observedAt, observation)
	if buildErr != nil {
		// Invalid adapter output is a known failed provider observation, not a
		// successful or empty integration state.
		issue := guestruntimedomain.Issue{Code: "external-upstream-provider-contract-invalid", Message: "external upstream provider returned an invalid observation", Retryable: boolPointer(false), Dependency: command.Spec.Provider.ID}
		observation = guestruntimedomain.ExternalUpstreamObservation{State: "failed", Connection: guestruntimedomain.ConnectionObservation{State: "failed", ObservedAt: guestruntimedomain.Timestamp(observedAt), Issue: &issue}, Issue: &issue}
		integration, capability, buildErr = guestruntimedomain.NewExternalUpstreamIntegration(command, nextRevision, createdAt, observedAt, observation)
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: guestruntimedomain.ExternalUpstreamIntegrationResourceType, ID: integration.ID}}
	if capability != nil {
		terminal.EvidenceReferences = append(terminal.EvidenceReferences, guestruntimedomain.EvidenceReference{Kind: "capability-document", ID: capability.ID})
	}
	if err := service.repository.CommitExternalUpstreamOutcome(ctx, integration, capability, terminal); err != nil {
		// The running operation is already durable. Terminal write failure does
		// not grant permission to report an integration state or terminal result.
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeExternalUpstreamApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "external-upstream-rejection-correlation-unavailable", Message: "External Upstream could not allocate a rejection correlation identifier", Retryable: boolPointer(true), Dependency: "guest-runtime"})
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeExternalUpstreamApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeExternalUpstreamApplicationService) newAdmissionFailure(requestID string, admissionState string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func (service *GuestRuntimeExternalUpstreamApplicationService) handleAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned ExternalUpstreamIntegration"})
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadExternalUpstreamIntegrationOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.ExternalUpstreamApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "external-upstream-state-store-write-outcome-unknown", Message: "External Upstream could not determine whether the operation was durably admitted", Retryable: boolPointer(true), Dependency: "guest-state-store"})
}

func externalIdentifierIssue(subject string) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "external-upstream-identifier-unavailable", Message: "External Upstream " + subject + " identifier could not be allocated", Retryable: boolPointer(true), Dependency: "guest-runtime"}
}

var _ GuestRuntimeExternalUpstreamCapabilityReader = (*GuestRuntimeExternalUpstreamApplicationService)(nil)
