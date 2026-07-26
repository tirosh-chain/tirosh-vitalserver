package guestruntimeapplication

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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
	runner      GuestRuntimeLabRecorderRunner
	clock       GuestRuntimeClock
	identifiers GuestRuntimeRequestCorrelationIdentifierGenerator
	workflowMu  sync.Mutex
}

func NewGuestRuntimeLabApplicationService(repository GuestRuntimeLabStateRepository, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeLabApplicationService, error) {
	return newGuestRuntimeLabApplicationService(repository, nil, clock, identifiers)
}

// NewGuestRuntimeLabApplicationServiceWithRecorderRunner composes the real
// Guest-local runner port. Production composition must use this constructor;
// the no-runner constructor remains for Lab read/delete-only fixtures and
// reports an explicit unavailable command result for execution effects.
func NewGuestRuntimeLabApplicationServiceWithRecorderRunner(repository GuestRuntimeLabStateRepository, runner GuestRuntimeLabRecorderRunner, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeLabApplicationService, error) {
	if runner == nil {
		return nil, fmt.Errorf("Lab recorder Runner is required")
	}
	return newGuestRuntimeLabApplicationService(repository, runner, clock, identifiers)
}

func newGuestRuntimeLabApplicationService(repository GuestRuntimeLabStateRepository, runner GuestRuntimeLabRecorderRunner, clock GuestRuntimeClock, identifiers GuestRuntimeRequestCorrelationIdentifierGenerator) (*GuestRuntimeLabApplicationService, error) {
	if repository == nil || clock == nil || identifiers == nil {
		return nil, fmt.Errorf("Lab repository, clock, and identifier generator are required")
	}
	return &GuestRuntimeLabApplicationService{repository: repository, runner: runner, clock: clock, identifiers: identifiers}, nil
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
			if service.runner != nil {
				return service.executeLabSessionRunnerStart(ctx, command, *session, recorders, operationID, at, digest)
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
			if service.runner == nil {
				return service.admissionFailure(command.RequestID, "not-admitted", runnerUnavailableIssue())
			}
			return service.executeVirtualRecorderRunnerStart(ctx, command, owner, *recorder, operationID, at, digest)
		}
	case "stop":
		if session != nil {
			recorders, readErr := service.repository.ListVirtualRecordersBySession(ctx, session.ID)
			if readErr != nil {
				return service.admissionFailure(command.RequestID, "not-admitted", storeReadIssue("Lab session stop", readErr))
			}
			if service.runner != nil {
				return service.executeLabSessionRunnerStop(ctx, command, *session, recorders, operationID, at, digest)
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
			if service.runner == nil {
				return service.admissionFailure(command.RequestID, "not-admitted", runnerUnavailableIssue())
			}
			return service.executeVirtualRecorderRunnerStop(ctx, command, owner, *recorder, operationID, at, digest)
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
		// A terminal archive intent is an explicit immutable source snapshot.
		// Later visibility/detach/dispatch revisions must not make its named C45
		// receipt unreadable, but no arbitrary older recorder revision is valid.
		if recorder.TerminalArchiveIntent == nil || recorder.TerminalArchiveIntent.SourceResourceRevision != expectedRevision || recorder.TerminalArchiveIntent.ColdPathFinalizationReceiptID != recorder.RecorderGatewayFinalizationReceiptID {
			return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: revisionConflictIssue()}
		}
	}
	if recorder.ExecutionState != "stopped" {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "virtual-recorder-not-stopped", Message: "a virtual recorder must be stopped before artifact export"}}
	}
	if !guestruntimedomain.ValidIdentifier(recorder.RecorderGatewayRecorderID) || !guestruntimedomain.ValidIdentifier(recorder.RecorderGatewayColdPathCaptureID) || !guestruntimedomain.ValidIdentifier(recorder.RecorderGatewayFinalizationReceiptID) {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "virtual-recorder-recorder-gateway-finalization-missing", Message: "the stopped virtual recorder has no explicit Recorder Gateway recorder, capture, and finalization receipt identities"}}
	}
	session, err := service.repository.ReadLabSession(ctx, recorder.SessionReference.ResourceID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return guestruntimedomain.StoppedRecorderSource{}, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-source-session-missing", Message: "the stopped virtual recorder has no owning Lab session"}}
	}
	if err != nil {
		return guestruntimedomain.StoppedRecorderSource{}, fmt.Errorf("read Lab source session: %w", err)
	}
	return guestruntimedomain.StoppedRecorderSource{
		VirtualRecorderID:                    recorder.ID,
		VirtualRecorderRevision:              expectedRevision,
		VirtualRecorderName:                  recorder.Name,
		RecorderGatewayRecorderID:            recorder.RecorderGatewayRecorderID,
		RecorderGatewayColdPathCaptureID:     recorder.RecorderGatewayColdPathCaptureID,
		RecorderGatewayFinalizationReceiptID: recorder.RecorderGatewayFinalizationReceiptID,
		SessionID:                            session.ID,
		SessionName:                          session.Name,
		StoppedAt:                            recorder.UpdatedAt,
	}, nil
}

