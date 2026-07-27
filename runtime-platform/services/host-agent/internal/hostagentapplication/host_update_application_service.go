package hostagentapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type HostUpdateWorkflowOutcome struct {
	Operation hostagentdomain.Operation         `json:"operation"`
	Journal   hostagentdomain.HostUpdateJournal `json:"journal"`
}

// HostUpdateApplicationService owns durable admission, bootstrap handoff state, and the
// installed-release update.  It does not decode C26 ProductUpdateSpecification:
// that belongs to the staged next updater.
type HostUpdateApplicationService struct {
	repository   HostUpdateStateRepository
	bootstrapper HostUpdateBootstrapper
	clock        HostAgentClock
	identifiers  HostAgentRequestCorrelationIdentifierGenerator
	mu           sync.Mutex
}

func NewHostUpdateApplicationService(repository HostUpdateStateRepository, bootstrapper HostUpdateBootstrapper, clock HostAgentClock, identifiers HostAgentRequestCorrelationIdentifierGenerator) (*HostUpdateApplicationService, error) {
	if repository == nil || bootstrapper == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("update repository, bootstrapper, clock, and identifier generator are required")
	}
	return &HostUpdateApplicationService{repository: repository, bootstrapper: bootstrapper, clock: clock, identifiers: identifiers}, nil
}

func (service *HostUpdateApplicationService) ReadHostUpdateJournal(ctx context.Context, updateID string) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	if !hostagentdomain.ValidIdentifier(updateID) {
		return invalidRead(now, "invalid-update-id", "updateId must be a v1 identifier")
	}
	journal, err := service.repository.ReadHostUpdateJournal(ctx, updateID)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "host-update-journal-missing", "the requested Host update journal does not exist")
	}
	if err != nil {
		return failedRead(now, "host-state-store-read-failed", err.Error(), "host-state-store")
	}
	if issue := hostagentdomain.ValidateHostUpdateJournal(journal); issue != nil {
		return invalidRead(now, issue.Code, issue.Message)
	}
	revision := journal.JournalRevision
	return hostagentdomain.ReadResult{SchemaVersion: hostagentdomain.SchemaVersion, State: "available", ObservedAt: now, Value: journal, SourceRevision: &revision}
}

func (service *HostUpdateApplicationService) ReadHostUpdateOperationOwnership(ctx context.Context) hostagentdomain.ReadResult {
	now := hostagentdomain.Timestamp(service.clock.Now())
	installation, err := service.repository.ReadHostPlatformInstallation(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return missingRead(now, "platform-installation-missing", "Host installation state has not been configured")
	}
	if err != nil {
		return failedRead(now, "host-installation-state-read-failed", err.Error(), "host-state-store")
	}
	activeJournals, err := service.repository.ReadActiveHostUpdateJournals(ctx)
	if err != nil {
		return failedRead(now, "active-host-update-state-read-failed", err.Error(), "host-state-store")
	}
	ownership, issue := hostagentdomain.ProjectHostUpdateOperationOwnership(installation, activeJournals)
	if issue != nil {
		return invalidRead(now, issue.Code, issue.Message)
	}
	return hostagentdomain.ReadResult{
		SchemaVersion: hostagentdomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value:         ownership,
	}
}

// RecoverDurableHostUpdateHandoffs is startup recovery for the one state whose effect is
// safe to repeat: a durable bootstrap-staged or handoff-pending journal.  It
// never guesses about an applying next updater.  That updater must later send
// C28 evidence, and an untrusted/missing bootstrap document is a startup
// failure rather than a fallback to a legacy update path.
func (service *HostUpdateApplicationService) RecoverDurableHostUpdateHandoffs(ctx context.Context) error {
	service.mu.Lock()
	defer service.mu.Unlock()
	journals, err := service.repository.ReadRecoverableHostUpdateJournals(ctx)
	if err != nil {
		return fmt.Errorf("read recoverable Host update journals: %w", err)
	}
	for _, journal := range journals {
		if issue := hostagentdomain.ValidateHostUpdateJournal(journal); issue != nil {
			return fmt.Errorf("recover update %s: persisted Host update journal is invalid: %s", journal.ID, issue.Code)
		}
		operation, err := service.repository.ReadHostOperation(ctx, journal.OperationID)
		if err != nil {
			return fmt.Errorf("recover update %s: read Host operation: %w", journal.ID, err)
		}
		if journal.State == "bootstrap-staged" {
			next, transitionErr := hostagentdomain.MarkUpdateHandoffPending(journal, hostagentdomain.Timestamp(service.clock.Now()))
			if transitionErr != nil {
				return fmt.Errorf("recover update %s: mark handoff pending: %w", journal.ID, transitionErr)
			}
			if err := service.repository.PersistHostUpdateProgress(ctx, operation, next); err != nil {
				return fmt.Errorf("recover update %s: persist handoff pending: %w", journal.ID, err)
			}
			journal = next
		}
		if journal.State != "handoff-pending" {
			return fmt.Errorf("recover update %s: unsupported durable recovery state %s", journal.ID, journal.State)
		}
		if issue := service.bootstrapper.RequestHandoff(ctx, journal); issue != nil {
			_, _, admissionFailure := service.failAfterAdmission(ctx, operation, journal, *issue)
			if admissionFailure != nil {
				return fmt.Errorf("recover update %s: persist failed handoff: %s", journal.ID, admissionFailure.Issue.Code)
			}
		}
	}
	return nil
}

