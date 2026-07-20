// Package hostplatformstagedreleaseupdatedomain owns pure C68 validation and
// Host Platform transition policy. It performs no filesystem or service effect.
package hostplatformstagedreleaseupdatedomain

import (
	"fmt"
	"regexp"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

const (
	SchemaVersion                         = "v1"
	HostPlatformReleaseArchiveMedia       = "application/vnd.tirosh.vitalserver.host-platform-release+tar+gzip"
	OperationApply                        = "apply"
	OperationRollback                     = "rollback"
	StateReceived                         = "received"
	StateStaged                           = "staged"
	StateServicesQuiescing                = "services-quiescing"
	StateReleasePublishing                = "release-publishing"
	StateActivating                       = "activating"
	StateSucceeded                        = "succeeded"
	StateFailed                           = "failed"
	StateUnavailable                      = "unavailable"
	RecoveryActionReconcileCurrentRelease = "reconcile-current-release"
	RecoveryStateSucceeded                = "succeeded"
	RecoveryStateBlocked                  = "blocked"
	RecoveryStateFailed                   = "failed"
	RecoveryStateUnavailable              = "unavailable"
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type ReleaseTransition struct {
	ExpectedActiveReleaseID string `json:"expectedActiveReleaseId"`
	TargetReleaseID         string `json:"targetReleaseId"`
}
type ArchiveArtifact struct {
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
	MediaType string `json:"mediaType"`
}
type StagedReleaseUpdateCommand struct {
	SchemaVersion string            `json:"schemaVersion"`
	OperationID   string            `json:"operationId"`
	UpdateID      string            `json:"updateId"`
	Operation     string            `json:"operation"`
	Transition    ReleaseTransition `json:"transition"`
	Artifact      ArchiveArtifact   `json:"artifact"`
	RequestedAt   string            `json:"requestedAt"`
}
type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}
type StagedReleaseUpdateOperation struct {
	SchemaVersion string            `json:"schemaVersion"`
	OperationID   string            `json:"operationId"`
	UpdateID      string            `json:"updateId"`
	Operation     string            `json:"operation"`
	Transition    ReleaseTransition `json:"transition"`
	Artifact      ArchiveArtifact   `json:"artifact"`
	State         string            `json:"state"`
	ObservedAt    string            `json:"observedAt"`
	Issue         *Issue            `json:"issue,omitempty"`
	// LastDurableState is deliberately retained when a terminal failure is
	// recorded. It says what C68 had durably recorded before an effect could
	// have been interrupted; it does not claim that the external effect did or
	// did not complete.
	LastDurableState string `json:"lastDurableState,omitempty"`
}
type StagedReleaseRecoveryCommand struct {
	SchemaVersion string `json:"schemaVersion"`
	RecoveryID    string `json:"recoveryId"`
	OperationID   string `json:"operationId"`
	Action        string `json:"action"`
	RequestedAt   string `json:"requestedAt"`
}
type StagedReleaseRecoveryReceipt struct {
	SchemaVersion   string `json:"schemaVersion"`
	RecoveryID      string `json:"recoveryId"`
	OperationID     string `json:"operationId"`
	Action          string `json:"action"`
	State           string `json:"state"`
	ActiveReleaseID string `json:"activeReleaseId,omitempty"`
	ObservedAt      string `json:"observedAt"`
	Issue           *Issue `json:"issue,omitempty"`
}
type ActiveHostRelease struct {
	Manifest hostinstallationmanagerdomain.HostProductInstallationManifest `json:"-"`
}
type CandidateHostRelease struct {
	Manifest           hostinstallationmanagerdomain.HostProductInstallationManifest `json:"-"`
	CandidateDirectory string                                                        `json:"-"`
}

func ValidateCommand(value StagedReleaseUpdateCommand) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.OperationID) || !validIdentifier(value.UpdateID) || (value.Operation != OperationApply && value.Operation != OperationRollback) || value.RequestedAt == "" {
		return fmt.Errorf("C68 command identity is invalid")
	}
	if err := validateTransition(value.Transition); err != nil {
		return err
	}
	if !sha256Pattern.MatchString(value.Artifact.SHA256) || value.Artifact.SizeBytes < 1 || value.Artifact.MediaType != HostPlatformReleaseArchiveMedia {
		return fmt.Errorf("C68 archive artifact is invalid")
	}
	return nil
}
func ValidateOperation(value StagedReleaseUpdateOperation) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.OperationID) || !validIdentifier(value.UpdateID) || (value.Operation != OperationApply && value.Operation != OperationRollback) || value.ObservedAt == "" {
		return fmt.Errorf("C68 operation identity is invalid")
	}
	if err := validateTransition(value.Transition); err != nil {
		return err
	}
	if !sha256Pattern.MatchString(value.Artifact.SHA256) || value.Artifact.SizeBytes < 1 || value.Artifact.MediaType != HostPlatformReleaseArchiveMedia {
		return fmt.Errorf("C68 operation artifact is invalid")
	}
	switch value.State {
	case StateReceived, StateStaged, StateServicesQuiescing, StateReleasePublishing, StateActivating, StateSucceeded:
		if value.Issue != nil || value.LastDurableState != "" {
			return fmt.Errorf("non-failed C68 operation must not contain failure context")
		}
	case StateFailed, StateUnavailable:
		if value.Issue == nil || !validIssue(*value.Issue) || !validDurableState(value.LastDurableState) {
			return fmt.Errorf("failed or unavailable C68 operation requires an issue and last durable state")
		}
	default:
		return fmt.Errorf("C68 operation state is unsupported")
	}
	return nil
}
func NewOperation(command StagedReleaseUpdateCommand, state string, issue *Issue, observedAt string) (StagedReleaseUpdateOperation, error) {
	if err := ValidateCommand(command); err != nil {
		return StagedReleaseUpdateOperation{}, err
	}
	operation := StagedReleaseUpdateOperation{SchemaVersion: SchemaVersion, OperationID: command.OperationID, UpdateID: command.UpdateID, Operation: command.Operation, Transition: command.Transition, Artifact: command.Artifact, State: state, ObservedAt: observedAt, Issue: issue}
	if err := ValidateOperation(operation); err != nil {
		return StagedReleaseUpdateOperation{}, err
	}
	return operation, nil
}
func NewRecoveryReceipt(command StagedReleaseRecoveryCommand, state, activeReleaseID string, issue *Issue, observedAt string) (StagedReleaseRecoveryReceipt, error) {
	if err := ValidateRecoveryCommand(command); err != nil {
		return StagedReleaseRecoveryReceipt{}, err
	}
	receipt := StagedReleaseRecoveryReceipt{SchemaVersion: SchemaVersion, RecoveryID: command.RecoveryID, OperationID: command.OperationID, Action: command.Action, State: state, ActiveReleaseID: activeReleaseID, ObservedAt: observedAt, Issue: issue}
	if err := ValidateRecoveryReceipt(receipt); err != nil {
		return StagedReleaseRecoveryReceipt{}, err
	}
	return receipt, nil
}
func SameOperation(command StagedReleaseUpdateCommand, operation StagedReleaseUpdateOperation) bool {
	return operation.SchemaVersion == SchemaVersion && operation.OperationID == command.OperationID && operation.UpdateID == command.UpdateID && operation.Operation == command.Operation && operation.Transition == command.Transition && operation.Artifact == command.Artifact
}
func SameRecoveryCommand(command StagedReleaseRecoveryCommand, receipt StagedReleaseRecoveryReceipt) bool {
	return receipt.SchemaVersion == SchemaVersion && receipt.RecoveryID == command.RecoveryID && receipt.OperationID == command.OperationID && receipt.Action == command.Action
}