// ListPendingTerminalArchiveExportCandidates reads only Lab-owned durable
// terminal intents. It is the explicit Lab-to-coordinator boundary: the
// coordinator never scans Lab SQLite documents or derives an archive request
// from a name, timestamp, or absent artifact.
func (service *GuestRuntimeLabApplicationService) ListPendingTerminalArchiveExportCandidates(ctx context.Context, target guestruntimedomain.ResourceReference) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	if !guestruntimedomain.ValidIdentifier(target.ResourceID) {
		return nil, fmt.Errorf("terminal archive target has an invalid resource ID")
	}
	var recorders []guestruntimedomain.VirtualRecorder
	switch target.ResourceType {
	case guestruntimedomain.LabSessionResourceType:
		session, err := service.repository.ReadLabSession(ctx, target.ResourceID)
		if err != nil {
			return nil, fmt.Errorf("read terminal archive Lab session: %w", err)
		}
		if session.State != "stopped" {
			return nil, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "lab-session-not-stopped", Message: "terminal archive dispatch requires a stopped Lab session"}}
		}
		recorders, err = service.repository.ListVirtualRecordersBySession(ctx, session.ID)
		if err != nil {
			return nil, fmt.Errorf("list terminal archive session recorders: %w", err)
		}
	case guestruntimedomain.VirtualRecorderResourceType:
		recorder, err := service.repository.ReadLabVirtualRecorder(ctx, target.ResourceID)
		if err != nil {
			return nil, fmt.Errorf("read terminal archive virtual recorder: %w", err)
		}
		recorders = []guestruntimedomain.VirtualRecorder{recorder}
	default:
		return nil, fmt.Errorf("terminal archive dispatch does not support resource type %q", target.ResourceType)
	}
	return terminalArchiveExportCandidates(recorders)
}

// ListAllPendingTerminalArchiveExportCandidates is the explicit restart
// recovery read. It receives the complete Lab-owned recorder collection from
// the repository and returns only persisted terminal intents; it never builds
// a new archive request from a stopped recorder or a file-system scan.
func (service *GuestRuntimeLabApplicationService) ListAllPendingTerminalArchiveExportCandidates(ctx context.Context) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	recorders, err := service.repository.ListVirtualRecorders(ctx)
	if err != nil {
		return nil, fmt.Errorf("list terminal archive virtual recorders: %w", err)
	}
	return terminalArchiveExportCandidates(recorders)
}

func terminalArchiveExportCandidates(recorders []guestruntimedomain.VirtualRecorder) ([]guestruntimedomain.TerminalArchiveExportCandidate, error) {
	candidates := make([]guestruntimedomain.TerminalArchiveExportCandidate, 0, len(recorders))
	for _, recorder := range recorders {
		if recorder.ExecutionState != "stopped" || recorder.TerminalArchivePolicy == "no-export" {
			continue
		}
		if recorder.TerminalArchivePolicy != "export-on-stop" {
			return nil, SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "terminal-archive-policy-not-selected", Message: "a stopped Lab recorder has no explicit terminal archive policy"}}
		}
		if recorder.TerminalArchiveIntent != nil && recorder.TerminalArchiveIntent.State == "submitted" {
			continue
		}
		candidate, issue := guestruntimedomain.TerminalArchiveExportCandidateForRecorder(recorder)
		if issue != nil {
			return nil, SourceEligibilityError{Issue: *issue}
		}
		candidates = append(candidates, candidate)
	}
	return candidates, nil
}

