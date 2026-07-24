package guestruntimeapplication_test

import (
	"context"
	"encoding/json"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/externalupstreamobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func newOperationalRepository(t *testing.T) *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository {
	t.Helper()
	repository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open SQLite: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	return repository
}

func operationalClock() fixedClock {
	return fixedClock{now: time.Date(2026, 7, 17, 9, 0, 0, 0, time.UTC)}
}

func guestNode() guestruntimedomain.NodeReference {
	return guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-test"}
}

func timeCommand(requestID string, authorityID string, node guestruntimedomain.NodeReference) guestruntimedomain.TimeAuthorityApplyCommand {
	return guestruntimedomain.TimeAuthorityApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                requestID,
		AuthorityID:              authorityID,
		ExpectedResourceRevision: 0,
		Node:                     node,
		Spec:                     guestruntimedomain.TimeAuthoritySpec{Profile: "enterprise-ntp", Source: guestruntimedomain.TimeSource{Profile: "enterprise-ntp", SourceID: "ntp-primary"}},
	}
}

func TestGuestTimeAuthorityRequiresExplicitQualityEvidenceAndKeepsUnknownProbeRunning(t *testing.T) {
	repository := newOperationalRepository(t)
	probe, err := timeprovider.NewConfiguredTimeAuthorityOutcomeProfile(timeprovider.ModeSynchronized)
	if err != nil {
		t.Fatal(err)
	}
	service, err := guestruntimeapplication.NewGuestRuntimeTimeAuthorityApplicationService(repository, probe, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestNode(), "guest-time")
	if err != nil {
		t.Fatal(err)
	}
	operation, rejection, admissionFailure := service.ApplyTimeAuthority(context.Background(), timeCommand("time-apply-1", "guest-time", guestNode()))
	if rejection != nil || admissionFailure != nil || operation.State != "succeeded" {
		t.Fatalf("time apply operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	qualityRead := service.ReadGuestClockQuality(context.Background())
	if qualityRead.State != "available" {
		t.Fatalf("clock quality read=%+v", qualityRead)
	}
	quality := qualityRead.Value.(guestruntimedomain.ClockQuality)
	if quality.State != "synchronized" || quality.Source == nil || quality.Stratum == nil || quality.OffsetMs == nil || quality.UncertaintyMs == nil || quality.LastSyncAt == nil {
		t.Fatalf("synchronized quality lacks evidence=%+v", quality)
	}

	unknownProbe, err := timeprovider.NewConfiguredTimeAuthorityOutcomeProfile(timeprovider.ModeOutcomeUnknown)
	if err != nil {
		t.Fatal(err)
	}
	unknown, err := guestruntimeapplication.NewGuestRuntimeTimeAuthorityApplicationService(repository, unknownProbe, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestNode(), "guest-time-unknown")
	if err != nil {
		t.Fatal(err)
	}
	unknownOperation, rejection, admissionFailure := unknown.ApplyTimeAuthority(context.Background(), timeCommand("time-unknown-1", "guest-time-unknown", guestNode()))
	if rejection != nil || admissionFailure != nil || unknownOperation.State != "running" {
		t.Fatalf("unknown time operation=%+v rejection=%+v admissionFailure=%+v", unknownOperation, rejection, admissionFailure)
	}
	if read := unknown.ReadTimeAuthority(context.Background(), "guest-time-unknown"); read.State != "missing" {
		t.Fatalf("unknown time probe wrote a ClockQuality=%+v", read)
	}
}

func recorderEnvelope(sequence int, runtimeVersion string) guestruntimedomain.RecorderObservationEnvelope {
	offset := 0.5
	uncertainty := 1.0
	source := "recorder-ntp"
	lastSync := "2026-07-17T08:59:00Z"
	return guestruntimedomain.RecorderObservationEnvelope{
		SchemaVersion:   guestruntimedomain.SchemaVersion,
		ProtocolVersion: "v1",
		RecorderID:      "recorder-a",
		BootID:          "boot-a",
		Sequence:        sequence,
		OccurredAt:      "2026-07-17T08:59:00Z",
		Time:            guestruntimedomain.RecorderTimeObservation{State: "synchronized", SourceID: &source, OffsetMs: &offset, UncertaintyMs: &uncertainty, LastSyncAt: &lastSync},
		Runtime:         guestruntimedomain.RecorderRuntimeObservation{State: "ready", Version: &runtimeVersion},
	}
}

func TestObservationCatalogPreservesDeviceOccurrenceAndEnforcesSourceIdentity(t *testing.T) {
	repository := newOperationalCatalogRepository()
	service, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(repository, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300})
	if err != nil {
		t.Fatal(err)
	}
	command := guestruntimedomain.CatalogObservationIngestCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "catalog-1", ObservationID: "observation-1", Envelope: recorderEnvelope(7, "1.2.3")}
	evidence := guestruntimeapplication.CatalogObservationAdmissionEvidence{SourceIdentity: "recorder-gateway", MediaType: "application/json", ReceivedBytes: 1024}
	admission, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), command, evidence)
	if rejection != nil || admissionFailure != nil || admission.Outcome != "accepted" {
		t.Fatalf("catalog ingest admission=%+v rejection=%+v admissionFailure=%+v", admission, rejection, admissionFailure)
	}
	read := service.ReadCatalogObservation(context.Background(), "observation-1")
	if read.State != "available" {
		t.Fatalf("catalog read=%+v", read)
	}
	observation := read.Value.(guestruntimedomain.CatalogObservation)
	if observation.Envelope.OccurredAt != command.Envelope.OccurredAt || observation.SourceIdentity.OccurredAt != command.Envelope.OccurredAt || observation.ReceivedAt == command.Envelope.OccurredAt {
		t.Fatalf("catalog did not preserve source occurrence=%+v", observation)
	}
	summaryRead := service.ReadRecorderObservabilitySummary(context.Background(), command.Envelope.RecorderID)
	if summaryRead.State != "available" {
		t.Fatalf("Recorder current projection read=%+v", summaryRead)
	}
	summary := summaryRead.Value.(guestruntimedomain.RecorderObservabilitySummary)
	if summary.ResourceRevision != 1 || summary.SupportState != "supported" || summary.ExpectationState != "unset" || summary.ReportState != "current" {
		t.Fatalf("Recorder current projection=%+v", summary)
	}
	replay := command
	replay.RequestID = "catalog-2"
	replay.ObservationID = "observation-other-id"
	replayedAdmission, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), replay, evidence)
	if rejection != nil || admissionFailure != nil || replayedAdmission.Outcome != "duplicate" || replayedAdmission.DuplicateOfObservationReference == nil || replayedAdmission.DuplicateOfObservationReference.ResourceID != command.ObservationID {
		t.Fatalf("same source envelope should persist duplicate admission=%+v rejection=%+v admissionFailure=%+v", replayedAdmission, rejection, admissionFailure)
	}
	conflict := command
	conflict.RequestID = "catalog-3"
	conflict.ObservationID = "observation-conflict"
	conflict.Envelope = recorderEnvelope(7, "9.9.9")
	_, rejection, admissionFailure = service.IngestCatalogObservation(context.Background(), conflict, evidence)
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "catalog-source-identity-conflict" {
		t.Fatalf("source conflict rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
}

func TestRecorderHistoryIsBoundedCursorBasedAndIncludesOnlyRecorderReportedIssues(t *testing.T) {
	repository := newOperationalCatalogRepository()
	issue := guestruntimedomain.Issue{Code: "recorder-runtime-failed", Message: "Recorder reported a runtime failure"}
	repository.observations["history-observation-1"] = guestruntimedomain.CatalogObservation{
		SchemaVersion: guestruntimedomain.SchemaVersion, ID: "history-observation-1", ReceivedAt: "2026-07-24T00:00:01Z", PersistedAt: "2026-07-24T00:00:01Z",
		Envelope: guestruntimedomain.RecorderObservationEnvelope{RecorderID: "history-recorder-1", OccurredAt: "2026-07-24T00:00:00Z", Runtime: guestruntimedomain.RecorderRuntimeObservation{State: "ready"}},
	}
	repository.observations["history-observation-2"] = guestruntimedomain.CatalogObservation{
		SchemaVersion: guestruntimedomain.SchemaVersion, ID: "history-observation-2", ReceivedAt: "2026-07-24T00:00:02Z", PersistedAt: "2026-07-24T00:00:02Z",
		Envelope: guestruntimedomain.RecorderObservationEnvelope{RecorderID: "history-recorder-1", OccurredAt: "2026-07-24T00:00:01Z", Runtime: guestruntimedomain.RecorderRuntimeObservation{State: "failed", Issue: &issue}},
	}
	service, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(repository, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300})
	if err != nil {
		t.Fatal(err)
	}
	first := service.ReadRecorderObservationTimeline(context.Background(), "history-recorder-1", 1, "")
	page := first.Value.(guestruntimedomain.RecorderObservationTimelinePage)
	if len(page.Items) != 1 || page.Items[0].ID != "history-observation-2" || page.NextCursor == nil {
		t.Fatalf("first bounded timeline page=%+v", page)
	}
	second := service.ReadRecorderObservationTimeline(context.Background(), "history-recorder-1", 1, *page.NextCursor)
	secondPage := second.Value.(guestruntimedomain.RecorderObservationTimelinePage)
	if len(secondPage.Items) != 1 || secondPage.Items[0].ID != "history-observation-1" || secondPage.NextCursor != nil {
		t.Fatalf("second bounded timeline page=%+v", secondPage)
	}
	incidents := service.ReadRecorderIncidentHistory(context.Background(), "history-recorder-1", 10, "")
	incidentPage := incidents.Value.(guestruntimedomain.RecorderIncidentPage)
	if len(incidentPage.Items) != 1 || incidentPage.Items[0].ObservationReference.ResourceID != "history-observation-2" || incidentPage.Items[0].RuntimeIssue == nil {
		t.Fatalf("Recorder-reported incident page=%+v", incidentPage)
	}
}

