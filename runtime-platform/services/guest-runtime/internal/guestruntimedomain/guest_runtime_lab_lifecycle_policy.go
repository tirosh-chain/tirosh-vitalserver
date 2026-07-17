package guestruntimedomain

import (
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
	SchemaVersion    string             `json:"schemaVersion"`
	ID               string             `json:"id"`
	Name             string             `json:"name"`
	Origin           string             `json:"origin"`
	ResourceRevision int                `json:"resourceRevision"`
	SessionReference ResourceReference  `json:"sessionReference"`
	BedReference     *ResourceReference `json:"bedReference,omitempty"`
	ExecutionState   string             `json:"executionState"`
	Visibility       string             `json:"visibility"`
	CreatedAt        string             `json:"createdAt"`
	UpdatedAt        string             `json:"updatedAt"`
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
	VirtualRecorderID       string
	VirtualRecorderRevision int
	VirtualRecorderName     string
	SessionID               string
	SessionName             string
	StoppedAt               string
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
		SchemaVersion:    SchemaVersion,
		ID:               id,
		Name:             labChildName(session.Name, "recorder", ordinal),
		Origin:           "lab",
		ResourceRevision: 1,
		SessionReference: ResourceReference{ResourceType: LabSessionResourceType, ResourceID: session.ID},
		BedReference:     &ResourceReference{ResourceType: LabBedResourceType, ResourceID: bedID},
		ExecutionState:   "ready",
		Visibility:       "visible",
		CreatedAt:        at,
		UpdatedAt:        at,
	}
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
