package hostagentdomain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
)

var operationTransitions = map[string]map[string]bool{
	"requested": {"accepted": true, "cancelled": true},
	"accepted":  {"running": true, "cancelled": true, "interrupted": true},
	"running":   {"succeeded": true, "failed": true, "cancelled": true, "interrupted": true},
}

func ValidateLifecycleCommand(command GuestLifecycleCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) {
		return &Issue{Code: "invalid-request-id", Message: "requestId must be a non-empty v1 identifier"}
	}
	if !ValidIdentifier(command.GuestRuntimeControlEndpointID) {
		return &Issue{Code: "invalid-guest-runtime-control-endpoint-id", Message: "guestRuntimeControlEndpointId must be a non-empty v1 identifier"}
	}
	if command.ExpectedResourceRevision < 1 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be at least one"}
	}
	if command.Action != "start" && command.Action != "stop" && command.Action != "reboot" {
		return &Issue{Code: "invalid-lifecycle-action", Message: "action must be start, stop, or reboot"}
	}
	return nil
}

func LifecycleCommandDigest(command GuestLifecycleCommand) (string, error) {
	encoded, err := json.Marshal(command)
	if err != nil {
		return "", fmt.Errorf("encode lifecycle command: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func NewLifecycleOperation(id string, command GuestLifecycleCommand, requestedAt string, digest string) Operation {
	return Operation{
		SchemaVersion: SchemaVersion,
		ID:            id,
		Kind:          "platform.guest." + command.Action,
		RequestID:     command.RequestID,
		Target: OperationTarget{
			ResourceType:              "guest-runtime-control-endpoint",
			ResourceID:                command.GuestRuntimeControlEndpointID,
			RequestedResourceRevision: command.ExpectedResourceRevision,
		},
		RequestedAt:   requestedAt,
		State:         "requested",
		CommandDigest: digest,
	}
}

func TransitionOperation(operation Operation, targetState string, at string, issue *Issue) (Operation, error) {
	if !operationTransitions[operation.State][targetState] {
		return Operation{}, fmt.Errorf("operation transition %s -> %s is not allowed", operation.State, targetState)
	}
	if targetState == "failed" && issue == nil {
		return Operation{}, fmt.Errorf("failed operation requires failure issue")
	}
	if targetState != "failed" && issue != nil {
		return Operation{}, fmt.Errorf("only failed transition can carry an issue")
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
		next.Failure = issue
	case "cancelled", "interrupted":
		next.FinishedAt = &at
		next.TerminalReason = issue
	}
	return next, nil
}

func ValidateProviderResult(request ProviderLifecycleRequest, result ProviderLifecycleResult) *Issue {
	if result.SchemaVersion != SchemaVersion {
		return &Issue{Code: "provider-contract-invalid", Message: "provider result schemaVersion must be v1"}
	}
	if result.RequestID != request.RequestID || result.ProviderID != request.ProviderID {
		return &Issue{Code: "provider-contract-invalid", Message: "provider result correlation does not match the request"}
	}
	switch result.ObservedState {
	case "starting", "running", "stopping", "stopped":
		if result.Issue != nil {
			return &Issue{Code: "provider-contract-invalid", Message: "successful provider observation must not carry issue"}
		}
	case "unavailable", "failed":
		if result.Issue == nil {
			return &Issue{Code: "provider-contract-invalid", Message: "unavailable or failed provider observation requires issue"}
		}
	default:
		return &Issue{Code: "provider-contract-invalid", Message: "provider observation state is not supported"}
	}
	return nil
}

func FailedProviderResult(request ProviderLifecycleRequest, observedAt string, issue Issue) ProviderLifecycleResult {
	return ProviderLifecycleResult{
		SchemaVersion: SchemaVersion,
		RequestID:     request.RequestID,
		ProviderID:    request.ProviderID,
		ObservedState: "failed",
		ObservedAt:    observedAt,
		Issue:         &issue,
	}
}

func ApplyPlatformProviderObservation(endpoint GuestRuntimeControlEndpoint, action string, result ProviderLifecycleResult) (GuestRuntimeControlEndpoint, error) {
	if result.ProviderID != endpoint.Provider.ID {
		return GuestRuntimeControlEndpoint{}, fmt.Errorf("provider result does not belong to Guest Runtime Control endpoint Platform Provider")
	}
	if result.ObservedAt == "" {
		return GuestRuntimeControlEndpoint{}, fmt.Errorf("provider result has no observedAt")
	}
	next := endpoint
	next.ResourceRevision++
	next.Provider.State = result.ObservedState
	next.Provider.ObservedAt = result.ObservedAt
	next.Provider.Issue = result.Issue
	next.UpdatedAt = result.ObservedAt
	switch result.ObservedState {
	case "stopped":
		next.Transport = GuestRuntimeControlTransportObservation{
			State:      "unavailable",
			ObservedAt: result.ObservedAt,
			Issue: &Issue{
				Code:       "guest-provider-stopped",
				Message:    "Host provider observed the Guest as stopped",
				Retryable:  Bool(true),
				Dependency: "guest-provider",
			},
		}
	case "unavailable":
		next.Transport = GuestRuntimeControlTransportObservation{
			State:      "unavailable",
			ObservedAt: result.ObservedAt,
			Issue: &Issue{
				Code:       "guest-provider-unavailable",
				Message:    "Host provider reported the Guest as unavailable",
				Retryable:  Bool(true),
				Dependency: "guest-provider",
			},
		}
	case "running", "starting", "stopping":
		if action == "start" || action == "reboot" || action == "stop" {
			next.Transport = GuestRuntimeControlTransportObservation{State: "not-checked", ObservedAt: result.ObservedAt}
		}
	case "failed":
		// A provider effect failure does not prove a previously reachable Guest transport failed.
	}
	return next, nil
}

func ApplyGuestRuntimeControlTransportObservation(endpoint GuestRuntimeControlEndpoint, state string, observedAt string, issue *Issue) (GuestRuntimeControlEndpoint, error) {
	if state != "not-checked" && state != "reachable" && state != "unavailable" && state != "failed" {
		return GuestRuntimeControlEndpoint{}, fmt.Errorf("unsupported Guest Runtime Control transport observation state %q", state)
	}
	if (state == "unavailable" || state == "failed") && issue == nil {
		return GuestRuntimeControlEndpoint{}, fmt.Errorf("unavailable or failed Guest Runtime Control transport observation requires issue")
	}
	if (state == "not-checked" || state == "reachable") && issue != nil {
		return GuestRuntimeControlEndpoint{}, fmt.Errorf("successful or unchecked Guest Runtime Control transport observation must not carry issue")
	}
	next := endpoint
	next.ResourceRevision++
	next.Transport = GuestRuntimeControlTransportObservation{State: state, ObservedAt: observedAt, Issue: issue}
	next.UpdatedAt = observedAt
	return next, nil
}

func KnownPlatformProviderUnavailable(endpoint GuestRuntimeControlEndpoint) *Issue {
	switch endpoint.Provider.State {
	case "stopped":
		return &Issue{Code: "guest-provider-stopped", Message: "Host provider explicitly reports the Guest as stopped", Retryable: Bool(true), Dependency: "guest-provider"}
	case "unavailable":
		return &Issue{Code: "guest-provider-unavailable", Message: "Host provider explicitly reports the Guest as unavailable", Retryable: Bool(true), Dependency: "guest-provider"}
	default:
		return nil
	}
}

func CompleteLifecycleOperation(operation Operation, action string, result ProviderLifecycleResult, at string) (Operation, error) {
	want := "running"
	if action == "stop" {
		want = "stopped"
	}
	if result.ObservedState == want {
		return TransitionOperation(operation, "succeeded", at, nil)
	}
	issue := result.Issue
	if issue == nil {
		issue = &Issue{Code: "provider-did-not-reach-requested-state", Message: "provider observation did not reach the requested lifecycle state", Retryable: Bool(true), Dependency: "guest-provider"}
	}
	return TransitionOperation(operation, "failed", at, issue)
}

func SameInstallationConfiguration(existing PlatformInstallation, configured PlatformInstallation) bool {
	return existing.ID == configured.ID && existing.Release == configured.Release && existing.DataDirectory == configured.DataDirectory
}

func SameGuestRuntimeControlEndpointConfiguration(existing GuestRuntimeControlEndpoint, configured GuestRuntimeControlEndpoint) bool {
	return existing.ID == configured.ID && existing.Address == configured.Address && existing.Provider.Kind == configured.Provider.Kind && existing.Provider.ID == configured.Provider.ID
}