func TestRecorderSummaryPageIsOwnerBoundedAndProjectsFreshnessAtReadTime(t *testing.T) {
	repository := newOperationalCatalogRepository()
	bootID := "boot-summary-a"
	sequence := 1
	occurredAt := "2026-07-17T08:49:00Z"
	receivedAt := "2026-07-17T08:50:00Z"
	persistedAt := "2026-07-17T08:50:01Z"
	repository.summaries["recorder-a"] = guestruntimedomain.RecorderObservabilitySummary{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		RecorderID:       "recorder-a",
		ResourceRevision: 1,
		SupportState:     "supported",
		ExpectationState: "expected",
		ReportState:      "current",
		ReadState:        "available",
		LatestObservationReference: &guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.CatalogObservationResourceType,
			ResourceID:   "summary-observation-a",
		},
		LatestBootID:      &bootID,
		LatestSequence:    &sequence,
		LatestOccurredAt:  &occurredAt,
		LatestReceivedAt:  &receivedAt,
		LatestPersistedAt: &persistedAt,
		UpdatedAt:         persistedAt,
	}
	repository.summaries["recorder-b"] = guestruntimedomain.RecorderObservabilitySummary{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		RecorderID:       "recorder-b",
		ResourceRevision: 1,
		SupportState:     "unknown",
		ExpectationState: "unset",
		ReportState:      "never-reported",
		ReadState:        "available",
		UpdatedAt:        "2026-07-17T08:51:00Z",
	}
	service, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
		repository,
		operationalClock(),
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: 300},
	)
	if err != nil {
		t.Fatal(err)
	}
	firstRead := service.ReadRecorderObservabilitySummaryPage(context.Background(), 1, "")
	first := firstRead.Value.(guestruntimedomain.RecorderObservabilitySummaryPage)
	if len(first.Items) != 1 ||
		first.Items[0].RecorderID != "recorder-a" ||
		first.Items[0].ReportState != "stale" ||
		first.NextCursor == nil {
		t.Fatalf("first Recorder summary page=%+v", first)
	}
	secondRead := service.ReadRecorderObservabilitySummaryPage(context.Background(), 1, *first.NextCursor)
	second := secondRead.Value.(guestruntimedomain.RecorderObservabilitySummaryPage)
	if len(second.Items) != 1 ||
		second.Items[0].RecorderID != "recorder-b" ||
		second.Items[0].ReportState != "never-reported" ||
		second.NextCursor != nil {
		t.Fatalf("second Recorder summary page=%+v", second)
	}
	invalid := service.ReadRecorderObservabilitySummaryPage(context.Background(), 1, "not-a-cursor")
	if invalid.State != "invalid" || invalid.Issue == nil ||
		invalid.Issue.Code != "invalid-recorder-summary-page-cursor" {
		t.Fatalf("invalid Recorder summary page cursor read=%+v", invalid)
	}
}

