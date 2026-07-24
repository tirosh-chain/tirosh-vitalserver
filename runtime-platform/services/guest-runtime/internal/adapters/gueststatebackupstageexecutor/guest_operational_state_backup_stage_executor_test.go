package gueststatebackupstageexecutor

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupsqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlbackup"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestBackupStageExecutorPublishesCompleteImmutableManifest(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	destination := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-destination",
		ResourceID:   "local-backup-test-1",
	}
	clock := fixedClock{now: time.Date(2026, 7, 24, 18, 0, 1, 0, time.UTC)}
	executor, err := New(
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
	ledger, err := gueststatebackupsqliterepository.Open(
		ctx,
		filepath.Join(root, "backup-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer ledger.Close()
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		ledger,
		executor,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	operation, err := service.AdmitBackup(
		ctx,
		guestruntimedomain.GuestOperationalStateBackupCommand{
			SchemaVersion:        guestruntimedomain.SchemaVersion,
			RequestID:            "backup-request-stage-executor-1",
			OperationID:          "backup-operation-stage-executor-1",
			DestinationReference: destination,
			RequestedAt:          "2026-07-24T18:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 5; index++ {
		var ran bool
		operation, ran, err = service.RunNextPendingEffect(ctx)
		if err != nil || !ran {
			t.Fatalf(
				"stage index=%d operation=%+v ran=%t err=%v",
				index,
				operation,
				ran,
				err,
			)
		}
	}
	if operation.State != guestruntimedomain.GuestStateBackupSucceededState ||
		operation.ManifestReference == nil ||
		len(operation.StageReceipts) != 4 {
		t.Fatalf("terminal operation=%+v", operation)
	}
	manifestPath := filepath.Join(
		root,
		"manifests",
		operation.ManifestReference.ResourceID+".json",
	)
	var manifest guestruntimedomain.GuestOperationalStateBackupManifest
	if err := decodeStrictJSONFile(manifestPath, &manifest); err != nil {
		t.Fatal(err)
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupManifest(manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.ObjectBytesIncluded ||
		len(manifest.PostgreSQLSnapshot.IncludedOwnerSchemas) != 4 ||
		manifest.ArtifactInventory.ArtifactCount != 1 {
		t.Fatalf("manifest=%+v", manifest)
	}
}

func TestBackupStageExecutorRejectsUnconfiguredDestination(t *testing.T) {
	root := t.TempDir()
	executor, err := New(
		Configuration{
			RootDirectory: root,
			DestinationReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-destination",
				ResourceID:   "configured-destination-1",
			},
		},
		fakeSQLiteSnapshotOwner{},
		fakePostgreSQLSnapshotOwner{},
		fakeArtifactInventoryOwner{},
		fixedClock{now: time.Date(2026, 7, 24, 19, 0, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	other := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-destination",
		ResourceID:   "other-destination-1",
	}
	result, err := executor.ExecuteStage(
		context.Background(),
		guestruntimedomain.GuestOperationalStateBackupOperation{
			Kind:                 guestruntimedomain.GuestStateBackupKind,
			DestinationReference: &other,
		},
		guestruntimedomain.GuestStateBackupSQLiteSnapshotStage,
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Outcome != guestruntimeapplication.GuestStateBackupStageOutcomeRejected ||
		result.FailureCode != "backup-destination-not-configured" {
		t.Fatalf("result=%+v", result)
	}
}

type fixedClock struct {
	now time.Time
}

func (clock fixedClock) Now() time.Time {
	return clock.now
}

type fakeSQLiteSnapshotOwner struct{}

func (fakeSQLiteSnapshotOwner) CreateOnlineSnapshot(
	_ context.Context,
	path string,
) (gueststatesqliterepository.GuestRuntimeStateSQLiteSnapshot, error) {
	if err := os.WriteFile(path, []byte("sqlite-snapshot"), 0o600); err != nil {
		return gueststatesqliterepository.GuestRuntimeStateSQLiteSnapshot{}, err
	}
	return gueststatesqliterepository.GuestRuntimeStateSQLiteSnapshot{
		DatabaseID:    "guest-runtime-ledger-test-1",
		SchemaVersion: 1,
		ByteSize:      int64(len("sqlite-snapshot")),
		SHA256:        strings.Repeat("a", 64),
	}, nil
}

type fakePostgreSQLSnapshotOwner struct{}

func (fakePostgreSQLSnapshotOwner) CreateLogicalSnapshot(
	_ context.Context,
	path string,
) (gueststatepostgresqlbackup.Snapshot, error) {
	if err := os.WriteFile(path, []byte("postgresql-snapshot"), 0o600); err != nil {
		return gueststatepostgresqlbackup.Snapshot{}, err
	}
	return gueststatepostgresqlbackup.Snapshot{
		DatabaseID:      "guest-postgresql-12345678-1234-1234-1234-123456789abc",
		AlembicRevision: "0006_backup_owner",
		IncludedOwnerSchemas: append(
			[]string{},
			guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
		),
		ByteSize: int64(len("postgresql-snapshot")),
		SHA256:   strings.Repeat("b", 64),
	}, nil
}

type fakeArtifactInventoryOwner struct{}

func (fakeArtifactInventoryOwner) WriteGuestOperationalStateArtifactInventory(
	_ context.Context,
	operationID string,
	createdAt string,
	destination io.Writer,
) (int, error) {
	inventory := guestruntimedomain.GuestOperationalStateArtifactInventory{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		OperationID:   operationID,
		Artifacts: []guestruntimedomain.GuestOperationalStateArtifactInventoryItem{
			{
				ArtifactID: "archive-artifact-test-1",
				StorageReference: guestruntimedomain.ResourceReference{
					ResourceType: "archive-artifact-object",
					ResourceID:   "archive-artifact-test-1",
				},
				ByteSize:          2048,
				SHA256:            strings.Repeat("c", 64),
				FinalizationState: "finalized",
			},
		},
		ObjectBytesIncluded: false,
		CreatedAt:           createdAt,
	}
	return 1, json.NewEncoder(destination).Encode(inventory)
}
