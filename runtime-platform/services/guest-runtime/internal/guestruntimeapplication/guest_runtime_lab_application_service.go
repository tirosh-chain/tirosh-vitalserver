package guestruntimeapplication

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeLabApplicationService owns only Lab aggregate lifecycle state. It never reads Archive
// manifests or provider receipts; the HTTP composition obtains explicit archive
// retention evidence before it asks this service to execute a delete command.
type GuestRuntimeLabApplicationService struct {
	repository  GuestRuntimeLabStateRepository
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	workflowMu  sync.Mutex
}

func NewGuestRuntimeLabApplicationService(repository GuestRuntimeLabStateRepository, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeLabApplicationService, error) {
	if repository == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Lab repository, clock, and identifier generator are required")
	}
	return &GuestRuntimeLabApplicationService{repository: repository, clock: clock, identifiers: identifiers}, nil
}

func (service *GuestRuntimeLabApplicationService) ReadLabSession(ctx context.Context, id string) guestruntimedomain.ReadResult {
	return service.readSession(ctx, id)
}

func (service *GuestRuntimeLabApplicationService) ListLabSessions(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	sessions, err := service.repository.ListLabSessions(ctx)
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(sessions) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: sessions}
}

func (service *GuestRuntimeLabApplicationService) ReadLabBed(ctx context.Context, id string) guestruntimedomain.ReadResult {
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(guestruntimedomain.Timestamp(service.clock.Now()), "invalid-lab-bed-id", "bedId must be a v1 identifier")
	}
	now := guestruntimedomain.Timestamp(service.clock.Now())
	bed, err := service.repository.ReadLabBed(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "lab-bed-missing", "the requested Lab bed does not exist")
	}
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := bed.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: bed, SourceRevision: &revision}
}

func (service *GuestRuntimeLabApplicationService) ListLabBeds(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	beds, err := service.repository.ListLabBeds(ctx)
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(beds) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: beds}
}

func (service *GuestRuntimeLabApplicationService) ReadLabVirtualRecorder(ctx context.Context, id string) guestruntimedomain.ReadResult {
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(guestruntimedomain.Timestamp(service.clock.Now()), "invalid-virtual-recorder-id", "virtualRecorderId must be a v1 identifier")
	}
	now := guestruntimedomain.Timestamp(service.clock.Now())
	recorder, err := service.repository.ReadLabVirtualRecorder(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "virtual-recorder-missing", "the requested virtual recorder does not exist")
	}
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := recorder.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: recorder, SourceRevision: &revision}
}

func (service *GuestRuntimeLabApplicationService) ListLabVirtualRecorders(ctx context.Context) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	recorders, err := service.repository.ListVirtualRecorders(ctx)
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	if len(recorders) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: recorders}
}

func (service *GuestRuntimeLabApplicationService) ReadLabResourceDeletionReceipt(ctx context.Context, id string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(now, "invalid-deletion-receipt-id", "receiptId must be a v1 identifier")
	}
	receipt, err := service.repository.ReadLabResourceDeletionReceipt(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "deletion-receipt-missing", "the requested deletion receipt does not exist")
	}
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: receipt}
}

