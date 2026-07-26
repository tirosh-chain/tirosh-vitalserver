package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

const topologyApplyOperationKind = "runtime.topology.apply"

var operationTransitions = map[string]map[string]bool{
	"requested": {"accepted": true, "cancelled": true},
	"accepted":  {"running": true, "cancelled": true, "interrupted": true},
	"running":   {"succeeded": true, "failed": true, "cancelled": true, "interrupted": true},
}

func NewTopologyApplyOperation(id string, command TopologyApplyCommand, requestedAt string, digest string) Operation {
	return NewOperation(
		id,
		topologyApplyOperationKind,
		command.RequestID,
		"runtime-topology",
		command.TopologyID,
		command.ExpectedResourceRevision,
		requestedAt,
		digest,
	)
}

// NewOperation constructs only the requested state. Application workflows are
// responsible for applying the declared accepted/running/terminal transitions
// before persistence or an external effect.
func NewOperation(id string, kind string, requestID string, resourceType string, resourceID string, requestedResourceRevision int, requestedAt string, digest string) Operation {
	return Operation{
		SchemaVersion: SchemaVersion,
		ID:            id,
		Kind:          kind,
		RequestID:     requestID,
		Target: OperationTarget{
			ResourceType:              resourceType,
			ResourceID:                resourceID,
			RequestedResourceRevision: requestedResourceRevision,
		},
		RequestedAt:   requestedAt,
		State:         "requested",
		CommandDigest: digest,
	}
}

func TransitionOperation(operation Operation, targetState string, at string, failure *Issue) (Operation, error) {
	if !operationTransitions[operation.State][targetState] {
		return Operation{}, fmt.Errorf("operation transition %s -> %s is not allowed", operation.State, targetState)
	}
	if targetState == "failed" && failure == nil {
		return Operation{}, fmt.Errorf("failed operation requires failure")
	}
	if targetState != "failed" && failure != nil {
		return Operation{}, fmt.Errorf("only failed operation may carry failure")
	}

	next := operation
	next.State = targetState
	switch targetState {
	case "accepted":
		next.AcceptedAt = &at
	case "running":
		next.StartedAt = &at
	case "succeeded":
		next.FinishedAt = &at
	case "failed":
		next.FinishedAt = &at
		next.Failure = failure
	case "cancelled", "interrupted":
		next.FinishedAt = &at
		next.TerminalReason = failure
	}
	return next, nil
}

func TopologyCommandDigest(command TopologyApplyCommand) (string, error) {
	return CommandDigest(command)
}

// CommandDigest binds request-id idempotency to the whole explicit command.
// It never derives a command from runtime state or an observation.
func CommandDigest(command any) (string, error) {
	canonical, err := json.Marshal(command)
	if err != nil {
		return "", fmt.Errorf("encode command: %w", err)
	}
	sum := sha256.Sum256(canonical)
	return hex.EncodeToString(sum[:]), nil
}

func UnsupportedTopologyStatus(now time.Time, operationID string) TopologyStatus {
	observedAt := Timestamp(now)
	return TopologyStatus{
		ReadState: "unsupported",
		Connection: ConnectionObservation{
			State:      "not-checked",
			ObservedAt: observedAt,
		},
		LastOperationReference: &ResourceReference{
			ResourceType: "operation",
			ResourceID:   operationID,
		},
		ObservedAt: observedAt,
		Issue: &Issue{
			Code:       "upstream-adapter-not-installed",
			Message:    "no VitalServer upstream adapter is installed in the Guest Runtime",
			Retryable:  boolPointer(false),
			Dependency: "vitalserver-upstream",
		},
	}
}

// BundledUpstreamCapability describes the static contract surface packaged in
// this Guest Runtime profile. It does not observe, infer, or claim whether the
// upstream process is currently reachable.
func BundledUpstreamCapability(topologyID string, spec RuntimeTopologySpec, revision int, now time.Time) (CapabilityDocument, error) {
	if !ValidIdentifier(topologyID) || !ValidIdentifier(spec.ProviderKind) || !ValidIdentifier(spec.EndpointReference.ResourceID) || revision < 1 {
		return CapabilityDocument{}, fmt.Errorf("invalid bundled upstream capability input")
	}
	return CapabilityDocument{
		SchemaVersion:      SchemaVersion,
		ID:                 fmt.Sprintf("capability-%s-r%d", topologyID, revision),
		Provider:           Provider{Kind: spec.ProviderKind, ID: spec.EndpointReference.ResourceID},
		CapabilityRevision: revision,
		ObservedAt:         Timestamp(now),
		Commands: []Capability{
			{Name: "upstream.recorder.deliver", State: "supported"},
		},
		Reads: []Capability{
			{Name: "upstream.delivery.receipt", State: "supported"},
			{Name: "upstream.connection", State: "supported"},
		},
	}, nil
}

func BundledTopologyStatus(now time.Time, operationID string, capability CapabilityDocument) TopologyStatus {
	observedAt := Timestamp(now)
	revision := capability.CapabilityRevision
	return TopologyStatus{
		ReadState: "available",
		Connection: ConnectionObservation{
			State:      "not-checked",
			ObservedAt: observedAt,
		},
		CapabilityDocumentReference: &ResourceReference{
			ResourceType: "capability-document",
			ResourceID:   capability.ID,
		},
		CapabilityRevision: &revision,
		LastOperationReference: &ResourceReference{
			ResourceType: "operation",
			ResourceID:   operationID,
		},
		ObservedAt: observedAt,
	}
}

func boolPointer(value bool) *bool {
	return &value
}
