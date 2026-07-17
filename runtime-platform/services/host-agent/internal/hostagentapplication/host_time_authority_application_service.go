package hostagentapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// HostTimeAuthorityApplicationService owns Host-node NTP configuration and quality only. It
// has no GuestControl dependency and cannot read or overwrite Guest time.
type HostTimeAuthorityApplicationService struct {
	repository  HostTimeAuthorityStateRepository
	provider    HostTimeAuthorityProvider
	clock       HostAgentClock
	identifiers HostAgentRequestCorrelationIdentifierGenerator
	node        hostagentdomain.NodeReference
	defaultID   string
	workflowMu  sync.Mutex
}

func NewHostTimeAuthorityApplicationService(repository HostTimeAuthorityStateRepository, provider HostTimeAuthorityProvider, clock HostAgentClock, identifiers HostAgentRequestCorrelationIdentifierGenerator, node hostagentdomain.NodeReference, defaultAuthorityID string) (*HostTimeAuthorityApplicationService, error) {
	if repository == nil || provider == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Host Time Authority repository, provider, clock, and identifier generator are required")
	}
	if node.Kind != "host" || !hostagentdomain.ValidIdentifier(node.ID) || !hostagentdomain.ValidIdentifier(defaultAuthorityID) {
		return nil, fmt.Errorf("Host Time Authority requires an explicit host node and default authority id")
	}
	return &HostTimeAuthorityApplicationService{repository: repository, provider: provider, clock: clock, identifiers: identifiers, node: node, defaultID: defaultAuthorityID}, nil
}

func (service *HostTimeAuthorityApplicationService) ReadHostTimeAuthority(ctx context.Context, id string) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	if !hostagentdomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-time-authority-id", "authorityId must be a v1 identifier")
	}
	authority, err := service.repository.ReadHostTimeAuthority(ctx, id)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "time-authority-missing", "the requested Host TimeAuthority does not exist")
	}
	if err != nil {
		return failedRead(now, "time-authority-state-store-read-failed", err.Error(), "host-state-store")
	}
	revision := authority.ResourceRevision
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: authority, SourceRevision: &revision}
}

func (service *HostTimeAuthorityApplicationService) ReadHostClockQuality(ctx context.Context) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	authority, err := service.repository.ReadHostTimeAuthority(ctx, service.defaultID)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "host-time-authority-missing", "the configured Host TimeAuthority has not been applied")
	}
	if err != nil {
		return failedRead(now, "time-authority-state-store-read-failed", err.Error(), "host-state-store")
	}
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: authority.ClockQuality, SourceRevision: &authority.ResourceRevision}
}

