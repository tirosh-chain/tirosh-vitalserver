package guestruntimeapplication

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type recorderHistoryCursor struct {
	PersistedAt   string `json:"persistedAt"`
	ObservationID string `json:"observationId"`
}

func (service *GuestRuntimeObservationCatalogApplicationService) ReadRecorderObservationTimeline(ctx context.Context, recorderID string, limit int, cursor string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	position, issue := decodeRecorderHistoryRequest(recorderID, limit, cursor)
	if issue != nil {
		return invalidRead(now, issue.Code, issue.Message)
	}
	observations, err := service.repository.ListRecorderCatalogObservations(ctx, recorderID, limit+1, position, false)
	if err != nil {
		return failedRead(now, "recorder-observation-timeline-read-failed", err.Error(), "observation-catalog")
	}
	if len(observations) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	pageItems, nextCursor, err := boundRecorderHistory(observations, limit)
	if err != nil {
		return failedRead(now, "recorder-observation-timeline-cursor-failed", err.Error(), "observation-catalog")
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now,
		Value: guestruntimedomain.RecorderObservationTimelinePage{SchemaVersion: guestruntimedomain.SchemaVersion, RecorderID: recorderID, Items: pageItems, NextCursor: nextCursor},
	}
}

func (service *GuestRuntimeObservationCatalogApplicationService) ReadRecorderIncidentHistory(ctx context.Context, recorderID string, limit int, cursor string) guestruntimedomain.ReadResult {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	position, issue := decodeRecorderHistoryRequest(recorderID, limit, cursor)
	if issue != nil {
		return invalidRead(now, issue.Code, issue.Message)
	}
	observations, err := service.repository.ListRecorderCatalogObservations(ctx, recorderID, limit+1, position, true)
	if err != nil {
		return failedRead(now, "recorder-incident-history-read-failed", err.Error(), "observation-catalog")
	}
	if len(observations) == 0 {
		return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "empty", ObservedAt: now}
	}
	pageItems, nextCursor, err := boundRecorderHistory(observations, limit)
	if err != nil {
		return failedRead(now, "recorder-incident-history-cursor-failed", err.Error(), "observation-catalog")
	}
	incidents := make([]guestruntimedomain.RecorderReportedIncident, 0, len(pageItems))
	for _, observation := range pageItems {
		incident, reported := guestruntimedomain.ProjectRecorderReportedIncident(observation)
		if !reported {
			return failedRead(now, "recorder-incident-query-owner-mismatch", "incident query returned an observation without a Recorder-reported issue", "observation-catalog")
		}
		incidents = append(incidents, incident)
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion, State: "available", ObservedAt: now,
		Value: guestruntimedomain.RecorderIncidentPage{SchemaVersion: guestruntimedomain.SchemaVersion, RecorderID: recorderID, Items: incidents, NextCursor: nextCursor},
	}
}

func decodeRecorderHistoryRequest(recorderID string, limit int, cursor string) (*CatalogObservationPagePosition, *guestruntimedomain.Issue) {
	if !guestruntimedomain.ValidIdentifier(recorderID) {
		return nil, &guestruntimedomain.Issue{Code: "invalid-recorder-id", Message: "recorderId must be a valid v1 identifier"}
	}
	if limit < 1 || limit > 100 {
		return nil, &guestruntimedomain.Issue{Code: "invalid-recorder-history-limit", Message: "limit must be between 1 and 100"}
	}
	if cursor == "" {
		return nil, nil
	}
	encoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return nil, &guestruntimedomain.Issue{Code: "invalid-recorder-history-cursor", Message: "cursor is not a valid opaque Recorder history cursor"}
	}
	var decoded recorderHistoryCursor
	if err := json.Unmarshal(encoded, &decoded); err != nil || !guestruntimedomain.ValidIdentifier(decoded.ObservationID) {
		return nil, &guestruntimedomain.Issue{Code: "invalid-recorder-history-cursor", Message: "cursor is not a valid opaque Recorder history cursor"}
	}
	if _, err := time.Parse(time.RFC3339Nano, decoded.PersistedAt); err != nil {
		return nil, &guestruntimedomain.Issue{Code: "invalid-recorder-history-cursor", Message: "cursor is not a valid opaque Recorder history cursor"}
	}
	return &CatalogObservationPagePosition{PersistedAt: decoded.PersistedAt, ObservationID: decoded.ObservationID}, nil
}

func boundRecorderHistory(observations []guestruntimedomain.CatalogObservation, limit int) ([]guestruntimedomain.CatalogObservation, *string, error) {
	if len(observations) <= limit {
		return observations, nil, nil
	}
	items := observations[:limit]
	last := items[len(items)-1]
	encoded, err := json.Marshal(recorderHistoryCursor{PersistedAt: last.PersistedAt, ObservationID: last.ID})
	if err != nil {
		return nil, nil, fmt.Errorf("encode Recorder history cursor: %w", err)
	}
	cursor := base64.RawURLEncoding.EncodeToString(encoded)
	return items, &cursor, nil
}
