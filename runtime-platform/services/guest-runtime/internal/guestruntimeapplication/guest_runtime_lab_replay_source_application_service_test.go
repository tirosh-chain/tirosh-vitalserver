package guestruntimeapplication_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type memoryLabReplaySourceRepository struct {
	stored *guestruntimeapplication.StoredLabReplaySourceAdmission
}

func (repository *memoryLabReplaySourceRepository) ReadLabReplaySourceAdmission(
	_ context.Context,
	requestID string,
) (guestruntimeapplication.StoredLabReplaySourceAdmission, error) {
	if repository.stored == nil || repository.stored.Command.RequestID != requestID {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return *repository.stored, nil
}

func (repository *memoryLabReplaySourceRepository) CommitLabReplaySourceAdmission(
	_ context.Context,
	commandDigest string,
	command guestruntimedomain.LabReplaySourceAdmissionCommand,
	receipt guestruntimedomain.LabReplaySourceAdmissionReceipt,
) error {
	if repository.stored != nil {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.stored = &guestruntimeapplication.StoredLabReplaySourceAdmission{
		CommandDigest: commandDigest,
		Command:       command,
		Receipt:       receipt,
	}
	return nil
}

type memoryLabReplaySourceObjectStore struct {
	content []byte
	commits int
	opens   int
}

func (store *memoryLabReplaySourceObjectStore) CommitLabReplaySourceObject(
	_ context.Context,
	commit guestruntimeapplication.LabReplaySourceObjectCommit,
) (guestruntimedomain.LabReplaySourceObjectReceipt, error) {
	store.commits++
	content, err := io.ReadAll(commit.Content)
	if err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{}, err
	}
	digest := sha256.Sum256(content)
	if int64(len(content)) != commit.Command.ByteSize ||
		hex.EncodeToString(digest[:]) != commit.Command.SHA256 {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			guestruntimeapplication.ErrLabReplaySourceObjectContentMismatch
	}
	store.content = append([]byte(nil), content...)
	return guestruntimedomain.LabReplaySourceObjectReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		SourceReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceResourceType,
			ResourceID:   commit.Command.SourceID,
		},
		State:    "committed",
		ByteSize: int64(len(content)),
		SHA256:   commit.Command.SHA256,
		StorageReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceStorageType,
			ResourceID:   commit.Command.SourceID,
		},
		PersistedAt: commit.PersistedAt,
	}, nil
}

func (store *memoryLabReplaySourceObjectStore) OpenLabReplaySourceObject(
	context.Context,
	guestruntimedomain.ResourceReference,
	string,
) (io.ReadCloser, error) {
	store.opens++
	return io.NopCloser(bytes.NewReader(store.content)), nil
}

func TestLabReplaySourceApplicationAdmitsAndDeduplicatesImmutableSource(t *testing.T) {
	repository := &memoryLabReplaySourceRepository{}
	objectStore := &memoryLabReplaySourceObjectStore{}
	service, err := guestruntimeapplication.NewGuestRuntimeLabReplaySourceApplicationService(
		repository,
		objectStore,
		fixedClock{},
		64<<20,
	)
	if err != nil {
		t.Fatal(err)
	}
	content := []byte("one complete vital file")
	command := labReplaySourceCommand(content)
	accepted, err := service.AdmitLabReplaySource(
		context.Background(),
		command,
		bytes.NewReader(content),
	)
	if err != nil {
		t.Fatal(err)
	}
	if accepted.Outcome != "accepted" || objectStore.commits != 1 {
		t.Fatalf("accepted=%#v commits=%d", accepted, objectStore.commits)
	}
	duplicate, err := service.AdmitLabReplaySource(
		context.Background(),
		command,
		bytes.NewReader(content),
	)
	if err != nil {
		t.Fatal(err)
	}
	if duplicate.Outcome != "duplicate" ||
		objectStore.commits != 1 ||
		objectStore.opens != 1 {
		t.Fatalf(
			"duplicate=%#v commits=%d opens=%d",
			duplicate,
			objectStore.commits,
			objectStore.opens,
		)
	}
}

func TestLabReplaySourceApplicationRejectsBodyThatDoesNotMatchEvidence(t *testing.T) {
	service, err := guestruntimeapplication.NewGuestRuntimeLabReplaySourceApplicationService(
		&memoryLabReplaySourceRepository{},
		&memoryLabReplaySourceObjectStore{},
		fixedClock{},
		64<<20,
	)
	if err != nil {
		t.Fatal(err)
	}
	command := labReplaySourceCommand([]byte("declared"))
	_, err = service.AdmitLabReplaySource(
		context.Background(),
		command,
		bytes.NewReader([]byte("different")),
	)
	var rejection guestruntimeapplication.LabReplaySourceAdmissionRejectedError
	if !errors.As(err, &rejection) ||
		rejection.Issue.Code != "lab-replay-source-content-mismatch" {
		t.Fatalf("err=%v", err)
	}
}

func labReplaySourceCommand(
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
