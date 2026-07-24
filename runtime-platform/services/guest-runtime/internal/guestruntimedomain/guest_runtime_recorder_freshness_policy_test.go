package guestruntimedomain

import (
	"testing"
	"time"
)

func TestRecorderFreshnessUsesCatalogReceivedTimeWithoutChangingOtherAxes(t *testing.T) {
	received := "2026-07-24T00:00:00Z"
	summary := RecorderObservabilitySummary{
		SchemaVersion: SchemaVersion, RecorderID: "recorder-1", ResourceRevision: 3,
		SupportState: "supported", ExpectationState: "expected", ReportState: "current",
		ReadState: "available", LatestReceivedAt: &received, UpdatedAt: received,
	}
	projected, err := ProjectRecorderReportFreshness(
		summary,
		RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300},
		time.Date(2026, 7, 24, 0, 5, 1, 0, time.UTC),
	)
	if err != nil {
		t.Fatal(err)
	}
	if projected.ReportState != "stale" || projected.SupportState != "supported" || projected.ExpectationState != "expected" || projected.ResourceRevision != 3 {
		t.Fatalf("freshness projection changed unrelated axes: %+v", projected)
	}
}

func TestRecorderFreshnessRejectsFutureCatalogTimestamp(t *testing.T) {
	received := "2026-07-24T00:00:01Z"
	_, err := ProjectRecorderReportFreshness(
		RecorderObservabilitySummary{ReportState: "current", LatestReceivedAt: &received},
		RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300},
		time.Date(2026, 7, 24, 0, 0, 0, 0, time.UTC),
	)
	if err == nil {
		t.Fatal("future Catalog timestamp must be an explicit failed read input")
	}
}
