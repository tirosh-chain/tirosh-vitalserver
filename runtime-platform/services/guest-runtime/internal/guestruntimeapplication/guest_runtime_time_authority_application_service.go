package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeTimeAuthorityApplicationService owns only the configured Guest node's NTP profile and
// ClockQuality. It cannot read, project, or repair Host clock state.
type GuestRuntimeTimeAuthorityApplicationService struct {
	repository  GuestRuntimeTimeAuthorityStateRepository
	provider    GuestRuntimeTimeAuthorityProvider
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	node        guestruntimedomain.NodeReference
	defaultID   string
	workflowMu  sync.Mutex
}

func NewGuestRuntimeTimeAuthorityApplicationService(repository GuestRuntimeTimeAuthorityStateRepository, provider GuestRuntimeTimeAuthorityProvider, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator, node guestruntimedomain.NodeReference, defaultAuthorityID string) (*GuestRuntimeTimeAuthorityApplicationService, error) {
	if repository == nil || provider == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Time Authority repository, provider, clock, and identifier generator are required")
	}
	if node.Kind != "guest" || !guestruntimedomain.ValidIdentifier(node.ID) || !guestruntimedomain.ValidIdentifier(defaultAuthorityID) {
		return nil, fmt.Errorf("Guest Time Authority requires an explicit guest node and default authority id")
	}
	return &GuestRuntimeTimeAuthorityApplicationService{repository: repository, provider: provider, clock: clock, identifiers: identifiers, node: node, defaultID: defaultAuthorityID}, nil
}

func (service *GuestRuntimeTimeAuthorityApplicationService) ReadTimeAuthority(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-time-authority-id", "authorityId must be a v1 identifier")
	}
	authority, err := service.repository.ReadTimeAuthority(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "time-authority-missing", "the requested TimeAuthority does not exist")
	}
	if err != nil {
		return failedRead(now, "time-authority-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := authority.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: authority, SourceRevision: &revision}
}

func (service *GuestRuntimeTimeAuthorityApplicationService) ReadGuestClockQuality(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	authority, err := service.repository.ReadTimeAuthority(ctx, service.defaultID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "guest-time-authority-missing", "the configured Guest TimeAuthority has not been applied")
	}
	if err != nil {
		return failedRead(now, "time-authority-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: authority.ClockQuality, SourceRevision: &authority.ResourceRevision}
}

func (service *GuestRuntimeTimeAuthorityApplicationService) ApplyTimeAuthority(ctx context.Context, command guestruntimedomain.TimeAuthorityApplyCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateTimeAuthorityApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if command.Node != service.node {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "time-authority-node-owner-mismatch", Message: "Guest Time Authority can only manage its configured guest node"})
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", timeIssue("time-authority-command-digest-failed", "Guest Time Authority could not calculate the command digest", true))
	}
	existing, err := service.repository.ReadTimeAuthorityOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == guestruntimedomain.TimeAuthorityApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
	}
	if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", timeIssue("time-authority-state-store-read-failed", "Guest Time Authority could not read command request ownership", true))
	}
	current, err := service.repository.ReadTimeAuthority(ctx, command.AuthorityID)
	if err != nil && !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", timeIssue("time-authority-state-store-read-failed", "Guest Time Authority could not read its current resource", true))
	}
	createdAt := ""
	nextRevision := 1
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "TimeAuthority is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TimeAuthority"})
		}
		createdAt = current.CreatedAt
		nextRevision = current.ResourceRevision + 1
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", timeIssue("time-authority-operation-id-unavailable", "Guest Time Authority could not allocate an operation identifier", true))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(operationID, guestruntimedomain.TimeAuthorityApplyOperationKind, command.RequestID, guestruntimedomain.TimeAuthorityResourceType, command.AuthorityID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", timeIssue("time-authority-operation-transition-failed", "Guest Time Authority could not construct operation transitions", false))
	}
	if err := service.repository.AdmitTimeAuthorityOperation(ctx, command.AuthorityID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	quality, observationErr := service.provider.ObserveTimeAuthority(ctx, service.node, command.Spec, guestruntimedomain.Timestamp(observedAt))
	if observationErr != nil {
		return operation, nil, nil
	}
	authority, buildErr := guestruntimedomain.NewTimeAuthority(command, nextRevision, createdAt, observedAt, quality)
	if buildErr != nil {
		issue := timeIssue("time-authority-provider-contract-invalid", "Guest Time Authority provider returned an invalid ClockQuality", false)
		quality = guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: service.node, State: "failed", ObservedAt: guestruntimedomain.Timestamp(observedAt), Issue: &issue}
		authority, buildErr = guestruntimedomain.NewTimeAuthority(command, nextRevision, createdAt, observedAt, quality)
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := guestruntimedomain.TransitionOperation(operation, "succeeded", guestruntimedomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	terminal.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: guestruntimedomain.TimeAuthorityResourceType, ID: authority.ID}}
	if err := service.repository.CommitTimeAuthorityOutcome(ctx, authority, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeTimeAuthorityApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", timeIssue("time-authority-rejection-correlation-unavailable", "Guest Time Authority could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeTimeAuthorityApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeTimeAuthorityApplicationService) newAdmissionFailure(requestID string, state string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *GuestRuntimeTimeAuthorityApplicationService) handleAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TimeAuthority"})
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadTimeAuthorityOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == guestruntimedomain.TimeAuthorityApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", timeIssue("time-authority-state-store-write-outcome-unknown", "Guest Time Authority could not determine whether the operation was durably admitted", true))
}

func timeIssue(code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(retryable), Dependency: "guest-time-authority"}
}