func (service *GuestRuntimeLabApplicationService) CreateLabSession(ctx context.Context, command guestruntimedomain.CreateLabSessionCommand) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateCreateLabSessionCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-command-digest-failed", Message: "Lab could not calculate the create command digest", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	if existing, rejection, failure := service.idempotentOperation(ctx, command.RequestID, guestruntimedomain.LabCreateSessionOperationKind, digest); existing != nil || rejection != nil || failure != nil {
		if existing != nil {
			return *existing, nil, nil
		}
		return guestruntimedomain.Operation{}, rejection, failure
	}
	if _, err := service.repository.ReadLabSession(ctx, command.SessionID); err == nil {
		return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "lab-session-already-exists", Message: "sessionId already belongs to a Lab session"})
	} else if !errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.admissionFailure(command.RequestID, "not-admitted", storeReadIssue("Lab session create precondition", err))
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", identifierIssue("Lab create operation"))
	}
	bedIDs := make([]string, command.RecorderCount)
	recorderIDs := make([]string, command.RecorderCount)
	for index := range bedIDs {
		if bedIDs[index], err = service.identifiers.NewRequestCorrelationIdentifier("lab-bed"); err != nil {
			return service.admissionFailure(command.RequestID, "not-admitted", identifierIssue("Lab bed"))
		}
		if recorderIDs[index], err = service.identifiers.NewRequestCorrelationIdentifier("lab-recorder"); err != nil {
			return service.admissionFailure(command.RequestID, "not-admitted", identifierIssue("virtual recorder"))
		}
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	session := guestruntimedomain.NewLabSession(command, at)
	beds := make([]guestruntimedomain.LabBed, command.RecorderCount)
	recorders := make([]guestruntimedomain.VirtualRecorder, command.RecorderCount)
	for index := range beds {
		recorders[index] = guestruntimedomain.NewVirtualRecorder(recorderIDs[index], session, bedIDs[index], index+1, at)
		beds[index] = guestruntimedomain.NewLabBed(bedIDs[index], session, recorderIDs[index], index+1, at)
	}
	operation, failure := service.newSucceededOperation(operationID, guestruntimedomain.LabCreateSessionOperationKind, command.RequestID, guestruntimedomain.LabSessionResourceType, session.ID, 0, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, UpsertSession: &session, UpsertBeds: beds, UpsertRecorders: recorders}); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, guestruntimedomain.LabCreateSessionOperationKind, digest, err)
	}
	return operation, nil, nil
}

