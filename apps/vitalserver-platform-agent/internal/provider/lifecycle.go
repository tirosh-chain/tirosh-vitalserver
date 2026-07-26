package provider

import (
	"fmt"
	"time"
)

type State string

const (
	StateStarting      State = "starting"
	StateBootstrapping State = "bootstrapping"
	StateRunning       State = "running"
	StateStopping      State = "stopping"
	StateStopped       State = "stopped"
	StateFailed        State = "failed"
)

type Event string

const (
	EventRuntimeStarted Event = "runtime-started"
	EventEndpointReady  Event = "endpoint-ready"
	EventStopRequested  Event = "stop-requested"
	EventRuntimeStopped Event = "runtime-stopped"
	EventFailed         Event = "failed"
)

type Document struct {
	SchemaVersion  int     `json:"schemaVersion"`
	State          State   `json:"state"`
	Operation      *string `json:"operation"`
	OperationID    *string `json:"operationID"`
	BootID         *string `json:"bootID"`
	StartedAt      string  `json:"startedAt"`
	UpdatedAt      string  `json:"updatedAt"`
	DeadlineAt     *string `json:"deadlineAt"`
	TerminalReason *string `json:"terminalReason"`
	Message        *string `json:"message"`
}

func Starting(operationID, bootID string, now, deadline time.Time) Document {
	operation := "start-services"
	message := "Runtime Provider start requested"
	operationIDCopy, bootIDCopy := operationID, bootID
	deadlineText := deadline.UTC().Format(time.RFC3339Nano)
	return Document{
		SchemaVersion: 1,
		State:         StateStarting,
		Operation:     &operation,
		OperationID:   &operationIDCopy,
		BootID:        &bootIDCopy,
		StartedAt:     now.UTC().Format(time.RFC3339Nano),
		UpdatedAt:     now.UTC().Format(time.RFC3339Nano),
		DeadlineAt:    &deadlineText,
		Message:       &message,
	}
}

func Transition(current Document, event Event, now time.Time, message string) (Document, error) {
	next, valid := transitionState(current.State, event)
	if !valid {
		return Document{}, fmt.Errorf("runtime provider transition invalid state=%s event=%s", current.State, event)
	}
	current.State = next
	current.UpdatedAt = now.UTC().Format(time.RFC3339Nano)
	current.Message = stringPointer(message)
	if next == StateRunning || next == StateStopped {
		current.DeadlineAt = nil
	}
	if next == StateStopping || next == StateStopped {
		operation := "stop-services"
		current.Operation = &operation
	}
	if next != StateFailed {
		current.TerminalReason = nil
	}
	return current, nil
}

func Fail(current Document, now time.Time, reason, message string) Document {
	current.State = StateFailed
	current.UpdatedAt = now.UTC().Format(time.RFC3339Nano)
	current.DeadlineAt = nil
	current.TerminalReason = stringPointer(reason)
	current.Message = stringPointer(message)
	return current
}

func transitionState(state State, event Event) (State, bool) {
	switch {
	case state == StateStarting && event == EventRuntimeStarted:
		return StateBootstrapping, true
	case state == StateBootstrapping && event == EventEndpointReady:
		return StateRunning, true
	case (state == StateStarting || state == StateBootstrapping || state == StateRunning) && event == EventStopRequested:
		return StateStopping, true
	case state == StateStopping && event == EventRuntimeStopped:
		return StateStopped, true
	case event == EventFailed && state != StateStopped:
		return StateFailed, true
	default:
		return "", false
	}
}

func stringPointer(value string) *string {
	if value == "" {
		return nil
	}
	copy := value
	return &copy
}
