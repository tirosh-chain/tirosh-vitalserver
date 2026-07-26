package guestruntimedomain

import (
	"strings"
	"testing"
)

func TestGuestOperationalStateBackupManifestRequiresEveryPostgreSQLOwner(t *testing.T) {
	manifest := validGuestOperationalStateBackupManifest()
	if err := ValidateGuestOperationalStateBackupManifest(manifest); err != nil {
		t.Fatal(err)
	}
	manifest.PostgreSQLSnapshot.IncludedOwnerSchemas = []string{
		"recorder_catalog",
		"archive_export",
	}
	if err := ValidateGuestOperationalStateBackupManifest(manifest); err == nil {
		t.Fatal("manifest without Recorder Assignment owner unexpectedly passed")
	}
}

func TestGuestOperationalStateBackupManifestRejectsObjectBytesClaim(t *testing.T) {
	manifest := validGuestOperationalStateBackupManifest()
	manifest.ObjectBytesIncluded = true
	if err := ValidateGuestOperationalStateBackupManifest(manifest); err == nil {
		t.Fatal("manifest claiming raw object bytes unexpectedly passed")
	}
}

func TestGuestOperationalStateArtifactInventoryRequiresOrderedOwnerMetadata(t *testing.T) {
	inventory := GuestOperationalStateArtifactInventory{
		SchemaVersion: SchemaVersion,
		OperationID:   "guest-backup-operation-test-1",
		Artifacts: []GuestOperationalStateArtifactInventoryItem{
			{
				ArtifactID: "archive-artifact-1",
				StorageReference: ResourceReference{
					ResourceType: "archive-artifact-object",
					ResourceID:   "archive-artifact-1",
				},
				ByteSize:          2048,
				SHA256:            strings.Repeat("d", 64),
				FinalizationState: "finalized",
			},
			{
				ArtifactID: "archive-artifact-2",
				StorageReference: ResourceReference{
					ResourceType: "archive-artifact-object",
					ResourceID:   "archive-artifact-2",
				},
				ByteSize:          4096,
				SHA256:            strings.Repeat("e", 64),
				FinalizationState: "finalized",
			},
		},
		ObjectBytesIncluded: false,
		CreatedAt:           "2026-07-24T23:00:00Z",
	}
	if err := ValidateGuestOperationalStateArtifactInventory(inventory); err != nil {
		t.Fatal(err)
	}
	inventory.Artifacts[1].ArtifactID = inventory.Artifacts[0].ArtifactID
	if err := ValidateGuestOperationalStateArtifactInventory(inventory); err == nil {
		t.Fatal("duplicate artifact inventory unexpectedly passed")
	}
}

func validGuestOperationalStateBackupManifest() GuestOperationalStateBackupManifest {
	return GuestOperationalStateBackupManifest{
		SchemaVersion: SchemaVersion,
		ID:            "guest-backup-manifest-test-1",
		OperationID:   "guest-backup-operation-test-1",
		DestinationReference: ResourceReference{
			ResourceType: "guest-backup-destination",
			ResourceID:   "guest-backup-destination-test-1",
		},
		SQLiteSnapshot: GuestOperationalStateSQLiteSnapshotReceipt{
			DatabaseID:    "guest-runtime-ledger-test-1",
			SchemaVersion: 1,
			Snapshot: GuestOperationalStateBackupSnapshotArtifact{
				Reference: ResourceReference{
					ResourceType: "guest-backup-object",
					ResourceID:   "guest-runtime-sqlite-test-1",
				},
				ByteSize: 4096,
				SHA256:   strings.Repeat("a", 64),
			},
		},
		PostgreSQLSnapshot: GuestOperationalStatePostgreSQLSnapshotReceipt{
			DatabaseID:           "guest-operational-postgresql-test-1",
			AlembicRevision:      "0006_backup_owner",
			IncludedOwnerSchemas: append([]string{}, GuestOperationalStatePostgreSQLOwnerSchemas...),
			Snapshot: GuestOperationalStateBackupSnapshotArtifact{
				Reference: ResourceReference{
					ResourceType: "guest-backup-object",
					ResourceID:   "guest-operational-postgresql-test-1",
				},
				ByteSize: 8192,
				SHA256:   strings.Repeat("b", 64),
			},
		},
		ArtifactInventory: GuestOperationalStateArtifactInventoryReceipt{
			ArtifactCount: 0,
			Inventory: GuestOperationalStateBackupSnapshotArtifact{
				Reference: ResourceReference{
					ResourceType: "guest-backup-object",
					ResourceID:   "guest-artifact-inventory-test-1",
				},
				ByteSize: 2,
				SHA256:   strings.Repeat("c", 64),
			},
		},
		ObjectBytesIncluded: false,
		CreatedAt:           "2026-07-24T23:00:00Z",
	}
}
