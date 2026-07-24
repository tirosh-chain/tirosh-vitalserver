package guestbootstrapidentityfile

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReaderReturnsStableNonSecretBootstrapIdentity(t *testing.T) {
	directory := t.TempDir()
	configuration := writeValidEvidence(t, directory)
	reader, err := NewReader(configuration)
	if err != nil {
		t.Fatal(err)
	}
	first, err := reader.ReadGuestOperationalStateBootstrapIdentity(
		context.Background(),
	)
	if err != nil {
		t.Fatal(err)
	}
	second, err := reader.ReadGuestOperationalStateBootstrapIdentity(
		context.Background(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if first.PrivateMaterialSet.MaterialCount != 3 ||
		first.PrivateMaterialSet.SHA256 == "" ||
		first.PrivateMaterialSet.SHA256 != second.PrivateMaterialSet.SHA256 ||
		first.MigrationReceipt.Revision != "0006_backup_owner" {
		t.Fatalf("first=%+v second=%+v", first, second)
	}
	for _, secret := range []string{
		"database-secret", "catalog-secret", "archive-secret",
	} {
		if strings.Contains(first.PrivateMaterialSet.SHA256, secret) {
			t.Fatalf("aggregate digest exposed material %q", secret)
		}
	}
}

func TestReaderRejectsMissingOrInvalidOwnerEvidence(t *testing.T) {
	directory := t.TempDir()
	configuration := writeValidEvidence(t, directory)
	if err := os.Remove(configuration.MigrationReceiptPath); err != nil {
		t.Fatal(err)
	}
	reader, err := NewReader(configuration)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reader.ReadGuestOperationalStateBootstrapIdentity(
		context.Background(),
	); err == nil {
		t.Fatal("missing migration receipt must not become available identity")
	}

	configuration = writeValidEvidence(t, directory)
	if err := os.WriteFile(
		configuration.MigrationReceiptPath,
		[]byte(`{"schemaVersion":"v1","state":"failed","revision":"0006_backup_owner","startedAt":"2026-07-24T22:59:00Z","finishedAt":"2026-07-24T22:59:05Z"}`),
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := reader.ReadGuestOperationalStateBootstrapIdentity(
		context.Background(),
	); err == nil {
		t.Fatal("failed migration receipt must not become available identity")
	}
}

func TestReaderRejectsMaterialReadableByOtherUsers(t *testing.T) {
	directory := t.TempDir()
	configuration := writeValidEvidence(t, directory)
	if err := os.Chmod(
		configuration.CatalogAdmissionBearerTokenMaterialPath,
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	reader, err := NewReader(configuration)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reader.ReadGuestOperationalStateBootstrapIdentity(
		context.Background(),
	); err == nil {
		t.Fatal("non-private material must not become available identity")
	}
}

func writeValidEvidence(t *testing.T, directory string) Configuration {
	t.Helper()
	configuration := Configuration{
		MigrationReceiptPath: filepath.Join(directory, "migration.json"),
		RecorderCatalogDatabaseURLMaterialPath: filepath.Join(
			directory,
			"database-url",
		),
		CatalogAdmissionBearerTokenMaterialPath: filepath.Join(
			directory,
			"catalog-token",
		),
		ArchiveSourceAdmissionBearerTokenMaterialPath: filepath.Join(
			directory,
			"archive-token",
		),
	}
	files := map[string]string{
		configuration.MigrationReceiptPath:                          `{"schemaVersion":"v1","state":"succeeded","revision":"0006_backup_owner","startedAt":"2026-07-24T22:59:00Z","finishedAt":"2026-07-24T22:59:05Z"}`,
		configuration.RecorderCatalogDatabaseURLMaterialPath:        "database-secret",
		configuration.CatalogAdmissionBearerTokenMaterialPath:       "catalog-secret",
		configuration.ArchiveSourceAdmissionBearerTokenMaterialPath: "archive-secret",
	}
	for path, value := range files {
		if err := os.WriteFile(path, []byte(value), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return configuration
}