func (service *HostTimeAuthorityApplicationService) ApplyHostTimeAuthorityCommand(ctx context.Context, command hostagentdomain.TimeAuthorityApplyCommand) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := hostagentdomain.ValidateTimeAuthorityApplyCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	if command.Node != service.node {
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "time-authority-node-owner-mismatch", Message: "Host Time Authority can only manage its configured host node"})
	}
	digest, err := hostagentdomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTimeIssue("time-authority-command-digest-failed", "Host Time Authority could not calculate the command digest", true))
	}
	existing, err := service.repository.ReadHostTimeAuthorityOperationByRequestID(ctx, command.RequestID)
	if err == nil {
		if existing.Kind == hostagentdomain.TimeAuthorityApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
	}
	if !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTimeIssue("time-authority-state-store-read-failed", "Host Time Authority could not read command request ownership", true))
	}
	current, err := service.repository.ReadHostTimeAuthority(ctx, command.AuthorityID)
	if err != nil && !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTimeIssue("time-authority-state-store-read-failed", "Host Time Authority could not read its current resource", true))
	}
	createdAt := ""
	nextRevision := 1
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		if command.ExpectedResourceRevision != 0 {
			return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "TimeAuthority is missing, so expectedResourceRevision must be zero"})
		}
	} else {
		if current.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the owned TimeAuthority"})
		}
		createdAt, nextRevision = current.CreatedAt, current.ResourceRevision+1
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("host-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTimeIssue("time-authority-operation-id-unavailable", "Host Time Authority could not allocate an operation identifier", true))
	}
	at := hostagentdomain.Timestamp(service.clock.Now())
	operation, err := runningOperationalOperation(operationID, hostagentdomain.TimeAuthorityApplyOperationKind, command.RequestID, hostagentdomain.TimeAuthorityResourceType, command.AuthorityID, command.ExpectedResourceRevision, at, digest)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", hostTimeIssue("time-authority-operation-transition-failed", "Host Time Authority could not construct operation transitions", false))
	}
	if err := service.repository.AdmitHostTimeAuthorityOperation(ctx, command.AuthorityID, command.ExpectedResourceRevision, operation); err != nil {
		return service.handleAdmissionFailure(ctx, command.RequestID, digest, err)
	}
	if createdAt == "" {
		createdAt = at
	}
	observedAt := service.clock.Now()
	quality, observeErr := service.provider.ObserveTimeAuthority(ctx, service.node, command.Spec, hostagentdomain.Timestamp(observedAt))
	if observeErr != nil {
		return operation, nil, nil
	}
	authority, buildErr := hostagentdomain.NewTimeAuthority(command, nextRevision, createdAt, observedAt, quality)
	if buildErr != nil {
		issue := hostTimeIssue("time-authority-provider-contract-invalid", "Host Time Authority provider returned an invalid ClockQuality", false)
		authority, buildErr = hostagentdomain.NewTimeAuthority(command, nextRevision, createdAt, observedAt, hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: service.node, State: "failed", ObservedAt: hostagentdomain.Timestamp(observedAt), Issue: &issue})
		if buildErr != nil {
			return operation, nil, nil
		}
	}
	terminal, transitionErr := hostagentdomain.TransitionOperation(operation, "succeeded", hostagentdomain.Timestamp(service.clock.Now()), nil)
	if transitionErr != nil {
		return operation, nil, nil
	}
	if err := service.repository.CommitHostTimeAuthorityOutcome(ctx, authority, terminal); err != nil {
		return operation, nil, nil
	}
	return terminal, nil, nil
}

func (service *HostTimeAuthorityApplicationService) commandRejection(requestID string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if !hostagentdomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", hostTimeIssue("time-authority-rejection-correlation-unavailable", "Host Time Authority could not allocate a rejection correlation identifier", true))
		}
		requestID = generated
	}
	return hostagentdomain.Operation{}, &hostagentdomain.CommandRejection{SchemaVersion: hostagentdomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *HostTimeAuthorityApplicationService) admissionFailure(requestID string, state string, issue hostagentdomain.Issue) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *HostTimeAuthorityApplicationService) newAdmissionFailure(requestID string, state string, issue hostagentdomain.Issue) *hostagentdomain.CommandAdmissionFailure {
	return &hostagentdomain.CommandAdmissionFailure{SchemaVersion: hostagentdomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), AdmissionState: state, Issue: issue}
}

func (service *HostTimeAuthorityApplicationService) handleAdmissionFailure(ctx context.Context, requestID string, digest string, err error) (hostagentdomain.Operation, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		existing, readErr := service.repository.ReadHostTimeAuthorityOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == hostagentdomain.TimeAuthorityApplyOperationKind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host command"})
		}
	}
	if errors.Is(err, ErrHostAgentOwnedResourceRevisionConflict) || errors.Is(err, ErrHostAgentOwnedResourceConflict) {
		return service.commandRejection(requestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision no longer matches the owned TimeAuthority"})
	}
	return hostagentdomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", hostTimeIssue("time-authority-state-store-write-outcome-unknown", "Host Time Authority could not determine whether the operation was durably admitted", true))
}

func runningOperationalOperation(id string, kind string, requestID string, targetType string, targetID string, revision int, at string, digest string) (hostagentdomain.Operation, error) {
	operation := hostagentdomain.NewOperationalOperation(id, kind, requestID, targetType, targetID, revision, at, digest)
	var err error
	operation, err = hostagentdomain.TransitionOperation(operation, "accepted", at, nil)
	if err == nil {
		operation, err = hostagentdomain.TransitionOperation(operation, "running", at, nil)
	}
	return operation, err
}

func hostTimeIssue(code string, message string, retryable bool) hostagentdomain.Issue {
	return hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(retryable), Dependency: "host-time-authority"}
}
