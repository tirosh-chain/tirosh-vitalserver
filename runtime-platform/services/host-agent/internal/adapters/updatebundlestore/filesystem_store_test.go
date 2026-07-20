package updatebundlestore

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type testClock struct{}

func (testClock) Now() time.Time { return time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC) }

func TestImportPublishesOnlyCompleteImmutableBundleAndReadsOwnerDeclaration(t *testing.T) {
	root := t.TempDir()
	storeDirectory := filepath.Join(root, "store")
	if err := os.Mkdir(storeDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	source := writeBundle(t, filepath.Join(root, "release"), "release-bootstrap-020", "updater-bytes")
	store, err := NewFileSystemStore(FileSystemStoreConfig{Directory: storeDirectory, Clock: testClock{}})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	command := hostagentdomain.HostUpdateBundleImportCommand{SchemaVersion: "v1", RequestID: "import-020", SourceDirectory: source}
	receipt, err := store.Import(context.Background(), command)
	if err != nil {
		t.Fatalf("import bundle: %v", err)
	}
	if receipt.State != "imported" || receipt.Bundle.ID != "release-bootstrap-020" || receipt.Bundle.State != "declared" || receipt.SourceFingerprint == "" {
		t.Fatalf("receipt=%+v", receipt)
	}
	if _, err := os.Stat(filepath.Join(storeDirectory, receipt.Bundle.ID, "payload", "host-updater")); err != nil {
		t.Fatalf("published bundle bytes missing: %v", err)
	}
	read, err := store.Read(context.Background(), receipt.Bundle.ID)
	if err != nil {
		t.Fatalf("read imported bundle: %v", err)
	}
	if !reflect.DeepEqual(read, receipt.Bundle) {
		t.Fatalf("read=%+v\nreceipt=%+v", read, receipt.Bundle)
	}
	replayed, err := store.Import(context.Background(), command)
	if err != nil {
		t.Fatalf("replay same bytes: %v", err)
	}
	if replayed.State != "already-imported" || replayed.SourceFingerprint != receipt.SourceFingerprint {
		t.Fatalf("replayed receipt=%+v", replayed)
	}
}

func TestImportRejectsSymlinkAndConflictingBundleBytes(t *testing.T) {
	root := t.TempDir()
	storeDirectory := filepath.Join(root, "store")
	if err := os.Mkdir(storeDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	store, err := NewFileSystemStore(FileSystemStoreConfig{Directory: storeDirectory, Clock: testClock{}})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	first := writeBundle(t, filepath.Join(root, "first"), "release-bootstrap-020", "first-updater")
	if _, err := store.Import(context.Background(), hostagentdomain.HostUpdateBundleImportCommand{SchemaVersion: "v1", RequestID: "import-first", SourceDirectory: first}); err != nil {
		t.Fatalf("import first: %v", err)
	}
	conflicting := writeBundle(t, filepath.Join(root, "second"), "release-bootstrap-020", "different-updater")
	_, err = store.Import(context.Background(), hostagentdomain.HostUpdateBundleImportCommand{SchemaVersion: "v1", RequestID: "import-conflict", SourceDirectory: conflicting})
	if !errors.Is(err, hostagentapplication.ErrHostUpdateBundleConflict) {
		t.Fatalf("conflicting import error=%v", err)
	}
	symlinkSource := filepath.Join(root, "symlink-release")
	if err := os.Symlink(first, symlinkSource); err != nil {
		t.Fatal(err)
	}
	_, err = store.Import(context.Background(), hostagentdomain.HostUpdateBundleImportCommand{SchemaVersion: "v1", RequestID: "import-symlink", SourceDirectory: symlinkSource})
	if !errors.Is(err, hostagentapplication.ErrHostUpdateBundleInvalid) || !strings.Contains(err.Error(), "non-symlink") {
		t.Fatalf("symlink import error=%v", err)
	}
}

func writeBundle(t *testing.T, directory string, id string, updater string) string {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(directory, "payload"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "payload", "host-updater"), []byte(updater), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "payload", "product-update.json"), []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	envelope := hostagentdomain.UpdateBootstrapEnvelope{
		SchemaVersion: "v1", ID: id, ProductID: "vitalserver-runtime-platform",
		Target:              hostagentdomain.UpdateTarget{Platform: "macos", Architecture: "arm64"},
		TargetRelease:       hostagentdomain.Release{ProductVersion: "0.2.0", RuntimeVersion: "0.2.0"},
		LayerOrder:          []string{hostagentdomain.UpdateLayerGuestRuntime, hostagentdomain.UpdateLayerHostPlatform},
		NextUpdaterArtifact: hostagentdomain.UpdateArtifact{ID: "host-updater-020", RelativePath: "payload/host-updater", SHA256: strings.Repeat("a", 64), SizeBytes: 1, MediaType: "application/octet-stream"},
		Specification:       hostagentdomain.UpdateArtifact{ID: "product-update-020", RelativePath: "payload/product-update.json", SHA256: strings.Repeat("b", 64), SizeBytes: 1, MediaType: "application/json"},
		Signature:           hostagentdomain.UpdateSignature{Algorithm: "ed25519", KeyID: "release-key-2026", SignedSHA256: strings.Repeat("c", 64), Value: "signature"},
		IssuedAt:            "2026-07-20T00:00:00Z",
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, bootstrapEnvelopeFilename), encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	return directory
}