// RecordTerminalArchiveDispatch commits the Lab-owned observation that one
// terminal intent was submitted to Archive, rejected before admission, or
// unavailable. Archive operation state remains owned and read by Archive.
func (service *GuestRuntimeLabApplicationService) RecordTerminalArchiveDispatch(ctx context.Context, candidate guestruntimedomain.TerminalArchiveExportCandidate, outcome string, archiveOperation *guestruntimedomain.ResourceReference, dispatchIssue *guestruntimedomain.Issue) error {
	service.workflowMu.Lock()
	defer service.workflowMu.Unlock()
	if candidate.LabOperationReference.ResourceType != "operation" || !guestruntimedomain.ValidIdentifier(candidate.LabOperationReference.ResourceID) {
		return fmt.Errorf("terminal archive dispatch requires the terminal intent's explicit Lab operation reference")
	}
	labOperation, err := service.repository.ReadLabOperation(ctx, candidate.LabOperationReference.ResourceID)
	if err != nil {
		return fmt.Errorf("read terminal archive owning Lab operation: %w", err)
	}
	if labOperation.ID != candidate.LabOperationReference.ResourceID || labOperation.Kind != guestruntimedomain.LabResourceOperationKind("stop") || labOperation.State != "succeeded" {
		return SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "terminal-archive-lab-operation-invalid", Message: "terminal archive dispatch requires the completed stop operation recorded by the finalization intent"}}
	}
	recorder, err := service.repository.ReadLabVirtualRecorder(ctx, candidate.VirtualRecorderID)
	if err != nil {
		return fmt.Errorf("read terminal archive recorder: %w", err)
	}
	next, issue := guestruntimedomain.RecordTerminalArchiveDispatch(recorder, candidate.RequestID, outcome, archiveOperation, dispatchIssue, guestruntimedomain.Timestamp(service.clock.Now()))
	if issue != nil {
		return SourceEligibilityError{Issue: *issue}
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: labOperation, OperationContinuation: true, UpsertRecorders: []guestruntimedomain.VirtualRecorder{next}}); err != nil {
		return fmt.Errorf("commit terminal archive dispatch: %w", err)
	}
	return nil
}

// executeLabSessionRunnerStart owns the durable Lab-side saga around multiple
// Runner effects. Every external effect is preceded by an explicit persisted
// `starting` fact and followed by a receipt-bearing transition. A process
// crash therefore leaves `starting`/a running operation rather than inventing
// either a stopped recorder or a complete session.
func (service *GuestRuntimeLabApplicationService) executeLabSessionRunnerStart(ctx context.Context, command guestruntimedomain.LabResourceCommand, session guestruntimedomain.LabSession, recorders []guestruntimedomain.VirtualRecorder, operationID string, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	nextSession, issue := guestruntimedomain.BeginLabSessionStart(session, recorders, at)
	if issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	operation, failure := service.newRunningOperation(operationID, guestruntimedomain.LabResourceOperationKind(command.Action), command.RequestID, command.ResourceType, command.ResourceID, command.ExpectedResourceRevision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, UpsertSession: &nextSession}); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, operation.Kind, digest, err)
	}
	session = nextSession

	for index, recorder := range recorders {
		startingRecorder, transitionIssue := guestruntimedomain.BeginVirtualRecorderStart(session, recorder, at)
		if transitionIssue != nil {
			return service.failLabSessionRunnerOperation(ctx, command, operation, session, recorder, *transitionIssue, at)
		}
		if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, &session, []guestruntimedomain.VirtualRecorder{startingRecorder}); failure != nil {
			return guestruntimedomain.Operation{}, nil, failure
		}
		recorders[index] = startingRecorder

		receipt, runnerErr := service.runner.StartLabVirtualRecorderRun(ctx, labRunnerRequestID(command.RequestID, "session-start", recorder.ID), recorder.ID, recorder.RecorderGatewayRecorderCode, session.Scenario)
		if runnerErr != nil {
			if runnerIssue, known := knownRunnerIssue(runnerErr); known {
				return service.failLabSessionRunnerOperation(ctx, command, operation, session, startingRecorder, runnerIssue, at)
			}
			// The durable `starting` record and running operation are the only
			// truthful result while the Runner effect outcome is unknown.
			return operation, nil, nil
		}
		runningRecorder, transitionIssue := guestruntimedomain.CompleteVirtualRecorderStart(startingRecorder, receipt, at)
		if transitionIssue != nil {
			return service.failLabSessionRunnerOperation(ctx, command, operation, session, startingRecorder, guestruntimedomain.Issue{Code: "lab-recorder-runner-start-receipt-transition-failed", Message: "Lab could not record the explicit Runner start receipt after its external effect completed", Retryable: boolPointer(true), Dependency: "lab-recorder-runner"}, at)
		}
		if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, nil, []guestruntimedomain.VirtualRecorder{runningRecorder}); failure != nil {
			return guestruntimedomain.Operation{}, nil, failure
		}
		recorders[index] = runningRecorder
	}

	completedSession, issue := guestruntimedomain.CompleteLabSessionStart(session, recorders, at)
	if issue != nil {
		return service.failLabSessionRunnerOperation(ctx, command, operation, session, guestruntimedomain.VirtualRecorder{}, *issue, at)
	}
	operation, failure = service.completeLabOperation(operation, "succeeded", at, nil)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, &completedSession, nil); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return operation, nil, nil
}