type operationalCatalogRepository struct {
	mu                sync.Mutex
	observations      map[string]guestruntimedomain.CatalogObservation
	bySource          map[string]guestruntimeapplication.CatalogStoredObservation
	byRequest         map[string]guestruntimeapplication.CatalogStoredAdmission
	summaries         map[string]guestruntimedomain.RecorderObservabilitySummary
	expectations      map[string]guestruntimedomain.RecorderExpectation
	expectationEvents map[string]guestruntimeapplication.CatalogStoredExpectationEvent
}

func newOperationalCatalogRepository() *operationalCatalogRepository {
	return &operationalCatalogRepository{
		observations:      make(map[string]guestruntimedomain.CatalogObservation),
		bySource:          make(map[string]guestruntimeapplication.CatalogStoredObservation),
		byRequest:         make(map[string]guestruntimeapplication.CatalogStoredAdmission),
		summaries:         make(map[string]guestruntimedomain.RecorderObservabilitySummary),
		expectations:      make(map[string]guestruntimedomain.RecorderExpectation),
		expectationEvents: make(map[string]guestruntimeapplication.CatalogStoredExpectationEvent),
	}
}

func (repository *operationalCatalogRepository) ReadRecorderExpectation(_ context.Context, recorderID string) (guestruntimedomain.RecorderExpectation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	value, exists := repository.expectations[recorderID]
	if !exists {
		return guestruntimedomain.RecorderExpectation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *operationalCatalogRepository) ReadRecorderExpectationEventByRequestID(_ context.Context, requestID string) (guestruntimeapplication.CatalogStoredExpectationEvent, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	value, exists := repository.expectationEvents[requestID]
	if !exists {
		return guestruntimeapplication.CatalogStoredExpectationEvent{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *operationalCatalogRepository) CommitRecorderExpectation(_ context.Context, event guestruntimedomain.RecorderExpectationEvent, digest string, expectation guestruntimedomain.RecorderExpectation, summary guestruntimedomain.RecorderObservabilitySummary, expectedSummaryRevision int) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.expectationEvents[event.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if current, exists := repository.summaries[summary.RecorderID]; (exists && current.ResourceRevision != expectedSummaryRevision) || (!exists && expectedSummaryRevision != 0) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.expectationEvents[event.RequestID] = guestruntimeapplication.CatalogStoredExpectationEvent{Event: event, CommandDigest: digest}
	repository.expectations[expectation.RecorderID] = expectation
	repository.summaries[summary.RecorderID] = summary
	return nil
}

func (repository *operationalCatalogRepository) ReadCatalogObservation(_ context.Context, id string) (guestruntimedomain.CatalogObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	observation, exists := repository.observations[id]
	if !exists {
		return guestruntimedomain.CatalogObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return observation, nil
}

func (repository *operationalCatalogRepository) ListRecorderCatalogObservations(_ context.Context, recorderID string, limit int, position *guestruntimeapplication.CatalogObservationPagePosition, reportedIssuesOnly bool) ([]guestruntimedomain.CatalogObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	values := make([]guestruntimedomain.CatalogObservation, 0)
	for _, observation := range repository.observations {
		if observation.Envelope.RecorderID != recorderID || (reportedIssuesOnly && observation.Envelope.Time.Issue == nil && observation.Envelope.Runtime.Issue == nil) {
			continue
		}
		if position != nil && !(observation.PersistedAt < position.PersistedAt || (observation.PersistedAt == position.PersistedAt && observation.ID < position.ObservationID)) {
			continue
		}
		values = append(values, observation)
	}
	sort.Slice(values, func(left, right int) bool {
		if values[left].PersistedAt == values[right].PersistedAt {
			return values[left].ID > values[right].ID
		}
		return values[left].PersistedAt > values[right].PersistedAt
	})
	if len(values) > limit {
		values = values[:limit]
	}
	return values, nil
}

func (repository *operationalCatalogRepository) ListRecorderObservabilitySummaries(_ context.Context, limit int, position *guestruntimeapplication.RecorderSummaryPagePosition) ([]guestruntimedomain.RecorderObservabilitySummary, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	values := make([]guestruntimedomain.RecorderObservabilitySummary, 0)
	for _, summary := range repository.summaries {
		if position == nil || summary.RecorderID > position.RecorderID {
			values = append(values, summary)
		}
	}
	sort.Slice(values, func(left, right int) bool {
		return values[left].RecorderID < values[right].RecorderID
	})
	if len(values) > limit {
		values = values[:limit]
	}
	return values, nil
}

func (repository *operationalCatalogRepository) ReadCatalogObservationBySourceKey(_ context.Context, sourceKey string) (guestruntimeapplication.CatalogStoredObservation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	stored, exists := repository.bySource[sourceKey]
	if !exists {
		return guestruntimeapplication.CatalogStoredObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return stored, nil
}

func (repository *operationalCatalogRepository) ReadCatalogObservationAdmissionByRequestID(_ context.Context, requestID string) (guestruntimeapplication.CatalogStoredAdmission, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	admission, exists := repository.byRequest[requestID]
	if !exists {
		return guestruntimeapplication.CatalogStoredAdmission{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return admission, nil
}

func (repository *operationalCatalogRepository) ReadRecorderObservabilitySummary(_ context.Context, recorderID string) (guestruntimedomain.RecorderObservabilitySummary, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	summary, exists := repository.summaries[recorderID]
	if !exists {
		return guestruntimedomain.RecorderObservabilitySummary{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return summary, nil
}

func (repository *operationalCatalogRepository) CommitAcceptedCatalogObservation(_ context.Context, observation guestruntimedomain.CatalogObservation, commandDigest string, envelopeDigest string, admission guestruntimedomain.CatalogObservationAdmission, summary guestruntimedomain.RecorderObservabilitySummary, expectedPreviousRevision int, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	sourceKey := guestruntimedomain.CatalogSourceKey(observation.Envelope)
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if _, exists := repository.bySource[sourceKey]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if existing, exists := repository.summaries[summary.RecorderID]; (exists && existing.ResourceRevision != expectedPreviousRevision) || (!exists && expectedPreviousRevision != 0) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.observations[observation.ID] = observation
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	repository.summaries[summary.RecorderID] = summary
	repository.bySource[sourceKey] = guestruntimeapplication.CatalogStoredObservation{Observation: observation, EnvelopeDigest: envelopeDigest, Admission: admission}
	return nil
}

func (repository *operationalCatalogRepository) CommitDuplicateCatalogObservationAdmission(_ context.Context, commandDigest string, _ string, _ string, admission guestruntimedomain.CatalogObservationAdmission, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	return nil
}

func (repository *operationalCatalogRepository) CommitQuarantinedCatalogObservationAdmission(_ context.Context, commandDigest string, admission guestruntimedomain.CatalogObservationAdmission, _ map[string]any, _ guestruntimeapplication.CatalogObservationAdmissionEvidence) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.byRequest[admission.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[admission.RequestID] = guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}
	return nil
}

func telemetrySpec(maxDistinct int) guestruntimedomain.TelemetryPipelineSpec {
	return guestruntimedomain.TelemetryPipelineSpec{
		Protocol:           "otlp-http",
		CollectorReference: guestruntimedomain.ResourceReference{ResourceType: "otel-collector", ResourceID: "collector-a"},
		SignalKinds:        []string{"logs", "metrics", "traces"},
		Redaction:          guestruntimedomain.TelemetryRedactionPolicy{AllowedAttributeKeys: []string{"operation.kind", "deployment.environment"}, MaxAttributes: 2, MaxValueLength: 16, MaxDistinctValuesPerKey: maxDistinct},
	}
}

func telemetryApplyCommand(requestID string, pipelineID string, spec guestruntimedomain.TelemetryPipelineSpec) guestruntimedomain.TelemetryPipelineApplyCommand {
	return guestruntimedomain.TelemetryPipelineApplyCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: requestID, PipelineID: pipelineID, ExpectedResourceRevision: 0, Node: guestNode(), Spec: spec}
}

func telemetrySignalCommand(requestID string, pipelineID string, attributes map[string]string) guestruntimedomain.TelemetrySignalEmitCommand {
	return guestruntimedomain.TelemetrySignalEmitCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                requestID,
		PipelineID:               pipelineID,
		ExpectedResourceRevision: 1,
		Signal: guestruntimedomain.TelemetryCorrelation{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			Service:       guestruntimedomain.ServiceIdentity{Name: "guest-runtime", Version: "test", InstanceID: "guest-test"},
			SignalKinds:   []string{"logs", "metrics", "traces"},
			SignalName:    "runtime.event",
			EmittedAt:     "2026-07-17T09:00:00Z",
		},
		Attributes: attributes,
	}
}

func TestTelemetryRedactsAndBoundsWithoutChangingExternalIntegration(t *testing.T) {
	repository := newOperationalRepository(t)
	externalReference := integrationReference("external-capability-profile", "external-vitalserver")
	externalProvider, err := externalupstreamobservationprovider.NewConfiguredExternalUpstreamObservationProfile(externalReference, externalupstreamobservationprovider.ModeAvailable)
	if err != nil {
		t.Fatal(err)
	}
	external, err := guestruntimeapplication.NewGuestRuntimeExternalUpstreamApplicationService(repository, externalProvider, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{})
	if err != nil {
		t.Fatal(err)
	}
	externalOperation, rejection, admissionFailure := external.ApplyExternalUpstreamIntegration(context.Background(), externalCommand("external-before-telemetry", "external-primary", externalReference))
	if rejection != nil || admissionFailure != nil || externalOperation.State != "succeeded" {
		t.Fatalf("external operation=%+v rejection=%+v admissionFailure=%+v", externalOperation, rejection, admissionFailure)
	}

	exporter, err := telemetryexporter.NewConfiguredTelemetryExportOutcomeProfile(telemetryexporter.PipelineReady, telemetryexporter.Exported)
	if err != nil {
		t.Fatal(err)
	}
	service, err := guestruntimeapplication.NewGuestRuntimeTelemetryPipelineApplicationService(repository, exporter, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestNode())
	if err != nil {
		t.Fatal(err)
	}
	pipelineOperation, rejection, admissionFailure := service.ApplyTelemetryPipeline(context.Background(), telemetryApplyCommand("telemetry-pipeline-1", "telemetry-primary", telemetrySpec(1)))
	if rejection != nil || admissionFailure != nil || pipelineOperation.State != "succeeded" {
		t.Fatalf("pipeline operation=%+v rejection=%+v admissionFailure=%+v", pipelineOperation, rejection, admissionFailure)
	}
	emit, rejection, admissionFailure := service.EmitTelemetrySignal(context.Background(), telemetrySignalCommand("telemetry-signal-1", "telemetry-primary", map[string]string{
		"operation.kind":         "lab-delete",
		"patient.id":             "must-never-leave-process",
		"deployment.environment": strings.Repeat("x", 17),
		"unbounded.label":        "not-allowlisted",
	}))
	if rejection != nil || admissionFailure != nil || emit.State != "succeeded" {
		t.Fatalf("telemetry emission=%+v rejection=%+v admissionFailure=%+v", emit, rejection, admissionFailure)
	}
	if len(emit.EvidenceReferences) != 1 {
		t.Fatalf("telemetry receipt evidence=%+v", emit.EvidenceReferences)
	}
	receiptRead := service.ReadTelemetryEmissionReceipt(context.Background(), emit.EvidenceReferences[0].ID)
	if receiptRead.State != "available" {
		t.Fatalf("telemetry receipt read=%+v", receiptRead)
	}
	receipt := receiptRead.Value.(guestruntimedomain.TelemetryEmissionReceipt)
	if receipt.Outcome != "exported" || receipt.ExportedAttributeCount != 1 || !contains(receipt.RedactedAttributeKeys, "patient.id") || !contains(receipt.RedactedAttributeKeys, "deployment.environment") || !contains(receipt.RedactedAttributeKeys, "unbounded.label") {
		t.Fatalf("telemetry receipt redaction=%+v", receipt)
	}
	encodedBytes, err := json.Marshal(receipt)
	if err != nil {
		t.Fatalf("encode telemetry receipt: %v", err)
	}
	encoded := string(encodedBytes)
	if strings.Contains(encoded, "must-never-leave-process") || strings.Contains(encoded, "not-allowlisted") {
		t.Fatalf("telemetry receipt retained untrusted value=%s", encoded)
	}
	second, rejection, admissionFailure := service.EmitTelemetrySignal(context.Background(), telemetrySignalCommand("telemetry-signal-2", "telemetry-primary", map[string]string{"operation.kind": "new-value"}))
	if rejection != nil || admissionFailure != nil || second.State != "succeeded" {
		t.Fatalf("cardinality emission=%+v rejection=%+v admissionFailure=%+v", second, rejection, admissionFailure)
	}
	secondReceipt := service.ReadTelemetryEmissionReceipt(context.Background(), second.EvidenceReferences[0].ID).Value.(guestruntimedomain.TelemetryEmissionReceipt)
	if secondReceipt.Outcome != "dropped" || !contains(secondReceipt.DroppedAttributeKeys, "operation.kind") {
		t.Fatalf("cardinality receipt=%+v", secondReceipt)
	}
	after := external.ReadExternalUpstreamIntegrationDocument(context.Background(), "external-primary").Value.(guestruntimedomain.ExternalUpstreamIntegration)
	if after.Status.State != "available" {
		t.Fatalf("telemetry changed external product state=%+v", after.Status)
	}
}

func TestTelemetryExporterUnknownLeavesRunningWithoutReceipt(t *testing.T) {
	repository := newOperationalRepository(t)
	exporter, err := telemetryexporter.NewConfiguredTelemetryExportOutcomeProfile(telemetryexporter.PipelineReady, telemetryexporter.OutcomeUnknown)
	if err != nil {
		t.Fatal(err)
	}
	service, err := guestruntimeapplication.NewGuestRuntimeTelemetryPipelineApplicationService(repository, exporter, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, guestNode())
	if err != nil {
		t.Fatal(err)
	}
	_, rejection, admissionFailure := service.ApplyTelemetryPipeline(context.Background(), telemetryApplyCommand("telemetry-pipeline-unknown", "telemetry-unknown", telemetrySpec(1)))
	if rejection != nil || admissionFailure != nil {
		t.Fatalf("pipeline setup rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
	operation, rejection, admissionFailure := service.EmitTelemetrySignal(context.Background(), telemetrySignalCommand("telemetry-signal-unknown", "telemetry-unknown", map[string]string{"operation.kind": "lab-delete"}))
	if rejection != nil || admissionFailure != nil || operation.State != "running" {
		t.Fatalf("unknown emission=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if len(operation.EvidenceReferences) != 0 {
		t.Fatalf("unknown telemetry export wrote receipt evidence=%+v", operation.EvidenceReferences)
	}
}

func contains(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}
