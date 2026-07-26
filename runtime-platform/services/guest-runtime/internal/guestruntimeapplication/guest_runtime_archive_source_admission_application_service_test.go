package guestruntimeapplication

import (
	"bytes"
	"context"
	"errors"
	"io"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type archiveSourceAdmissionTestRepository struct {
	byRequest map[string]ArchiveStoredSourceAdmission
	bySource  map[string]guestruntimedomain.ArchiveArtifactDetail
}

func newArchiveSourceAdmissionTestRepository() *archiveSourceAdmissionTestRepository {
	return &archiveSourceAdmissionTestRepository{
		byRequest: make(map[string]ArchiveStoredSourceAdmission),
		bySource:  make(map[string]guestruntimedomain.ArchiveArtifactDetail),
	}
}

func (repository *archiveSourceAdmissionTestRepository) ReadArchiveSourceAdmission(
	_ context.Context,
	requestID string,
) (ArchiveStoredSourceAdmission, error) {
	stored, exists := repository.byRequest[requestID]
	if !exists {
		return ArchiveStoredSourceAdmission{}, ErrGuestRuntimeOwnedResourceNotFound
	}
	return stored, nil
}

func (repository *archiveSourceAdmissionTestRepository) ReadArchiveArtifactDetailBySourceReceipt(
	_ context.Context,
	sourceKind string,
	sourceReceiptType string,
	sourceReceiptID string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	sourceKey := sourceKind + "\x00" + sourceReceiptType + "\x00" + sourceReceiptID
	detail, exists := repository.bySource[sourceKey]
	if !exists {
		return guestruntimedomain.ArchiveArtifactDetail{},
			ErrGuestRuntimeOwnedResourceNotFound
	}
	return detail, nil
}

func (repository *archiveSourceAdmissionTestRepository) CommitAcceptedArchiveSourceAdmission(
	_ context.Context,
	digest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
	artifact guestruntimedomain.ArchiveArtifact,
	attribution guestruntimedomain.RecorderArtifactAttribution,
) error {
	if _, exists := repository.byRequest[command.RequestID]; exists {
		return ErrGuestRuntimeOwnedResourceConflict
	}
	sourceKey := artifact.SourceKind + "\x00" +
		artifact.SourceReceiptType + "\x00" + artifact.SourceReceiptID
	if _, exists := repository.bySource[sourceKey]; exists {
		return ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[command.RequestID] = ArchiveStoredSourceAdmission{
		CommandDigest: digest,
		Command:       command,
		Receipt:       receipt,
	}
	repository.bySource[sourceKey] = guestruntimedomain.ArchiveArtifactDetail{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		Artifact:      artifact,
		Attribution:   attribution,
	}
	return nil
}

func (repository *archiveSourceAdmissionTestRepository) CommitTerminalArchiveSourceAdmission(
	_ context.Context,
	digest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
) error {
	if _, exists := repository.byRequest[command.RequestID]; exists {
		return ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[command.RequestID] = ArchiveStoredSourceAdmission{
		CommandDigest: digest,
		Command:       command,
		Receipt:       receipt,
	}
	return nil
}

type archiveSourceAdmissionTestObjectStore struct {
	calls int
	err   error
}

func (store *archiveSourceAdmissionTestObjectStore) CommitArchiveArtifactObject(
	_ context.Context,
	commit ArchiveArtifactObjectCommit,
) (guestruntimedomain.ArchiveArtifactObjectReceipt, error) {
	store.calls++
	if store.err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{}, store.err
	}
	_, _ = io.Copy(io.Discard, commit.Content)
	return guestruntimedomain.ArchiveArtifactObjectReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ArtifactID:    commit.ArtifactID,
		State:         "committed",
		ByteSize:      commit.Source.ByteSize,
		SHA256:        commit.Source.SHA256,
		StorageReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-archive-object",
			ResourceID:   commit.ArtifactID,
		},
		PersistedAt: commit.PersistedAt,
	}, nil
}

type archiveSourceAdmissionTestAttributionResolver struct {
	calls      int
	candidates []string
}

func (resolver *archiveSourceAdmissionTestAttributionResolver) ResolveRecorderArtifactAttribution(
	_ context.Context,
	source guestruntimedomain.RecorderVitalUploadSourceReceipt,
	artifactID string,
	resolvedAt string,
) (guestruntimedomain.RecorderAttributionResolutionInput, error) {
	resolver.calls++
	return guestruntimedomain.RecorderAttributionResolutionInput{
		ArtifactID:           artifactID,
		ReportedBedName:      &source.ReportedBedName,
		EvidenceObservedAt:   source.FinalizedAt,
		CandidateRecorderIDs: resolver.candidates,
		PolicyVersion:        "test-assignment-owner-v1",
		ResolvedAt:           resolvedAt,
	}, nil
}

