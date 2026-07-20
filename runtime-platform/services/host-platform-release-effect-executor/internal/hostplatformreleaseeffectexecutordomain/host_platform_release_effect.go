// Package hostplatformreleaseeffectexecutordomain owns pure C67/C68 and C55
// mapping. It has no Host filesystem, process, or package-manager dependency.
package hostplatformreleaseeffectexecutordomain

import (
	"fmt"
	"regexp"
)

const (
	SchemaVersion                   = "v1"
	HostPlatformReleaseArchiveMedia = "application/vnd.tirosh.vitalserver.host-platform-release+tar+gzip"
	OperationApply                  = "apply"
	OperationRollback               = "rollback"
	ReceiptStateSucceeded           = "succeeded"
	ReceiptStateFailed              = "failed"
	ReceiptStateUnavailable         = "unavailable"
	ReceiptStateUnsupported         = "unsupported"
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type HostInstallationManagerEndpoint struct {
	Platform                   string `json:"platform"`
	ExecutablePath             string `json:"executablePath"`
	ActiveReleaseManifestPath  string `json:"activeReleaseManifestPath"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
}

type ReleaseTransitionIntent struct {
	ExpectedActiveReleaseID string `json:"expectedActiveReleaseId"`
	TargetReleaseID         string `json:"targetReleaseId"`
}

type EffectExecutorConfiguration struct {
	SchemaVersion           string                          `json:"schemaVersion"`
	EffectExecutorID        string                          `json:"effectExecutorId"`
	HostInstallationManager HostInstallationManagerEndpoint `json:"hostInstallationManager"`
	Apply                   ReleaseTransitionIntent         `json:"apply"`
	Rollback                *ReleaseTransitionIntent        `json:"rollback,omitempty"`
}

type FixedProtocolInvocation struct {
	ProtocolVersion         string
	EffectExecutorID        string
	EffectConfigurationPath string
	ReceiptPath             string
	UpdateID                string
	Layer                   string
	Operation               string
	ArtifactPath            string
	ArtifactSHA256          string
}

type ReleaseArtifact struct {
	Path      string
	SHA256    string
	SizeBytes int64
}

type HostPlatformReleaseArtifact struct {
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
	MediaType string `json:"mediaType"`
}

type HostPlatformStagedReleaseUpdateCommand struct {
	SchemaVersion string                      `json:"schemaVersion"`
	OperationID   string                      `json:"operationId"`
	UpdateID      string                      `json:"updateId"`
	Operation     string                      `json:"operation"`
	Transition    ReleaseTransitionIntent     `json:"transition"`
	Artifact      HostPlatformReleaseArtifact `json:"artifact"`
	RequestedAt   string                      `json:"requestedAt"`
}

type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type HostPlatformStagedReleaseUpdateOperation struct {
	SchemaVersion string                      `json:"schemaVersion"`
	OperationID   string                      `json:"operationId"`
	UpdateID      string                      `json:"updateId"`
	Operation     string                      `json:"operation"`
	Transition    ReleaseTransitionIntent     `json:"transition"`
	Artifact      HostPlatformReleaseArtifact `json:"artifact"`
	State         string                      `json:"state"`
	ObservedAt    string                      `json:"observedAt"`
	Issue         *Issue                      `json:"issue,omitempty"`
}

type HostPlatformReleaseManagerRequestFailure struct {
	State string
	Issue Issue
}

func (failure HostPlatformReleaseManagerRequestFailure) Error() string { return failure.Issue.Message }

type EvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}
type StagedUpdateLayerEffectReceipt struct {
	SchemaVersion    string            `json:"schemaVersion"`
	UpdateID         string            `json:"updateId"`
	Layer            string            `json:"layer"`
	EffectExecutorID string            `json:"effectExecutorId"`
	Operation        string            `json:"operation"`
	ArtifactSHA256   string            `json:"artifactSha256"`
	State            string            `json:"state"`
	ObservedAt       string            `json:"observedAt"`
	Evidence         EvidenceReference `json:"evidence"`
	Issue            *Issue            `json:"issue,omitempty"`
}

func ValidateConfiguration(value EffectExecutorConfiguration) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.EffectExecutorID) {
		return fmt.Errorf("C67 schema version and effect executor id are required")
	}
	if err := validateEndpoint(value.HostInstallationManager); err != nil {
		return err
	}
	if err := validateTransition(value.Apply); err != nil {
		return fmt.Errorf("C67 apply transition: %w", err)
	}
	if value.Rollback != nil {
		if err := validateTransition(*value.Rollback); err != nil {
			return fmt.Errorf("C67 rollback transition: %w", err)
		}
		if value.Rollback.ExpectedActiveReleaseID != value.Apply.TargetReleaseID {
			return fmt.Errorf("C67 rollback must compare against the apply target release")
		}
	}
	return nil
}

func ValidateFixedProtocolInvocation(value FixedProtocolInvocation) error {
	if value.ProtocolVersion != SchemaVersion || !validIdentifier(value.EffectExecutorID) || value.EffectConfigurationPath == "" || value.ReceiptPath == "" || !validIdentifier(value.UpdateID) || value.Layer != "host-platform" || (value.Operation != OperationApply && value.Operation != OperationRollback) || value.ArtifactPath == "" || !sha256Pattern.MatchString(value.ArtifactSHA256) {
		return fmt.Errorf("C55 fixed C67 invocation is invalid")
	}
	return nil
}

func SelectTransition(configuration EffectExecutorConfiguration, invocation FixedProtocolInvocation) (ReleaseTransitionIntent, error) {
	if invocation.EffectExecutorID != configuration.EffectExecutorID {
		return ReleaseTransitionIntent{}, fmt.Errorf("C55 effect executor id does not match C67 configuration")
	}
	switch invocation.Operation {
	case OperationApply:
		return configuration.Apply, nil
	case OperationRollback:
		if configuration.Rollback == nil {
			return ReleaseTransitionIntent{}, fmt.Errorf("C67 rollback was not declared")
		}
		return *configuration.Rollback, nil
	default:
		return ReleaseTransitionIntent{}, fmt.Errorf("C55 operation is unsupported")
	}
}

func NewHostPlatformStagedReleaseUpdateCommand(invocation FixedProtocolInvocation, transition ReleaseTransitionIntent, artifact ReleaseArtifact, requestedAt string) (HostPlatformStagedReleaseUpdateCommand, error) {
	if err := ValidateFixedProtocolInvocation(invocation); err != nil {
		return HostPlatformStagedReleaseUpdateCommand{}, err
	}
	if err := validateTransition(transition); err != nil || artifact.Path == "" || artifact.SHA256 != invocation.ArtifactSHA256 || artifact.SizeBytes < 1 || requestedAt == "" {
		return HostPlatformStagedReleaseUpdateCommand{}, fmt.Errorf("C68 command inputs are invalid")
	}
	return HostPlatformStagedReleaseUpdateCommand{SchemaVersion: SchemaVersion, OperationID: invocation.UpdateID + "-host-platform-" + invocation.Operation, UpdateID: invocation.UpdateID, Operation: invocation.Operation, Transition: transition, Artifact: HostPlatformReleaseArtifact{SHA256: artifact.SHA256, SizeBytes: artifact.SizeBytes, MediaType: HostPlatformReleaseArchiveMedia}, RequestedAt: requestedAt}, nil
}

func ValidateHostPlatformReleaseManagerRequestFailure(value HostPlatformReleaseManagerRequestFailure) error {
	if (value.State != ReceiptStateFailed && value.State != ReceiptStateUnavailable) || !validIssue(value.Issue) {
		return fmt.Errorf("Host Platform manager request failure is invalid")
	}
	return nil
}

func OutcomeForHostPlatformOperation(invocation FixedProtocolInvocation, command HostPlatformStagedReleaseUpdateCommand, operation HostPlatformStagedReleaseUpdateOperation, observedAt string) (StagedUpdateLayerEffectReceipt, error) {
	if operation.SchemaVersion != SchemaVersion || operation.OperationID != command.OperationID || operation.UpdateID != command.UpdateID || operation.Operation != command.Operation || operation.Transition != command.Transition || operation.Artifact != command.Artifact || operation.ObservedAt == "" {
		return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C68 operation does not correlate to C67 command")
	}
	switch operation.State {
	case "succeeded":
		if operation.Issue != nil {
			return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C68 succeeded operation must not carry an issue")
		}
		return receipt(invocation, ReceiptStateSucceeded, observedAt, nil), nil
	case "failed", "unavailable":
		if operation.Issue == nil || !validIssue(*operation.Issue) {
			return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C68 terminal operation issue is invalid")
		}
		state := ReceiptStateFailed
		if operation.State == "unavailable" {
			state = ReceiptStateUnavailable
		}
		return receipt(invocation, state, observedAt, operation.Issue), nil
	default:
		return receipt(invocation, ReceiptStateUnsupported, observedAt, &Issue{Code: "host-platform-operation-incomplete", Message: "C68 returned a nonterminal Host Platform operation", Dependency: "host-installation-manager"}), nil
	}
}

func FailureReceipt(invocation FixedProtocolInvocation, state, code, message, dependency, observedAt string) StagedUpdateLayerEffectReceipt {
	return receipt(invocation, state, observedAt, &Issue{Code: code, Message: message, Dependency: dependency})
}
func receipt(invocation FixedProtocolInvocation, state, observedAt string, issue *Issue) StagedUpdateLayerEffectReceipt {
	return StagedUpdateLayerEffectReceipt{SchemaVersion: SchemaVersion, UpdateID: invocation.UpdateID, Layer: invocation.Layer, EffectExecutorID: invocation.EffectExecutorID, Operation: invocation.Operation, ArtifactSHA256: invocation.ArtifactSHA256, State: state, ObservedAt: observedAt, Evidence: EvidenceReference{Kind: "host-platform-staged-release-operation", ID: invocation.UpdateID + "-host-platform-" + invocation.Operation}, Issue: issue}
}

func validateEndpoint(value HostInstallationManagerEndpoint) error {
	if value.RequestTimeoutMilliseconds < 1 || value.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("C67 Host Installation Manager timeout is invalid")
	}
	switch value.Platform {
	case "macos":
		if value.ExecutablePath != "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager" || value.ActiveReleaseManifestPath != "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json" {
			return fmt.Errorf("C67 macOS Host Installation Manager endpoint is invalid")
		}
	case "windows":
		if value.ExecutablePath != "C:\\ProgramData\\VitalServerRuntimePlatform\\current\\bin\\host-installation-manager.exe" || value.ActiveReleaseManifestPath != "C:\\ProgramData\\VitalServerRuntimePlatform\\current\\installation-manifest.json" {
			return fmt.Errorf("C67 Windows Host Installation Manager endpoint is invalid")
		}
	case "linux":
		if value.ExecutablePath != "/opt/vitalserver-runtime-platform/current/bin/host-installation-manager" || value.ActiveReleaseManifestPath != "/opt/vitalserver-runtime-platform/current/installation-manifest.json" {
			return fmt.Errorf("C67 Linux Host Installation Manager endpoint is invalid")
		}
	default:
		return fmt.Errorf("C67 Host Installation Manager platform is unsupported")
	}
	return nil
}
func validateTransition(value ReleaseTransitionIntent) error {
	if !validIdentifier(value.ExpectedActiveReleaseID) || !validIdentifier(value.TargetReleaseID) || value.ExpectedActiveReleaseID == value.TargetReleaseID {
		return fmt.Errorf("release transition is invalid")
	}
	return nil
}
func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }
func validIssue(value Issue) bool       { return validIdentifier(value.Code) && value.Message != "" }
