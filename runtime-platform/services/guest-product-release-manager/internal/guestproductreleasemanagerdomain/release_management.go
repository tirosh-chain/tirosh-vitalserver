// Package guestproductreleasemanagerdomain defines the pure C59 Guest Product
// release transition policy. It neither reads a Guest directory nor runs
// systemctl; those effects remain behind application ports.
package guestproductreleasemanagerdomain

import (
	"fmt"
	"path"
	"regexp"
	"strings"
)

const SchemaVersion = "v1"

const (
	OperationStateReceived         = "received"
	OperationStateStaged           = "staged"
	OperationStateApplying         = "applying"
	OperationStateSucceeded        = "succeeded"
	OperationStateRollbackApplying = "rollback-applying"
	OperationStateRolledBack       = "rolled-back"
	OperationStateFailed           = "failed"
	OperationStateUnavailable      = "unavailable"
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

// Issue reports one external dependency or data failure without mapping it to
// a successful or empty release operation.
type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	Dependency string `json:"dependency,omitempty"`
}

// ReleaseArtifact identifies the complete compressed release archive that a
// caller streams beside a C59 command. The manager validates byte identity
// before it extracts anything under the immutable release root.
type ReleaseArtifact struct {
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
	MediaType string `json:"mediaType"`
}

type ReleaseTarget struct {
	ReleaseID        string          `json:"releaseId"`
	ReleaseDirectory string          `json:"releaseDirectory"`
	Artifact         ReleaseArtifact `json:"artifact"`
}

// ReleaseReference is the exact existing Guest release selected for an
// activation or restoration. It intentionally has no archive identity: an
// already staged release is selected by its declared immutable directory.
type ReleaseReference struct {
	ReleaseID        string
	ReleaseDirectory string
}

// GuestProductReleaseUpdateCommand is C59 command metadata. Its archive
// bytes are deliberately a separate request part: base64 JSON would make the
// control contract an accidental release-transport implementation.
type GuestProductReleaseUpdateCommand struct {
	SchemaVersion           string        `json:"schemaVersion"`
	UpdateID                string        `json:"updateId"`
	ExpectedActiveReleaseID string        `json:"expectedActiveReleaseId"`
	TargetRelease           ReleaseTarget `json:"targetRelease"`
	RequestedAt             string        `json:"requestedAt"`
}

// GuestProductReleaseOperation is C59 durable manager-owned state. A
// rolled-back operation still carries the original failure issue; rollback is
// recovery evidence, not erased evidence of a failed target release.
type GuestProductReleaseOperation struct {
	SchemaVersion           string        `json:"schemaVersion"`
	UpdateID                string        `json:"updateId"`
	ExpectedActiveReleaseID string        `json:"expectedActiveReleaseId"`
	TargetRelease           ReleaseTarget `json:"targetRelease"`
	State                   string        `json:"state"`
	ActiveReleaseID         string        `json:"activeReleaseId,omitempty"`
	ObservedAt              string        `json:"observedAt"`
	Issue                   *Issue        `json:"issue,omitempty"`
}

// ManagerConfiguration is the C59 deployment subset the manager itself
// needs. Network listener composition belongs to the command adapter, while
// this pure model protects the release and state ownership boundaries.
type ManagerConfiguration struct {
	ManagerID                      string
	ReleaseDirectoryRoot           string
	CurrentReleaseLinkPath         string
	StagingDirectory               string
	StateDirectory                 string
	StateDirectoryMode             string
	MaximumReleaseArtifactBytes    int64
	SystemctlExecutablePath        string
	ManagedServiceUnitName         string
	RestartTimeoutMilliseconds     int
	HealthCheckURL                 string
	HealthCheckTimeoutMilliseconds int
	HealthCheckAcceptedStatusCodes []int
}

// LoopbackListener is the only listener the release manager itself can bind.
// C37 later decides whether another Guest component publishes a separate,
// authenticated Host-facing route; this manager never listens on a LAN address.
type LoopbackListener struct {
	BindHost string
	Port     int
}

func ValidateLoopbackListener(listener LoopbackListener) error {
	if listener.BindHost != "127.0.0.1" || listener.Port < 1 || listener.Port > 65535 {
		return fmt.Errorf("C59 Guest Product Release Manager listener must be an explicit loopback address and port")
	}
	return nil
}

