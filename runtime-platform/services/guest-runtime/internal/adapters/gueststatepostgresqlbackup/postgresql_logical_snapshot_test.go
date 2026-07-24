package gueststatepostgresqlbackup

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInspectSnapshotRequiresEveryOwnerAndRevisionProof(t *testing.T) {
	root := t.TempDir()
	restore := filepath.Join(root, "pg_restore")
	if err := os.WriteFile(
		restore,
		[]byte("#!/bin/sh\nprintf '%s\\n' 'recorder_catalog archive_export recorder_assignment guest_operational_state public alembic_version'\n"),
		0o700,
	); err != nil {
		t.Fatal(err)
	}
	snapshotPath := filepath.Join(root, "snapshot.dump")
	if err := os.WriteFile(snapshotPath, []byte("custom-dump"), 0o600); err != nil {
		t.Fatal(err)
	}
	owner := &Owner{configuration: Configuration{
		DatabaseURL:             "postgresql://unused",
		PGRestoreExecutablePath: restore,
	}, commandEnvironment: os.Environ()}
	snapshot, err := owner.inspectSnapshot(
		t.Context(),
		snapshotPath,
		"guest-postgresql-12345678-1234-1234-1234-123456789abc",
		"0006_backup_owner",
	)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.ByteSize != int64(len("custom-dump")) ||
		len(snapshot.SHA256) != 64 ||
		len(snapshot.IncludedOwnerSchemas) != 4 {
		t.Fatalf("snapshot=%+v", snapshot)
	}
}

func TestCommandOutputRetainsOnlyBoundedEvidence(t *testing.T) {
	output := &boundedCommandOutput{maximumBytes: 8}
	contents := strings.Repeat("x", 32)
	written, err := output.Write([]byte(contents))
	if err != nil {
		t.Fatal(err)
	}
	if written != len(contents) ||
		output.buffer.Len() != 8 ||
		!output.exceeded {
		t.Fatalf("written=%d output=%+v", written, output)
	}
}
