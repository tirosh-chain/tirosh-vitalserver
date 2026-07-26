package guestruntimeapplication

import (
	"context"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type archiveLineageApplicationTestRepository struct {
	details []guestruntimedomain.ArchiveArtifactDetail
}

func (repository *archiveLineageApplicationTestRepository) CommitFinalizedArchiveArtifact(
	context.Context,
	guestruntimedomain.ArchiveArtifact,
	guestruntimedomain.RecorderArtifactAttribution,
) error {
	return nil
}

func (repository *archiveLineageApplicationTestRepository) CommitArchiveUploadAttempt(
	context.Context,
	guestruntimedomain.ArchiveUploadAttempt,
) error {
	return nil
}

func (repository *archiveLineageApplicationTestRepository) CommitArchiveIndexingReceipt(
	context.Context,
	guestruntimedomain.ArchiveIndexingReceipt,
) error {
	return nil
}

func (repository *archiveLineageApplicationTestRepository) ReadArchiveArtifactDetail(
	_ context.Context,
	artifactID string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	for _, detail := range repository.details {
		if detail.Artifact.ArtifactID == artifactID {
			return detail, nil
		}
	}
	return guestruntimedomain.ArchiveArtifactDetail{}, ErrGuestRuntimeOwnedResourceNotFound
}

func (repository *archiveLineageApplicationTestRepository) ListMatchedRecorderArchiveArtifacts(
	_ context.Context,
	recorderID string,
	limit int,
	position *ArchiveArtifactPagePosition,
) ([]guestruntimedomain.ArchiveArtifactDetail, error) {
	result := make([]guestruntimedomain.ArchiveArtifactDetail, 0, limit)
	for _, detail := range repository.details {
		if detail.Attribution.MatchedRecorderID == nil ||
			*detail.Attribution.MatchedRecorderID != recorderID {
			continue
		}
		if position != nil &&
			!(detail.Attribution.ResolvedAt < position.ResolvedAt ||
				(detail.Attribution.ResolvedAt == position.ResolvedAt &&
					detail.Artifact.ArtifactID < position.ArtifactID)) {
			continue
		}
		result = append(result, detail)
		if len(result) == limit {
			break
		}
	}
	return result, nil
}

func TestRecorderArtifactReadUsesOpaqueBoundedCursor(t *testing.T) {
	recorderID := "recorder-1"
	repository := &archiveLineageApplicationTestRepository{
		details: []guestruntimedomain.ArchiveArtifactDetail{
			archiveLineageDetailForTest("artifact-3", recorderID, "2026-07-24T09:03:00Z"),
			archiveLineageDetailForTest("artifact-2", recorderID, "2026-07-24T09:02:00Z"),
			archiveLineageDetailForTest("artifact-1", recorderID, "2026-07-24T09:01:00Z"),
		},
	}
	service, err := NewGuestRuntimeArchiveLineageApplicationService(
		repository,
		fixedArchiveLineageClock{at: time.Date(2026, 7, 24, 9, 4, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	first := service.ReadRecorderArtifacts(context.Background(), recorderID, 2, "")
	if first.State != "available" {
		t.Fatalf("expected available first page, got %#v", first)
	}
	page := first.Value.(guestruntimedomain.RecorderArtifactPage)
	if len(page.Items) != 2 || page.NextCursor == nil {
		t.Fatalf("expected bounded first page and cursor, got %#v", page)
	}
	second := service.ReadRecorderArtifacts(
		context.Background(),
		recorderID,
		2,
		*page.NextCursor,
	)
	secondPage := second.Value.(guestruntimedomain.RecorderArtifactPage)
	if len(secondPage.Items) != 1 ||
		secondPage.Items[0].Artifact.ArtifactID != "artifact-1" {
		t.Fatalf("expected next keyset page, got %#v", secondPage)
	}
}

type fixedArchiveLineageClock struct {
	at time.Time
}

func (clock fixedArchiveLineageClock) Now() time.Time {
	return clock.at
}

func archiveLineageDetailForTest(
	artifactID string,
	recorderID string,
	resolvedAt string,
) guestruntimedomain.ArchiveArtifactDetail {
	return guestruntimedomain.ArchiveArtifactDetail{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		Artifact: guestruntimedomain.ArchiveArtifact{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			ArtifactID:    artifactID,
		},
		Attribution: guestruntimedomain.RecorderArtifactAttribution{
			SchemaVersion:     guestruntimedomain.SchemaVersion,
			ArtifactID:        artifactID,
			Outcome:           guestruntimedomain.MatchedRecorderAttributionOutcome,
			MatchedRecorderID: &recorderID,
			ResolvedAt:        resolvedAt,
		},
		UploadAttempts:   []guestruntimedomain.ArchiveUploadAttempt{},
		IndexingReceipts: []guestruntimedomain.ArchiveIndexingReceipt{},
	}
}