func (service *HostUpdateApplicationService) ExecuteHostUpdateCommand(ctx context.Context, command hostagentdomain.HostUpdateCommand) (HostUpdateWorkflowOutcome, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	service.mu.Lock()
	defer service.mu.Unlock()
	if issue := hostagentdomain.ValidateHostUpdateCommand(command); issue != nil {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, *issue), nil
	}
	digest, err := hostagentdomain.HostUpdateCommandDigest(command)
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{Code: "host-update-command-digest-failed", Message: "Host Agent could not calculate the update command digest", Retryable: hostagentdomain.Bool(true), Dependency: "host-agent"})
	}
	existing, err := service.repository.ReadHostUpdateJournalByRequestID(ctx, command.RequestID)
	if err == nil {
		if issue := hostagentdomain.ValidateHostUpdateJournal(existing); issue != nil {
			return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-state-store"})
		}
		operation, operationErr := service.repository.ReadHostOperation(ctx, existing.OperationID)
		if operationErr != nil {
			return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-operation-read-failed", Message: operationErr.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
		}
		if existing.CommandDigest == digest {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: existing}, nil, nil
		}
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host update command"}), nil
	}
	if !errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "host-state-store-read-outcome-unknown", Message: "Host Agent could not read update request ownership", Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}
	installation, err := service.repository.ReadHostPlatformInstallation(ctx)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, hostagentdomain.Issue{Code: "platform-installation-missing", Message: "Host installation state has not been configured"}), nil
	}
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "host-state-store-read-outcome-unknown", Message: "Host Agent could not read its installation state", Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}
	if installation.ID != command.InstallationID {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, hostagentdomain.Issue{Code: "installation-id-mismatch", Message: "update command installationId does not match the Host-owned installation"}), nil
	}
	if installation.ResourceRevision != command.ExpectedInstallationRevision {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, hostagentdomain.Issue{Code: "resource-revision-conflict", Message: "expectedInstallationRevision does not match the Host-owned installation"}), nil
	}
	activeJournals, err := service.repository.ReadActiveHostUpdateJournals(ctx)
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "active-host-update-state-read-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}
	if issue := hostagentdomain.DecideHostUpdateAdmission(activeJournals); issue != nil {
		if issue.Code == "host-update-operation-active" {
			return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, *issue), nil
		}
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", *issue)
	}
	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("host-update-operation")
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{Code: "host-update-operation-id-unavailable", Message: "Host Agent could not allocate an update operation identifier", Retryable: hostagentdomain.Bool(true), Dependency: "host-agent"})
	}
	journalID, err := service.identifiers.NewRequestCorrelationIdentifier("host-update")
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{Code: "host-update-journal-id-unavailable", Message: "Host Agent could not allocate an update journal identifier", Retryable: hostagentdomain.Bool(true), Dependency: "host-agent"})
	}
	now := hostagentdomain.Timestamp(service.clock.Now())
	operation := hostagentdomain.NewHostUpdateOperation(operationID, command, now, digest)
	operation, err = hostagentdomain.TransitionOperation(operation, "accepted", now, nil)
	if err == nil {
		operation, err = hostagentdomain.TransitionOperation(operation, "running", now, nil)
	}
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "not-admitted", hostagentdomain.Issue{Code: "host-update-operation-transition-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	journal := hostagentdomain.NewHostUpdateJournal(journalID, operation, command, now)
	if err := service.repository.PersistNewHostUpdate(ctx, operation, journal); err != nil {
		if errors.Is(err, ErrHostAgentOwnedResourceConflict) {
			existing, readErr := service.repository.ReadHostUpdateJournalByRequestID(ctx, command.RequestID)
			if readErr == nil && existing.CommandDigest == digest {
				if issue := hostagentdomain.ValidateHostUpdateJournal(existing); issue != nil {
					return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-state-store"})
				}
				existingOperation, operationErr := service.repository.ReadHostOperation(ctx, existing.OperationID)
				if operationErr == nil {
					return HostUpdateWorkflowOutcome{Operation: existingOperation, Journal: existing}, nil, nil
				}
			}
			if readErr == nil {
				return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, hostagentdomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Host update command"}), nil
			}
			activeJournals, activeReadErr := service.repository.ReadActiveHostUpdateJournals(ctx)
			if activeReadErr == nil {
				if issue := hostagentdomain.DecideHostUpdateAdmission(activeJournals); issue != nil && issue.Code == "host-update-operation-active" {
					return HostUpdateWorkflowOutcome{}, service.rejection(command.RequestID, *issue), nil
				}
			}
		}
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.RequestID, "unknown", hostagentdomain.Issue{Code: "host-state-store-write-outcome-unknown", Message: "Host Agent could not determine whether the update was durably admitted", Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}

	receipt := service.bootstrapper.Stage(ctx, journal, command.BootstrapEnvelope)
	if issue := hostagentdomain.ValidateUpdateBootstrapReceipt(journal, receipt); issue != nil {
		return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "update-bootstrapper"})
	}
	journal, err = hostagentdomain.StageUpdateBootstrap(journal, receipt)
	if err != nil {
		return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: "update-bootstrap-state-transition-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	if journal.State == "failed" {
		return service.failAfterAdmission(ctx, operation, journal, *journal.Failure)
	}
	if err := service.repository.PersistHostUpdateProgress(ctx, operation, journal); err != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(command.RequestID, "persist staged bootstrap journal", err)
	}
	journal, err = hostagentdomain.MarkUpdateHandoffPending(journal, hostagentdomain.Timestamp(service.clock.Now()))
	if err != nil {
		return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: "update-handoff-state-transition-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	if err := service.repository.PersistHostUpdateProgress(ctx, operation, journal); err != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(command.RequestID, "persist handoff-pending journal", err)
	}
	if issue := service.bootstrapper.RequestHandoff(ctx, journal); issue != nil {
		return service.failAfterAdmission(ctx, operation, journal, *issue)
	}
	return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, nil
}

