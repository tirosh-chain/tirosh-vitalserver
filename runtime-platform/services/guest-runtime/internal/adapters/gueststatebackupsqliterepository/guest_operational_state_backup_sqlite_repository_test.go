package gueststatebackupsqliterepository

import (
	"context"
	"errors"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestRepositoryPreservesPendingEffectAcrossRestart(t *testing.T) {
	ctx := context.Background()
	databasePath := filepath.Join(t.TempDir(), "backup-workflow.sqlite")
	repository, err := Open(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	command := backupCommand(
		"backup-request-restart-1",
		"backup-operation-restart-1",
		"2026-07-24T20:00:00Z",
	)
	admission, err := guestruntimedomain.NewGuestOperationalStateBackupOperation(command)
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.AdmitOperation(
		ctx,
		"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		admission.Next,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); err != nil {
		t.Fatal(err)
	}
	stored, err := repository.ReadOperationByRequestID(ctx, command.RequestID)
	if err != nil {
		t.Fatal(err)
	}
	decision, err := guestruntimedomain.DecideGuestOperationalStateBackupTransition(
		stored,
		guestruntimedomain.GuestOperationalStateBackupEvent{
			Kind:       guestruntimedomain.GuestStateBackupWorkflowStartedEvent,
			OccurredAt: "2026-07-24T20:00:01Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.CommitTransition(
		ctx,
		stored,
		decision.Next,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
		decision.Effect,
	); err != nil {
		t.Fatal(err)
	}
	if err := repository.Close(); err != nil {
		t.Fatal(err)
	}

	repository, err = Open(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	pending, err := repository.ListPendingEffects(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 1 ||
		pending[0].Effect != guestruntimedomain.GuestStateBackupSQLiteSnapshotStage ||
		pending[0].Operation.ResourceRevision != 2 ||
		pending[0].Operation.State != guestruntimedomain.GuestStateBackupSnapshottingSQLiteState {
		t.Fatalf("pending effects after restart=%+v", pending)
	}
	readByID, err := repository.ReadOperation(ctx, command.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	if readByID.ResourceRevision != decision.Next.ResourceRevision ||
		readByID.State != decision.Next.State {
		t.Fatalf("stored operation=%+v decision=%+v", readByID, decision.Next)
	}
	if err := repository.CommitTransition(
		ctx,
		stored,
		decision.Next,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
		decision.Effect,
	); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict) {
		t.Fatalf("stale transition error=%v", err)
	}
}

func TestRepositoryRejectsOperationAndRequestIdentityConflicts(t *testing.T) {
	ctx := context.Background()
	repository, err := Open(ctx, filepath.Join(t.TempDir(), "backup-workflow.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	first := mustBackupOperation(
		t,
		backupCommand("backup-request-conflict-1", "backup-operation-conflict-1", "2026-07-24T21:00:00Z"),
	)
	if err := repository.AdmitOperation(
		ctx,
		"1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		first,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); err != nil {
		t.Fatal(err)
	}
	sameRequest := mustBackupOperation(
		t,
		backupCommand("backup-request-conflict-1", "backup-operation-conflict-2", "2026-07-24T21:00:01Z"),
	)
	if err := repository.AdmitOperation(
		ctx,
		"2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		sameRequest,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict) {
		t.Fatalf("same request conflict error=%v", err)
	}
	sameOperation := mustBackupOperation(
		t,
		backupCommand("backup-request-conflict-2", "backup-operation-conflict-1", "2026-07-24T21:00:02Z"),
	)
	if err := repository.AdmitOperation(
		ctx,
		"3123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		sameOperation,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict) {
		t.Fatalf("same operation conflict error=%v", err)
	}
}

func TestRepositoryReportsStoredDocumentDecodeFailure(t *testing.T) {
	ctx := context.Background()
	repository, err := Open(ctx, filepath.Join(t.TempDir(), "backup-workflow.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	operation := mustBackupOperation(
		t,
		backupCommand("backup-request-corrupt-1", "backup-operation-corrupt-1", "2026-07-24T22:00:00Z"),
	)
	if err := repository.AdmitOperation(
		ctx,
		"4123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		operation,
		guestruntimedomain.GuestStateBackupStartWorkflowEffect,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.database.ExecContext(
		ctx,
		`UPDATE backup_operations SET document_json = document_json || '{}' WHERE id = ?`,
		operation.ID,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := repository.ReadOperation(ctx, operation.ID); err == nil {
		t.Fatal("corrupt stored operation unexpectedly decoded")
	}
}

func backupCommand(
	requestID string,
	operationID string,
	requestedAt string,
) guestruntimedomain.GuestOperationalStateBackupCommand {
	return guestruntimedomain.GuestOperationalStateBackupCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     requestID,
		OperationID:   operationID,
		DestinationReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-backup-destination",
			ResourceID:   "backup-destination-test-1",
		},
		RequestedAt: requestedAt,
	}
}

func mustBackupOperation(
	t *testing.T,
	command guestruntimedomain.GuestOperationalStateBackupCommand,
) guestruntimedomain.GuestOperationalStateBackupOperation {
	t.Helper()
	decision, err := guestruntimedomain.NewGuestOperationalStateBackupOperation(command)
	if err != nil {
		t.Fatal(err)
	}
	return decision.Next
}
