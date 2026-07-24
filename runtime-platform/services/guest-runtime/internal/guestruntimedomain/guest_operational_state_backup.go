package guestruntimedomain

import (
	"fmt"
	"time"
)

const (
	GuestStateBackupKind  = "backup"
	GuestStateRestoreKind = "restore"

	GuestStateBackupRequestedState              = "requested"
	GuestStateBackupSnapshottingSQLiteState     = "snapshotting-sqlite"
	GuestStateBackupSnapshottingPostgreSQLState = "snapshotting-postgresql"
	GuestStateBackupInventoryingArtifactsState  = "inventorying-artifacts"
	GuestStateBackupPublishingState             = "publishing"
	GuestStateRestoreValidatingBackupState      = "validating-backup"
	GuestStateRestoreProvingEmptyTargetState    = "proving-empty-target"
	GuestStateRestoreRestoringSQLiteState       = "restoring-sqlite"
	GuestStateRestoreRestoringPostgreSQLState   = "restoring-postgresql"
	GuestStateRestoreVerifyingOwnerReadsState   = "verifying-owner-reads"
	GuestStateBackupSucceededState              = "succeeded"
	GuestStateBackupFailedState                 = "failed"

	GuestStateBackupWorkflowStartedEvent = "workflow-started"
	GuestStateBackupStageSucceededEvent  = "stage-succeeded"
	GuestStateBackupStageFailedEvent     = "stage-failed"

	GuestStateBackupStartWorkflowEffect         = "start-workflow"
	GuestStateBackupSQLiteSnapshotStage         = "sqlite-snapshot"
	GuestStateBackupPostgreSQLSnapshotStage     = "postgresql-snapshot"
	GuestStateBackupArtifactInventoryStage      = "artifact-inventory"
	GuestStateBackupManifestPublicationStage    = "manifest-publication"
	GuestStateRestoreBackupValidationStage      = "backup-validation"
	GuestStateRestoreEmptyTargetProofStage      = "empty-target-proof"
	GuestStateRestoreSQLiteStage                = "sqlite-restore"
	GuestStateRestorePostgreSQLStage            = "postgresql-restore"
	GuestStateRestoreOwnerReadVerificationStage = "owner-read-verification"
)

type GuestOperationalStateBackupCommand struct {
	SchemaVersion        string            `json:"schemaVersion"`
	RequestID            string            `json:"requestId"`
	OperationID          string            `json:"operationId"`
	DestinationReference ResourceReference `json:"destinationReference"`
	RequestedAt          string            `json:"requestedAt"`
}

type GuestOperationalStateRestoreCommand struct {
	SchemaVersion     string            `json:"schemaVersion"`
	RequestID         string            `json:"requestId"`
	OperationID       string            `json:"operationId"`
	ManifestReference ResourceReference `json:"manifestReference"`
	ManifestSHA256    string            `json:"manifestSha256"`
	TargetReference   ResourceReference `json:"targetReference"`
	RequestedAt       string            `json:"requestedAt"`
}

type GuestOperationalStateBackupStageReceipt struct {
	Stage             string            `json:"stage"`
	EvidenceReference ResourceReference `json:"evidenceReference"`
	EvidenceSHA256    string            `json:"evidenceSha256"`
	CompletedAt       string            `json:"completedAt"`
}

type GuestOperationalStateBackupFailure struct {
	Stage    string `json:"stage"`
	Code     string `json:"code"`
	Message  string `json:"message"`
	FailedAt string `json:"failedAt"`
}

type GuestOperationalStateBackupOperation struct {
	SchemaVersion        string                                    `json:"schemaVersion"`
	ID                   string                                    `json:"id"`
	RequestID            string                                    `json:"requestId"`
	ResourceRevision     int                                       `json:"resourceRevision"`
	Kind                 string                                    `json:"kind"`
	State                string                                    `json:"state"`
	DestinationReference *ResourceReference                        `json:"destinationReference,omitempty"`
	ManifestReference    *ResourceReference                        `json:"manifestReference,omitempty"`
	ManifestSHA256       string                                    `json:"manifestSha256,omitempty"`
	TargetReference      *ResourceReference                        `json:"targetReference,omitempty"`
	StageReceipts        []GuestOperationalStateBackupStageReceipt `json:"stageReceipts"`
	Failure              *GuestOperationalStateBackupFailure       `json:"failure,omitempty"`
	CreatedAt            string                                    `json:"createdAt"`
	UpdatedAt            string                                    `json:"updatedAt"`
}