// executeVirtualRecorderRunnerStart is the single-recorder counterpart to the
// session workflow.  It writes `starting` before the Runner call so a network
// timeout remains an explicit in-progress effect instead of a guessed failed
// start or a false running recorder.
func (service *GuestRuntimeLabApplicationService) executeVirtualRecorderRunnerStart(ctx context.Context, command guestruntimedomain.LabResourceCommand, session guestruntimedomain.LabSession, recorder guestruntimedomain.VirtualRecorder, operationID string, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	startingRecorder, issue := guestruntimedomain.BeginVirtualRecorderStart(session, recorder, at)
	if issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	operation, failure := service.newRunningOperation(operationID, guestruntimedomain.LabResourceOperationKind(command.Action), command.RequestID, command.ResourceType, command.ResourceID, command.ExpectedResourceRevision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, UpsertRecorders: []guestruntimedomain.VirtualRecorder{startingRecorder}}); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, operation.Kind, digest, err)
	}

	receipt, runnerErr := service.runner.StartLabVirtualRecorderRun(ctx, labRunnerRequestID(command.RequestID, "start", recorder.ID), recorder.ID, recorder.RecorderGatewayRecorderCode, session.Scenario)
	if runnerErr != nil {
		if runnerIssue, known := knownRunnerIssue(runnerErr); known {
			return service.failVirtualRecorderRunnerOperation(ctx, command, operation, startingRecorder, runnerIssue, at)
		}
		return operation, nil, nil
	}
	runningRecorder, issue := guestruntimedomain.CompleteVirtualRecorderStart(startingRecorder, receipt, at)
	if issue != nil {
		return service.failVirtualRecorderRunnerOperation(ctx, command, operation, startingRecorder, guestruntimedomain.Issue{Code: "lab-recorder-runner-start-receipt-transition-failed", Message: "Lab could not record the explicit Runner start receipt after its external effect completed", Retryable: boolPointer(true), Dependency: "lab-recorder-runner"}, at)
	}
	terminal, failure := service.completeLabOperation(operation, "succeeded", at, nil)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, terminal, nil, []guestruntimedomain.VirtualRecorder{runningRecorder}); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return terminal, nil, nil
}

