package gueststatepostgresqlrepository_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type integrationClock struct{ now time.Time }

func (clock integrationClock) Now() time.Time { return clock.now }

type integrationIdentifierGenerator struct{ id string }

func (generator integrationIdentifierGenerator) NewRequestCorrelationIdentifier(string) (string, error) {
	return generator.id, nil
}

func TestRecorderCatalogPostgreSQLRepositoryPersistsAtomicIdempotentAdmission(t *testing.T) {
	databaseURL := os.Getenv("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is not configured")
	}
	repository, err := gueststatepostgresqlrepository.OpenRecorderCatalogPostgreSQLRepository(
		context.Background(),
		databaseURL,
	)
	if err != nil {
		t.Fatalf("open Recorder Catalog PostgreSQL repository: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })

	now := time.Date(2026, 7, 24, 3, 4, 5, 0, time.UTC)
	service, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
		repository,
		integrationClock{now: now},
		integrationIdentifierGenerator{id: "postgres-operation-1"},
		guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300},
	)
	if err != nil {
		t.Fatalf("compose Recorder Catalog application service: %v", err)
	}
	source := "recorder-ntp"
	offset := 0.25
	uncertainty := 0.5
	lastSync := "2026-07-24T03:04:00Z"
	version := "1.2.3"
	command := guestruntimedomain.CatalogObservationIngestCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "postgres-request-1",
		ObservationID: "postgres-observation-1",
		Envelope: guestruntimedomain.RecorderObservationEnvelope{
			SchemaVersion:   guestruntimedomain.SchemaVersion,
			ProtocolVersion: "v1",
			RecorderID:      "postgres-recorder-1",
			BootID:          "postgres-boot-1",
			Sequence:        1,
			OccurredAt:      "2026-07-24T03:04:01Z",
			Time: guestruntimedomain.RecorderTimeObservation{
				State:         "synchronized",
				SourceID:      &source,
				OffsetMs:      &offset,
				UncertaintyMs: &uncertainty,
				LastSyncAt:    &lastSync,
			},
			Runtime: guestruntimedomain.RecorderRuntimeObservation{
				State:   "ready",
				Version: &version,
			},
		},
	}

	evidence := guestruntimeapplication.CatalogObservationAdmissionEvidence{SourceIdentity: "recorder-gateway", MediaType: "application/json", ReceivedBytes: 2048}
	first, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), command, evidence)
	if rejection != nil || admissionFailure != nil || first.Outcome != "accepted" {
		t.Fatalf("first PostgreSQL admission=%+v rejection=%+v admissionFailure=%+v", first, rejection, admissionFailure)
	}
	second, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), command, evidence)
	if rejection != nil || admissionFailure != nil || second.RequestID != first.RequestID || second.Outcome != "accepted" {
		t.Fatalf("idempotent PostgreSQL admission=%+v rejection=%+v admissionFailure=%+v", second, rejection, admissionFailure)
	}
	replay := command
	replay.RequestID = "postgres-request-duplicate-1"
	replay.ObservationID = "postgres-observation-duplicate-1"
	duplicate, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), replay, evidence)
	if rejection != nil || admissionFailure != nil || duplicate.Outcome != "duplicate" || duplicate.DuplicateOfObservationReference == nil || duplicate.DuplicateOfObservationReference.ResourceID != command.ObservationID {
		t.Fatalf("duplicate PostgreSQL admission=%+v rejection=%+v admissionFailure=%+v", duplicate, rejection, admissionFailure)
	}
	read := service.ReadCatalogObservation(context.Background(), command.ObservationID)
	if read.State != "available" {
		t.Fatalf("PostgreSQL Catalog read=%+v", read)
	}
	summaryRead := service.ReadRecorderObservabilitySummary(context.Background(), command.Envelope.RecorderID)
	if summaryRead.State != "available" {
		t.Fatalf("PostgreSQL Recorder current projection read=%+v", summaryRead)
	}
	summary := summaryRead.Value.(guestruntimedomain.RecorderObservabilitySummary)
	if summary.ResourceRevision != 1 || summary.SupportState != "supported" || summary.ExpectationState != "unset" || summary.ReportState != "current" {
		t.Fatalf("PostgreSQL Recorder current projection=%+v", summary)
	}
	expected := "expected"
	expectationSource := "operator-console"
	expectationCommand := guestruntimedomain.RecorderObservabilityExpectationCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                "postgres-expectation-request-1",
		ExpectedResourceRevision: 0,
		Action:                   "set",
		ExpectationState:         &expected,
		Source:                   &expectationSource,
		Evidence:                 map[string]any{"ticketId": "support-1"},
	}
	receipt, rejection, admissionFailure := service.ApplyRecorderExpectation(context.Background(), command.Envelope.RecorderID, expectationCommand)
	if rejection != nil || admissionFailure != nil || receipt.State != "persisted" || receipt.Revision != 1 {
		t.Fatalf("PostgreSQL expectation receipt=%+v rejection=%+v admissionFailure=%+v", receipt, rejection, admissionFailure)
	}
	replayedReceipt, rejection, admissionFailure := service.ApplyRecorderExpectation(context.Background(), command.Envelope.RecorderID, expectationCommand)
	if rejection != nil || admissionFailure != nil || replayedReceipt != receipt {
		t.Fatalf("idempotent PostgreSQL expectation receipt=%+v rejection=%+v admissionFailure=%+v", replayedReceipt, rejection, admissionFailure)
	}
	summaryRead = service.ReadRecorderObservabilitySummary(context.Background(), command.Envelope.RecorderID)
	summary = summaryRead.Value.(guestruntimedomain.RecorderObservabilitySummary)
	if summary.ResourceRevision != 2 || summary.SupportState != "supported" || summary.ExpectationState != "expected" || summary.ReportState != "current" {
		t.Fatalf("PostgreSQL expectation/current transaction projection=%+v", summary)
	}
	reportedIssue := guestruntimedomain.Issue{Code: "recorder-runtime-failed", Message: "Recorder reported its runtime failure"}
	incidentCommand := command
	incidentCommand.RequestID = "postgres-request-incident-1"
	incidentCommand.ObservationID = "postgres-observation-incident-1"
	incidentCommand.Envelope.Sequence = 2
	incidentCommand.Envelope.OccurredAt = "2026-07-24T03:04:02Z"
	incidentCommand.Envelope.Runtime = guestruntimedomain.RecorderRuntimeObservation{State: "failed", Issue: &reportedIssue}
	incidentAdmission, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), incidentCommand, evidence)
	if rejection != nil || admissionFailure != nil || incidentAdmission.Outcome != "accepted" {
		t.Fatalf("PostgreSQL incident observation=%+v rejection=%+v admissionFailure=%+v", incidentAdmission, rejection, admissionFailure)
	}
	timelineRead := service.ReadRecorderObservationTimeline(context.Background(), command.Envelope.RecorderID, 1, "")
	timelinePage := timelineRead.Value.(guestruntimedomain.RecorderObservationTimelinePage)
	if len(timelinePage.Items) != 1 || timelinePage.NextCursor == nil {
		t.Fatalf("PostgreSQL bounded timeline page=%+v", timelinePage)
	}
	nextTimelineRead := service.ReadRecorderObservationTimeline(context.Background(), command.Envelope.RecorderID, 1, *timelinePage.NextCursor)
	nextTimelinePage := nextTimelineRead.Value.(guestruntimedomain.RecorderObservationTimelinePage)
	if len(nextTimelinePage.Items) != 1 || nextTimelinePage.NextCursor != nil {
		t.Fatalf("PostgreSQL bounded timeline second page=%+v", nextTimelinePage)
	}
	incidentRead := service.ReadRecorderIncidentHistory(context.Background(), command.Envelope.RecorderID, 10, "")
	incidentPage := incidentRead.Value.(guestruntimedomain.RecorderIncidentPage)
	if len(incidentPage.Items) != 1 || incidentPage.Items[0].RuntimeIssue == nil || incidentPage.Items[0].RuntimeIssue.Code != reportedIssue.Code {
		t.Fatalf("PostgreSQL Recorder-reported incident page=%+v", incidentPage)
	}
	staleReader, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
		repository,
		integrationClock{now: now.Add(301 * time.Second)},
		integrationIdentifierGenerator{id: "unused-stale-reader-id"},
		guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300},
	)
	if err != nil {
		t.Fatal(err)
	}
	staleRead := staleReader.ReadRecorderObservabilitySummary(context.Background(), command.Envelope.RecorderID)
	staleSummary := staleRead.Value.(guestruntimedomain.RecorderObservabilitySummary)
	if staleSummary.ReportState != "stale" || staleSummary.ExpectationState != "expected" || staleSummary.SupportState != "supported" {
		t.Fatalf("PostgreSQL freshness projection changed unrelated state=%+v", staleSummary)
	}
	quarantinedSource := map[string]any{
		"schemaVersion": "v1",
		"requestId":     "postgres-quarantine-request-1",
		"envelope":      map[string]any{"occurredAt": "not-a-time"},
	}
	quarantined, rejection, admissionFailure := service.QuarantineCatalogObservation(
		context.Background(),
		"postgres-quarantine-request-1",
		quarantinedSource,
		guestruntimedomain.Issue{Code: "invalid-recorder-observation-document", Message: "Recorder observation did not match the command contract"},
		evidence,
	)
	if rejection != nil || admissionFailure != nil || quarantined.Outcome != "quarantined" {
		t.Fatalf("PostgreSQL quarantine=%+v rejection=%+v admissionFailure=%+v", quarantined, rejection, admissionFailure)
	}
	replayedQuarantine, rejection, admissionFailure := service.QuarantineCatalogObservation(
		context.Background(),
		"postgres-quarantine-request-1",
		quarantinedSource,
		guestruntimedomain.Issue{Code: "invalid-recorder-observation-document", Message: "Recorder observation did not match the command contract"},
		evidence,
	)
	if rejection != nil || admissionFailure != nil || replayedQuarantine.RequestID != quarantined.RequestID || replayedQuarantine.Outcome != quarantined.Outcome || replayedQuarantine.PersistedAt != quarantined.PersistedAt || replayedQuarantine.Issue == nil || quarantined.Issue == nil || replayedQuarantine.Issue.Code != quarantined.Issue.Code {
		t.Fatalf("idempotent PostgreSQL quarantine=%+v rejection=%+v admissionFailure=%+v", replayedQuarantine, rejection, admissionFailure)
	}
}