// ExecuteResource receives retained Archive references only for delete. The
// caller must obtain them from Archive Export before invoking this Lab-owned
// transition, so a failed retention read cannot produce a partial Lab delete.
func (service *GuestRuntimeLabApplicationService) ExecuteLabResourceCommand(ctx context.Context, command guestruntimedomain.LabResourceCommand, retained []guestruntimedomain.ResourceReference) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if issue := guestruntimedomain.ValidateLabResourceCommand(command); issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-command-digest-failed", Message: "Lab could not calculate the resource command digest", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	kind := guestruntimedomain.LabResourceOperationKind(command.Action)
	if existing, rejection, failure := service.idempotentOperation(ctx, command.RequestID, kind, digest); existing != nil || rejection != nil || failure != nil {
		if existing != nil {
			return *existing, nil, nil
		}
		return guestruntimedomain.Operation{}, rejection, failure
	}

	var session *guestruntimedomain.LabSession
	var bed *guestruntimedomain.LabBed
	var recorder *guestruntimedomain.VirtualRecorder
	switch command.ResourceType {
	case guestruntimedomain.LabSessionResourceType:
		value, readErr := service.repository.ReadLabSession(ctx, command.ResourceID)
		if result := service.requiredLabRead(command.RequestID, "lab-session-missing", "Lab session is missing", readErr); result != nil {
			return result.operation, result.rejection, result.failure
		}
		session = &value
		if session.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, revisionConflictIssue())
		}
	case guestruntimedomain.LabBedResourceType:
		value, readErr := service.repository.ReadLabBed(ctx, command.ResourceID)
		if result := service.requiredLabRead(command.RequestID, "lab-bed-missing", "Lab bed is missing", readErr); result != nil {
			return result.operation, result.rejection, result.failure
		}
		bed = &value
		if bed.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, revisionConflictIssue())
		}
	case guestruntimedomain.VirtualRecorderResourceType:
		value, readErr := service.repository.ReadLabVirtualRecorder(ctx, command.ResourceID)
		if result := service.requiredLabRead(command.RequestID, "virtual-recorder-missing", "virtual recorder is missing", readErr); result != nil {
			return result.operation, result.rejection, result.failure
		}
		recorder = &value
		if recorder.ResourceRevision != command.ExpectedResourceRevision {
			return service.commandRejection(command.RequestID, revisionConflictIssue())
		}
	}

	operationID, err := service.identifiers.NewRequestCorrelationIdentifier("guest-operation")
	if err != nil {
		return service.admissionFailure(command.RequestID, "not-admitted", identifierIssue("Lab resource operation"))
	}
	at := guestruntimedomain.Timestamp(service.clock.Now())
	commit := LabStateTransitionCommit{}
	switch command.Action {
	case "start":
		if session != nil {
			recorders, readErr := service.repository.ListVirtualRecordersBySession(ctx, session.ID)
			if readErr != nil {
				return service.admissionFailure(command.RequestID, "not-admitted", storeReadIssue("Lab session start", readErr))
			}
			nextSession, nextRecorders, issue := guestruntimedomain.StartLabSession(*session, recorders, at)
			if issue != nil {
				return service.commandRejection(command.RequestID, *issue)
			}
			commit.UpsertSession = &nextSession
			commit.UpsertRecorders = nextRecorders
		} else {
			owner, readErr := service.recorderSession(ctx, *recorder)
			if readErr != nil {
				return service.readFailureForResourceCommand(command.RequestID, readErr)
			}
			nextRecorder, issue := guestruntimedomain.StartVirtualRecorder(owner, *recorder, at)
			if issue != nil {
				return service.commandRejection(command.RequestID, *issue)
			}
			commit.UpsertRecorders = []guestruntimedomain.VirtualRecorder{nextRecorder}
		}
	case "stop":
		if session != nil {
			recorders, readErr := service.repository.ListVirtualRecordersBySession(ctx, session.ID)
			if readErr != nil {
				return service.admissionFailure(command.RequestID, "not-admitted", storeReadIssue("Lab session stop", readErr))
			}
			nextSession, nextRecorders, issue := guestruntimedomain.StopLabSession(*session, recorders, at)
			if issue != nil {
				return service.commandRejection(command.RequestID, *issue)
			}
			commit.UpsertSession = &nextSession
			commit.UpsertRecorders = nextRecorders
		} else {
			owner, readErr := service.recorderSession(ctx, *recorder)
			if readErr != nil {
				return service.readFailureForResourceCommand(command.RequestID, readErr)
			}
			nextRecorder, issue := guestruntimedomain.StopVirtualRecorder(owner, *recorder, at)
			if issue != nil {
				return service.commandRejection(command.RequestID, *issue)
			}
			commit.UpsertRecorders = []guestruntimedomain.VirtualRecorder{nextRecorder}
		}
	case "hide", "unhide":
		nextBed, nextRecorder, issue := guestruntimedomain.ChangeLabVisibility(command.ResourceType, bed, recorder, command.Action, at)
		if issue != nil {
			return service.commandRejection(command.RequestID, *issue)
		}
		if nextBed != nil {
			commit.UpsertBeds = []guestruntimedomain.LabBed{*nextBed}
		}
		if nextRecorder != nil {
			commit.UpsertRecorders = []guestruntimedomain.VirtualRecorder{*nextRecorder}
		}
	case "detach":
		if recorder.BedReference == nil {
			return service.commandRejection(command.RequestID, guestruntimedomain.Issue{Code: "virtual-recorder-already-detached", Message: "virtual recorder has no Lab bed assignment"})
		}
		currentBed, readErr := service.repository.ReadLabBed(ctx, recorder.BedReference.ResourceID)
		if readErr != nil {
			return service.readFailureForResourceCommand(command.RequestID, readErr)
		}
		nextRecorder, nextBed, issue := guestruntimedomain.DetachVirtualRecorder(*recorder, currentBed, at)
		if issue != nil {
			return service.commandRejection(command.RequestID, *issue)
		}
		commit.UpsertRecorders = []guestruntimedomain.VirtualRecorder{nextRecorder}
		commit.UpsertBeds = []guestruntimedomain.LabBed{nextBed}
	case "delete":
		if issue := guestruntimedomain.ValidateLabDelete(command, session, bed, recorder); issue != nil {
			return service.commandRejection(command.RequestID, *issue)
		}
		receiptID, idErr := service.identifiers.NewRequestCorrelationIdentifier("deletion-receipt")
		if idErr != nil {
			return service.admissionFailure(command.RequestID, "not-admitted", identifierIssue("deletion receipt"))
		}
		deleted, populateErr := service.populateDeleteCommit(ctx, command, session, bed, recorder, &commit)
		if populateErr != nil {
			return service.readFailureForResourceCommand(command.RequestID, populateErr)
		}
		commit.DeletionReceipt = &guestruntimedomain.DeletionReceipt{
			SchemaVersion:     guestruntimedomain.SchemaVersion,
			ID:                receiptID,
			OperationID:       operationID,
			RequestID:         command.RequestID,
			Target:            guestruntimedomain.ResourceReference{ResourceType: command.ResourceType, ResourceID: command.ResourceID},
			Cascade:           command.Cascade,
			DeletedResources:  deleted,
			RetainedResources: append([]guestruntimedomain.ResourceReference(nil), retained...),
			CompletedAt:       at,
		}
	}

	operation, failure := service.newSucceededOperation(operationID, kind, command.RequestID, command.ResourceType, command.ResourceID, command.ExpectedResourceRevision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if commit.DeletionReceipt != nil {
		operation.EvidenceReferences = []guestruntimedomain.EvidenceReference{{Kind: "deletion-receipt", ID: commit.DeletionReceipt.ID}}
	}
	commit.Operation = operation
	if err := service.repository.CommitLabStateTransition(ctx, commit); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, kind, digest, err)
	}
	return operation, nil, nil
}

