package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
)

const (
	LabSessionResourceType      = "lab-session"
	LabBedResourceType          = "lab-bed"
	VirtualRecorderResourceType = "virtual-recorder"

	LabCreateSessionOperationKind = "lab.session.create"
	LabResourceOperationPrefix    = "lab.resource."
)

// LabSession is the aggregate root for a controlled virtual-recorder scenario.
// Its state says only whether the Lab execution is active; it does not attest
// to artifact finalization, upload, or indexing.
type LabSession struct {
	SchemaVersion    string `json:"schemaVersion"`
	ID               string `json:"id"`
	Name             string `json:"name"`
	Origin           string `json:"origin"`
	ResourceRevision int    `json:"resourceRevision"`
	Scenario         string `json:"scenario"`
	State            string `json:"state"`
	CreatedAt        string `json:"createdAt"`
	UpdatedAt        string `json:"updatedAt"`
}

// LabBed is owned by one LabSession. Visibility is presentation state and is
// intentionally distinct from assignment and deletion.
type LabBed struct {
	SchemaVersion     string             `json:"schemaVersion"`
	ID                string             `json:"id"`
	Name              string             `json:"name"`
	Origin            string             `json:"origin"`
	ResourceRevision  int                `json:"resourceRevision"`
	SessionReference  ResourceReference  `json:"sessionReference"`
	AssignmentState   string             `json:"assignmentState"`
	RecorderReference *ResourceReference `json:"recorderReference,omitempty"`
	Visibility        string             `json:"visibility"`
	CreatedAt         string             `json:"createdAt"`
	UpdatedAt         string             `json:"updatedAt"`
}

// VirtualRecorder owns only simulated Lab execution. It is explicitly marked
// origin=lab so callers do not infer ownership from the display name.
type VirtualRecorder struct {
	SchemaVersion                        string `json:"schemaVersion"`
	ID                                   string `json:"id"`
	Name                                 string `json:"name"`
	Origin                               string `json:"origin"`
	RecorderGatewayRecorderCode          string `json:"recorderGatewayRecorderCode"`
	RecorderGatewayRecorderID            string `json:"recorderGatewayRecorderId,omitempty"`
	LabRecorderRunnerRunID               string `json:"labRecorderRunnerRunId,omitempty"`
	LabRecorderRunnerRunRevision         int    `json:"labRecorderRunnerRunRevision,omitempty"`
	RecorderGatewayColdPathCaptureID     string `json:"recorderGatewayColdPathCaptureId,omitempty"`
	RecorderGatewayFinalizationReceiptID string `json:"recorderGatewayFinalizationReceiptId,omitempty"`
	// TerminalArchivePolicy is the Runner-selected terminal artifact policy.
	// `not-selected` means no Runner start receipt has been persisted yet;
	// it is deliberately different from `no-export`.
	TerminalArchivePolicy string                 `json:"terminalArchivePolicy"`
	TerminalArchiveIntent *TerminalArchiveIntent `json:"terminalArchiveIntent,omitempty"`
	ResourceRevision      int                    `json:"resourceRevision"`
	SessionReference      ResourceReference      `json:"sessionReference"`
	BedReference          *ResourceReference     `json:"bedReference,omitempty"`
	ExecutionState        string                 `json:"executionState"`
	Visibility            string                 `json:"visibility"`
	CreatedAt             string                 `json:"createdAt"`
	UpdatedAt             string                 `json:"updatedAt"`
}

// TerminalArchiveIntent is Lab-owned durable intent to ask Archive Export to
// process one immutable terminal cold-path source. Archive owns the export
// operation and receipt; this document never claims an upload outcome.
type TerminalArchiveIntent struct {
	State                         string             `json:"state"`
	RequestID                     string             `json:"requestId"`
	SourceResourceRevision        int                `json:"sourceResourceRevision"`
	ColdPathFinalizationReceiptID string             `json:"coldPathFinalizationReceiptId"`
	LabOperationReference         ResourceReference  `json:"labOperationReference"`
	ArchiveOperationReference     *ResourceReference `json:"archiveOperationReference,omitempty"`
	LastAttemptAt                 string             `json:"lastAttemptAt,omitempty"`
	LastDispatchIssue             *Issue             `json:"lastDispatchIssue,omitempty"`
}

// TerminalArchiveExportCandidate is the explicit cross-aggregate command
// input. It contains a stopped Lab recorder's immutable source selection but
// no Archive provider or artifact outcome.
type TerminalArchiveExportCandidate struct {
	RequestID                     string
	VirtualRecorderID             string
	ExpectedResourceRevision      int
	ColdPathFinalizationReceiptID string
	LabOperationReference         ResourceReference
}