func ValidateManagerConfiguration(configuration ManagerConfiguration) error {
	if !validIdentifier(configuration.ManagerID) ||
		!safeAbsolutePath(configuration.ReleaseDirectoryRoot) ||
		!safeAbsolutePath(configuration.CurrentReleaseLinkPath) ||
		!safeAbsolutePath(configuration.StagingDirectory) ||
		!safeAbsolutePath(configuration.StateDirectory) ||
		configuration.StateDirectoryMode != "0700" || configuration.MaximumReleaseArtifactBytes < 1 ||
		!safeAbsolutePath(configuration.SystemctlExecutablePath) || configuration.ManagedServiceUnitName != "vitalserver-guest-product.service" ||
		configuration.RestartTimeoutMilliseconds < 1 || configuration.RestartTimeoutMilliseconds > 600000 ||
		configuration.HealthCheckURL == "" || configuration.HealthCheckTimeoutMilliseconds < 1 || configuration.HealthCheckTimeoutMilliseconds > 600000 ||
		len(configuration.HealthCheckAcceptedStatusCodes) == 0 {
		return fmt.Errorf("C59 Guest Product Release Manager configuration is invalid")
	}
	if path.Dir(configuration.CurrentReleaseLinkPath) != path.Dir(configuration.ReleaseDirectoryRoot) ||
		configuration.ReleaseDirectoryRoot == configuration.StagingDirectory ||
		configuration.ReleaseDirectoryRoot == configuration.StateDirectory ||
		configuration.StagingDirectory == configuration.StateDirectory {
		return fmt.Errorf("C59 release, staging, state, and current-link paths must be distinct declared ownership roots")
	}
	statuses := map[int]struct{}{}
	for _, status := range configuration.HealthCheckAcceptedStatusCodes {
		if status < 100 || status > 599 {
			return fmt.Errorf("C59 health check accepted status code is invalid")
		}
		if _, exists := statuses[status]; exists {
			return fmt.Errorf("C59 health check accepted status codes must be unique")
		}
		statuses[status] = struct{}{}
	}
	return nil
}

func ValidateReleaseUpdateCommand(configuration ManagerConfiguration, command GuestProductReleaseUpdateCommand) error {
	if err := ValidateManagerConfiguration(configuration); err != nil {
		return err
	}
	if command.SchemaVersion != SchemaVersion || !validIdentifier(command.UpdateID) || !validIdentifier(command.ExpectedActiveReleaseID) || command.RequestedAt == "" || !validIdentifier(command.TargetRelease.ReleaseID) ||
		command.TargetRelease.ReleaseDirectory != path.Join(configuration.ReleaseDirectoryRoot, command.TargetRelease.ReleaseID) ||
		!sha256Pattern.MatchString(command.TargetRelease.Artifact.SHA256) || command.TargetRelease.Artifact.SizeBytes < 1 || command.TargetRelease.Artifact.SizeBytes > configuration.MaximumReleaseArtifactBytes || command.TargetRelease.Artifact.MediaType != "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip" {
		return fmt.Errorf("C59 Guest Product release update command is invalid")
	}
	return nil
}

func ValidateReleaseOperation(configuration ManagerConfiguration, operation GuestProductReleaseOperation) error {
	command := GuestProductReleaseUpdateCommand{SchemaVersion: operation.SchemaVersion, UpdateID: operation.UpdateID, ExpectedActiveReleaseID: operation.ExpectedActiveReleaseID, TargetRelease: operation.TargetRelease, RequestedAt: operation.ObservedAt}
	if err := ValidateReleaseUpdateCommand(configuration, command); err != nil || operation.ObservedAt == "" {
		return fmt.Errorf("C59 Guest Product release operation identity is invalid")
	}
	switch operation.State {
	case OperationStateReceived, OperationStateStaged, OperationStateApplying, OperationStateRollbackApplying:
		if operation.ActiveReleaseID != "" || operation.Issue != nil {
			return fmt.Errorf("C59 active release transition must not claim an outcome")
		}
	case OperationStateSucceeded:
		if operation.ActiveReleaseID != operation.TargetRelease.ReleaseID || operation.Issue != nil {
			return fmt.Errorf("C59 succeeded release operation must name the target active release without issue")
		}
	case OperationStateRolledBack:
		if operation.ActiveReleaseID != operation.ExpectedActiveReleaseID || !validIssue(operation.Issue) {
			return fmt.Errorf("C59 rolled-back release operation must name the restored release and original issue")
		}
	case OperationStateFailed, OperationStateUnavailable:
		if operation.ActiveReleaseID != "" || !validIssue(operation.Issue) {
			return fmt.Errorf("C59 failed or unavailable release operation requires an issue and no active-release claim")
		}
	default:
		return fmt.Errorf("C59 Guest Product release operation state is unsupported")
	}
	return nil
}