type GuestOperationalStateBackupEvent struct {
	Kind              string
	OccurredAt        string
	StageReceipt      *GuestOperationalStateBackupStageReceipt
	Failure           *GuestOperationalStateBackupFailure
	ManifestReference *ResourceReference
	ManifestSHA256    string
}

type GuestOperationalStateBackupDecision struct {
	Next   GuestOperationalStateBackupOperation
	Effect string
}

func NewGuestOperationalStateBackupOperation(
	command GuestOperationalStateBackupCommand,
) (GuestOperationalStateBackupDecision, error) {
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) ||
		!ValidIdentifier(command.OperationID) ||
		!validResourceReference(command.DestinationReference) ||
		!validTimestamp(command.RequestedAt) {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup command is incomplete or invalid")
	}
	destination := command.DestinationReference
	return GuestOperationalStateBackupDecision{
		Next: GuestOperationalStateBackupOperation{
			SchemaVersion:        SchemaVersion,
			ID:                   command.OperationID,
			RequestID:            command.RequestID,
			ResourceRevision:     1,
			Kind:                 GuestStateBackupKind,
			State:                GuestStateBackupRequestedState,
			DestinationReference: &destination,
			StageReceipts:        []GuestOperationalStateBackupStageReceipt{},
			CreatedAt:            command.RequestedAt,
			UpdatedAt:            command.RequestedAt,
		},
	}, nil
}

func NewGuestOperationalStateRestoreOperation(
	command GuestOperationalStateRestoreCommand,
) (GuestOperationalStateBackupDecision, error) {
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) ||
		!ValidIdentifier(command.OperationID) ||
		!validResourceReference(command.ManifestReference) ||
		!validSHA256(command.ManifestSHA256) ||
		!validResourceReference(command.TargetReference) ||
		!validTimestamp(command.RequestedAt) {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state restore command is incomplete or invalid")
	}
	manifest := command.ManifestReference
	target := command.TargetReference
	return GuestOperationalStateBackupDecision{
		Next: GuestOperationalStateBackupOperation{
			SchemaVersion:     SchemaVersion,
			ID:                command.OperationID,
			RequestID:         command.RequestID,
			ResourceRevision:  1,
			Kind:              GuestStateRestoreKind,
			State:             GuestStateBackupRequestedState,
			ManifestReference: &manifest,
			ManifestSHA256:    command.ManifestSHA256,
			TargetReference:   &target,
			StageReceipts:     []GuestOperationalStateBackupStageReceipt{},
			CreatedAt:         command.RequestedAt,
			UpdatedAt:         command.RequestedAt,
		},
	}, nil
}