// LabRecorderRunnerStartReceipt is the explicit external-effect fact supplied
// by the Guest-local runner after a Gateway join and first accepted packet.
// It is not a Lab state transition or an Archive artifact receipt.
type LabRecorderRunnerStartReceipt struct {
	RunID                     string
	RunRevision               int
	RecorderGatewayRecorderID string
	ColdPathCaptureID         string
	ArchiveOnTerminalStop     bool
}

// LabRecorderRunnerFinalizationReceipt is the explicit finalization effect
// fact that later permits Archive Export to read the Gateway C45 source.
type LabRecorderRunnerFinalizationReceipt struct {
	RunID                     string
	RunRevision               int
	RecorderGatewayRecorderID string
	ColdPathCaptureID         string
	FinalizationReceiptID     string
}

type CreateLabSessionCommand struct {
	SchemaVersion           string `json:"schemaVersion"`
	RequestID               string `json:"requestId"`
	SessionID               string `json:"sessionId"`
	ExpectedSessionRevision int    `json:"expectedSessionRevision"`
	Name                    string `json:"name"`
	Scenario                string `json:"scenario"`
	RecorderCount           int    `json:"recorderCount"`
}

type LabResourceCommand struct {
	SchemaVersion            string `json:"schemaVersion"`
	RequestID                string `json:"requestId"`
	ResourceType             string `json:"resourceType"`
	ResourceID               string `json:"resourceId"`
	ExpectedResourceRevision int    `json:"expectedResourceRevision"`
	Action                   string `json:"action"`
	Cascade                  string `json:"cascade,omitempty"`
}

// DeletionReceipt is Lab-owned evidence of what was deleted and what remains
// under Archive retention. An empty retainedResources array means the Archive
// owner explicitly reported none; it never means Archive was not consulted.
type DeletionReceipt struct {
	SchemaVersion     string              `json:"schemaVersion"`
	ID                string              `json:"id"`
	OperationID       string              `json:"operationId"`
	RequestID         string              `json:"requestId"`
	Target            ResourceReference   `json:"target"`
	Cascade           string              `json:"cascade"`
	DeletedResources  []ResourceReference `json:"deletedResources"`
	RetainedResources []ResourceReference `json:"retainedResources"`
	CompletedAt       string              `json:"completedAt"`
}

// StoppedRecorderSource is the explicit Lab-to-Archive port document. It is
// not an Archive artifact and contains no claim that an artifact exists.
type StoppedRecorderSource struct {
	VirtualRecorderID                    string
	VirtualRecorderRevision              int
	VirtualRecorderName                  string
	RecorderGatewayRecorderID            string
	RecorderGatewayColdPathCaptureID     string
	RecorderGatewayFinalizationReceiptID string
	SessionID                            string
	SessionName                          string
	StoppedAt                            string
}

func ValidateCreateLabSessionCommand(command CreateLabSessionCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) {
		return &Issue{Code: "invalid-request-id", Message: "requestId must be a non-empty v1 identifier"}
	}
	if !ValidIdentifier(command.SessionID) {
		return &Issue{Code: "invalid-session-id", Message: "sessionId must be a non-empty v1 identifier"}
	}
	if command.ExpectedSessionRevision != 0 {
		return &Issue{Code: "invalid-expected-session-revision", Message: "a new Lab session must use expectedSessionRevision zero"}
	}
	if !validLabText(command.Name) || !validLabText(command.Scenario) {
		return &Issue{Code: "invalid-lab-name-or-scenario", Message: "name and scenario must be non-empty Lab text within the supported length"}
	}
	if command.RecorderCount < 1 || command.RecorderCount > 64 {
		return &Issue{Code: "invalid-recorder-count", Message: "recorderCount must be between 1 and 64"}
	}
	return nil
}

