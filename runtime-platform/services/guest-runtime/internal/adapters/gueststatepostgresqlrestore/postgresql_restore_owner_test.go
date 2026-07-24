package gueststatepostgresqlrestore

import (
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestRestoreSnapshotValidationRequiresEveryOwner(t *testing.T) {
	snapshot := Snapshot{
		DatabaseID:      "guest-postgresql-12345678-1234-1234-1234-123456789abc",
		AlembicRevision: gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision,
		IncludedOwnerSchemas: append(
			[]string{},
			guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
		),
		ByteSize: 1,
		SHA256:   strings.Repeat("a", 64),
	}
	if err := validateSnapshot(snapshot); err != nil {
		t.Fatal(err)
	}
	snapshot.IncludedOwnerSchemas = snapshot.IncludedOwnerSchemas[:3]
	if err := validateSnapshot(snapshot); err == nil {
		t.Fatal("incomplete owner schema set unexpectedly passed")
	}
}

func TestRestoreOutputIsBounded(t *testing.T) {
	output := &boundedOutput{maximumBytes: 8}
	contents := strings.Repeat("x", 32)
	written, err := output.Write([]byte(contents))
	if err != nil {
		t.Fatal(err)
	}
	if written != len(contents) || output.buffer.Len() != 8 || !output.exceeded {
		t.Fatalf("written=%d output=%+v", written, output)
	}
}

func TestRestoreDatabaseNameIsExplicitWithoutCredentialMaterial(t *testing.T) {
	name, err := restoreDatabaseName(
		"postgresql://restore-user:private-password@127.0.0.1:5432/restore_target",
	)
	if err != nil || name != "restore_target" ||
		strings.Contains(name, "private-password") {
		t.Fatalf("name=%q err=%v", name, err)
	}
}
