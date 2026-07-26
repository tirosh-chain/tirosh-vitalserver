package gueststatesqliterestore

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestSQLiteRestoreRequiresAbsentTargetAndPublishesVerifiedIdentity(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	sourcePath := filepath.Join(root, "source.sqlite")
	database, err := sql.Open("sqlite", sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.ExecContext(
		ctx,
		`CREATE TABLE state_store_metadata (
		   singleton integer PRIMARY KEY,
		   database_id text NOT NULL,
		   schema_version integer NOT NULL
		 );
		 INSERT INTO state_store_metadata VALUES (
		   1,
		   'guest-runtime-ledger-restore-test-1',
		   7
		 );`,
	); err != nil {
		t.Fatal(err)
	}
	if err := database.Close(); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(contents)
	expected := guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{
		DatabaseID:    "guest-runtime-ledger-restore-test-1",
		SchemaVersion: 7,
		Snapshot: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-object",
				ResourceID:   "sqlite-restore-source-1",
			},
			ByteSize: int64(len(contents)),
			SHA256:   hex.EncodeToString(digest[:]),
		},
	}
	targetPath := filepath.Join(root, "target.sqlite")
	owner, err := New(targetPath)
	if err != nil {
		t.Fatal(err)
	}
	proof, err := owner.ProveEmpty(ctx)
	if err != nil ||
		proof.State != guestruntimedomain.GuestOperationalStateSQLiteRestoreTargetAbsent {
		t.Fatalf("proof=%+v err=%v", proof, err)
	}
	receipt, err := owner.Restore(ctx, sourcePath, expected)
	if err != nil {
		t.Fatal(err)
	}
	if receipt.DatabaseID != expected.DatabaseID {
		t.Fatalf("receipt=%+v", receipt)
	}
	if _, err := owner.ProveEmpty(ctx); err == nil {
		t.Fatal("published target must no longer prove empty")
	}
}

func TestSQLiteRestoreNeverOverwritesExistingTarget(t *testing.T) {
	root := t.TempDir()
	targetPath := filepath.Join(root, "target.sqlite")
	if err := os.WriteFile(targetPath, []byte("owned-state"), 0o600); err != nil {
		t.Fatal(err)
	}
	owner, err := New(targetPath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := owner.ProveEmpty(context.Background()); err == nil {
		t.Fatal("existing target must be rejected")
	}
	contents, err := os.ReadFile(targetPath)
	if err != nil || string(contents) != "owned-state" {
		t.Fatalf("existing target was changed: %q err=%v", contents, err)
	}
}