func ValidateLabResourceCommand(command LabResourceCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) {
		return &Issue{Code: "invalid-request-id", Message: "requestId must be a non-empty v1 identifier"}
	}
	if !validLabResourceType(command.ResourceType) || !ValidIdentifier(command.ResourceID) {
		return &Issue{Code: "invalid-lab-resource-reference", Message: "resourceType and resourceId must identify a Lab-owned resource"}
	}
	if command.ExpectedResourceRevision < 1 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be one or greater"}
	}
	switch command.Action {
	case "start", "stop":
		if command.ResourceType != LabSessionResourceType && command.ResourceType != VirtualRecorderResourceType {
			return &Issue{Code: "unsupported-action-for-resource", Message: "start and stop apply only to Lab sessions and virtual recorders"}
		}
	case "hide", "unhide":
		if command.ResourceType == LabSessionResourceType {
			return &Issue{Code: "unsupported-action-for-resource", Message: "session visibility is not a Lab resource action"}
		}
	case "detach":
		if command.ResourceType != VirtualRecorderResourceType {
			return &Issue{Code: "unsupported-action-for-resource", Message: "detach applies only to a virtual recorder"}
		}
	case "delete":
		if command.ResourceType == LabSessionResourceType && command.Cascade != "owned-resources" {
			return &Issue{Code: "session-delete-requires-owned-resource-cascade", Message: "deleting a Lab session requires cascade=owned-resources"}
		}
		if command.ResourceType != LabSessionResourceType && command.Cascade != "none" {
			return &Issue{Code: "resource-delete-requires-none-cascade", Message: "deleting one Lab bed or virtual recorder requires cascade=none"}
		}
	default:
		return &Issue{Code: "unsupported-lab-action", Message: "action must be start, stop, hide, unhide, detach, or delete"}
	}
	if command.Action != "delete" && command.Cascade != "" {
		return &Issue{Code: "cascade-not-applicable", Message: "cascade is allowed only for delete"}
	}
	return nil
}

func NewLabSession(command CreateLabSessionCommand, at string) LabSession {
	return LabSession{
		SchemaVersion:    SchemaVersion,
		ID:               command.SessionID,
		Name:             "LAB-" + command.Name,
		Origin:           "lab",
		ResourceRevision: 1,
		Scenario:         command.Scenario,
		State:            "prepared",
		CreatedAt:        at,
		UpdatedAt:        at,
	}
}

func NewLabBed(id string, session LabSession, recorderID string, ordinal int, at string) LabBed {
	return LabBed{
		SchemaVersion:     SchemaVersion,
		ID:                id,
		Name:              labChildName(session.Name, "bed", ordinal),
		Origin:            "lab",
		ResourceRevision:  1,
		SessionReference:  ResourceReference{ResourceType: LabSessionResourceType, ResourceID: session.ID},
		AssignmentState:   "assigned",
		RecorderReference: &ResourceReference{ResourceType: VirtualRecorderResourceType, ResourceID: recorderID},
		Visibility:        "visible",
		CreatedAt:         at,
		UpdatedAt:         at,
	}
}

func NewVirtualRecorder(id string, session LabSession, bedID string, ordinal int, at string) VirtualRecorder {
	return VirtualRecorder{
		SchemaVersion:               SchemaVersion,
		ID:                          id,
		Name:                        labChildName(session.Name, "recorder", ordinal),
		Origin:                      "lab",
		ResourceRevision:            1,
		SessionReference:            ResourceReference{ResourceType: LabSessionResourceType, ResourceID: session.ID},
		BedReference:                &ResourceReference{ResourceType: LabBedResourceType, ResourceID: bedID},
		RecorderGatewayRecorderCode: id,
		TerminalArchivePolicy:       "not-selected",
		ExecutionState:              "ready",
		Visibility:                  "visible",
		CreatedAt:                   at,
		UpdatedAt:                   at,
	}
}

// AttachLabRecorderRunnerStartReceipt records only an effect receipt returned
// by the Runner. The caller must first obtain the pure Lab transition that
// placed this virtual recorder in `running`; this function never starts a
// recorder itself or derives Gateway identities from a display name.
func AttachLabRecorderRunnerStartReceipt(recorder VirtualRecorder, receipt LabRecorderRunnerStartReceipt, at string) (VirtualRecorder, *Issue) {
	if recorder.ExecutionState != "running" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-running", Message: "a Lab recorder Runner start receipt requires a running virtual recorder"}
	}
	if !ValidIdentifier(recorder.RecorderGatewayRecorderCode) || !ValidIdentifier(receipt.RunID) || receipt.RunRevision < 1 || !ValidIdentifier(receipt.RecorderGatewayRecorderID) || !ValidIdentifier(receipt.ColdPathCaptureID) {
		return VirtualRecorder{}, &Issue{Code: "lab-recorder-runner-start-receipt-invalid", Message: "Lab recorder Runner start receipt must contain valid explicit run, Gateway recorder, and capture identities"}
	}
	if receipt.RecorderGatewayRecorderID != "recorder-"+recorder.RecorderGatewayRecorderCode {
		return VirtualRecorder{}, &Issue{Code: "lab-recorder-runner-recorder-identity-mismatch", Message: "Lab recorder Runner returned a Gateway recorder identity that does not match the virtual recorder's declared recorder code"}
	}
	next := recorder
	next.RecorderGatewayRecorderID = receipt.RecorderGatewayRecorderID
	next.LabRecorderRunnerRunID = receipt.RunID
	next.LabRecorderRunnerRunRevision = receipt.RunRevision
	next.RecorderGatewayColdPathCaptureID = receipt.ColdPathCaptureID
	next.RecorderGatewayFinalizationReceiptID = ""
	if receipt.ArchiveOnTerminalStop {
		next.TerminalArchivePolicy = "export-on-stop"
	} else {
		next.TerminalArchivePolicy = "no-export"
	}
	next.UpdatedAt = at
	return next, nil
}

