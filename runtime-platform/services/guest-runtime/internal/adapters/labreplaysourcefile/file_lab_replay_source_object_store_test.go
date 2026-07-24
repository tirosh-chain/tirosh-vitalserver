package labreplaysourcefile_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/labreplaysourcefile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestFileLabReplaySourceObjectStoreCommitsAndReopensExactSource(t *testing.T) {
	store, err := labreplaysourcefile.OpenFileLabReplaySourceObjectStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	content := []byte("one complete vital file")
	command := labReplaySourceObjectCommand(content)
	receipt, err := store.CommitLabReplaySourceObject(
		context.Background(),
		guestruntimeapplication.LabReplaySourceObjectCommit{
			Command:     command,
			Content:     bytes.NewReader(content),
			PersistedAt: "2026-07-24T16:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if receipt.State != "committed" ||
		receipt.SourceReference.ResourceType != guestruntimedomain.LabReplaySourceResourceType {
		t.Fatalf("receipt=%#v", receipt)
	}
	opened, err := store.OpenLabReplaySourceObject(
		context.Background(),
		receipt.SourceReference,
		receipt.SHA256,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer opened.Close()
	actual, err := io.ReadAll(opened)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(actual, content) {
		t.Fatalf("content=%q", actual)
	}
	existing, err := store.CommitLabReplaySourceObject(
		context.Background(),
		guestruntimeapplication.LabReplaySourceObjectCommit{
			Command:     command,
			Content:     bytes.NewReader([]byte("not-consumed")),
			PersistedAt: "2026-07-24T16:00:01Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if existing.State != "existing" {
		t.Fatalf("existing=%#v", existing)
	}
}

func TestFileLabReplaySourceObjectStoreRejectsContentMismatch(t *testing.T) {
	store, err := labreplaysourcefile.OpenFileLabReplaySourceObjectStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	command := labReplaySourceObjectCommand([]byte("declared"))
	_, err = store.CommitLabReplaySourceObject(
		context.Background(),
		guestruntimeapplication.LabReplaySourceObjectCommit{
			Command:     command,
			Content:     bytes.NewReader([]byte("different")),
			PersistedAt: "2026-07-24T16:00:00Z",
		},
	)
	if !errors.Is(err, guestruntimeapplication.ErrLabReplaySourceObjectContentMismatch) {
		t.Fatalf("err=%v", err)
	}
}

func labReplaySourceObjectCommand(
	content []byte,
) guestruntimedomain.LabReplaySourceAdmissionCommand {
	digest := sha256.Sum256(content)
	return guestruntimedomain.LabReplaySourceAdmissionCommand{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		RequestID:        "lab-replay-source-request-1",
		SourceID:         "lab-replay-source-1",
		OriginalFileName: "sample.vital",
		MediaType:        guestruntimedomain.LabReplaySourceMediaType,
		ByteSize:         int64(len(content)),
		SHA256:           hex.EncodeToString(digest[:]),
	}
}