// ReadStoppedRecorderSource is the Lab-side implementation of the explicit
// Archive port. It returns a typed eligibility error for known lifecycle and
// revision failures, never an empty source object.
func (service *GuestRuntimeLabApplicationService) ReadStoppedLabVirtualRecorderArchiveSource(ctx context.Context, recorderID string, expectedRevision int) (guestruntimedomain.StoppedRecorderSource, error) {
	if !guestruntimedomain.ValidIdentifier(recorderID) || expectedRevision < 1 {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "invalid-artifact-source-reference", Message: "virtual recorder id and expected revision must be valid"}}
	}
	recorder, err := service.repository.ReadLabVirtualRecorder(ctx, recorderID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "virtual-recorder-missing", Message: "the selected virtual recorder does not exist"}}
	}
	if err != nil {
		return guestruntimedomain.StoppedRecorderSource{}, fmt.Errorf("read virtual recorder source: %w", err)
	}
	if recorder.ResourceRevision != expectedRevision {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: revisionConflictIssue()}
	}
	if recorder.ExecutionState != "stopped" {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "virtual-recorder-not-stopped", Message: "a virtual recorder must be stopped before artifact export"}}
	}
	session, err := service.repository.ReadLabSession(ctx, recorder.SessionReference.ResourceID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-source-session-missing", Message: "the stopped virtual recorder has no owning Lab session"}}
	}
	if err != nil {
		return guestruntimedomain.StoppedRecorderSource{}, fmt.Errorf("read Lab source session: %w", err)
	}
	return guestruntimedomain.StoppedRecorderSource{
		VirtualRecorderID:       recorder.ID,
		VirtualRecorderRevision: recorder.ResourceRevision,
		VirtualRecorderName:     recorder.Name,
		SessionID:               session.ID,
		SessionName:             session.Name,
		StoppedAt:               recorder.UpdatedAt,
	}, nil
}

func (service *GuestRuntimeLabApplicationService) readSession(ctx context.Context, id string) guestruntimedomain.ReadResult {
	if !guestruntimedomain.ValidIdentifier(id) {
		return invalidRead(guestruntimedomain.Timestamp(service.clock.Now()), "invalid-lab-session-id", "sessionId must be a v1 identifier")
	}
	now := guestruntimedomain.Timestamp(service.clock.Now())
	session, err := service.repository.ReadLabSession(ctx, id)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(now, "lab-session-missing", "the requested Lab session does not exist")
	}
	if err != nil {
		return failedRead(now, "lab-state-store-read-failed", err.Error(), "guest-state-store")
	}
	revision := session.ResourceRevision
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now, Value: session, SourceRevision: &revision}
}

