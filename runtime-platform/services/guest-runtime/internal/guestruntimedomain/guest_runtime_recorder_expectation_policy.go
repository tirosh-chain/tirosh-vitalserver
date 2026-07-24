package guestruntimedomain

import (
	"encoding/json"
	"fmt"
	"time"
)

const RecorderExpectationEventResourceType = "recorder-expectation-event"

type RecorderObservabilityExpectationCommand struct {
	SchemaVersion            string         `json:"schemaVersion"`
	RequestID                string         `json:"requestId"`
	ExpectedResourceRevision int            `json:"expectedResourceRevision"`
	Action                   string         `json:"action"`
	ExpectationState         *string        `json:"expectationState,omitempty"`
	SupportState             *string        `json:"supportState,omitempty"`
	Source                   *string        `json:"source,omitempty"`
	Reason                   *string        `json:"reason,omitempty"`
	Evidence                 map[string]any `json:"evidence"`
}

type RecorderExpectationEvent struct {
	SchemaVersion    string         `json:"schemaVersion"`
	ID               string         `json:"id"`
	RequestID        string         `json:"requestId"`
	RecorderID       string         `json:"recorderId"`
	PreviousRevision int            `json:"previousRevision"`
	Revision         int            `json:"revision"`
	Action           string         `json:"action"`
	ExpectationState *string        `json:"expectationState,omitempty"`
	SupportState     *string        `json:"supportState,omitempty"`
	Source           *string        `json:"source,omitempty"`
	Reason           *string        `json:"reason,omitempty"`
	Evidence         map[string]any `json:"evidence"`
	DecidedAt        string         `json:"decidedAt"`
	ReceivedAt       string         `json:"receivedAt"`
	PersistedAt      string         `json:"persistedAt"`
}

type RecorderExpectation struct {
	SchemaVersion    string            `json:"schemaVersion"`
	RecorderID       string            `json:"recorderId"`
	ResourceRevision int               `json:"resourceRevision"`
	LifecycleState   string            `json:"lifecycleState"`
	ExpectationState *string           `json:"expectationState,omitempty"`
	SupportState     *string           `json:"supportState,omitempty"`
	Source           *string           `json:"source,omitempty"`
	Reason           *string           `json:"reason,omitempty"`
	Evidence         map[string]any    `json:"evidence"`
	SourceEvent      ResourceReference `json:"sourceEvent"`
	UpdatedAt        string            `json:"updatedAt"`
}

type RecorderExpectationReceipt struct {
	SchemaVersion string            `json:"schemaVersion"`
	RequestID     string            `json:"requestId"`
	State         string            `json:"state"`
	Event         ResourceReference `json:"event"`
	Recorder      ResourceReference `json:"recorder"`
	Revision      int               `json:"revision"`
	PersistedAt   string            `json:"persistedAt"`
}

func ValidateRecorderObservabilityExpectationCommand(recorderID string, command RecorderObservabilityExpectationCommand) *Issue {
	if !ValidIdentifier(recorderID) || command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) {
		return &Issue{Code: "invalid-recorder-expectation-command-identity", Message: "Recorder expectation command requires valid schema, request, and Recorder identifiers"}
	}
	if command.ExpectedResourceRevision < 0 || command.Evidence == nil {
		return &Issue{Code: "invalid-recorder-expectation-command-evidence", Message: "expectedResourceRevision and evidence must be explicit"}
	}
	switch command.Action {
	case "set":
		if command.ExpectationState == nil || (*command.ExpectationState != "expected" && *command.ExpectationState != "not-expected") || command.Source == nil || *command.Source == "" {
			return &Issue{Code: "invalid-recorder-expectation-set-command", Message: "set requires expected or not-expected state and an explicit source"}
		}
		if command.SupportState != nil && *command.SupportState != "supported" && *command.SupportState != "unsupported" {
			return &Issue{Code: "invalid-recorder-support-declaration", Message: "supportState must be supported or unsupported when declared"}
		}
	case "clear":
		if command.ExpectationState != nil || command.SupportState != nil || command.Source != nil || command.Reason != nil || len(command.Evidence) != 0 {
			return &Issue{Code: "invalid-recorder-expectation-clear-command", Message: "clear must not carry expectation, support, source, reason, or evidence values"}
		}
	default:
		return &Issue{Code: "invalid-recorder-expectation-action", Message: "action must be set or clear"}
	}
	return nil
}