func (service *HostUpdateApplicationService) CompleteHostUpdateExecution(ctx context.Context, command hostagentdomain.UpdateCompletionCommand) (HostUpdateWorkflowOutcome, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	service.mu.Lock()
	defer service.mu.Unlock()
	if issue := hostagentdomain.ValidateUpdateCompletionCommand(command); issue != nil {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, *issue), nil
	}
	journal, err := service.repository.ReadHostUpdateJournal(ctx, command.UpdateID)
	if errors.Is(err, ErrHostAgentOwnedResourceNotFound) {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, hostagentdomain.Issue{Code: "host-update-journal-missing", Message: "the update journal does not exist"}), nil
	}
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.Report.RequestID, "unknown", hostagentdomain.Issue{Code: "host-state-store-read-outcome-unknown", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}
	if issue := hostagentdomain.ValidateHostUpdateJournal(journal); issue != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.Report.RequestID, "unknown", hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-state-store"})
	}
	operation, err := service.repository.ReadHostOperation(ctx, journal.OperationID)
	if err != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.Report.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-operation-read-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
	}
	reportDigest, digestErr := hostagentdomain.UpdateExecutionReportDigest(command.Report)
	if digestErr != nil {
		return HostUpdateWorkflowOutcome{}, nil, service.admissionFailure(command.Report.RequestID, "not-admitted", hostagentdomain.Issue{Code: "update-execution-report-digest-failed", Message: digestErr.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	if journal.State == "succeeded" || journal.State == "failed" {
		if journal.ExecutionDigest == reportDigest {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, nil
		}
		return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, hostagentdomain.Issue{Code: "update-already-terminal", Message: "a different report cannot settle a terminal update journal"}), nil
	}
	if command.ExpectedJournalRevision != journal.JournalRevision {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, hostagentdomain.Issue{Code: "update-journal-revision-conflict", Message: "expectedJournalRevision does not match the Host-owned update journal"}), nil
	}
	if journal.State == "handoff-pending" {
		journal, err = hostagentdomain.BeginUpdateExecution(journal, hostagentdomain.Timestamp(service.clock.Now()))
		if err != nil {
			return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, hostagentdomain.Issue{Code: "update-execution-state-transition-failed", Message: err.Error()}), nil
		}
		if err := service.repository.PersistHostUpdateProgress(ctx, operation, journal); err != nil {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(command.Report.RequestID, "persist applying journal", err)
		}
	}
	if journal.State != "applying" {
		return HostUpdateWorkflowOutcome{}, service.rejection(command.Report.RequestID, hostagentdomain.Issue{Code: "update-journal-not-ready-for-completion", Message: "only a handed-off update can be completed"}), nil
	}
	nextJournal, err := hostagentdomain.CompleteUpdateExecution(journal, command.Report)
	if err != nil {
		return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: "update-execution-report-invalid", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "next-updater"})
	}
	if nextJournal.State == "succeeded" {
		installation, installationErr := service.repository.ReadHostPlatformInstallation(ctx)
		if installationErr != nil {
			return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: "host-update-installation-read-failed", Message: installationErr.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
		}
		nextInstallation, releaseErr := hostagentdomain.ApplyUpdateRelease(installation, nextJournal, command.Report.FinishedAt)
		if releaseErr != nil {
			return service.failAfterAdmission(ctx, operation, journal, hostagentdomain.Issue{Code: "host-update-installation-revision-conflict", Message: releaseErr.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-state-store"})
		}
		terminal, transitionErr := hostagentdomain.TransitionOperation(operation, "succeeded", command.Report.FinishedAt, nil)
		if transitionErr != nil {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.admissionFailure(command.Report.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-operation-transition-failed", Message: transitionErr.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
		}
		if err := service.repository.CommitHostUpdateOutcome(ctx, terminal, nextJournal, &nextInstallation); err != nil {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(command.Report.RequestID, "persist successful update outcome", err)
		}
		return HostUpdateWorkflowOutcome{Operation: terminal, Journal: nextJournal}, nil, nil
	}
	terminal, transitionErr := hostagentdomain.TransitionOperation(operation, "failed", command.Report.FinishedAt, nextJournal.Failure)
	if transitionErr != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.admissionFailure(command.Report.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-operation-transition-failed", Message: transitionErr.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	if err := service.repository.CommitHostUpdateOutcome(ctx, terminal, nextJournal, nil); err != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(command.Report.RequestID, "persist failed update outcome", err)
	}
	return HostUpdateWorkflowOutcome{Operation: terminal, Journal: nextJournal}, nil, nil
}

func (service *HostUpdateApplicationService) failAfterAdmission(ctx context.Context, operation hostagentdomain.Operation, journal hostagentdomain.HostUpdateJournal, issue hostagentdomain.Issue) (HostUpdateWorkflowOutcome, *hostagentdomain.CommandRejection, *hostagentdomain.CommandAdmissionFailure) {
	failedJournal := journal
	if journal.State != "failed" {
		journalErr := error(nil)
		failedJournal, journalErr = hostagentdomain.FailUpdateJournal(journal, hostagentdomain.Timestamp(service.clock.Now()), issue)
		if journalErr != nil {
			return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.admissionFailure(operation.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-failure-transition-failed", Message: journalErr.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
		}
	} else if failedJournal.Failure == nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.admissionFailure(operation.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-failure-document-invalid", Message: "failed Host update journal has no failure issue", Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	failedOperation, operationErr := hostagentdomain.TransitionOperation(operation, "failed", failedJournal.UpdatedAt, &issue)
	if operationErr != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.admissionFailure(operation.RequestID, "unknown", hostagentdomain.Issue{Code: "host-update-operation-failure-transition-failed", Message: operationErr.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-agent"})
	}
	if err := service.repository.CommitHostUpdateOutcome(ctx, failedOperation, failedJournal, nil); err != nil {
		return HostUpdateWorkflowOutcome{Operation: operation, Journal: journal}, nil, service.persistenceFailure(operation.RequestID, "persist failed update journal", err)
	}
	return HostUpdateWorkflowOutcome{Operation: failedOperation, Journal: failedJournal}, nil, nil
}

func (service *HostUpdateApplicationService) rejection(requestID string, issue hostagentdomain.Issue) *hostagentdomain.CommandRejection {
	if !hostagentdomain.ValidIdentifier(requestID) {
		requestID = "rejection-unavailable-request-id"
	}
	return &hostagentdomain.CommandRejection{SchemaVersion: hostagentdomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: hostagentdomain.Timestamp(service.clock.Now()), Issue: issue}
}

func (service *HostUpdateApplicationService) admissionFailure(requestID string, admissionState string, issue hostagentdomain.Issue) *hostagentdomain.CommandAdmissionFailure {
	if !hostagentdomain.ValidIdentifier(requestID) {
		requestID = "admission-unavailable-request-id"
	}
	return &hostagentdomain.CommandAdmissionFailure{SchemaVersion: hostagentdomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: hostagentdomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func (service *HostUpdateApplicationService) persistenceFailure(requestID string, action string, err error) *hostagentdomain.CommandAdmissionFailure {
	return service.admissionFailure(requestID, "unknown", hostagentdomain.Issue{
		Code:       "host-state-store-write-outcome-unknown",
		Message:    "Host Agent could not " + action + ": " + err.Error(),
		Retryable:  hostagentdomain.Bool(true),
		Dependency: "host-state-store",
	})
}