func ValidateRecoveryCommand(value StagedReleaseRecoveryCommand) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.RecoveryID) || !validIdentifier(value.OperationID) || value.Action != RecoveryActionReconcileCurrentRelease || value.RequestedAt == "" {
		return fmt.Errorf("C68 recovery command is invalid")
	}
	return nil
}
func ValidateRecoveryReceipt(value StagedReleaseRecoveryReceipt) error {
	if value.SchemaVersion != SchemaVersion || !validIdentifier(value.RecoveryID) || !validIdentifier(value.OperationID) || value.Action != RecoveryActionReconcileCurrentRelease || value.ObservedAt == "" {
		return fmt.Errorf("C68 recovery receipt identity is invalid")
	}
	switch value.State {
	case RecoveryStateSucceeded:
		if !validIdentifier(value.ActiveReleaseID) || value.Issue != nil {
			return fmt.Errorf("succeeded C68 recovery requires active release and no issue")
		}
	case RecoveryStateBlocked, RecoveryStateFailed, RecoveryStateUnavailable:
		if value.ActiveReleaseID != "" || value.Issue == nil || !validIssue(*value.Issue) {
			return fmt.Errorf("non-succeeded C68 recovery requires an issue and no active release")
		}
	default:
		return fmt.Errorf("C68 recovery state is unsupported")
	}
	return nil
}