func DecideRecorderExpectation(
	recorderID string,
	eventID string,
	command RecorderObservabilityExpectationCommand,
	previous *RecorderExpectation,
	current *RecorderObservabilitySummary,
	decidedAt time.Time,
	receivedAt time.Time,
	persistedAt time.Time,
) (RecorderExpectationEvent, RecorderExpectation, RecorderObservabilitySummary, error) {
	if issue := ValidateRecorderObservabilityExpectationCommand(recorderID, command); issue != nil {
		return RecorderExpectationEvent{}, RecorderExpectation{}, RecorderObservabilitySummary{}, fmt.Errorf("%s", issue.Code)
	}
	if !ValidIdentifier(eventID) {
		return RecorderExpectationEvent{}, RecorderExpectation{}, RecorderObservabilitySummary{}, fmt.Errorf("invalid Recorder expectation event identifier")
	}
	previousRevision := 0
	if previous != nil {
		if previous.RecorderID != recorderID || previous.ResourceRevision < 1 {
			return RecorderExpectationEvent{}, RecorderExpectation{}, RecorderObservabilitySummary{}, fmt.Errorf("invalid previous Recorder expectation")
		}
		previousRevision = previous.ResourceRevision
	}
	if command.ExpectedResourceRevision != previousRevision {
		return RecorderExpectationEvent{}, RecorderExpectation{}, RecorderObservabilitySummary{}, fmt.Errorf("recorder-expectation-revision-conflict")
	}
	revision := previousRevision + 1
	event := RecorderExpectationEvent{
		SchemaVersion: SchemaVersion, ID: eventID, RequestID: command.RequestID, RecorderID: recorderID,
		PreviousRevision: previousRevision, Revision: revision, Action: command.Action,
		ExpectationState: command.ExpectationState, SupportState: command.SupportState,
		Source: command.Source, Reason: command.Reason, Evidence: cloneExpectationEvidence(command.Evidence),
		DecidedAt: Timestamp(decidedAt), ReceivedAt: Timestamp(receivedAt), PersistedAt: Timestamp(persistedAt),
	}
	lifecycleState := "active"
	if command.Action == "clear" {
		lifecycleState = "cleared"
	}
	expectation := RecorderExpectation{
		SchemaVersion: SchemaVersion, RecorderID: recorderID, ResourceRevision: revision,
		LifecycleState: lifecycleState, ExpectationState: command.ExpectationState,
		SupportState: command.SupportState, Source: command.Source, Reason: command.Reason,
		Evidence:    cloneExpectationEvidence(command.Evidence),
		SourceEvent: ResourceReference{ResourceType: RecorderExpectationEventResourceType, ResourceID: eventID},
		UpdatedAt:   Timestamp(persistedAt),
	}
	summary, err := projectRecorderSummaryFromExpectation(recorderID, command, current, persistedAt)
	if err != nil {
		return RecorderExpectationEvent{}, RecorderExpectation{}, RecorderObservabilitySummary{}, err
	}
	return event, expectation, summary, nil
}

func NewRecorderExpectationReceipt(event RecorderExpectationEvent) RecorderExpectationReceipt {
	return RecorderExpectationReceipt{
		SchemaVersion: SchemaVersion, RequestID: event.RequestID, State: "persisted",
		Event:    ResourceReference{ResourceType: RecorderExpectationEventResourceType, ResourceID: event.ID},
		Recorder: ResourceReference{ResourceType: "recorder", ResourceID: event.RecorderID},
		Revision: event.Revision, PersistedAt: event.PersistedAt,
	}
}

func projectRecorderSummaryFromExpectation(recorderID string, command RecorderObservabilityExpectationCommand, current *RecorderObservabilitySummary, persistedAt time.Time) (RecorderObservabilitySummary, error) {
	summary := RecorderObservabilitySummary{
		SchemaVersion: SchemaVersion, RecorderID: recorderID, ResourceRevision: 1,
		SupportState: "unknown", ExpectationState: "unset", ReportState: "never-reported",
		ReadState: "available", UpdatedAt: Timestamp(persistedAt),
	}
	if current != nil {
		if current.RecorderID != recorderID || current.ResourceRevision < 1 {
			return RecorderObservabilitySummary{}, fmt.Errorf("invalid current Recorder summary")
		}
		summary = *current
		summary.ResourceRevision++
		summary.UpdatedAt = Timestamp(persistedAt)
	}
	if command.Action == "set" {
		summary.ExpectationState = *command.ExpectationState
		if command.SupportState != nil {
			summary.SupportState = *command.SupportState
		} else if summary.LatestObservationReference == nil {
			summary.SupportState = "unknown"
		}
	} else {
		summary.ExpectationState = "unset"
		if summary.LatestObservationReference == nil {
			summary.SupportState = "unknown"
		} else {
			summary.SupportState = "supported"
		}
	}
	return summary, nil
}

func cloneExpectationEvidence(source map[string]any) map[string]any {
	encoded, _ := json.Marshal(source)
	var cloned map[string]any
	_ = json.Unmarshal(encoded, &cloned)
	if cloned == nil {
		return map[string]any{}
	}
	return cloned
}