// executeVirtualRecorderRunnerStop retains a durable `stopping` intent until
// the Runner returns the exact cold-path finalization receipt.  The Lab
// session itself stays running: an individual recorder stop is not a claim
// that the other recorders or the session have finished.
func (service *GuestRuntimeLabApplicationService) executeVirtualRecorderRunnerStop(ctx context.Context, command guestruntimedomain.LabResourceCommand, session guestruntimedomain.LabSession, recorder guestruntimedomain.VirtualRecorder, operationID string, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	stoppingRecorder, issue := guestruntimedomain.BeginVirtualRecorderStop(session, recorder, at)
	if issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	operation, failure := service.newRunningOperation(operationID, guestruntimedomain.LabResourceOperationKind(command.Action), command.RequestID, command.ResourceType, command.ResourceID, command.ExpectedResourceRevision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, UpsertRecorders: []guestruntimedomain.VirtualRecorder{stoppingRecorder}}); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, operation.Kind, digest, err)
	}

	receipt, runnerErr := service.runner.StopLabVirtualRecorderRun(ctx, labRunnerRequestID(command.RequestID, "stop", recorder.ID), recorder.LabRecorderRunnerRunID, recorder.LabRecorderRunnerRunRevision)
	if runnerErr != nil {
		if runnerIssue, known := knownRunnerIssue(runnerErr); known {
			return service.failVirtualRecorderRunnerOperation(ctx, command, operation, stoppingRecorder, runnerIssue, at)
		}
		return operation, nil, nil
	}
	stoppedRecorder, issue := guestruntimedomain.CompleteVirtualRecorderStop(stoppingRecorder, receipt, labOperationReference(operation), at)
	if issue != nil {
		return service.failVirtualRecorderRunnerOperation(ctx, command, operation, stoppingRecorder, guestruntimedomain.Issue{Code: "lab-recorder-runner-finalization-receipt-transition-failed", Message: "Lab could not record the explicit Runner finalization receipt after its external effect completed", Retryable: boolPointer(true), Dependency: "lab-recorder-runner"}, at)
	}
	terminal, failure := service.completeLabOperation(operation, "succeeded", at, nil)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, terminal, nil, []guestruntimedomain.VirtualRecorder{stoppedRecorder}); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return terminal, nil, nil
}

func (service *GuestRuntimeLabApplicationService) failVirtualRecorderRunnerOperation(ctx context.Context, command guestruntimedomain.LabResourceCommand, operation guestruntimedomain.Operation, recorder guestruntimedomain.VirtualRecorder, issue guestruntimedomain.Issue, at string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	failedRecorder, transitionIssue := guestruntimedomain.FailVirtualRecorderExecution(recorder, at)
	if transitionIssue != nil {
		return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(command.RequestID, "unknown", guestruntimedomain.Issue{Code: "virtual-recorder-failure-transition-failed", Message: "Lab could not persist the explicit virtual recorder failure after a Runner result", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	failedOperation, failure := service.completeLabOperation(operation, "failed", at, &issue)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, failedOperation, nil, []guestruntimedomain.VirtualRecorder{failedRecorder}); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return failedOperation, nil, nil
}

// executeLabSessionRunnerStop mirrors start: it first persists `stopping`,
// then accepts only the Runner's explicit finalization receipt as evidence
// that a virtual recorder can become stopped.
func (service *GuestRuntimeLabApplicationService) executeLabSessionRunnerStop(ctx context.Context, command guestruntimedomain.LabResourceCommand, session guestruntimedomain.LabSession, recorders []guestruntimedomain.VirtualRecorder, operationID string, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	nextSession, issue := guestruntimedomain.BeginLabSessionStop(session, recorders, at)
	if issue != nil {
		return service.commandRejection(command.RequestID, *issue)
	}
	operation, failure := service.newRunningOperation(operationID, guestruntimedomain.LabResourceOperationKind(command.Action), command.RequestID, command.ResourceType, command.ResourceID, command.ExpectedResourceRevision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, UpsertSession: &nextSession}); err != nil {
		return service.handleCommitFailure(ctx, command.RequestID, operation.Kind, digest, err)
	}
	session = nextSession

	for index, recorder := range recorders {
		if recorder.ExecutionState != "running" {
			continue
		}
		stoppingRecorder, transitionIssue := guestruntimedomain.BeginVirtualRecorderStop(session, recorder, at)
		if transitionIssue != nil {
			return service.failLabSessionRunnerOperation(ctx, command, operation, session, recorder, *transitionIssue, at)
		}
		if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, nil, []guestruntimedomain.VirtualRecorder{stoppingRecorder}); failure != nil {
			return guestruntimedomain.Operation{}, nil, failure
		}
		recorders[index] = stoppingRecorder

		receipt, runnerErr := service.runner.StopLabVirtualRecorderRun(ctx, labRunnerRequestID(command.RequestID, "session-stop", recorder.ID), recorder.LabRecorderRunnerRunID, recorder.LabRecorderRunnerRunRevision)
		if runnerErr != nil {
			if runnerIssue, known := knownRunnerIssue(runnerErr); known {
				return service.failLabSessionRunnerOperation(ctx, command, operation, session, stoppingRecorder, runnerIssue, at)
			}
			return operation, nil, nil
		}
		stoppedRecorder, transitionIssue := guestruntimedomain.CompleteVirtualRecorderStop(stoppingRecorder, receipt, labOperationReference(operation), at)
		if transitionIssue != nil {
			return service.failLabSessionRunnerOperation(ctx, command, operation, session, stoppingRecorder, guestruntimedomain.Issue{Code: "lab-recorder-runner-finalization-receipt-transition-failed", Message: "Lab could not record the explicit Runner finalization receipt after its external effect completed", Retryable: boolPointer(true), Dependency: "lab-recorder-runner"}, at)
		}
		if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, nil, []guestruntimedomain.VirtualRecorder{stoppedRecorder}); failure != nil {
			return guestruntimedomain.Operation{}, nil, failure
		}
		recorders[index] = stoppedRecorder
	}

	completedSession, issue := guestruntimedomain.CompleteLabSessionStop(session, recorders, at)
	if issue != nil {
		return service.failLabSessionRunnerOperation(ctx, command, operation, session, guestruntimedomain.VirtualRecorder{}, *issue, at)
	}
	operation, failure = service.completeLabOperation(operation, "succeeded", at, nil)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, operation, &completedSession, nil); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return operation, nil, nil
}