func TestArchiveSourceAdmissionIsDurableIdempotentAndDoesNotTrustRecorderDeclaration(
	t *testing.T,
) {
	repository := newArchiveSourceAdmissionTestRepository()
	objectStore := &archiveSourceAdmissionTestObjectStore{}
	resolver := &archiveSourceAdmissionTestAttributionResolver{}
	service, err := NewGuestRuntimeArchiveSourceAdmissionApplicationService(
		repository,
		objectStore,
		resolver,
		fixedArchiveSourceAdmissionClock{
			at: time.Date(2026, 7, 24, 12, 0, 1, 0, time.UTC),
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	command := archiveSourceAdmissionCommandForTest()
	declaredRecorderID := "recorder-claimed"
	command.Source.DeclaredRecorderID = &declaredRecorderID
	first, err := service.AdmitRecorderVitalUpload(
		context.Background(),
		command,
		bytes.NewReader([]byte("vital-content")),
	)
	if err != nil {
		t.Fatalf("admit Recorder Vital upload: %v", err)
	}
	if first.Outcome != "accepted" || first.ArtifactReference == nil {
		t.Fatalf("expected accepted admission: %#v", first)
	}
	sourceKey := command.Source.SourceKind + "\x00" +
		guestruntimedomain.RecorderVitalUploadSourceReceiptType + "\x00" +
		command.Source.ID
	detail := repository.bySource[sourceKey]
	if detail.Attribution.Outcome != guestruntimedomain.UnresolvedRecorderAttributionOutcome ||
		detail.Attribution.MatchedRecorderID != nil {
		t.Fatalf("Recorder declaration must remain evidence only: %#v", detail.Attribution)
	}

	second, err := service.AdmitRecorderVitalUpload(
		context.Background(),
		command,
		bytes.NewReader(nil),
	)
	if err != nil {
		t.Fatalf("repeat identical source request: %v", err)
	}
	if second.Outcome != first.Outcome ||
		second.ArtifactReference == nil ||
		second.ArtifactReference.ResourceID != first.ArtifactReference.ResourceID {
		t.Fatalf("idempotent receipt differs: first=%#v second=%#v", first, second)
	}
	if objectStore.calls != 1 || resolver.calls != 1 {
		t.Fatalf(
			"idempotent request repeated effects: objectCalls=%d resolverCalls=%d",
			objectStore.calls,
			resolver.calls,
		)
	}
}

func TestArchiveSourceAdmissionPersistsContentMismatchAsQuarantine(t *testing.T) {
	repository := newArchiveSourceAdmissionTestRepository()
	objectStore := &archiveSourceAdmissionTestObjectStore{
		err: ErrArchiveArtifactObjectContentMismatch,
	}
	service, err := NewGuestRuntimeArchiveSourceAdmissionApplicationService(
		repository,
		objectStore,
		&archiveSourceAdmissionTestAttributionResolver{},
		fixedArchiveSourceAdmissionClock{
			at: time.Date(2026, 7, 24, 12, 0, 1, 0, time.UTC),
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	command := archiveSourceAdmissionCommandForTest()
	receipt, err := service.AdmitRecorderVitalUpload(
		context.Background(),
		command,
		bytes.NewReader([]byte("wrong")),
	)
	if err != nil {
		t.Fatalf("known content mismatch must return its durable receipt: %v", err)
	}
	if receipt.Outcome != "quarantined" ||
		receipt.Issue == nil ||
		receipt.Issue.Code != "archive-source-content-mismatch" {
		t.Fatalf("content mismatch was not preserved: %#v", receipt)
	}
	stored := repository.byRequest[command.RequestID]
	if stored.Receipt.Outcome != "quarantined" {
		t.Fatalf("quarantine receipt is not durable: %#v", stored)
	}
}

func TestArchiveSourceAdmissionDoesNotConvertObjectStoreFailureToSuccess(t *testing.T) {
	service, err := NewGuestRuntimeArchiveSourceAdmissionApplicationService(
		newArchiveSourceAdmissionTestRepository(),
		&archiveSourceAdmissionTestObjectStore{err: errors.New("disk unavailable")},
		&archiveSourceAdmissionTestAttributionResolver{},
		fixedArchiveSourceAdmissionClock{
			at: time.Date(2026, 7, 24, 12, 0, 1, 0, time.UTC),
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = service.AdmitRecorderVitalUpload(
		context.Background(),
		archiveSourceAdmissionCommandForTest(),
		bytes.NewReader([]byte("vital-content")),
	)
	var unknown ArchiveSourceAdmissionUnknownError
	if !errors.As(err, &unknown) ||
		unknown.Issue.Code != "archive-artifact-object-commit-unknown" {
		t.Fatalf("object store failure must remain admission unknown, got %v", err)
	}
}

type fixedArchiveSourceAdmissionClock struct {
	at time.Time
}

func (clock fixedArchiveSourceAdmissionClock) Now() time.Time {
	return clock.at
}

func archiveSourceAdmissionCommandForTest() guestruntimedomain.ArchiveSourceAdmissionCommand {
	return guestruntimedomain.ArchiveSourceAdmissionCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "archive-source-request-1",
		Source: guestruntimedomain.RecorderVitalUploadSourceReceipt{
			SchemaVersion:    guestruntimedomain.SchemaVersion,
			ID:               "recorder-vital-upload-1",
			SourceKind:       guestruntimedomain.RecorderUploadArchiveSourceKind,
			UploadID:         "upload-1",
			OriginalFileName: "OR-01.vital",
			MediaType:        "application/x-vital",
			ByteSize:         13,
			SHA256:           "f150534180b661f2eaa91d6398374c1001c7fb628ca388ca5d21e7fac2df3be4",
			ReportedBedName:  "OR-01",
			State:            "admitted",
			ContentReference: guestruntimedomain.ResourceReference{
				ResourceType: "recorder-vital-upload-content",
				ResourceID:   "recorder-vital-upload-1",
			},
			ReceivedAt:  "2026-07-24T12:00:00Z",
			FinalizedAt: "2026-07-24T12:00:00Z",
		},
	}
}