func (service *GuestRuntimeLabApplicationService) idempotentOperation(ctx context.Context, requestID string, kind string, digest string) (*guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	existing, err := service.repository.ReadLabOperationByRequestID(ctx, requestID)
	if err == nil {
		if existing.Kind == kind && existing.CommandDigest == digest {
			return &existing, nil, nil
		}
		_, rejection, failure := service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		return nil, rejection, failure
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return nil, nil, nil
	}
	return nil, nil, service.newAdmissionFailure(requestID, "not-admitted", storeReadIssue("Lab request id ownership", err))
}

func (service *GuestRuntimeLabApplicationService) newSucceededOperation(id string, kind string, requestID string, resourceType string, resourceID string, revision int, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandAdmissionFailure) {
	operation := guestruntimedomain.NewOperation(id, kind, requestID, resourceType, resourceID, revision, at, digest)
	var err error
	operation, err = guestruntimedomain.TransitionOperation(operation, "accepted", at, nil)
	if err == nil {
		operation, err = guestruntimedomain.TransitionOperation(operation, "running", at, nil)
	}
	if err == nil {
		operation, err = guestruntimedomain.TransitionOperation(operation, "succeeded", at, nil)
	}
	if err != nil {
		return guestruntimedomain.Operation{}, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-operation-transition-failed", Message: "Lab could not construct an operation transition", Retryable: boolPointer(false), Dependency: "guest-runtime"})
	}
	return operation, nil
}

func (service *GuestRuntimeLabApplicationService) populateDeleteCommit(ctx context.Context, command guestruntimedomain.LabResourceCommand, session *guestruntimedomain.LabSession, bed *guestruntimedomain.LabBed, recorder *guestruntimedomain.VirtualRecorder, commit *LabStateTransitionCommit) ([]guestruntimedomain.ResourceReference, error) {
	switch command.ResourceType {
	case guestruntimedomain.LabSessionResourceType:
		recorders, err := service.repository.ListVirtualRecordersBySession(ctx, session.ID)
		if err != nil {
			return nil, err
		}
		beds, err := service.repository.ListLabBedsBySession(ctx, session.ID)
		if err != nil {
			return nil, err
		}
		deleted := make([]guestruntimedomain.ResourceReference, 0, len(recorders)+len(beds)+1)
		for _, owned := range recorders {
			if owned.ExecutionState == "running" {
				return nil, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-session-owned-recorder-running", Message: "a running owned recorder prevents session delete"}}
			}
			commit.DeleteRecorderIDs = append(commit.DeleteRecorderIDs, owned.ID)
			deleted = append(deleted, guestruntimedomain.ResourceReference{ResourceType: guestruntimedomain.VirtualRecorderResourceType, ResourceID: owned.ID})
		}
		for _, owned := range beds {
			commit.DeleteBedIDs = append(commit.DeleteBedIDs, owned.ID)
			deleted = append(deleted, guestruntimedomain.ResourceReference{ResourceType: guestruntimedomain.LabBedResourceType, ResourceID: owned.ID})
		}
		commit.DeleteSessionID = session.ID
		deleted = append(deleted, guestruntimedomain.ResourceReference{ResourceType: guestruntimedomain.LabSessionResourceType, ResourceID: session.ID})
		return deleted, nil
	case guestruntimedomain.LabBedResourceType:
		commit.DeleteBedIDs = []string{bed.ID}
		return []guestruntimedomain.ResourceReference{{ResourceType: guestruntimedomain.LabBedResourceType, ResourceID: bed.ID}}, nil
	case guestruntimedomain.VirtualRecorderResourceType:
		commit.DeleteRecorderIDs = []string{recorder.ID}
		return []guestruntimedomain.ResourceReference{{ResourceType: guestruntimedomain.VirtualRecorderResourceType, ResourceID: recorder.ID}}, nil
	default:
		return nil, fmt.Errorf("unsupported Lab delete target type %q", command.ResourceType)
	}
}

