package guestruntimeapplication_test

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
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
	repository := newOperationalRepository(t)
	service, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(repository, operationalClock(), guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{})
	if err != nil {
		t.Fatal(err)
	}
	command := guestruntimedomain.CatalogObservationIngestCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "catalog-1", ObservationID: "observation-1", Envelope: recorderEnvelope(7, "1.2.3")}
	operation, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), command)
	if rejection != nil || admissionFailure != nil || operation.State != "succeeded" {
		t.Fatalf("catalog ingest operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	read := service.ReadCatalogObservation(context.Background(), "observation-1")
	if read.State != "available" {
		t.Fatalf("catalog read=%+v", read)
	}
	observation := read.Value.(guestruntimedomain.CatalogObservation)
	if observation.Envelope.OccurredAt != command.Envelope.OccurredAt || observation.SourceIdentity.OccurredAt != command.Envelope.OccurredAt || observation.ReceivedAt == command.Envelope.OccurredAt {
		t.Fatalf("catalog did not preserve source occurrence=%+v", observation)
	}
	replay := command
	replay.RequestID = "catalog-2"
	replay.ObservationID = "observation-other-id"
	replayedOperation, rejection, admissionFailure := service.IngestCatalogObservation(context.Background(), replay)
	if rejection != nil || admissionFailure != nil || replayedOperation.ID != operation.ID {
		t.Fatalf("same source envelope should return original operation=%+v rejection=%+v admissionFailure=%+v", replayedOperation, rejection, admissionFailure)
	}
	conflict := command
	conflict.RequestID = "catalog-3"
	conflict.ObservationID = "observation-conflict"
	conflict.Envelope = recorderEnvelope(7, "9.9.9")
	_, rejection, admissionFailure = service.IngestCatalogObservation(context.Background(), conflict)
	if admissionFailure != nil || rejection == nil || rejection.Issue.Code != "catalog-source-identity-conflict" {
		t.Fatalf("source conflict rejection=%+v admissionFailure=%+v", rejection, admissionFailure)
	}
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
