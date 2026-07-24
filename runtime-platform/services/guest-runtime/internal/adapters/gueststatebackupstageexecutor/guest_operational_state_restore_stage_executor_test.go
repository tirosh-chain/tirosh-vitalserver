package gueststatebackupstageexecutor

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupsqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestRestoreExecutorRecoversCompletedEffectsWithoutRepeatingMutation(
	t *testing.T,
) {
	ctx := context.Background()
	root := t.TempDir()
	destination := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-destination",
		ResourceID:   "restore-source-destination-1",
	}
	clock := fixedClock{now: time.Date(2026, 7, 24, 21, 0, 0, 0, time.UTC)}
	backupExecutor, err := New(
		Configuration{
			RootDirectory:        root,
			DestinationReference: destination,
		},
		fakeSQLiteSnapshotOwner{},
		fakePostgreSQLSnapshotOwner{},
		fakeArtifactInventoryOwner{},
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	backupLedger, err := gueststatebackupsqliterepository.Open(
		ctx,
		filepath.Join(root, "backup-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer backupLedger.Close()
	backupService, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		backupLedger,
		backupExecutor,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	backupOperation, err := backupService.AdmitBackup(
		ctx,
		guestruntimedomain.GuestOperationalStateBackupCommand{
			SchemaVersion:        guestruntimedomain.SchemaVersion,
			RequestID:            "restore-source-request-1",
			OperationID:          "restore-source-operation-1",
			DestinationReference: destination,
			RequestedAt:          "2026-07-24T20:59:59Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 5; index++ {
		var ran bool
		backupOperation, ran, err = backupService.RunNextPendingEffect(ctx)
		if err != nil || !ran {
			t.Fatalf("backup index=%d ran=%t err=%v", index, ran, err)
		}
	}
	if backupOperation.ManifestReference == nil {
		t.Fatalf("backup operation=%+v", backupOperation)
	}
	target := guestruntimedomain.ResourceReference{
		ResourceType: "guest-restore-target",
		ResourceID:   "empty-restore-target-1",
	}
	sqliteOwner := &fakeSQLiteRestoreOwner{}
	postgresqlOwner := &fakePostgreSQLRestoreOwner{}
	restoreExecutor, err := NewRestore(
		RestoreConfiguration{
			RootDirectory:   root,
			TargetReference: target,
		},
		sqliteOwner,
		postgresqlOwner,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	restoreLedger, err := gueststatebackupsqliterepository.Open(
		ctx,
		filepath.Join(root, "restore-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer restoreLedger.Close()
	restoreService, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		restoreLedger,
		restoreExecutor,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	restoreOperation, err := restoreService.AdmitRestore(
		ctx,
		guestruntimedomain.GuestOperationalStateRestoreCommand{
			SchemaVersion:     guestruntimedomain.SchemaVersion,
			RequestID:         "restore-request-1",
			OperationID:       "restore-operation-1",
			ManifestReference: *backupOperation.ManifestReference,
			ManifestSHA256:    backupOperation.ManifestSHA256,
			TargetReference:   target,
			RequestedAt:       "2026-07-24T20:59:59Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	stages := []string{
		guestruntimedomain.GuestStateRestoreBackupValidationStage,
		guestruntimedomain.GuestStateRestoreEmptyTargetProofStage,
		guestruntimedomain.GuestStateRestoreSQLiteStage,
		guestruntimedomain.GuestStateRestorePostgreSQLStage,
		guestruntimedomain.GuestStateRestoreOwnerReadVerificationStage,
	}
	for index := 0; index < 6; index++ {
		var ran bool
		restoreOperation, ran, err = restoreService.RunNextPendingEffect(ctx)
		if err != nil || !ran {
			t.Fatalf(
				"restore index=%d operation=%+v ran=%t err=%v",
				index,
				restoreOperation,
				ran,
				err,
			)
		}
		if index > 0 {
			recovered, recoverErr := restoreExecutor.ExecuteStage(
				ctx,
				restoreOperation,
				stages[index-1],
			)
			if recoverErr != nil ||
				recovered.Outcome != guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded {
				t.Fatalf(
					"recover stage=%s result=%+v err=%v",
					stages[index-1],
					recovered,
					recoverErr,
				)
			}
		}
	}
	if restoreOperation.State != guestruntimedomain.GuestStateBackupSucceededState ||
		sqliteOwner.restoreCalls != 1 ||
		postgresqlOwner.restoreCalls != 1 {
		t.Fatalf(
			"operation=%+v sqlite=%+v postgresql=%+v",
			restoreOperation,
			sqliteOwner,
			postgresqlOwner,
		)
	}
}

type fakeSQLiteRestoreOwner struct {
	restored     bool
	restoreCalls int
}

func (owner *fakeSQLiteRestoreOwner) ProveEmpty(
	context.Context,
) (guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof, error) {
	return guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof{
		State: guestruntimedomain.GuestOperationalStateSQLiteRestoreTargetAbsent,
	}, nil
}

func (owner *fakeSQLiteRestoreOwner) Restore(
	_ context.Context,
	_ string,
	expected guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
) (guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt, error) {
	owner.restored = true
	owner.restoreCalls++
	return expected, nil
}

func (owner *fakeSQLiteRestoreOwner) Verify(
	context.Context,
	guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
) (guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof, error) {
	if !owner.restored {
		return guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof{},
			&restoreRejection{
				code:    "sqlite-restore-not-complete",
				message: "SQLite restore has not completed",
			}
	}
	return guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof{
		LedgerIdentityReadSucceeded: true,
	}, nil
}

type fakePostgreSQLRestoreOwner struct {
	restored     bool
	restoreCalls int
}

func (owner *fakePostgreSQLRestoreOwner) ProveEmptyTarget(
	context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof, error) {
	return guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof{
		State: guestruntimedomain.GuestOperationalStatePostgreSQLRestoreTargetEmpty,
	}, nil
}

func (owner *fakePostgreSQLRestoreOwner) RestoreSnapshot(
	_ context.Context,
	_ string,
	_ gueststatepostgresqlrestore.Snapshot,
) error {
	owner.restored = true
	owner.restoreCalls++
	return nil
}

func (owner *fakePostgreSQLRestoreOwner) VerifyOwnerReads(
	context.Context,
	gueststatepostgresqlrestore.Snapshot,
) (guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof, error) {
	if !owner.restored {
		return guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof{},
			&restoreRejection{
				code:    "postgresql-restore-not-complete",
				message: "PostgreSQL restore has not completed",
			}
	}
	return guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof{
		IdentityReadSucceeded:                   true,
		RecorderCurrentProjectionReadSucceeded:  true,
		RecorderExpectationReadSucceeded:        true,
		RecorderObservationHistoryReadSucceeded: true,
		ArchiveArtifactAttributionReadSucceeded: true,
		ArchiveUploadIndexReceiptsReadSucceeded: true,
		RecorderAssignmentEvidenceReadSucceeded: true,
	}, nil
}