func (service *GuestRuntimeLabApplicationService) recorderSession(ctx context.Context, recorder guestruntimedomain.VirtualRecorder) (guestruntimedomain.LabSession, error) {
	if recorder.SessionReference.ResourceType != guestruntimedomain.LabSessionResourceType || !guestruntimedomain.ValidIdentifier(recorder.SessionReference.ResourceID) {
		return guestruntimedomain.LabSession{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-session-reference-invalid", Message: "virtual recorder has an invalid Lab session reference"}}
	}
	session, err := service.repository.ReadLabSession(ctx, recorder.SessionReference.ResourceID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.LabSession{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-session-missing", Message: "virtual recorder has no owning Lab session"}}
	}
	if err != nil {
		return guestruntimedomain.LabSession{}, err
	}
	return session, nil
}

type labReadOutcome struct {
	operation guestruntimedomain.Operation
	rejection *guestruntimedomain.CommandRejection
	failure   *guestruntimedomain.CommandAdmissionFailure
}

func (service *GuestRuntimeLabApplicationService) requiredLabRead(requestID string, missingCode string, missingMessage string, err error) *labReadOutcome {
	if err == nil {
		return nil
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		_, rejection, failure := service.commandRejection(requestID, guestruntimedomain.Issue{Code: missingCode, Message: missingMessage})
		return &labReadOutcome{rejection: rejection, failure: failure}
	}
	return &labReadOutcome{failure: service.newAdmissionFailure(requestID, "not-admitted", storeReadIssue("Lab resource", err))}
}

func (service *GuestRuntimeLabApplicationService) readFailureForResourceCommand(requestID string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	var eligibility SourceEligibilityError
	if errors.As(err, &eligibility) {
		return service.commandRejection(requestID, eligibility.Issue)
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "lab-resource-missing", Message: "a required Lab resource is missing"})
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", storeReadIssue("Lab resource", err))
}

func (service *GuestRuntimeLabApplicationService) handleCommitFailure(ctx context.Context, requestID string, kind string, digest string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if errors.Is(err, ErrGuestRuntimeOwnedResourceRevisionConflict) {
		return service.commandRejection(requestID, revisionConflictIssue())
	}
	if errors.Is(err, ErrGuestRuntimeOwnedResourceConflict) {
		existing, readErr := service.repository.ReadLabOperationByRequestID(ctx, requestID)
		if readErr == nil && existing.Kind == kind && existing.CommandDigest == digest {
			return existing, nil, nil
		}
		if readErr == nil {
			return service.commandRejection(requestID, guestruntimedomain.Issue{Code: "request-id-reused-with-different-command", Message: "requestId already belongs to a different Guest Runtime command"})
		}
	}
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "lab-state-store-write-outcome-unknown", Message: "Lab could not determine whether the operation was durably admitted", Retryable: boolPointer(true), Dependency: "guest-state-store"})
}

func (service *GuestRuntimeLabApplicationService) commandRejection(requestID string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	if !guestruntimedomain.ValidIdentifier(requestID) {
		generated, err := service.identifiers.NewRequestCorrelationIdentifier("rejection")
		if err != nil {
			return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-rejection-correlation-unavailable", Message: "Lab could not allocate a rejection correlation identifier", Retryable: boolPointer(true), Dependency: "guest-runtime"})
		}
		requestID = generated
	}
	return guestruntimedomain.Operation{}, &guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestID, RejectedAt: guestruntimedomain.Timestamp(service.clock.Now()), Issue: issue}, nil
}

func (service *GuestRuntimeLabApplicationService) admissionFailure(requestID string, state string, issue guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(requestID, state, issue)
}

func (service *GuestRuntimeLabApplicationService) newAdmissionFailure(requestID string, admissionState string, issue guestruntimedomain.Issue) *guestruntimedomain.CommandAdmissionFailure {
	return &guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(service.clock.Now()), AdmissionState: admissionState, Issue: issue}
}

func storeReadIssue(subject string, err error) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "lab-state-store-read-failed", Message: subject + " read failed: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"}
}

func identifierIssue(subject string) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "lab-identifier-unavailable", Message: subject + " identifier could not be allocated", Retryable: boolPointer(true), Dependency: "guest-runtime"}
}

func revisionConflictIssue() guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "resource-revision-conflict", Message: "expectedResourceRevision does not match the Lab-owned resource"}
}
