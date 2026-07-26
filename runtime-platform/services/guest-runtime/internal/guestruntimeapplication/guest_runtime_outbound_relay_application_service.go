package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeOutboundRelayApplicationService owns relay target configuration and its explicit probe
// result. It has no dependency on RuntimeTopology or GuestRuntimeExternalUpstreamApplicationService.
type GuestRuntimeOutboundRelayApplicationService struct {
	repository  GuestRuntimeOutboundRelayStateRepository
	provider    GuestRuntimeOutboundRelayProvider
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	workflowMu  sync.Mutex
}

func NewGuestRuntimeOutboundRelayApplicationService(repository GuestRuntimeOutboundRelayStateRepository, provider GuestRuntimeOutboundRelayProvider, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeOutboundRelayApplicationService, error) {
	if repository == nil || provider == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Outbound Relay repository, provider, clock, and identifier generator are required")
	}
	return &GuestRuntimeOutboundRelayApplicationService{repository: repository, provider: provider, clock: clock, identifiers: identifiers}, nil
}

func (service *GuestRuntimeOutboundRelayApplicationService) ReadOutboundRelayTarget(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-outbound-relay-target-id", "targetId must be a v1 identifier")
	}
	target, err := service.repository.ReadOutboundRelayTarget(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "outbound-relay-target-missing", "the requested OutboundRelayTarget does not exist")
	}
	if err != nil {
		return failedRead(now, "outbound-relay-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := target.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: target, SourceRevision: &revision}
}

func (service *GuestRuntimeOutboundRelayApplicationService) ListOutboundRelayTargets(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	targets, err := service.repository.ListOutboundRelayTargets(ctx)
	if err != nil {
		return failedRead(now, "outbound-relay-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(targets) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: targets}
}

func (service *GuestRuntimeOutboundRelayApplicationService) ApplyOutboundRelayTarget(ctx context.Context, command guestruntimedomain.OutboundRelayApplyCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateOutboundRelayApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if !guestruntimedomain.ExternalProviderReferenceEqual(service.provider.OutboundRelayObservationProviderReference(), command.Spec.Provider) {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "outbound-relay-provider-reference-mismatch", Message: "command provider does not match the configured outbound relay provider"})
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "outbound-relay-command-digest-failed", Message: "Outbound Relay could not calculate the command digest", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	existing, err := service.repository.ReadOutboundRelayTargetOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.OutboundRelayApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "outbound-relay-state-store-read-failed", Message: "Outbound Relay could not read command request ownership: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"})
	}

	current, err := service.repository.ReadOutboundRelayTarget(ctx, command.TargetID)
	if err != nil && !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "outbound-relay-state-store-read-failed", Message: "Outbound Relay could not read its current target: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"})
	}
	createdAt := ""
	nextRevision := 1
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "OutboundRelayTarget is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned OutboundRelayTarget"})
		}
		createdAt = current.CreatedAt
		nextRevision = current.ResourceRevision + 1
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", relayIdentifierIssue("operation"))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.OutboundRelayApplyOperationKind, command.RequestID, guestruntimedomain.OutboundRelayTargetResourceType, command.TargetID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "outbound-relay-operation-transition-failed", Message: "Outbound Relay could not construct operation transitions", Retryable: boolPointer(false), Dependency: "outbound-relay"})
	}
	if err := service.repository.AdmitOutboundRelayOperation(ctx, command.TargetID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleAdmissionFailure(ctx, command.RequestID, digest, err)
	}

	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	observation, observeErr := service.provider.ObserveOutboundRelay(ctx, command.TargetID, command.Spec, guestruntimedomain.Timestamp(observedAt))
	if observeErr != nil {
		return operation, nil, nil
	}
	target, buildErr := guestruntimedomain.NewOutboundRelayTarget(command, nextRevision, createdAt, observedAt, observation)
	if buildErr != nil {
		issue := guestruntimedomain.Issue{Code: "outbound-relay-provider-contract-invalid", Message: "outbound relay provider returned an invalid observation", Retryable: boolPointer(false), Dependency: command.Spec.Provider.ID}
		target, buildErr = guestruntimedomain.NewOutboundRelayTarget(command, nextRevision, createdAt, observedAt, guestruntimedomain.OutboundRelayObservation{State: "failed", Issue: &issue})
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: guestruntimedomain.OutboundRelayTargetResourceType, ID: target.ID}}
	if target.Status.AcknowledgementReference != nil {
		terminal.EvidenceReferences = append(terminal.EvidenceReferences, *target.Status.AcknowledgementReference)
	}
	if err := service.repository.CommitOutboundRelayOutcome(ctx, target, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeOutboundRelayApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "outbound-relay-rejection-correlation-unavailable", Message: "Outbound Relay could not allocate a rejection correlation identifier", Retryable: boolPointer(true), Dependency: "guest-runtime"})
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeOutboundRelayApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeOutboundRelayApplicationService) newAdmissionFailure(requestID string, admissionState string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func (service *GuestRuntimeOutboundRelayApplicationService) handleAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned OutboundRelayTarget"})
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadOutboundRelayTargetOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.OutboundRelayApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "outbound-relay-state-store-write-outcome-unknown", Message: "Outbound Relay could not determine whether the operation was durably admitted", Retryable: boolPointer(true), Dependency: "guest-state-store"})
}

func relayIdentifierIssue(subject string) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "outbound-relay-identifier-unavailable", Message: "Outbound Relay " + subject + " identifier could not be allocated", Retryable: boolPointer(true), Dependency: "guest-runtime"}
}