func NewReleaseOperation(command GuestProductReleaseUpdateCommand, observedAt string) GuestProductReleaseOperation {
	return GuestProductReleaseOperation{SchemaVersion: SchemaVersion, UpdateID: command.UpdateID, ExpectedActiveReleaseID: command.ExpectedActiveReleaseID, TargetRelease: command.TargetRelease, State: OperationStateReceived, ObservedAt: observedAt}
}

func MarkReleaseStaged(operation GuestProductReleaseOperation, observedAt string) (GuestProductReleaseOperation, error) {
	return transition(operation, OperationStateReceived, OperationStateStaged, observedAt, "", nil)
}

func BeginReleaseActivation(operation GuestProductReleaseOperation, observedAt string) (GuestProductReleaseOperation, error) {
	return transition(operation, OperationStateStaged, OperationStateApplying, observedAt, "", nil)
}

func CompleteReleaseActivation(operation GuestProductReleaseOperation, observedAt string) (GuestProductReleaseOperation, error) {
	return transition(operation, OperationStateApplying, OperationStateSucceeded, observedAt, operation.TargetRelease.ReleaseID, nil)
}

func BeginReleaseRollback(operation GuestProductReleaseOperation, observedAt string, issue Issue) (GuestProductReleaseOperation, error) {
	if !validIssue(&issue) {
		return GuestProductReleaseOperation{}, fmt.Errorf("C59 rollback requires the target release failure issue")
	}
	return transition(operation, OperationStateApplying, OperationStateRollbackApplying, observedAt, "", &issue)
}

func CompleteReleaseRollback(operation GuestProductReleaseOperation, observedAt string) (GuestProductReleaseOperation, error) {
	if operation.State != OperationStateRollbackApplying || !validIssue(operation.Issue) || observedAt == "" {
		return GuestProductReleaseOperation{}, fmt.Errorf("C59 rollback completion requires an applying rollback and its original issue")
	}
	operation.State = OperationStateRolledBack
	operation.ActiveReleaseID = operation.ExpectedActiveReleaseID
	operation.ObservedAt = observedAt
	return operation, nil
}

func FailReleaseOperation(operation GuestProductReleaseOperation, observedAt string, state string, issue Issue) (GuestProductReleaseOperation, error) {
	if observedAt == "" || !validIssue(&issue) || (state != OperationStateFailed && state != OperationStateUnavailable) {
		return GuestProductReleaseOperation{}, fmt.Errorf("C59 terminal release failure is invalid")
	}
	switch operation.State {
	case OperationStateReceived, OperationStateStaged, OperationStateApplying, OperationStateRollbackApplying:
		operation.State = state
		operation.ActiveReleaseID = ""
		operation.ObservedAt = observedAt
		operation.Issue = &issue
		return operation, nil
	default:
		return GuestProductReleaseOperation{}, fmt.Errorf("C59 terminal release failure cannot replace a terminal operation")
	}
}

func SameReleaseUpdateCommand(operation GuestProductReleaseOperation, command GuestProductReleaseUpdateCommand) bool {
	return operation.UpdateID == command.UpdateID && operation.ExpectedActiveReleaseID == command.ExpectedActiveReleaseID && operation.TargetRelease == command.TargetRelease
}

func transition(operation GuestProductReleaseOperation, expected string, next string, observedAt string, activeReleaseID string, issue *Issue) (GuestProductReleaseOperation, error) {
	if operation.State != expected || observedAt == "" {
		return GuestProductReleaseOperation{}, fmt.Errorf("C59 invalid release operation transition from %q to %q", operation.State, next)
	}
	operation.State = next
	operation.ActiveReleaseID = activeReleaseID
	operation.ObservedAt = observedAt
	operation.Issue = issue
	return operation, nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

func safeAbsolutePath(value string) bool {
	return len(value) > 1 && strings.HasPrefix(value, "/") && path.Clean(value) == value && !strings.Contains(value, "..")
}

func validIssue(issue *Issue) bool { return issue != nil && issue.Code != "" && issue.Message != "" }