// AttachLabRecorderRunnerFinalizationReceipt records a named C45 receipt only
// after the pure Lab transition reached `stopped`. It does not form, upload,
// or index a .vital artifact.
func AttachLabRecorderRunnerFinalizationReceipt(recorder VirtualRecorder, receipt LabRecorderRunnerFinalizationReceipt, labOperationReference ResourceReference, at string) (VirtualRecorder, *Issue) {
	if recorder.ExecutionState != "stopped" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-stopped", Message: "a Lab recorder Runner finalization receipt requires a stopped virtual recorder"}
	}
	if !ValidIdentifier(recorder.LabRecorderRunnerRunID) || recorder.LabRecorderRunnerRunID != receipt.RunID || recorder.LabRecorderRunnerRunRevision < 1 || receipt.RunRevision != recorder.LabRecorderRunnerRunRevision+1 || !ValidIdentifier(recorder.RecorderGatewayRecorderID) || recorder.RecorderGatewayRecorderID != receipt.RecorderGatewayRecorderID || !ValidIdentifier(recorder.RecorderGatewayColdPathCaptureID) || recorder.RecorderGatewayColdPathCaptureID != receipt.ColdPathCaptureID || !ValidIdentifier(receipt.FinalizationReceiptID) {
		return VirtualRecorder{}, &Issue{Code: "lab-recorder-runner-finalization-receipt-invalid", Message: "Lab recorder Runner finalization receipt must match the persisted Runner run, Gateway recorder, and capture identities"}
	}
	if labOperationReference.ResourceType != "operation" || !ValidIdentifier(labOperationReference.ResourceID) {
		return VirtualRecorder{}, &Issue{Code: "terminal-archive-lab-operation-reference-invalid", Message: "Lab recorder Runner finalization requires the explicit owning Lab operation reference"}
	}
	next := recorder
	next.RecorderGatewayFinalizationReceiptID = receipt.FinalizationReceiptID
	next.LabRecorderRunnerRunRevision = receipt.RunRevision
	if next.TerminalArchivePolicy == "export-on-stop" {
		next.TerminalArchiveIntent = &TerminalArchiveIntent{
			State:                         "pending",
			RequestID:                     terminalArchiveRequestID(next.ID, next.ResourceRevision, next.RecorderGatewayFinalizationReceiptID),
			SourceResourceRevision:        next.ResourceRevision,
			ColdPathFinalizationReceiptID: next.RecorderGatewayFinalizationReceiptID,
			LabOperationReference:         labOperationReference,
		}
	}
	next.UpdatedAt = at
	return next, nil
}

// TerminalArchiveExportCandidateForRecorder returns the exact Archive
// command input selected by a durable Lab terminal intent. It never creates
// an intent from a stopped recorder: absent, malformed, and unsubmitted
// intent states remain distinct and visible to the caller.
func TerminalArchiveExportCandidateForRecorder(recorder VirtualRecorder) (TerminalArchiveExportCandidate, *Issue) {
	if recorder.TerminalArchivePolicy != "export-on-stop" || recorder.TerminalArchiveIntent == nil {
		return TerminalArchiveExportCandidate{}, &Issue{Code: "terminal-archive-intent-missing", Message: "the stopped virtual recorder has no export-on-stop terminal archive intent"}
	}
	intent := recorder.TerminalArchiveIntent
	if intent.State != "pending" && intent.State != "rejected" && intent.State != "unavailable" {
		return TerminalArchiveExportCandidate{}, &Issue{Code: "terminal-archive-intent-not-dispatchable", Message: "the terminal archive intent is not awaiting Archive Export dispatch"}
	}
	if recorder.ExecutionState != "stopped" || !ValidIdentifier(recorder.ID) || !ValidIdentifier(intent.RequestID) || intent.SourceResourceRevision < 1 || !ValidIdentifier(intent.ColdPathFinalizationReceiptID) || intent.ColdPathFinalizationReceiptID != recorder.RecorderGatewayFinalizationReceiptID || intent.LabOperationReference.ResourceType != "operation" || !ValidIdentifier(intent.LabOperationReference.ResourceID) {
		return TerminalArchiveExportCandidate{}, &Issue{Code: "terminal-archive-intent-invalid", Message: "the terminal archive intent does not match a stopped recorder finalization receipt"}
	}
	return TerminalArchiveExportCandidate{RequestID: intent.RequestID, VirtualRecorderID: recorder.ID, ExpectedResourceRevision: intent.SourceResourceRevision, ColdPathFinalizationReceiptID: intent.ColdPathFinalizationReceiptID, LabOperationReference: intent.LabOperationReference}, nil
}

