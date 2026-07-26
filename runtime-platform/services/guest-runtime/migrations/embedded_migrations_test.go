package migrations

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMaterializePublishesExactAlembicRevisionTree(t *testing.T) {
	destination := t.TempDir()
	if err := Materialize(destination); err != nil {
		t.Fatal(err)
	}
	for _, relativePath := range []string{
		"alembic.ini",
		"env.py",
		"script.py.mako",
		"versions/0001_recorder_catalog_foundation.py",
		"versions/0002_recorder_catalog_expectations.py",
		"versions/0003_archive_export_lineage.py",
		"versions/0004_archive_source_admissions.py",
		"versions/0005_recorder_assignment_owner.py",
		"versions/0006_guest_operational_state_backup_owner.py",
	} {
		info, err := os.Stat(filepath.Join(destination, relativePath))
		if err != nil {
			t.Fatalf("materialized migration %s: %v", relativePath, err)
		}
		if !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 {
			t.Fatalf("materialized migration %s mode=%s", relativePath, info.Mode())
		}
	}
}

func TestMaterializeRejectsNonEmptyDestination(t *testing.T) {
	destination := t.TempDir()
	if err := os.WriteFile(filepath.Join(destination, "unexpected"), []byte("state"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := Materialize(destination); err == nil {
		t.Fatal("expected non-empty migration destination rejection")
	}
}