func DecideGuestOperationalStateBackupTransition(
	current GuestOperationalStateBackupOperation,
	event GuestOperationalStateBackupEvent,
) (GuestOperationalStateBackupDecision, error) {
	if err := ValidateGuestOperationalStateBackupOperation(current); err != nil {
		return GuestOperationalStateBackupDecision{}, err
	}
	if !validTimestamp(event.OccurredAt) {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup event time is invalid")
	}
	if current.State == GuestStateBackupSucceededState || current.State == GuestStateBackupFailedState {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup terminal state cannot transition")
	}
	if current.State == GuestStateBackupRequestedState {
		if event.Kind != GuestStateBackupWorkflowStartedEvent ||
			event.StageReceipt != nil ||
			event.Failure != nil {
			return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup requested state accepts only workflow-started")
		}
		next := advanceGuestStateBackup(current, event.OccurredAt)
		if current.Kind == GuestStateBackupKind {
			next.State = GuestStateBackupSnapshottingSQLiteState
			return GuestOperationalStateBackupDecision{Next: next, Effect: GuestStateBackupSQLiteSnapshotStage}, nil
		}
		next.State = GuestStateRestoreValidatingBackupState
		return GuestOperationalStateBackupDecision{Next: next, Effect: GuestStateRestoreBackupValidationStage}, nil
	}
	expectedStage, nextState, nextEffect, terminal := guestStateBackupActiveStage(current)
	if expectedStage == "" {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup state has no transition policy")
	}
	if event.Kind == GuestStateBackupStageFailedEvent {
		if event.Failure == nil ||
			event.Failure.Stage != expectedStage ||
			!ValidIdentifier(event.Failure.Code) ||
			event.Failure.Message == "" ||
			!validTimestamp(event.Failure.FailedAt) ||
			event.Failure.FailedAt != event.OccurredAt {
			return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup failure evidence is invalid")
		}
		next := advanceGuestStateBackup(current, event.OccurredAt)
		failure := *event.Failure
		next.Failure = &failure
		next.State = GuestStateBackupFailedState
		return GuestOperationalStateBackupDecision{Next: next}, nil
	}
	if event.Kind != GuestStateBackupStageSucceededEvent ||
		event.StageReceipt == nil ||
		event.Failure != nil ||
		event.StageReceipt.Stage != expectedStage ||
		event.StageReceipt.CompletedAt != event.OccurredAt ||
		!validGuestStateBackupStageReceipt(*event.StageReceipt) {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup stage receipt is invalid or out of order")
	}
	next := advanceGuestStateBackup(current, event.OccurredAt)
	next.StageReceipts = append(
		append([]GuestOperationalStateBackupStageReceipt{}, current.StageReceipts...),
		*event.StageReceipt,
	)
	next.State = nextState
	if terminal {
		if current.Kind == GuestStateBackupKind {
			if event.ManifestReference == nil ||
				!validResourceReference(*event.ManifestReference) ||
				!validSHA256(event.ManifestSHA256) ||
				event.StageReceipt.EvidenceReference != *event.ManifestReference ||
				event.StageReceipt.EvidenceSHA256 != event.ManifestSHA256 {
				return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup manifest publication evidence is required")
			}
			manifest := *event.ManifestReference
			next.ManifestReference = &manifest
			next.ManifestSHA256 = event.ManifestSHA256
		}
		return GuestOperationalStateBackupDecision{Next: next}, nil
	}
	if event.ManifestReference != nil || event.ManifestSHA256 != "" {
		return GuestOperationalStateBackupDecision{}, fmt.Errorf("Guest operational-state backup manifest evidence is only valid at publication")
	}
	return GuestOperationalStateBackupDecision{Next: next, Effect: nextEffect}, nil
}

