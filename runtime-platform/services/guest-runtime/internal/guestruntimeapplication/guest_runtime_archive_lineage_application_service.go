package guestruntimeapplication

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type archiveArtifactCursor struct {
	ResolvedAt string `json:"resolvedAt"`
	ArtifactID string `json:"artifactId"`
}

type GuestRuntimeArchiveLineageApplicationService struct {
	repository GuestRuntimeArchiveLineageRepository
	clock      GuestRuntimeClock
}

func NewGuestRuntimeArchiveLineageApplicationService(
	repository GuestRuntimeArchiveLineageRepository,
	clock GuestRuntimeClock,
) (*GuestRuntimeArchiveLineageApplicationService, error) {
	if repository == nil || clock == nil {
		return nil, fmt.Errorf("Archive lineage repository and clock are required")
	}
	return &GuestRuntimeArchiveLineageApplicationService{
		repository: repository,
		clock:      clock,
	}, nil
}

func (service *GuestRuntimeArchiveLineageApplicationService) ReadArchiveArtifact(
	ctx context.Context,
	artifactID string,
) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if !guestruntimedomain.ValidIdentifier(artifactID) {
		return invalidRead(
			now,
			"invalid-archive-artifact-id",
			"artifactId must be a valid v1 identifier",
		)
	}
	detail, err := service.repository.ReadArchiveArtifactDetail(ctx, artifactID)
	if errors.Is(err, ErrGuestRuntimeOwnedResourceNotFound) {
		return missingRead(
			now,
			"archive-artifact-missing",
			"the requested Archive artifact does not exist",
		)
	}
	if err != nil {
		return failedRead(
			now,
			"archive-artifact-read-failed",
			err.Error(),
			"archive-export",
		)
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value:         detail,
	}
}

func (service *GuestRuntimeArchiveLineageApplicationService) ReadRecorderArtifacts(
	ctx context.Context,
	recorderID string,
	limit int,
	cursor string,
) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	position, issue := decodeArchiveArtifactPageRequest(
		recorderID,
		limit,
		cursor,
	)
	if issue != nil {
		return invalidRead(now, issue.Code, issue.Message)
	}
	details, err := service.repository.ListMatchedRecorderArchiveArtifacts(
		ctx,
		recorderID,
		limit+1,
		position,
	)
	if err != nil {
		return failedRead(
			now,
			"recorder-artifact-page-read-failed",
			err.Error(),
			"archive-export",
		)
	}
	if len(details) == 0 {
		return guestruntimedomain.ReadResult{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "empty",
			ObservedAt:    now,
		}
	}
	items, nextCursor, err := boundRecorderArtifactPage(details, limit)
	if err != nil {
		return failedRead(
			now,
			"recorder-artifact-page-cursor-failed",
			err.Error(),
			"archive-export",
		)
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    now,
		Value: guestruntimedomain.RecorderArtifactPage{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			RecorderID:    recorderID,
			Items:         items,
			NextCursor:    nextCursor,
		},
	}
}

func decodeArchiveArtifactPageRequest(
	recorderID string,
	limit int,
	cursor string,
) (*ArchiveArtifactPagePosition, *guestruntimedomain.Issue) {
	if !guestruntimedomain.ValidIdentifier(recorderID) {
		return nil, &guestruntimedomain.Issue{
			Code:    "invalid-recorder-id",
			Message: "recorderId must be a valid v1 identifier",
		}
	}
	if limit < 1 || limit > MaximumRecorderArtifactPageSize {
		return nil, &guestruntimedomain.Issue{
			Code:    "invalid-recorder-artifact-limit",
			Message: "limit must be between 1 and 100",
		}
	}
	if cursor == "" {
		return nil, nil
	}
	encoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return nil, invalidArchiveArtifactCursorIssue()
	}
	var decoded archiveArtifactCursor
	if err := json.Unmarshal(encoded, &decoded); err != nil ||
		!guestruntimedomain.ValidIdentifier(decoded.ArtifactID) {
		return nil, invalidArchiveArtifactCursorIssue()
	}
	if _, err := time.Parse(time.RFC3339Nano, decoded.ResolvedAt); err != nil {
		return nil, invalidArchiveArtifactCursorIssue()
	}
	return &ArchiveArtifactPagePosition{
		ResolvedAt: decoded.ResolvedAt,
		ArtifactID: decoded.ArtifactID,
	}, nil
}

func invalidArchiveArtifactCursorIssue() *guestruntimedomain.Issue {
	return &guestruntimedomain.Issue{
		Code:    "invalid-recorder-artifact-cursor",
		Message: "cursor is not a valid opaque Recorder artifact cursor",
	}
}

func boundRecorderArtifactPage(
	details []guestruntimedomain.ArchiveArtifactDetail,
	limit int,
) ([]guestruntimedomain.ArchiveArtifactDetail, *string, error) {
	if len(details) <= limit {
		return details, nil, nil
	}
	items := details[:limit]
	last := items[len(items)-1]
	encoded, err := json.Marshal(archiveArtifactCursor{
		ResolvedAt: last.Attribution.ResolvedAt,
		ArtifactID: last.Artifact.ArtifactID,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("encode Recorder artifact cursor: %w", err)
	}
	cursor := base64.RawURLEncoding.EncodeToString(encoded)
	return items, &cursor, nil
}
