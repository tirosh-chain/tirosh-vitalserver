package gueststatepostgresqlrepository_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestArchiveExportPostgreSQLRepositoryPreservesLineageAndIndependentOutcomes(t *testing.T) {
	databaseURL := os.Getenv("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is not configured")
	}
	repository, err := gueststatepostgresqlrepository.OpenArchiveExportPostgreSQLRepository(
		context.Background(),
		databaseURL,
	)
	if err != nil {
		t.Fatalf("open Archive Export PostgreSQL repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })

	finalizedAt := "2026-07-24T10:00:00Z"
	recorderID := "archive-recorder-1"
	artifact := archiveIntegrationArtifact(
		"archive-artifact-1",
		"archive-manifest-1",
		"archive-source-receipt-1",
		finalizedAt,
	)
	attribution := guestruntimedomain.RecorderArtifactAttribution{
		SchemaVersion:        guestruntimedomain.SchemaVersion,
		ArtifactID:           artifact.ArtifactID,
		EvidenceObservedAt:   finalizedAt,
		CandidateRecorderIDs: []string{recorderID},
		Outcome:              guestruntimedomain.MatchedRecorderAttributionOutcome,
		MatchedRecorderID:    &recorderID,
		PolicyVersion:        "integration-policy-v1",
		ResolvedAt:           finalizedAt,
	}
	if err := repository.CommitFinalizedArchiveArtifact(
		context.Background(),
		artifact,
		attribution,
	); err != nil {
		t.Fatalf("commit finalized Archive artifact: %v", err)
	}
	if err := repository.CommitFinalizedArchiveArtifact(
		context.Background(),
		artifact,
		attribution,
	); !errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict) {
		t.Fatalf("duplicate source identity must conflict, got %v", err)
	}

	finishedAt := "2026-07-24T10:00:01Z"
	attempt := guestruntimedomain.ArchiveUploadAttempt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		AttemptID:     "archive-upload-attempt-1",
		RequestID:     "archive-upload-request-1",
		ArtifactID:    artifact.ArtifactID,
		Provider: guestruntimedomain.ArchiveProviderReference{
			Kind:               "vitalserver-indexed-library",
			ID:                 "archive-provider-1",
			CapabilityRevision: 1,
		},
		State:      "succeeded",
		StartedAt:  finalizedAt,
		FinishedAt: &finishedAt,
	}
	if err := repository.CommitArchiveUploadAttempt(
		context.Background(),
		attempt,
	); err != nil {
		t.Fatalf("commit Archive upload attempt: %v", err)
	}
	indexing := guestruntimedomain.ArchiveIndexingReceipt{
		SchemaVersion:   guestruntimedomain.SchemaVersion,
		ReceiptID:       "archive-indexing-receipt-1",
		ArtifactID:      artifact.ArtifactID,
		UploadAttemptID: attempt.AttemptID,
		Outcome:         "not-indexed",
		Issue: &guestruntimedomain.Issue{
			Code:    "provider-index-missing",
			Message: "provider did not report an indexed library entry",
		},
		ObservedAt:  finishedAt,
		PersistedAt: finishedAt,
	}
	if err := repository.CommitArchiveIndexingReceipt(
		context.Background(),
		indexing,
	); err != nil {
		t.Fatalf("commit independent Archive indexing receipt: %v", err)
	}

	detail, err := repository.ReadArchiveArtifactDetail(
		context.Background(),
		artifact.ArtifactID,
	)
	if err != nil {
		t.Fatalf("read Archive artifact detail: %v", err)
	}
	if detail.Attribution.MatchedRecorderID == nil ||
		*detail.Attribution.MatchedRecorderID != recorderID ||
		len(detail.UploadAttempts) != 1 ||
		detail.UploadAttempts[0].State != "succeeded" ||
		len(detail.IndexingReceipts) != 1 ||
		detail.IndexingReceipts[0].Outcome != "not-indexed" {
		t.Fatalf("Archive artifact detail lost independent owner facts: %#v", detail)
	}

	service, err := guestruntimeapplication.NewGuestRuntimeArchiveLineageApplicationService(
		repository,
		integrationClock{now: time.Date(2026, 7, 24, 10, 1, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	pageRead := service.ReadRecorderArtifacts(
		context.Background(),
		recorderID,
		1,
		"",
	)
	if pageRead.State != "available" {
		t.Fatalf("read matched Recorder artifact page: %#v", pageRead)
	}
	page := pageRead.Value.(guestruntimedomain.RecorderArtifactPage)
	if len(page.Items) != 1 ||
		page.Items[0].Artifact.ArtifactID != artifact.ArtifactID {
		t.Fatalf("matched Recorder artifact page is wrong: %#v", page)
	}
}

func TestArchiveSourceAdmissionCommitsArtifactAndRequestReceiptAtomically(t *testing.T) {
	databaseURL := os.Getenv("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is not configured")
	}
	repository, err := gueststatepostgresqlrepository.OpenArchiveExportPostgreSQLRepository(
		context.Background(),
		databaseURL,
	)
	if err != nil {
		t.Fatalf("open Archive Export PostgreSQL repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })

	receivedAt := "2026-07-24T11:00:00Z"
	persistedAt := "2026-07-24T11:00:01Z"
	source := guestruntimedomain.RecorderVitalUploadSourceReceipt{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		ID:               "archive-source-admission-receipt-1",
		SourceKind:       guestruntimedomain.RecorderUploadArchiveSourceKind,
		UploadID:         "archive-source-upload-1",
		OriginalFileName: "archive-source-admission.vital",
		MediaType:        "application/x-vital",
		ByteSize:         20,
		SHA256:           "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		ReportedBedName:  "OR-01",
		State:            "admitted",
		ContentReference: guestruntimedomain.ResourceReference{
			ResourceType: "recorder-vital-upload-content",
			ResourceID:   "archive-source-admission-receipt-1",
		},
		ReceivedAt:  receivedAt,
		FinalizedAt: receivedAt,
	}
	command := guestruntimedomain.ArchiveSourceAdmissionCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "archive-source-admission-request-1",
		Source:        source,
	}
	digest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		t.Fatal(err)
	}
	artifact := archiveIntegrationArtifact(
		"archive-source-artifact-1",
		"archive-source-manifest-1",
		source.ID,
		receivedAt,
	)
	artifact.OriginalFileName = source.OriginalFileName
	artifact.SourceReceiptType = guestruntimedomain.RecorderVitalUploadSourceReceiptType
	artifact.Manifest.Source.ReceiptType = artifact.SourceReceiptType
	attribution, err := guestruntimedomain.ResolveRecorderArtifactAttribution(
		guestruntimedomain.RecorderAttributionResolutionInput{
			ArtifactID:           artifact.ArtifactID,
			ReportedBedName:      &source.ReportedBedName,
			EvidenceObservedAt:   source.FinalizedAt,
			CandidateRecorderIDs: nil,
			PolicyVersion:        "assignment-owner-v1",
			ResolvedAt:           persistedAt,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	receipt := guestruntimedomain.ArchiveSourceAdmissionReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     command.RequestID,
		Outcome:       "accepted",
		ArtifactReference: &guestruntimedomain.ResourceReference{
			ResourceType: "archive-artifact",
			ResourceID:   artifact.ArtifactID,
		},
		ReceivedAt:  receivedAt,
		PersistedAt: persistedAt,
	}
	if err := repository.CommitAcceptedArchiveSourceAdmission(
		context.Background(),
		digest,
		command,
		receipt,
		artifact,
		attribution,
	); err != nil {
		t.Fatalf("commit accepted Archive source admission: %v", err)
	}
	stored, err := repository.ReadArchiveSourceAdmission(
		context.Background(),
		command.RequestID,
	)
	if err != nil {
		t.Fatalf("read Archive source admission: %v", err)
	}
	if stored.CommandDigest != digest ||
		stored.Receipt.Outcome != "accepted" ||
		stored.Command.Source.ID != source.ID {
		t.Fatalf("stored Archive source admission lost idempotency evidence: %#v", stored)
	}
	detail, err := repository.ReadArchiveArtifactDetailBySourceReceipt(
		context.Background(),
		source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		source.ID,
	)
	if err != nil {
		t.Fatalf("read Archive artifact by source receipt: %v", err)
	}
	if detail.Artifact.ArtifactID != artifact.ArtifactID ||
		detail.Attribution.Outcome != guestruntimedomain.UnresolvedRecorderAttributionOutcome {
		t.Fatalf("accepted source lineage is wrong: %#v", detail)
	}

	duplicateCommand := command
	duplicateCommand.RequestID = "archive-source-admission-request-2"
	duplicateDigest, err := guestruntimedomain.CommandDigest(duplicateCommand)
	if err != nil {
		t.Fatal(err)
	}
	duplicateReceipt := receipt
	duplicateReceipt.RequestID = duplicateCommand.RequestID
	duplicateReceipt.Outcome = "duplicate"
	if err := repository.CommitTerminalArchiveSourceAdmission(
		context.Background(),
		duplicateDigest,
		duplicateCommand,
		duplicateReceipt,
	); err != nil {
		t.Fatalf("commit duplicate Archive source admission: %v", err)
	}
}

func archiveIntegrationArtifact(
	artifactID string,
	manifestID string,
	sourceReceiptID string,
	finalizedAt string,
) guestruntimedomain.ArchiveArtifact {
	digest := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	manifest := guestruntimedomain.ArchiveLineageManifest{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ID:            manifestID,
		Source: guestruntimedomain.ArchiveLineageManifestSource{
			Kind:        guestruntimedomain.RecorderUploadArchiveSourceKind,
			ReceiptType: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
			ReceiptID:   sourceReceiptID,
			FinalizedAt: finalizedAt,
			EvidenceReference: guestruntimedomain.EvidenceReference{
				Kind: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
				ID:   sourceReceiptID,
			},
		},
		Artifact: guestruntimedomain.ArchiveLineageArtifactIdentity{
			ArtifactID: artifactID,
			SHA256:     digest,
			ByteSize:   20,
			MediaType:  "application/x-vital",
			StorageReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-archive-object",
				ResourceID:   artifactID,
			},
		},
		CreatedAt: finalizedAt,
	}
	return guestruntimedomain.ArchiveArtifact{
		SchemaVersion:     guestruntimedomain.SchemaVersion,
		ArtifactID:        artifactID,
		SourceKind:        guestruntimedomain.RecorderUploadArchiveSourceKind,
		SourceReceiptType: guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		SourceReceiptID:   sourceReceiptID,
		Manifest:          manifest,
		OriginalFileName:  "archive-integration.vital",
		MediaType:         "application/x-vital",
		ByteSize:          20,
		SHA256:            digest,
		FinalizationState: "finalized",
		CreatedAt:         finalizedAt,
		FinalizedAt:       &finalizedAt,
	}
}
