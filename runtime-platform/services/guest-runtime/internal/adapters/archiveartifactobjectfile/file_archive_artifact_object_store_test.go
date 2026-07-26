package archiveartifactobjectfile

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestFileArchiveArtifactObjectStoreCommitsAndReopensExactContent(t *testing.T) {
	store, err := OpenFileArchiveArtifactObjectStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	content := []byte("vital-content")
	source := archiveObjectSourceReceiptForTest(content)
	artifactID, err := guestruntimedomain.ArchiveArtifactIDForSourceReceipt(
		source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		source.ID,
	)
	if err != nil {
		t.Fatal(err)
	}
	commit := guestruntimeapplication.ArchiveArtifactObjectCommit{
		ArtifactID:  artifactID,
		Source:      source,
		Content:     bytes.NewReader(content),
		PersistedAt: "2026-07-24T12:00:01Z",
	}
	receipt, err := store.CommitArchiveArtifactObject(context.Background(), commit)
	if err != nil {
		t.Fatalf("commit Archive artifact object: %v", err)
	}
	if receipt.State != "committed" || receipt.SHA256 != source.SHA256 {
		t.Fatalf("committed object receipt is wrong: %#v", receipt)
	}
	stored, err := os.ReadFile(filepath.Join(
		store.objectsDirectory,
		artifactID,
		"content.vital",
	))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(stored, content) {
		t.Fatalf("stored Archive content differs: %q", stored)
	}

	commit.Content = bytes.NewReader(nil)
	existing, err := store.CommitArchiveArtifactObject(context.Background(), commit)
	if err != nil {
		t.Fatalf("reopen idempotent Archive artifact object: %v", err)
	}
	if existing.State != "existing" {
		t.Fatalf("expected explicit existing object state: %#v", existing)
	}
}

func TestFileArchiveArtifactObjectStoreRejectsMismatchedSourceBytes(t *testing.T) {
	store, err := OpenFileArchiveArtifactObjectStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	source := archiveObjectSourceReceiptForTest([]byte("expected"))
	artifactID, err := guestruntimedomain.ArchiveArtifactIDForSourceReceipt(
		source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		source.ID,
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.CommitArchiveArtifactObject(
		context.Background(),
		guestruntimeapplication.ArchiveArtifactObjectCommit{
			ArtifactID:  artifactID,
			Source:      source,
			Content:     bytes.NewReader([]byte("different")),
			PersistedAt: "2026-07-24T12:00:01Z",
		},
	)
	if !errors.Is(err, guestruntimeapplication.ErrArchiveArtifactObjectContentMismatch) {
		t.Fatalf("expected explicit content mismatch, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(store.objectsDirectory, artifactID)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("mismatched content must not be exposed as an object, got %v", err)
	}
}

func archiveObjectSourceReceiptForTest(
	content []byte,
) guestruntimedomain.RecorderVitalUploadSourceReceipt {
	sum := sha256.Sum256(content)
	return guestruntimedomain.RecorderVitalUploadSourceReceipt{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		ID:               "recorder-vital-upload-object-test",
		SourceKind:       guestruntimedomain.RecorderUploadArchiveSourceKind,
		UploadID:         "upload-object-test",
		OriginalFileName: "object-test.vital",
		MediaType:        "application/x-vital",
		ByteSize:         int64(len(content)),
		SHA256:           hex.EncodeToString(sum[:]),
		ReportedBedName:  "OR-01",
		State:            "admitted",
		ContentReference: guestruntimedomain.ResourceReference{
			ResourceType: "recorder-vital-upload-content",
			ResourceID:   "recorder-vital-upload-object-test",
		},
		ReceivedAt:  "2026-07-24T12:00:00Z",
		FinalizedAt: "2026-07-24T12:00:00Z",
	}
}