// DecideAdmission checks complete explicit candidate and active-release facts.
// The target must keep the service and mutable-store topology stable; changing
// that topology is a separately designed Host migration, not archive fallback.
func DecideAdmission(command StagedReleaseUpdateCommand, candidate CandidateHostRelease, active ActiveHostRelease) error {
	if err := ValidateCommand(command); err != nil {
		return err
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductInstallationManifest(candidate.Manifest); err != nil {
		return fmt.Errorf("validate candidate C48: %w", err)
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductInstallationManifest(active.Manifest); err != nil {
		return fmt.Errorf("validate active C48: %w", err)
	}
	if active.Manifest.Platform != candidate.Manifest.Platform {
		return fmt.Errorf("C68 candidate and active Host platforms differ")
	}
	if candidate.Manifest.Release.ID != command.Transition.TargetReleaseID || active.Manifest.Release.ID != command.Transition.ExpectedActiveReleaseID {
		return fmt.Errorf("C68 release transition does not match active and candidate C48")
	}
	if candidate.Manifest.InstallationID != active.Manifest.InstallationID || candidate.Manifest.ImmutablePayload.ReleaseCatalogPath != active.Manifest.ImmutablePayload.ReleaseCatalogPath || candidate.Manifest.Activation.CurrentReleaseLinkPath != active.Manifest.Activation.CurrentReleaseLinkPath || candidate.Manifest.OperatorInterface.BootstrapConfigurationPath != active.Manifest.OperatorInterface.BootstrapConfigurationPath {
		return fmt.Errorf("C68 candidate changes the Host installation layout")
	}
	if candidate.Manifest.Package.Identifier != active.Manifest.Package.Identifier {
		return fmt.Errorf("C68 candidate changes the Host package identity")
	}
	if !sameServiceTopology(candidate.Manifest.RequiredServices, active.Manifest.RequiredServices) {
		return fmt.Errorf("C68 candidate changes Host service topology")
	}
	if !sameMutableStoreTopology(candidate.Manifest.MutableStores, active.Manifest.MutableStores) {
		return fmt.Errorf("C68 candidate changes Host mutable-store topology")
	}
	if candidate.CandidateDirectory == "" {
		return fmt.Errorf("C68 candidate directory is required")
	}
	return nil
}

// DecideRecoveryAdmission is intentionally narrower than an update retry.
// It permits an operator-requested reconciliation only where a prior C68
// effect may have quiesced services or changed `current`. It neither replays
// archive publication nor guesses whether an interrupted effect completed.
func DecideRecoveryAdmission(command StagedReleaseRecoveryCommand, prior StagedReleaseUpdateOperation, active ActiveHostRelease) *Issue {
	if err := ValidateRecoveryCommand(command); err != nil {
		return &Issue{Code: "recovery-command-invalid", Message: err.Error(), Dependency: "host-installation-manager"}
	}
	if err := ValidateOperation(prior); err != nil {
		return &Issue{Code: "prior-operation-invalid", Message: err.Error(), Dependency: "host-installation-manager"}
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductInstallationManifest(active.Manifest); err != nil {
		return &Issue{Code: "active-release-invalid", Message: err.Error(), Dependency: "host-installation-manager"}
	}
	if command.OperationID != prior.OperationID {
		return &Issue{Code: "recovery-operation-mismatch", Message: "recovery command does not name the persisted C68 operation", Dependency: "host-installation-manager"}
	}
	if prior.State != StateFailed && prior.State != StateUnavailable {
		return &Issue{Code: "recovery-not-required", Message: "only a failed or unavailable C68 operation can be recovered", Dependency: "host-installation-manager"}
	}
	switch prior.LastDurableState {
	case StateServicesQuiescing, StateReleasePublishing, StateActivating:
		// These are the only points at which a service quiesce or `current`
		// replacement might have happened. The current C48 is read below and
		// remains the only source of the selected release.
	default:
		return &Issue{Code: "recovery-not-required", Message: "the prior C68 operation had not reached a service-affecting boundary", Dependency: "host-installation-manager"}
	}
	if active.Manifest.Release.ID != prior.Transition.ExpectedActiveReleaseID && active.Manifest.Release.ID != prior.Transition.TargetReleaseID {
		return &Issue{Code: "recovery-current-release-unrelated", Message: "the current Host release is neither the declared source nor target of the failed C68 operation", Dependency: "host-installation-manager"}
	}
	return nil
}
func Failure(command StagedReleaseUpdateCommand, state, lastDurableState, code, message, dependency, observedAt string) StagedReleaseUpdateOperation {
	issue := &Issue{Code: code, Message: message, Dependency: dependency}
	operation := StagedReleaseUpdateOperation{SchemaVersion: SchemaVersion, OperationID: command.OperationID, UpdateID: command.UpdateID, Operation: command.Operation, Transition: command.Transition, Artifact: command.Artifact, State: state, ObservedAt: observedAt, Issue: issue, LastDurableState: lastDurableState}
	return operation
}
func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }
func validIssue(value Issue) bool       { return validIdentifier(value.Code) && value.Message != "" }
func validDurableState(value string) bool {
	switch value {
	case StateReceived, StateStaged, StateServicesQuiescing, StateReleasePublishing, StateActivating:
		return true
	default:
		return false
	}
}
func validateTransition(value ReleaseTransition) error {
	if !validIdentifier(value.ExpectedActiveReleaseID) || !validIdentifier(value.TargetReleaseID) || value.ExpectedActiveReleaseID == value.TargetReleaseID {
		return fmt.Errorf("C68 release transition is invalid")
	}
	return nil
}
func sameServiceTopology(left, right []hostinstallationmanagerdomain.HostProductRequiredService) bool {
	if len(left) != len(right) {
		return false
	}
	matched := map[string]hostinstallationmanagerdomain.HostProductRequiredService{}
	for _, item := range right {
		matched[item.Role] = item
	}
	for _, item := range left {
		other, ok := matched[item.Role]
		if !ok || item.Name != other.Name || item.Manager != other.Manager || item.DefinitionPath != other.DefinitionPath {
			return false
		}
	}
	return true
}
func sameMutableStoreTopology(left, right []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) bool {
	if len(left) != len(right) {
		return false
	}
	matched := map[string]hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{}
	for _, item := range right {
		matched[item.ID] = item
	}
	for _, item := range left {
		other, ok := matched[item.ID]
		if !ok || item.Path != other.Path || item.Kind != other.Kind || item.Owner != other.Owner || item.Retention != other.Retention {
			return false
		}
	}
	return true
}