func (service *GuestRuntimeLabApplicationService) failLabSessionRunnerOperation(ctx context.Context, command guestruntimedomain.LabResourceCommand, operation guestruntimedomain.Operation, session guestruntimedomain.LabSession, recorder guestruntimedomain.VirtualRecorder, issue guestruntimedomain.Issue, at string) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	failedSession, transitionIssue := guestruntimedomain.FailLabSessionExecution(session, at)
	if transitionIssue != nil {
		return guestruntimedomain.Operation{}, nil, service.newAdmissionFailure(command.RequestID, "unknown", guestruntimedomain.Issue{Code: "lab-session-failure-transition-failed", Message: "Lab could not persist the explicit session failure after a Runner result", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	var recorders []guestruntimedomain.VirtualRecorder
	if recorder.ID != "" {
		failedRecorder, recorderIssue := guestruntimedomain.FailVirtualRecorderExecution(recorder, at)
		if recorderIssue == nil {
			recorders = []guestruntimedomain.VirtualRecorder{failedRecorder}
		}
	}
	failedOperation, failure := service.completeLabOperation(operation, "failed", at, &issue)
	if failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	if failure := service.commitLabSessionRunnerContinuation(ctx, command.RequestID, failedOperation, &failedSession, recorders); failure != nil {
		return guestruntimedomain.Operation{}, nil, failure
	}
	return failedOperation, nil, nil
}

func (service *GuestRuntimeLabApplicationService) commitLabSessionRunnerContinuation(ctx context.Context, requestID string, operation guestruntimedomain.Operation, session *guestruntimedomain.LabSession, recorders []guestruntimedomain.VirtualRecorder) *guestruntimedomain.CommandAdmissionFailure {
	if err := service.repository.CommitLabStateTransition(ctx, LabStateTransitionCommit{Operation: operation, OperationContinuation: true, UpsertSession: session, UpsertRecorders: recorders}); err != nil {
		return service.newAdmissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "lab-session-runner-state-write-outcome-unknown", Message: "Lab could not determine whether its Runner lifecycle evidence was durably recorded: " + err.Error(), Retryable: boolPointer(true), Dependency: "guest-state-store"})
	}
	return nil
}

