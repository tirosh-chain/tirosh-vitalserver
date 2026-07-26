// Package guestbundledupstreamimageseteffectexecutordomain owns pure C66
// validation and C64-to-C55 mapping. It reads no Host file or network state.
package guestbundledupstreamimageseteffectexecutordomain

import (
	"fmt"
	"regexp"
)

const (
	SchemaVersion = "v1"
	ImageSetArchiveMediaType = "application/vnd.tirosh.vitalserver.bundled-upstream-image-set+tar+gzip"
	ImageSetManagerPath = "/v1/bundled-upstream-image-set-updates"
	UpdateOperationApply = "apply"
	UpdateOperationRollback = "rollback"
	ReceiptStateSucceeded = "succeeded"
	ReceiptStateFailed = "failed"
	ReceiptStateUnavailable = "unavailable"
	ReceiptStateUnsupported = "unsupported"
)

var (identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`); sha256Pattern = regexp.MustCompile(`^[a-f0-9]{64}$`))

type ActiveImageSetSelection struct { State string `json:"state"`; ImageSetID string `json:"imageSetId,omitempty"` }
type ImageSetManagerEndpoint struct { Scheme string `json:"scheme"`; Host string `json:"host"`; Port int `json:"port"`; Path string `json:"path"`; RequestTimeoutMilliseconds int `json:"requestTimeoutMilliseconds"` }
type ImageSetOperationIntent struct { ExpectedActiveImageSet ActiveImageSetSelection `json:"expectedActiveImageSet"`; TargetImageSetID string `json:"targetImageSetId"` }
type ImageSetEffectExecutorConfiguration struct { SchemaVersion string `json:"schemaVersion"`; EffectExecutorID string `json:"effectExecutorId"`; ImageSetManagerEndpoint ImageSetManagerEndpoint `json:"imageSetManagerEndpoint"`; Apply ImageSetOperationIntent `json:"apply"`; Rollback *ImageSetOperationIntent `json:"rollback,omitempty"` }
type FixedProtocolInvocation struct { ProtocolVersion string; EffectExecutorID string; EffectConfigurationPath string; ReceiptPath string; UpdateID string; Layer string; Operation string; ArtifactPath string; ArtifactSHA256 string }
type ImageSetArtifact struct { SHA256 string `json:"sha256"`; SizeBytes int64 `json:"sizeBytes"`; MediaType string `json:"mediaType"` }
type ImageSetTarget struct { ImageSetID string `json:"imageSetId"`; Artifact ImageSetArtifact `json:"artifact"` }
type ImageSetUpdateCommand struct { SchemaVersion string `json:"schemaVersion"`; UpdateID string `json:"updateId"`; ExpectedActiveImageSet ActiveImageSetSelection `json:"expectedActiveImageSet"`; TargetImageSet ImageSetTarget `json:"targetImageSet"`; RequestedAt string `json:"requestedAt"` }
type Issue struct { Code string `json:"code"`; Message string `json:"message,omitempty"`; Retryable *bool `json:"retryable,omitempty"`; Dependency string `json:"dependency,omitempty"` }
type ImageSetOperation struct { SchemaVersion string `json:"schemaVersion"`; UpdateID string `json:"updateId"`; ExpectedActiveImageSet ActiveImageSetSelection `json:"expectedActiveImageSet"`; TargetImageSet ImageSetTarget `json:"targetImageSet"`; State string `json:"state"`; ActiveImageSet *ActiveImageSetSelection `json:"activeImageSet,omitempty"`; ObservedAt string `json:"observedAt"`; Issue *Issue `json:"issue,omitempty"` }
type ImageSetManagerRequestFailure struct { State string; Issue Issue }
func (failure ImageSetManagerRequestFailure) Error() string { return failure.Issue.Message }
type ReleaseArtifact struct { Path string; SHA256 string; SizeBytes int64 }
type EvidenceReference struct { Kind string `json:"kind"`; ID string `json:"id"` }
type StagedUpdateLayerEffectReceipt struct { SchemaVersion string `json:"schemaVersion"`; UpdateID string `json:"updateId"`; Layer string `json:"layer"`; EffectExecutorID string `json:"effectExecutorId"`; Operation string `json:"operation"`; ArtifactSHA256 string `json:"artifactSha256"`; State string `json:"state"`; ObservedAt string `json:"observedAt"`; Evidence EvidenceReference `json:"evidence"`; Issue *Issue `json:"issue,omitempty"` }

func ValidateConfiguration(value ImageSetEffectExecutorConfiguration) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.EffectExecutorID) { return fmt.Errorf("C66 schema version and effect executor id are required") }
	endpoint := value.ImageSetManagerEndpoint
	if endpoint.Scheme != "http" || endpoint.Host != "127.0.0.1" || endpoint.Port < 1 || endpoint.Port > 65535 || endpoint.Path != ImageSetManagerPath || endpoint.RequestTimeoutMilliseconds < 1 || endpoint.RequestTimeoutMilliseconds > 900000 { return fmt.Errorf("C66 image-set manager endpoint is invalid") }
	if err := validateIntent(value.Apply); err != nil { return fmt.Errorf("C66 apply image-set intent: %w", err) }
	if value.Rollback != nil {
		if err := validateIntent(*value.Rollback); err != nil { return fmt.Errorf("C66 rollback image-set intent: %w", err) }
		if value.Apply.TargetImageSetID != value.Rollback.ExpectedActiveImageSet.ImageSetID || value.Rollback.ExpectedActiveImageSet.State != "active" { return fmt.Errorf("C66 rollback must compare against the apply target image set") }
	}
	return nil
}

func ValidateFixedProtocolInvocation(value FixedProtocolInvocation) error {
	if value.ProtocolVersion != SchemaVersion || !validIdentifier(value.EffectExecutorID) || value.EffectConfigurationPath == "" || value.ReceiptPath == "" || !validIdentifier(value.UpdateID) || value.Layer != "bundled-upstream" || (value.Operation != UpdateOperationApply && value.Operation != UpdateOperationRollback) || value.ArtifactPath == "" || !sha256Pattern.MatchString(value.ArtifactSHA256) { return fmt.Errorf("C55 fixed C66 invocation is invalid") }
	return nil
}

func SelectIntent(configuration ImageSetEffectExecutorConfiguration, invocation FixedProtocolInvocation) (ImageSetOperationIntent, error) {
	if invocation.EffectExecutorID != configuration.EffectExecutorID { return ImageSetOperationIntent{}, fmt.Errorf("C55 effect executor id does not match C66 configuration") }
	switch invocation.Operation { case UpdateOperationApply: return configuration.Apply, nil; case UpdateOperationRollback: if configuration.Rollback == nil { return ImageSetOperationIntent{}, fmt.Errorf("C66 rollback was not declared") }; return *configuration.Rollback, nil; default: return ImageSetOperationIntent{}, fmt.Errorf("C55 operation is unsupported") }
}

func NewImageSetUpdateCommand(invocation FixedProtocolInvocation, intent ImageSetOperationIntent, artifact ReleaseArtifact, requestedAt string) (ImageSetUpdateCommand, error) {
	if err := ValidateFixedProtocolInvocation(invocation); err != nil { return ImageSetUpdateCommand{}, err }
	if err := validateIntent(intent); err != nil || artifact.Path == "" || artifact.SHA256 != invocation.ArtifactSHA256 || artifact.SizeBytes < 1 || requestedAt == "" { return ImageSetUpdateCommand{}, fmt.Errorf("C66 image-set update command inputs are invalid") }
	return ImageSetUpdateCommand{SchemaVersion: SchemaVersion, UpdateID: invocation.UpdateID, ExpectedActiveImageSet: intent.ExpectedActiveImageSet, TargetImageSet: ImageSetTarget{ImageSetID: intent.TargetImageSetID, Artifact: ImageSetArtifact{SHA256: artifact.SHA256, SizeBytes: artifact.SizeBytes, MediaType: ImageSetArchiveMediaType}}, RequestedAt: requestedAt}, nil
}

func ValidateImageSetManagerRequestFailure(value ImageSetManagerRequestFailure) error { if (value.State != ReceiptStateFailed && value.State != ReceiptStateUnavailable) || !validIssue(&value.Issue) { return fmt.Errorf("C64 request failure state or issue is invalid") }; return nil }

func OutcomeForImageSetOperation(invocation FixedProtocolInvocation, command ImageSetUpdateCommand, operation ImageSetOperation, observedAt string) (StagedUpdateLayerEffectReceipt, error) {
	if operation.SchemaVersion != SchemaVersion || operation.UpdateID != command.UpdateID || operation.ExpectedActiveImageSet != command.ExpectedActiveImageSet || operation.TargetImageSet != command.TargetImageSet || operation.ObservedAt == "" { return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C64 operation does not correlate to C66 command") }
	switch operation.State {
	case "succeeded":
		if operation.ActiveImageSet == nil || operation.ActiveImageSet.State != "active" || operation.ActiveImageSet.ImageSetID != command.TargetImageSet.ImageSetID || operation.Issue != nil { return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C64 succeeded operation is invalid") }
		return receipt(invocation, ReceiptStateSucceeded, observedAt, nil), nil
	case "failed", "unavailable":
		if !validIssue(operation.Issue) { return StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C64 terminal operation issue is invalid") }
		state := ReceiptStateFailed; if operation.State == "unavailable" { state = ReceiptStateUnavailable }; return receipt(invocation, state, observedAt, operation.Issue), nil
	default:
		return receipt(invocation, ReceiptStateUnsupported, observedAt, &Issue{Code: "image-set-operation-incomplete", Message: "C64 returned a nonterminal image-set operation", Dependency: "guest-bundled-upstream-image-set-manager"}), nil
	}
}

func FailureReceipt(invocation FixedProtocolInvocation, state, code, message, dependency, observedAt string) StagedUpdateLayerEffectReceipt { return receipt(invocation, state, observedAt, &Issue{Code: code, Message: message, Dependency: dependency}) }
func receipt(invocation FixedProtocolInvocation, state, observedAt string, issue *Issue) StagedUpdateLayerEffectReceipt { return StagedUpdateLayerEffectReceipt{SchemaVersion: SchemaVersion, UpdateID: invocation.UpdateID, Layer: invocation.Layer, EffectExecutorID: invocation.EffectExecutorID, Operation: invocation.Operation, ArtifactSHA256: invocation.ArtifactSHA256, State: state, ObservedAt: observedAt, Evidence: EvidenceReference{Kind: "guest-bundled-upstream-image-set-operation", ID: invocation.UpdateID}, Issue: issue} }
func validateIntent(value ImageSetOperationIntent) error { if err := validateSelection(value.ExpectedActiveImageSet); err != nil || !validIdentifier(value.TargetImageSetID) { return fmt.Errorf("intent is invalid") }; if value.ExpectedActiveImageSet.State == "active" && value.ExpectedActiveImageSet.ImageSetID == value.TargetImageSetID { return fmt.Errorf("target cannot equal expected active image set") }; return nil }
func validateSelection(value ActiveImageSetSelection) error { switch value.State { case "unprovisioned": if value.ImageSetID != "" { return fmt.Errorf("unprovisioned selection cannot name image set") }; case "active": if !validIdentifier(value.ImageSetID) { return fmt.Errorf("active selection requires image set id") }; default: return fmt.Errorf("selection state unsupported") }; return nil }
func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }
func validIssue(value *Issue) bool { return value != nil && validIdentifier(value.Code) && value.Message != "" }