func ValidateGuestOperationalStateBackupOperation(
	operation GuestOperationalStateBackupOperation,
) error {
	if operation.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(operation.ID) ||
		!ValidIdentifier(operation.RequestID) ||
		operation.ResourceRevision < 1 ||
		!validTimestamp(operation.CreatedAt) ||
		!validTimestamp(operation.UpdatedAt) {
		return fmt.Errorf("Guest operational-state backup operation identity is invalid")
	}
	if operation.Kind == GuestStateBackupKind {
		if operation.DestinationReference == nil ||
			!validResourceReference(*operation.DestinationReference) ||
			operation.TargetReference != nil ||
			(operation.State != GuestStateBackupSucceededState &&
				(operation.ManifestReference != nil || operation.ManifestSHA256 != "")) {
			return fmt.Errorf("Guest operational-state backup owner references are invalid")
		}
	} else if operation.Kind == GuestStateRestoreKind {
		if operation.DestinationReference != nil ||
			operation.ManifestReference == nil ||
			!validResourceReference(*operation.ManifestReference) ||
			!validSHA256(operation.ManifestSHA256) ||
			operation.TargetReference == nil ||
			!validResourceReference(*operation.TargetReference) {
			return fmt.Errorf("Guest operational-state restore owner references are invalid")
		}
	} else {
		return fmt.Errorf("Guest operational-state backup kind is invalid")
	}
	expectedStages := guestStateBackupStages(operation.Kind)
	if len(operation.StageReceipts) > len(expectedStages) {
		return fmt.Errorf("Guest operational-state backup stage receipt count is invalid")
	}
	for index, receipt := range operation.StageReceipts {
		if receipt.Stage != expectedStages[index] ||
			!validGuestStateBackupStageReceipt(receipt) {
			return fmt.Errorf("Guest operational-state backup stage receipt chronology is invalid")
		}
		if index > 0 && !timestampBeforeOrEqual(
			operation.StageReceipts[index-1].CompletedAt,
			receipt.CompletedAt,
		) {
			return fmt.Errorf("Guest operational-state backup stage receipt time is out of order")
		}
	}
	if operation.State == GuestStateBackupFailedState {
		if operation.Failure == nil ||
			len(operation.StageReceipts) >= len(expectedStages) ||
			operation.Failure.Stage != expectedStages[len(operation.StageReceipts)] ||
			!ValidIdentifier(operation.Failure.Code) ||
			operation.Failure.Message == "" ||
			!validTimestamp(operation.Failure.FailedAt) ||
			operation.UpdatedAt != operation.Failure.FailedAt ||
			operation.ResourceRevision != 3+len(operation.StageReceipts) {
			return fmt.Errorf("Guest operational-state backup failed state requires failure")
		}
		return nil
	}
	if operation.Failure != nil {
		return fmt.Errorf("Guest operational-state backup non-failed state cannot contain failure")
	}
	if operation.State == GuestStateBackupSucceededState {
		if len(operation.StageReceipts) != len(expectedStages) {
			return fmt.Errorf("Guest operational-state backup success requires every stage receipt")
		}
		if operation.Kind == GuestStateBackupKind &&
			(operation.ManifestReference == nil ||
				!validResourceReference(*operation.ManifestReference) ||
				!validSHA256(operation.ManifestSHA256) ||
				operation.StageReceipts[len(operation.StageReceipts)-1].EvidenceReference != *operation.ManifestReference ||
				operation.StageReceipts[len(operation.StageReceipts)-1].EvidenceSHA256 != operation.ManifestSHA256) {
			return fmt.Errorf("Guest operational-state backup success requires manifest evidence")
		}
		if operation.ResourceRevision != 2+len(operation.StageReceipts) ||
			operation.UpdatedAt != operation.StageReceipts[len(operation.StageReceipts)-1].CompletedAt {
			return fmt.Errorf("Guest operational-state backup success revision is invalid")
		}
		return nil
	}
	if !validGuestStateBackupNonterminalState(operation.Kind, operation.State) {
		return fmt.Errorf("Guest operational-state backup nonterminal state is invalid")
	}
	expectedReceiptCount := guestStateBackupExpectedReceiptCount(
		operation.Kind,
		operation.State,
	)
	if len(operation.StageReceipts) != expectedReceiptCount {
		return fmt.Errorf("Guest operational-state backup state and receipts disagree")
	}
	expectedRevision := 1
	if operation.State != GuestStateBackupRequestedState {
		expectedRevision = 2 + len(operation.StageReceipts)
	}
	if operation.ResourceRevision != expectedRevision {
		return fmt.Errorf("Guest operational-state backup state revision is invalid")
	}
	return nil
}

func guestStateBackupActiveStage(
	operation GuestOperationalStateBackupOperation,
) (stage string, nextState string, nextEffect string, terminal bool) {
	switch operation.State {
	case GuestStateBackupSnapshottingSQLiteState:
		return GuestStateBackupSQLiteSnapshotStage, GuestStateBackupSnapshottingPostgreSQLState, GuestStateBackupPostgreSQLSnapshotStage, false
	case GuestStateBackupSnapshottingPostgreSQLState:
		return GuestStateBackupPostgreSQLSnapshotStage, GuestStateBackupInventoryingArtifactsState, GuestStateBackupArtifactInventoryStage, false
	case GuestStateBackupInventoryingArtifactsState:
		return GuestStateBackupArtifactInventoryStage, GuestStateBackupPublishingState, GuestStateBackupManifestPublicationStage, false
	case GuestStateBackupPublishingState:
		return GuestStateBackupManifestPublicationStage, GuestStateBackupSucceededState, "", true
	case GuestStateRestoreValidatingBackupState:
		return GuestStateRestoreBackupValidationStage, GuestStateRestoreProvingEmptyTargetState, GuestStateRestoreEmptyTargetProofStage, false
	case GuestStateRestoreProvingEmptyTargetState:
		return GuestStateRestoreEmptyTargetProofStage, GuestStateRestoreRestoringSQLiteState, GuestStateRestoreSQLiteStage, false
	case GuestStateRestoreRestoringSQLiteState:
		return GuestStateRestoreSQLiteStage, GuestStateRestoreRestoringPostgreSQLState, GuestStateRestorePostgreSQLStage, false
	case GuestStateRestoreRestoringPostgreSQLState:
		return GuestStateRestorePostgreSQLStage, GuestStateRestoreVerifyingOwnerReadsState, GuestStateRestoreOwnerReadVerificationStage, false
	case GuestStateRestoreVerifyingOwnerReadsState:
		return GuestStateRestoreOwnerReadVerificationStage, GuestStateBackupSucceededState, "", true
	default:
		return "", "", "", false
	}
}