// labOperationReference carries the existing durable Lab operation identity
// into a terminal archive intent. The intent may later be reconciled after a
// process restart, so it must not rely on the in-memory stop command that
// originally produced the finalization receipt.
func labOperationReference(operation guestruntimedomain.Operation) guestruntimedomain.ResourceReference {
	return guestruntimedomain.ResourceReference{ResourceType: "operation", ResourceID: operation.ID}
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
	operation, failure := service.newRunningOperation(id, kind, requestID, resourceType, resourceID, revision, at, digest)
	if failure != nil {
		return guestruntimedomain.Operation{}, failure
	}
	var err error
	operation, err = guestruntimedomain.TransitionOperation(operation, "succeeded", at, nil)
	if err != nil {
		return guestruntimedomain.Operation{}, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-operation-transition-failed", Message: "Lab could not construct an operation transition", Retryable: boolPointer(false), Dependency: "guest-runtime"})
	}
	return operation, nil
}

func (service *GuestRuntimeLabApplicationService) newRunningOperation(id string, kind string, requestID string, resourceType string, resourceID string, revision int, at string, digest string) (guestruntimedomain.Operation, *guestruntimedomain.CommandAdmissionFailure) {
	operation := guestruntimedomain.NewOperation(id, kind, requestID, resourceType, resourceID, revision, at, digest)
	var err error
	operation, err = guestruntimedomain.TransitionOperation(operation, "accepted", at, nil)
	if err == nil {
		operation, err = guestruntimedomain.TransitionOperation(operation, "running", at, nil)
	}
	if err != nil {
		return guestruntimedomain.Operation{}, service.newAdmissionFailure(requestID, "not-admitted", guestruntimedomain.Issue{Code: "lab-operation-transition-failed", Message: "Lab could not construct an operation transition", Retryable: boolPointer(false), Dependency: "guest-runtime"})
	}
	return operation, nil
}

func (service *GuestRuntimeLabApplicationService) completeLabOperation(operation guestruntimedomain.Operation, state string, at string, issue *guestruntimedomain.Issue) (guestruntimedomain.Operation, *guestruntimedomain.CommandAdmissionFailure) {
	next, err := guestruntimedomain.TransitionOperation(operation, state, at, issue)
	if err != nil {
		return guestruntimedomain.Operation{}, service.newAdmissionFailure(operation.RequestID, "unknown", guestruntimedomain.Issue{Code: "lab-operation-completion-transition-failed", Message: "Lab could not complete its durable operation transition", Retryable: boolPointer(true), Dependency: "guest-runtime"})
	}
	return next, nil
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

func runnerUnavailableIssue() guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: "lab-recorder-runner-unavailable", Message: "Lab execution cannot start or stop because the Guest-local Lab recorder Runner was not composed", Retryable: boolPointer(true), Dependency: "lab-recorder-runner"}
}

func (service *GuestRuntimeLabApplicationService) runnerFailureForResourceCommand(requestID string, action string, err error) (guestruntimedomain.Operation, *guestruntimedomain.CommandRejection, *guestruntimedomain.CommandAdmissionFailure) {
	var eligibility SourceEligibilityError
	if errors.As(err, &eligibility) {
		return service.commandRejection(requestID, eligibility.Issue)
	}
	return service.admissionFailure(requestID, "unknown", guestruntimedomain.Issue{Code: "lab-recorder-runner-" + action + "-outcome-unknown", Message: "Lab could not determine the Lab recorder Runner " + action + " effect outcome: " + err.Error(), Retryable: boolPointer(true), Dependency: "lab-recorder-runner"})
}

func knownRunnerIssue(err error) (guestruntimedomain.Issue, bool) {
	var eligibility SourceEligibilityError
	if errors.As(err, &eligibility) {
		return eligibility.Issue, true
	}
	return guestruntimedomain.Issue{}, false
}

func labRunnerRequestID(commandRequestID string, action string, virtualRecorderID string) string {
	digest := sha256.Sum256([]byte(commandRequestID + "\x00" + action + "\x00" + virtualRecorderID))
	return "lab-runner-" + action + "-" + hex.EncodeToString(digest[:12])
}
