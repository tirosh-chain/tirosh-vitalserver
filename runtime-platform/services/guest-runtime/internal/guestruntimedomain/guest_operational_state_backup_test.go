package guestruntimedomain

import "testing"

func TestGuestOperationalStateBackupRequiresOrderedReceiptsAndManifestEvidence(t *testing.T) {
	decision, err := NewGuestOperationalStateBackupOperation(
		GuestOperationalStateBackupCommand{
			SchemaVersion: SchemaVersion,
			RequestID:     "backup-request-1",
			OperationID:   "backup-operation-1",
			DestinationReference: ResourceReference{
				ResourceType: "guest-backup-destination",
				ResourceID:   "local-backup-1",
			},
			RequestedAt: "2026-07-24T18:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	current := decision.Next
	decision, err = DecideGuestOperationalStateBackupTransition(
		current,
		GuestOperationalStateBackupEvent{
			Kind:       GuestStateBackupWorkflowStartedEvent,
			OccurredAt: "2026-07-24T18:00:01Z",
		},
	)
	if err != nil || decision.Effect != GuestStateBackupSQLiteSnapshotStage {
		t.Fatalf("start decision=%+v err=%v", decision, err)
	}
	current = decision.Next
	ordered := []struct {
		stage string
		time  string
	}{
		{GuestStateBackupSQLiteSnapshotStage, "2026-07-24T18:00:02Z"},
		{GuestStateBackupPostgreSQLSnapshotStage, "2026-07-24T18:00:03Z"},
		{GuestStateBackupArtifactInventoryStage, "2026-07-24T18:00:04Z"},
		{GuestStateBackupManifestPublicationStage, "2026-07-24T18:00:05Z"},
	}
	for index, step := range ordered {
		receipt := backupStageReceipt(step.stage, step.time)
		event := GuestOperationalStateBackupEvent{
			Kind:         GuestStateBackupStageSucceededEvent,
			OccurredAt:   step.time,
			StageReceipt: &receipt,
		}
		if step.stage == GuestStateBackupManifestPublicationStage {
			manifest := ResourceReference{
				ResourceType: "guest-backup-manifest",
				ResourceID:   "backup-manifest-1",
			}
			event.ManifestReference = &manifest
			event.ManifestSHA256 = "b3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01"
			receipt.EvidenceReference = manifest
			receipt.EvidenceSHA256 = event.ManifestSHA256
			event.StageReceipt = &receipt
		}
		decision, err = DecideGuestOperationalStateBackupTransition(current, event)
		if err != nil {
			t.Fatalf("step %d: %v", index, err)
		}
		current = decision.Next
	}
	if current.State != GuestStateBackupSucceededState ||
		len(current.StageReceipts) != 4 ||
		current.ManifestReference == nil {
		t.Fatalf("backup terminal operation=%+v", current)
	}
	if err := ValidateGuestOperationalStateBackupOperation(current); err != nil {
		t.Fatal(err)
	}
}

func TestGuestOperationalStateBackupRejectsOutOfOrderAndTerminalTransitions(t *testing.T) {
	decision, err := NewGuestOperationalStateBackupOperation(
		GuestOperationalStateBackupCommand{
			SchemaVersion: SchemaVersion,
			RequestID:     "backup-request-2",
			OperationID:   "backup-operation-2",
			DestinationReference: ResourceReference{
				ResourceType: "guest-backup-destination",
				ResourceID:   "local-backup-2",
			},
			RequestedAt: "2026-07-24T18:10:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	decision, err = DecideGuestOperationalStateBackupTransition(
		decision.Next,
		GuestOperationalStateBackupEvent{
			Kind:       GuestStateBackupWorkflowStartedEvent,
			OccurredAt: "2026-07-24T18:10:01Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	wrong := backupStageReceipt(
		GuestStateBackupPostgreSQLSnapshotStage,
		"2026-07-24T18:10:02Z",
	)
	if _, err := DecideGuestOperationalStateBackupTransition(
		decision.Next,
		GuestOperationalStateBackupEvent{
			Kind:         GuestStateBackupStageSucceededEvent,
			OccurredAt:   wrong.CompletedAt,
			StageReceipt: &wrong,
		},
	); err == nil {
		t.Fatal("out-of-order stage receipt was accepted")
	}
	failure := GuestOperationalStateBackupFailure{
		Stage:    GuestStateBackupSQLiteSnapshotStage,
		Code:     "sqlite-snapshot-failed",
		Message:  "SQLite online snapshot failed",
		FailedAt: "2026-07-24T18:10:03Z",
	}
	failed, err := DecideGuestOperationalStateBackupTransition(
		decision.Next,
		GuestOperationalStateBackupEvent{
			Kind:       GuestStateBackupStageFailedEvent,
			OccurredAt: failure.FailedAt,
			Failure:    &failure,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if failed.Next.State != GuestStateBackupFailedState {
		t.Fatalf("failed operation=%+v", failed.Next)
	}
	if _, err := DecideGuestOperationalStateBackupTransition(
		failed.Next,
		GuestOperationalStateBackupEvent{
			Kind:       GuestStateBackupWorkflowStartedEvent,
			OccurredAt: "2026-07-24T18:10:04Z",
		},
	); err == nil {
		t.Fatal("terminal operation transitioned")
	}
}

func TestGuestOperationalStateRestoreRequiresEmptyTargetBeforeWrites(t *testing.T) {
	decision, err := NewGuestOperationalStateRestoreOperation(
		GuestOperationalStateRestoreCommand{
			SchemaVersion: SchemaVersion,
			RequestID:     "restore-request-1",
			OperationID:   "restore-operation-1",
			ManifestReference: ResourceReference{
				ResourceType: "guest-backup-manifest",
				ResourceID:   "backup-manifest-1",
			},
			ManifestSHA256: "c3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01",
			TargetReference: ResourceReference{
				ResourceType: "guest-restore-target",
				ResourceID:   "empty-target-1",
			},
			RequestedAt: "2026-07-24T19:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	decision, err = DecideGuestOperationalStateBackupTransition(
		decision.Next,
		GuestOperationalStateBackupEvent{
			Kind:       GuestStateBackupWorkflowStartedEvent,
			OccurredAt: "2026-07-24T19:00:01Z",
		},
	)
	if err != nil || decision.Effect != GuestStateRestoreBackupValidationStage {
		t.Fatalf("restore start=%+v err=%v", decision, err)
	}
	validation := backupStageReceipt(
		GuestStateRestoreBackupValidationStage,
		"2026-07-24T19:00:02Z",
	)
	decision, err = DecideGuestOperationalStateBackupTransition(
		decision.Next,
		GuestOperationalStateBackupEvent{
			Kind:         GuestStateBackupStageSucceededEvent,
			OccurredAt:   validation.CompletedAt,
			StageReceipt: &validation,
		},
	)
	if err != nil || decision.Effect != GuestStateRestoreEmptyTargetProofStage {
		t.Fatalf("restore validation=%+v err=%v", decision, err)
	}
	if decision.Next.State != GuestStateRestoreProvingEmptyTargetState {
		t.Fatalf("restore wrote before empty-target proof: %+v", decision.Next)
	}
}

func backupStageReceipt(
	stage string,
	completedAt string,
) GuestOperationalStateBackupStageReceipt {
	return GuestOperationalStateBackupStageReceipt{
		Stage: stage,
		EvidenceReference: ResourceReference{
			ResourceType: "guest-backup-stage-receipt",
			ResourceID:   stage + "-1",
		},
		EvidenceSHA256: "a3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01",
		CompletedAt:    completedAt,
	}
}