func GuestOperationalStateBackupEffectForState(
	operation GuestOperationalStateBackupOperation,
) (string, bool) {
	if operation.State == GuestStateBackupRequestedState {
		return GuestStateBackupStartWorkflowEffect, true
	}
	stage, _, _, _ := guestStateBackupActiveStage(operation)
	return stage, stage != ""
}

func guestStateBackupStages(kind string) []string {
	if kind == GuestStateBackupKind {
		return []string{
			GuestStateBackupSQLiteSnapshotStage,
			GuestStateBackupPostgreSQLSnapshotStage,
			GuestStateBackupArtifactInventoryStage,
			GuestStateBackupManifestPublicationStage,
		}
	}
	return []string{
		GuestStateRestoreBackupValidationStage,
		GuestStateRestoreEmptyTargetProofStage,
		GuestStateRestoreSQLiteStage,
		GuestStateRestorePostgreSQLStage,
		GuestStateRestoreOwnerReadVerificationStage,
	}
}

func validGuestStateBackupNonterminalState(kind string, state string) bool {
	if state == GuestStateBackupRequestedState {
		return true
	}
	if kind == GuestStateBackupKind {
		return state == GuestStateBackupSnapshottingSQLiteState ||
			state == GuestStateBackupSnapshottingPostgreSQLState ||
			state == GuestStateBackupInventoryingArtifactsState ||
			state == GuestStateBackupPublishingState
	}
	return state == GuestStateRestoreValidatingBackupState ||
		state == GuestStateRestoreProvingEmptyTargetState ||
		state == GuestStateRestoreRestoringSQLiteState ||
		state == GuestStateRestoreRestoringPostgreSQLState ||
		state == GuestStateRestoreVerifyingOwnerReadsState
}

func guestStateBackupExpectedReceiptCount(kind string, state string) int {
	states := []string{
		GuestStateBackupSnapshottingSQLiteState,
		GuestStateBackupSnapshottingPostgreSQLState,
		GuestStateBackupInventoryingArtifactsState,
		GuestStateBackupPublishingState,
	}
	if kind == GuestStateRestoreKind {
		states = []string{
			GuestStateRestoreValidatingBackupState,
			GuestStateRestoreProvingEmptyTargetState,
			GuestStateRestoreRestoringSQLiteState,
			GuestStateRestoreRestoringPostgreSQLState,
			GuestStateRestoreVerifyingOwnerReadsState,
		}
	}
	for index, candidate := range states {
		if state == candidate {
			return index
		}
	}
	return 0
}

func validGuestStateBackupStageReceipt(receipt GuestOperationalStateBackupStageReceipt) bool {
	return validGuestStateBackupStage(receipt.Stage) &&
		validResourceReference(receipt.EvidenceReference) &&
		validSHA256(receipt.EvidenceSHA256) &&
		validTimestamp(receipt.CompletedAt)
}

func validGuestStateBackupStage(stage string) bool {
	for _, candidate := range append(
		guestStateBackupStages(GuestStateBackupKind),
		guestStateBackupStages(GuestStateRestoreKind)...,
	) {
		if stage == candidate {
			return true
		}
	}
	return false
}

func validResourceReference(reference ResourceReference) bool {
	return ValidIdentifier(reference.ResourceType) &&
		ValidIdentifier(reference.ResourceID)
}

func advanceGuestStateBackup(
	current GuestOperationalStateBackupOperation,
	updatedAt string,
) GuestOperationalStateBackupOperation {
	next := current
	next.ResourceRevision++
	next.UpdatedAt = updatedAt
	return next
}

func timestampBeforeOrEqual(left string, right string) bool {
	leftTime, leftErr := time.Parse(time.RFC3339Nano, left)
	rightTime, rightErr := time.Parse(time.RFC3339Nano, right)
	return leftErr == nil &&
		rightErr == nil &&
		(leftTime.Before(rightTime) || leftTime.Equal(rightTime))
}