// RecordTerminalArchiveDispatch records only Archive admission evidence. A
// submitted operation may still be running or fail later; Lab therefore
// stores its reference, not a fabricated upload state.
func RecordTerminalArchiveDispatch(recorder VirtualRecorder, requestID string, outcome string, archiveOperation *ResourceReference, dispatchIssue *Issue, at string) (VirtualRecorder, *Issue) {
	candidate, issue := TerminalArchiveExportCandidateForRecorder(recorder)
	if issue != nil {
		return VirtualRecorder{}, issue
	}
	if candidate.RequestID != requestID {
		return VirtualRecorder{}, &Issue{Code: "terminal-archive-request-id-mismatch", Message: "Archive dispatch request ID must match the persisted terminal archive intent"}
	}
	next := recorder
	intent := *recorder.TerminalArchiveIntent
	intent.LastAttemptAt = at
	switch outcome {
	case "submitted":
		if archiveOperation == nil {
			return VirtualRecorder{}, &Issue{Code: "terminal-archive-dispatch-outcome-missing", Message: "a submitted Archive dispatch requires an operation reference"}
		}
		if archiveOperation.ResourceType != "operation" || !ValidIdentifier(archiveOperation.ResourceID) {
			return VirtualRecorder{}, &Issue{Code: "terminal-archive-operation-reference-invalid", Message: "Archive dispatch operation reference must be explicit"}
		}
		intent.State = "submitted"
		intent.ArchiveOperationReference = archiveOperation
		intent.LastDispatchIssue = nil
	case "rejected", "unavailable":
		if dispatchIssue == nil {
			return VirtualRecorder{}, &Issue{Code: "terminal-archive-dispatch-outcome-missing", Message: "a rejected or unavailable Archive dispatch requires explicit issue evidence"}
		}
		intent.ArchiveOperationReference = nil
		intent.LastDispatchIssue = dispatchIssue
		intent.State = outcome
	default:
		return VirtualRecorder{}, &Issue{Code: "terminal-archive-dispatch-state-invalid", Message: "Archive dispatch outcome must be submitted, rejected, or unavailable"}
	}
	next.TerminalArchiveIntent = &intent
	// The recorder document changed, so its normal resource revision advances.
	// The intent separately retains SourceResourceRevision so Archive can retry
	// the immutable stopped source after later visibility or dispatch changes.
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

func terminalArchiveRequestID(recorderID string, sourceRevision int, finalizationReceiptID string) string {
	digest := sha256.Sum256([]byte(recorderID + "\x00" + strconv.Itoa(sourceRevision) + "\x00" + finalizationReceiptID))
	return "lab-terminal-archive-" + hex.EncodeToString(digest[:16])
}

// BeginLabSessionStart persists an explicit execution intent before the
// application layer invokes any Runner effect. It does not start a Socket.IO
// connection, infer a Runner run, or change a virtual recorder state.
func BeginLabSessionStart(session LabSession, recorders []VirtualRecorder, at string) (LabSession, *Issue) {
	if session.State != "prepared" && session.State != "stopped" {
		return LabSession{}, &Issue{Code: "lab-session-not-startable", Message: "Lab session must be prepared or stopped before it can start"}
	}
	if len(recorders) == 0 {
		return LabSession{}, &Issue{Code: "lab-session-has-no-virtual-recorders", Message: "a Lab session requires one or more owned virtual recorders before it can start"}
	}
	for _, recorder := range recorders {
		if recorder.ExecutionState != "ready" && recorder.ExecutionState != "stopped" {
			return LabSession{}, &Issue{Code: "virtual-recorder-not-startable", Message: "all owned virtual recorders must be ready or stopped before session start"}
		}
	}
	next := session
	next.State = "starting"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

// CompleteLabSessionStart commits the aggregate fact only once every owned
// virtual recorder has returned an explicit Runner start receipt and is
// durable as running.
func CompleteLabSessionStart(session LabSession, recorders []VirtualRecorder, at string) (LabSession, *Issue) {
	if session.State != "starting" {
		return LabSession{}, &Issue{Code: "lab-session-start-not-in-progress", Message: "Lab session must be starting before start can complete"}
	}
	for _, recorder := range recorders {
		if recorder.ExecutionState != "running" || !ValidIdentifier(recorder.RecorderGatewayRecorderID) || !ValidIdentifier(recorder.LabRecorderRunnerRunID) || recorder.LabRecorderRunnerRunRevision < 1 || !ValidIdentifier(recorder.RecorderGatewayColdPathCaptureID) {
			return LabSession{}, &Issue{Code: "lab-session-recorder-start-incomplete", Message: "every owned virtual recorder must have a durable Runner start receipt before session start completes"}
		}
	}
	next := session
	next.State = "running"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

// BeginLabSessionStop records the terminal-stop intent before any Runner
// finalization call. Failed sessions may enter this workflow only when they
// still own running recorders, so an operator can make live effects explicit
// and clean them up without rewriting history.
func BeginLabSessionStop(session LabSession, recorders []VirtualRecorder, at string) (LabSession, *Issue) {
	if session.State != "running" && session.State != "failed" {
		return LabSession{}, &Issue{Code: "lab-session-not-stoppable", Message: "Lab session must be running or failed with live recorders before it can stop"}
	}
	running := false
	for _, recorder := range recorders {
		if recorder.ExecutionState == "running" {
			running = true
		}
	}
	if !running {
		return LabSession{}, &Issue{Code: "lab-session-has-no-running-virtual-recorders", Message: "Lab session has no running virtual recorder to finalize"}
	}
	next := session
	next.State = "stopping"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

// CompleteLabSessionStop commits a stopped session only when every owned
// virtual recorder is terminal and receipt-complete. It never interprets a
// failed or missing Runner result as a stopped recorder.
func CompleteLabSessionStop(session LabSession, recorders []VirtualRecorder, at string) (LabSession, *Issue) {
	if session.State != "stopping" {
		return LabSession{}, &Issue{Code: "lab-session-stop-not-in-progress", Message: "Lab session must be stopping before stop can complete"}
	}
	for _, recorder := range recorders {
		if recorder.ExecutionState != "stopped" || !ValidIdentifier(recorder.RecorderGatewayRecorderID) || !ValidIdentifier(recorder.LabRecorderRunnerRunID) || recorder.LabRecorderRunnerRunRevision < 2 || !ValidIdentifier(recorder.RecorderGatewayColdPathCaptureID) || !ValidIdentifier(recorder.RecorderGatewayFinalizationReceiptID) {
			return LabSession{}, &Issue{Code: "lab-session-recorder-stop-incomplete", Message: "every owned virtual recorder must be stopped with a durable Runner finalization receipt before session stop completes"}
		}
	}
	next := session
	next.State = "stopped"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

// FailLabSessionExecution makes an external Runner failure visible in Lab
// state. The caller supplies the failure evidence separately on its
// operation; this resource state deliberately does not fabricate a reason.
func FailLabSessionExecution(session LabSession, at string) (LabSession, *Issue) {
	if session.State != "starting" && session.State != "stopping" {
		return LabSession{}, &Issue{Code: "lab-session-execution-not-in-progress", Message: "only a starting or stopping Lab session can become failed"}
	}
	next := session
	next.State = "failed"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

// BeginVirtualRecorderStart makes an individual external effect recoverable:
// the persisted `starting` state says that a Runner effect was requested but
// is not yet attested by a start receipt.
func BeginVirtualRecorderStart(session LabSession, recorder VirtualRecorder, at string) (VirtualRecorder, *Issue) {
	if session.State != "starting" && session.State != "running" {
		return VirtualRecorder{}, &Issue{Code: "lab-session-not-starting-or-running", Message: "the owning Lab session must be starting or running before a virtual recorder can start"}
	}
	if recorder.ExecutionState != "ready" && recorder.ExecutionState != "stopped" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-startable", Message: "virtual recorder must be ready or stopped before it can start"}
	}
	next := recorder
	next.ExecutionState = "starting"
	next.ResourceRevision++
	next.RecorderGatewayRecorderID = ""
	next.LabRecorderRunnerRunID = ""
	next.LabRecorderRunnerRunRevision = 0
	next.RecorderGatewayColdPathCaptureID = ""
	next.RecorderGatewayFinalizationReceiptID = ""
	next.TerminalArchivePolicy = "not-selected"
	next.TerminalArchiveIntent = nil
	next.UpdatedAt = at
	return next, nil
}

func CompleteVirtualRecorderStart(recorder VirtualRecorder, receipt LabRecorderRunnerStartReceipt, at string) (VirtualRecorder, *Issue) {
	if recorder.ExecutionState != "starting" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-start-not-in-progress", Message: "virtual recorder must be starting before its Runner start receipt can complete the transition"}
	}
	next := recorder
	next.ExecutionState = "running"
	next.ResourceRevision++
	next.UpdatedAt = at
	return AttachLabRecorderRunnerStartReceipt(next, receipt, at)
}

func BeginVirtualRecorderStop(session LabSession, recorder VirtualRecorder, at string) (VirtualRecorder, *Issue) {
	if session.State != "stopping" && session.State != "running" && session.State != "failed" {
		return VirtualRecorder{}, &Issue{Code: "lab-session-not-stopping-running-or-failed", Message: "the owning Lab session must be stopping, running, or failed before a virtual recorder can stop"}
	}
	if recorder.ExecutionState != "running" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-running", Message: "virtual recorder must be running before it can stop"}
	}
	if !ValidIdentifier(recorder.LabRecorderRunnerRunID) || recorder.LabRecorderRunnerRunRevision < 1 {
		return VirtualRecorder{}, &Issue{Code: "lab-recorder-runner-run-reference-missing", Message: "a running virtual recorder has no explicit Lab recorder Runner run reference"}
	}
	next := recorder
	next.ExecutionState = "stopping"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

func CompleteVirtualRecorderStop(recorder VirtualRecorder, receipt LabRecorderRunnerFinalizationReceipt, labOperationReference ResourceReference, at string) (VirtualRecorder, *Issue) {
	if recorder.ExecutionState != "stopping" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-stop-not-in-progress", Message: "virtual recorder must be stopping before its Runner finalization receipt can complete the transition"}
	}
	next := recorder
	next.ExecutionState = "stopped"
	next.ResourceRevision++
	next.UpdatedAt = at
	return AttachLabRecorderRunnerFinalizationReceipt(next, receipt, labOperationReference, at)
}

func FailVirtualRecorderExecution(recorder VirtualRecorder, at string) (VirtualRecorder, *Issue) {
	if recorder.ExecutionState != "starting" && recorder.ExecutionState != "stopping" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-execution-not-in-progress", Message: "only a starting or stopping virtual recorder can become failed"}
	}
	next := recorder
	next.ExecutionState = "failed"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

func StartLabSession(session LabSession, recorders []VirtualRecorder, at string) (LabSession, []VirtualRecorder, *Issue) {
	if session.State != "prepared" && session.State != "stopped" {
		return LabSession{}, nil, &Issue{Code: "lab-session-not-startable", Message: "Lab session must be prepared or stopped before it can start"}
	}
	nextRecorders := make([]VirtualRecorder, len(recorders))
	for index, recorder := range recorders {
		if recorder.ExecutionState != "ready" && recorder.ExecutionState != "stopped" {
			return LabSession{}, nil, &Issue{Code: "virtual-recorder-not-startable", Message: "all owned virtual recorders must be ready or stopped before session start"}
		}
		nextRecorders[index] = recorder
		nextRecorders[index].ExecutionState = "running"
		nextRecorders[index].ResourceRevision++
		nextRecorders[index].UpdatedAt = at
	}
	nextSession := session
	nextSession.State = "running"
	nextSession.ResourceRevision++
	nextSession.UpdatedAt = at
	return nextSession, nextRecorders, nil
}

func StopLabSession(session LabSession, recorders []VirtualRecorder, at string) (LabSession, []VirtualRecorder, *Issue) {
	if session.State != "running" {
		return LabSession{}, nil, &Issue{Code: "lab-session-not-running", Message: "Lab session must be running before it can stop"}
	}
	nextRecorders := make([]VirtualRecorder, len(recorders))
	for index, recorder := range recorders {
		nextRecorders[index] = recorder
		if recorder.ExecutionState == "running" {
			nextRecorders[index].ExecutionState = "stopped"
			nextRecorders[index].ResourceRevision++
			nextRecorders[index].UpdatedAt = at
		}
	}
	nextSession := session
	nextSession.State = "stopped"
	nextSession.ResourceRevision++
	nextSession.UpdatedAt = at
	return nextSession, nextRecorders, nil
}

func StartVirtualRecorder(session LabSession, recorder VirtualRecorder, at string) (VirtualRecorder, *Issue) {
	if session.State != "running" {
		return VirtualRecorder{}, &Issue{Code: "lab-session-not-running", Message: "the owning Lab session must be running before a virtual recorder can start"}
	}
	if recorder.ExecutionState != "ready" && recorder.ExecutionState != "stopped" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-startable", Message: "virtual recorder must be ready or stopped before it can start"}
	}
	next := recorder
	next.ExecutionState = "running"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

func StopVirtualRecorder(session LabSession, recorder VirtualRecorder, at string) (VirtualRecorder, *Issue) {
	if session.State != "running" {
		return VirtualRecorder{}, &Issue{Code: "lab-session-not-running", Message: "the owning Lab session must be running before a virtual recorder can stop"}
	}
	if recorder.ExecutionState != "running" {
		return VirtualRecorder{}, &Issue{Code: "virtual-recorder-not-running", Message: "virtual recorder must be running before it can stop"}
	}
	next := recorder
	next.ExecutionState = "stopped"
	next.ResourceRevision++
	next.UpdatedAt = at
	return next, nil
}

func ChangeLabVisibility(resourceType string, bed *LabBed, recorder *VirtualRecorder, action string, at string) (*LabBed, *VirtualRecorder, *Issue) {
	visibility := ""
	switch action {
	case "hide":
		visibility = "hidden"
	case "unhide":
		visibility = "visible"
	default:
		return nil, nil, &Issue{Code: "unsupported-lab-action", Message: "visibility action must be hide or unhide"}
	}
	switch resourceType {
	case LabBedResourceType:
		if bed == nil {
			return nil, nil, &Issue{Code: "lab-bed-missing", Message: "Lab bed is missing"}
		}
		next := *bed
		next.Visibility = visibility
		next.ResourceRevision++
		next.UpdatedAt = at
		return &next, nil, nil
	case VirtualRecorderResourceType:
		if recorder == nil {
			return nil, nil, &Issue{Code: "virtual-recorder-missing", Message: "virtual recorder is missing"}
		}
		next := *recorder
		next.Visibility = visibility
		next.ResourceRevision++
		next.UpdatedAt = at
		return nil, &next, nil
	default:
		return nil, nil, &Issue{Code: "unsupported-action-for-resource", Message: "visibility applies only to Lab beds and virtual recorders"}
	}
}

func DetachVirtualRecorder(recorder VirtualRecorder, bed LabBed, at string) (VirtualRecorder, LabBed, *Issue) {
	if recorder.ExecutionState != "stopped" {
		return VirtualRecorder{}, LabBed{}, &Issue{Code: "virtual-recorder-not-stopped", Message: "a virtual recorder must be stopped before detach"}
	}
	if recorder.BedReference == nil {
		return VirtualRecorder{}, LabBed{}, &Issue{Code: "virtual-recorder-already-detached", Message: "virtual recorder has no Lab bed assignment"}
	}
	if recorder.BedReference.ResourceID != bed.ID || bed.AssignmentState != "assigned" || bed.RecorderReference == nil || bed.RecorderReference.ResourceID != recorder.ID {
		return VirtualRecorder{}, LabBed{}, &Issue{Code: "lab-assignment-invariant-failed", Message: "Lab bed and virtual recorder assignment does not match"}
	}
	nextRecorder := recorder
	nextRecorder.BedReference = nil
	nextRecorder.ResourceRevision++
	nextRecorder.UpdatedAt = at
	nextBed := bed
	nextBed.AssignmentState = "detached"
	nextBed.RecorderReference = nil
	nextBed.ResourceRevision++
	nextBed.UpdatedAt = at
	return nextRecorder, nextBed, nil
}

func ValidateLabDelete(command LabResourceCommand, session *LabSession, bed *LabBed, recorder *VirtualRecorder) *Issue {
	switch command.ResourceType {
	case LabSessionResourceType:
		if session == nil {
			return &Issue{Code: "lab-session-missing", Message: "Lab session is missing"}
		}
		if session.State == "running" {
			return &Issue{Code: "lab-session-running", Message: "a running Lab session must be stopped before delete"}
		}
	case LabBedResourceType:
		if bed == nil {
			return &Issue{Code: "lab-bed-missing", Message: "Lab bed is missing"}
		}
		if bed.AssignmentState != "detached" {
			return &Issue{Code: "lab-bed-still-assigned", Message: "a Lab bed must be detached before delete"}
		}
	case VirtualRecorderResourceType:
		if recorder == nil {
			return &Issue{Code: "virtual-recorder-missing", Message: "virtual recorder is missing"}
		}
		if recorder.ExecutionState == "running" {
			return &Issue{Code: "virtual-recorder-running", Message: "a running virtual recorder must be stopped before delete"}
		}
		if recorder.BedReference != nil {
			return &Issue{Code: "virtual-recorder-still-assigned", Message: "a virtual recorder must be detached before delete"}
		}
	}
	return nil
}

func LabResourceOperationKind(action string) string {
	return LabResourceOperationPrefix + action
}

func validLabResourceType(value string) bool {
	return value == LabSessionResourceType || value == LabBedResourceType || value == VirtualRecorderResourceType
}

func validLabText(value string) bool {
	trimmed := strings.TrimSpace(value)
	return trimmed != "" && len(trimmed) <= 100
}

func labChildName(sessionName string, kind string, ordinal int) string {
	return fmt.Sprintf("%s-%s-%s", sessionName, kind, strconv.Itoa(ordinal))
}
