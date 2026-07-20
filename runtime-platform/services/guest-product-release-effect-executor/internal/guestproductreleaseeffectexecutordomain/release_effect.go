// Package guestproductreleaseeffectexecutordomain owns pure C61 validation
// and C59-to-C55 outcome mapping. It reads no Host file, network, time, or
// process state.
package guestproductreleaseeffectexecutordomain

import (
	"fmt"
	"path"
	"regexp"
	"strings"
)

const (
	SchemaVersion                       = "v1"
	GuestProductReleaseManagerMediaType = "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"
	GuestProductReleaseManagerPath      = "/v1/guest-product-release-updates"
	UpdateOperationApply                = "apply"
	UpdateOperationRollback             = "rollback"
	ReceiptStateSucceeded               = "succeeded"
	ReceiptStateFailed                  = "failed"
	ReceiptStateUnavailable             = "unavailable"
	ReceiptStateUnsupported             = "unsupported"
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type GuestProductReleaseEffectExecutorConfiguration struct {
	SchemaVersion                      string                              `json:"schemaVersion"`
	EffectExecutorID                   string                              `json:"effectExecutorId"`
	GuestProductReleaseManagerEndpoint GuestProductReleaseManagerEndpoint  `json:"guestProductReleaseManagerEndpoint"`
	Apply                              GuestProductReleaseOperationIntent  `json:"apply"`
	Rollback                           *GuestProductReleaseOperationIntent `json:"rollback,omitempty"`
}

type GuestProductReleaseManagerEndpoint struct {
	Scheme                     string `json:"scheme"`
	Host                       string `json:"host"`
	Port                       int    `json:"port"`
	Path                       string `json:"path"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
}

type GuestProductReleaseOperationIntent struct {
	ExpectedActiveReleaseID string `json:"expectedActiveReleaseId"`
	TargetReleaseID         string `json:"targetReleaseId"`
	TargetReleaseDirectory  string `json:"targetReleaseDirectory"`
}

// FixedProtocolInvocation is the entire C26 invocation supplied by the Host
// updater. The executable uses no environment variable, sibling-file lookup,
// current-link read, or inferred endpoint as input.
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

type GuestProductReleaseUpdateCommand struct {
	SchemaVersion           string                    `json:"schemaVersion"`
	UpdateID                string                    `json:"updateId"`
	ExpectedActiveReleaseID string                    `json:"expectedActiveReleaseId"`
	TargetRelease           GuestProductReleaseTarget `json:"targetRelease"`
	RequestedAt             string                    `json:"requestedAt"`
}

type GuestProductReleaseTarget struct {
	ReleaseID        string                      `json:"releaseId"`
	ReleaseDirectory string                      `json:"releaseDirectory"`
	Artifact         GuestProductReleaseArtifact `json:"artifact"`
}

type GuestProductReleaseArtifact struct {
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
	MediaType string `json:"mediaType"`
}

type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type GuestProductReleaseOperation struct {
	SchemaVersion           string                    `json:"schemaVersion"`
	UpdateID                string                    `json:"updateId"`
	ExpectedActiveReleaseID string                    `json:"expectedActiveReleaseId"`
	TargetRelease           GuestProductReleaseTarget `json:"targetRelease"`
	State                   string                    `json:"state"`
	ActiveReleaseID         string                    `json:"activeReleaseId,omitempty"`
	ObservedAt              string                    `json:"observedAt"`
	Issue                   *Issue                    `json:"issue,omitempty"`
}

// GuestProductReleaseManagerRequestFailure is an adapter-reported C59 request
// outcome for which no C59 operation document was obtained. Its state and
// issue are explicit so the application does not collapse transport,
// rejection, and malformed-response failures into one generic outcome.
type GuestProductReleaseManagerRequestFailure struct {
	State string
	Issue Issue
}

func (failure GuestProductReleaseManagerRequestFailure) Error() string {
	return failure.Issue.Message
}

func ValidateGuestProductReleaseManagerRequestFailure(failure GuestProductReleaseManagerRequestFailure) error {
	if (failure.State != ReceiptStateFailed && failure.State != ReceiptStateUnavailable) || !validIssue(&failure.Issue) {
		return fmt.Errorf("C59 request failure state or issue is invalid")
	}
	return nil
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

type EvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

func ValidateConfiguration(configuration GuestProductReleaseEffectExecutorConfiguration) error {
	if configuration.SchemaVersion != SchemaVersion || !validIdentifier(configuration.EffectExecutorID) {
		return fmt.Errorf("C61 schema version and effect executor id are required")
	}
	endpoint := configuration.GuestProductReleaseManagerEndpoint
	if endpoint.Scheme != "http" || endpoint.Host != "127.0.0.1" || endpoint.Port < 1 || endpoint.Port > 65535 || endpoint.Path != GuestProductReleaseManagerPath || endpoint.RequestTimeoutMilliseconds < 1 || endpoint.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("C61 Guest Product Release Manager endpoint is invalid")
	}
	if err := validateIntent(configuration.Apply); err != nil {
		return fmt.Errorf("C61 apply release intent is invalid: %w", err)
	}
	if configuration.Rollback != nil {
		if err := validateIntent(*configuration.Rollback); err != nil {
			return fmt.Errorf("C61 rollback release intent is invalid: %w", err)
		}
		if configuration.Rollback.ExpectedActiveReleaseID != configuration.Apply.TargetReleaseID || configuration.Rollback.TargetReleaseID != configuration.Apply.ExpectedActiveReleaseID {
			return fmt.Errorf("C61 rollback release intent must reverse the declared apply release transition")
		}
	}
	return nil
}

func ValidateFixedProtocolInvocation(invocation FixedProtocolInvocation) error {
	if invocation.ProtocolVersion != SchemaVersion || !validIdentifier(invocation.EffectExecutorID) || !validIdentifier(invocation.UpdateID) || invocation.Layer != "guest-runtime" || (invocation.Operation != UpdateOperationApply && invocation.Operation != UpdateOperationRollback) || !sha256Pattern.MatchString(invocation.ArtifactSHA256) {
		return fmt.Errorf("C55 fixed protocol identity is invalid")
	}
	if invocation.EffectConfigurationPath == "" || !strings.HasPrefix(invocation.EffectConfigurationPath, "/") || invocation.ReceiptPath == "" || !strings.HasPrefix(invocation.ReceiptPath, "/") || invocation.ArtifactPath == "" || !strings.HasPrefix(invocation.ArtifactPath, "/") {
		return fmt.Errorf("C55 fixed protocol paths must be absolute")
	}
	return nil
}

func SelectIntent(configuration GuestProductReleaseEffectExecutorConfiguration, invocation FixedProtocolInvocation) (GuestProductReleaseOperationIntent, error) {
	if invocation.EffectExecutorID != configuration.EffectExecutorID {
		return GuestProductReleaseOperationIntent{}, fmt.Errorf("C55 effect executor id does not match C61 configuration")
	}
	switch invocation.Operation {
	case UpdateOperationApply:
		return configuration.Apply, nil
	case UpdateOperationRollback:
		if configuration.Rollback == nil {
			return GuestProductReleaseOperationIntent{}, fmt.Errorf("C61 does not declare a rollback release intent")
		}
		return *configuration.Rollback, nil
	default:
		return GuestProductReleaseOperationIntent{}, fmt.Errorf("C55 operation is unsupported")
	}
}

func NewGuestProductReleaseUpdateCommand(invocation FixedProtocolInvocation, intent GuestProductReleaseOperationIntent, artifact ReleaseArtifact, requestedAt string) (GuestProductReleaseUpdateCommand, error) {
	if err := validateIntent(intent); err != nil || artifact.Path == "" || artifact.SizeBytes < 1 || artifact.SHA256 != invocation.ArtifactSHA256 || !sha256Pattern.MatchString(artifact.SHA256) || requestedAt == "" {
		return GuestProductReleaseUpdateCommand{}, fmt.Errorf("C59 release command inputs are invalid")
	}
	return GuestProductReleaseUpdateCommand{
		SchemaVersion:           SchemaVersion,
		UpdateID:                invocation.UpdateID,
		ExpectedActiveReleaseID: intent.ExpectedActiveReleaseID,
		TargetRelease: GuestProductReleaseTarget{
			ReleaseID:        intent.TargetReleaseID,
			ReleaseDirectory: intent.TargetReleaseDirectory,
			Artifact:         GuestProductReleaseArtifact{SHA256: artifact.SHA256, SizeBytes: artifact.SizeBytes, MediaType: GuestProductReleaseManagerMediaType},
		},
		RequestedAt: requestedAt,
	}, nil
}

func OutcomeForGuestProductReleaseOperation(invocation FixedProtocolInvocation, command GuestProductReleaseUpdateCommand, operation GuestProductReleaseOperation, observedAt string) (StagedUpdateLayerEffectReceipt, error) {
	if operation.SchemaVersion != SchemaVersion || operation.UpdateID != command.UpdateID || operation.ExpectedActiveReleaseID != command.ExpectedActiveReleaseID || operation.TargetRelease.ReleaseID != command.TargetRelease.ReleaseID || operation.TargetRelease.ReleaseDirectory != command.TargetRelease.ReleaseDirectory || operation.TargetRelease.Artifact != command.TargetRelease.Artifact || operation.ObservedAt == "" || observedAt == "" {
		return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 operation does not match the submitted release command")
	}
	receipt := baseReceipt(invocation, observedAt)
	receipt.Evidence = EvidenceReference{Kind: "guest-product-release-operation", ID: operation.UpdateID}
	switch operation.State {
	case "succeeded":
		if operation.Issue != nil || operation.ActiveReleaseID != command.TargetRelease.ReleaseID {
			return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 succeeded operation does not prove the target active release")
		}
		receipt.State = ReceiptStateSucceeded
	case "rolled-back":
		receipt.State = ReceiptStateFailed
		receipt.Issue = &Issue{Code: "guest-product-release-rolled-back", Message: "Guest Product release activation failed and C59 restored the previous release", Dependency: "guest-product-release-manager"}
	case "failed":
		if !validIssue(operation.Issue) {
			return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 failed operation requires its typed issue")
		}
		receipt.State = ReceiptStateFailed
		receipt.Issue = operation.Issue
	case "unavailable":
		if !validIssue(operation.Issue) {
			return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 unavailable operation requires its typed issue")
		}
		receipt.State = ReceiptStateUnavailable
		receipt.Issue = operation.Issue
	case "received", "staged", "applying", "rollback-applying":
		receipt.State = ReceiptStateUnavailable
		receipt.Issue = &Issue{Code: "guest-product-release-operation-not-terminal", Message: "Guest Product Release Manager returned a non-terminal operation", Dependency: "guest-product-release-manager"}
	default:
		return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 operation state is unsupported")
	}
	return receipt, nil
}

func FailureReceipt(invocation FixedProtocolInvocation, state string, code string, message string, dependency string, observedAt string) StagedUpdateLayerEffectReceipt {
	receipt := baseReceipt(invocation, observedAt)
	receipt.State = state
	receipt.Evidence = EvidenceReference{Kind: "guest-product-release-effect-executor", ID: invocation.UpdateID}
	receipt.Issue = &Issue{Code: code, Message: message, Dependency: dependency}
	return receipt
}

func baseReceipt(invocation FixedProtocolInvocation, observedAt string) StagedUpdateLayerEffectReceipt {
	return StagedUpdateLayerEffectReceipt{SchemaVersion: SchemaVersion, UpdateID: invocation.UpdateID, Layer: invocation.Layer, EffectExecutorID: invocation.EffectExecutorID, Operation: invocation.Operation, ArtifactSHA256: invocation.ArtifactSHA256, ObservedAt: observedAt}
}

func validateIntent(intent GuestProductReleaseOperationIntent) error {
	if !validIdentifier(intent.ExpectedActiveReleaseID) || !validIdentifier(intent.TargetReleaseID) || intent.ExpectedActiveReleaseID == intent.TargetReleaseID || path.Clean(intent.TargetReleaseDirectory) != "/opt/vitalserver/releases/"+intent.TargetReleaseID {
		return fmt.Errorf("release ids and target release directory must be explicit and consistent")
	}
	return nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

func validIssue(issue *Issue) bool {
	return issue != nil && validIdentifier(issue.Code) && issue.Message != ""
}
