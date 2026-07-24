package guestruntimeapplication

import (
	"context"
	"encoding/base64"
	"encoding/json"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type recorderSummaryCursor struct {
	RecorderID string `json:"recorderId"`
}

func (service *GuestRuntimeObservationCatalogApplicationService) ReadRecorderObservabilitySummaryPage(
	ctx context.Context,
	limit int,
	cursor string,
) guestruntimedomain.ReadResult {
	observedTime := service.clock.Now()
	observedAt := guestruntimedomain.Timestamp(observedTime)
	position, issue := decodeRecorderSummaryPageRequest(limit, cursor)
	if issue != nil {
		return invalidRead(observedAt, issue.Code, issue.Message)
	}
	summaries, err := service.repository.ListRecorderObservabilitySummaries(
		ctx,
		limit+1,
		position,
	)
	if err != nil {
		return failedRead(observedAt, "recorder-summary-page-read-failed", err.Error(), "observation-catalog")
	}
	if len(summaries) == 0 {
		return guestruntimedomain.ReadResult{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "empty",
			ObservedAt:    observedAt,
		}
	}
	projected := make([]guestruntimedomain.RecorderObservabilitySummary, 0, min(len(summaries), limit))
	for index, summary := range summaries {
		if index == limit {
			break
		}
		fresh, err := guestruntimedomain.ProjectRecorderReportFreshness(
			summary,
			service.freshness,
			observedTime,
		)
		if err != nil {
			return failedRead(observedAt, "recorder-observation-freshness-projection-failed", err.Error(), "observation-catalog")
		}
		projected = append(projected, fresh)
	}
	var nextCursor *string
	if len(summaries) > limit {
		encoded, err := json.Marshal(recorderSummaryCursor{
			RecorderID: projected[len(projected)-1].RecorderID,
		})
		if err != nil {
			return failedRead(observedAt, "recorder-summary-page-cursor-failed", err.Error(), "observation-catalog")
		}
		value := base64.RawURLEncoding.EncodeToString(encoded)
		nextCursor = &value
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    observedAt,
		Value: guestruntimedomain.RecorderObservabilitySummaryPage{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			Items:         projected,
			NextCursor:    nextCursor,
		},
	}
}

func decodeRecorderSummaryPageRequest(
	limit int,
	cursor string,
) (*RecorderSummaryPagePosition, *guestruntimedomain.Issue) {
	if limit < 1 || limit > 100 {
		return nil, &guestruntimedomain.Issue{
			Code:    "invalid-recorder-summary-page-limit",
			Message: "limit must be between 1 and 100",
		}
	}
	if cursor == "" {
		return nil, nil
	}
	encoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return nil, invalidRecorderSummaryCursorIssue()
	}
	var decoded recorderSummaryCursor
	if err := json.Unmarshal(encoded, &decoded); err != nil ||
		!guestruntimedomain.ValidIdentifier(decoded.RecorderID) {
		return nil, invalidRecorderSummaryCursorIssue()
	}
	return &RecorderSummaryPagePosition{RecorderID: decoded.RecorderID}, nil
}

func invalidRecorderSummaryCursorIssue() *guestruntimedomain.Issue {
	return &guestruntimedomain.Issue{
		Code:    "invalid-recorder-summary-page-cursor",
		Message: "cursor is not a valid opaque Recorder summary cursor",
	}
}
