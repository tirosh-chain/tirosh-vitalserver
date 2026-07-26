package hostagentapplication_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

func hostNode() hostagentdomain.NodeReference {
	return hostagentdomain.NodeReference{Kind: "host", ID: "host-test"}
}

func hostOperationalClock() fixedClock {
	return fixedClock{now: time.Date(2026, 7, 17, 9, 0, 0, 0, time.UTC)}
}

func hostTimeCommand(requestID string) hostagentdomain.TimeAuthorityApplyCommand {
	return hostagentdomain.TimeAuthorityApplyCommand{
		SchemaVersion:            hostagentdomain.SchemaVersion,
		RequestID:                requestID,
		AuthorityID:              "host-time",
		ExpectedResourceRevision: 0,
		Node:                     hostNode(),
		Spec: hostagentdomain.TimeAuthoritySpec{
			Profile: "enterprise-ntp",
			Source:  hostagentdomain.TimeSource{Profile: "enterprise-ntp", SourceID: "ntp-host-primary"},
		},
	}
}

func hostTelemetrySpec() hostagentdomain.TelemetryPipelineSpec {
	return hostagentdomain.TelemetryPipelineSpec{
		Protocol:           "otlp-http",
		CollectorReference: hostagentdomain.ResourceReference{ResourceType: "otel-collector", ResourceID: "host-collector"},
		SignalKinds:        []string{"logs", "metrics", "traces"},
		Redaction: hostagentdomain.TelemetryRedactionPolicy{
			AllowedAttributeKeys:    []string{"operation.kind"},
			MaxAttributes:           1,
			MaxValueLength:          32,
			MaxDistinctValuesPerKey: 1,
		},
	}
}

func TestHostTimeAndTelemetryRemainNodeLocalAndExposeReceiptEvidence(t *testing.T) {
	repository := configuredRepository(t)
	identifiers := &sequentialIdentifiers{}
	timeProbe, err := timeprovider.NewConfiguredHostTimeAuthorityOutcomeProfile(timeprovider.ModeSynchronized)
	if err != nil {
		t.Fatal(err)
	}
	timeService, err := hostagentapplication.NewHostTimeAuthorityApplicationService(repository, timeProbe, hostOperationalClock(), identifiers, hostNode(), "host-time")
	if err != nil {
		t.Fatal(err)
	}
	timeOperation, rejection, admissionFailure := timeService.ApplyHostTimeAuthorityCommand(context.Background(), hostTimeCommand("host-time-apply"))
	if rejection != nil || admissionFailure != nil || timeOperation.State != "succeeded" {
		t.Fatalf("time operation=%+v rejection=%+v admissionFailure=%+v", timeOperation, rejection, admissionFailure)
	}
	qualityRead := timeService.ReadHostClockQuality(context.Background())
	if qualityRead.State != "available" {
		t.Fatalf("Host clock quality read=%+v", qualityRead)
	}
	quality := qualityRead.Value.(hostagentdomain.ClockQuality)
	if quality.Node != hostNode() || quality.State != "synchronized" || quality.Source == nil || quality.Stratum == nil || quality.LastSyncAt == nil {
		t.Fatalf("Host synchronized clock evidence=%+v", quality)
	}

	exporter, err := telemetryexporter.NewConfiguredHostTelemetryExportOutcomeProfile(telemetryexporter.PipelineReady, telemetryexporter.Exported)
	if err != nil {
		t.Fatal(err)
	}
	telemetry, err := hostagentapplication.NewHostTelemetryPipelineApplicationService(repository, exporter, hostOperationalClock(), identifiers, hostNode())
	if err != nil {
		t.Fatal(err)
	}
	pipelineCommand := hostagentdomain.TelemetryPipelineApplyCommand{
		SchemaVersion:            hostagentdomain.SchemaVersion,
		RequestID:                "host-telemetry-pipeline",
		PipelineID:               "host-telemetry",
		ExpectedResourceRevision: 0,
		Node:                     hostNode(),
		Spec:                     hostTelemetrySpec(),
	}
	pipelineOperation, rejection, admissionFailure := telemetry.ApplyHostTelemetryPipelineCommand(context.Background(), pipelineCommand)
	if rejection != nil || admissionFailure != nil || pipelineOperation.State != "succeeded" || len(pipelineOperation.EvidenceReferences) != 1 {
		t.Fatalf("pipeline operation=%+v rejection=%+v admissionFailure=%+v", pipelineOperation, rejection, admissionFailure)
	}

	emitCommand := hostagentdomain.TelemetrySignalEmitCommand{
		SchemaVersion:            hostagentdomain.SchemaVersion,
		RequestID:                "host-telemetry-signal",
		PipelineID:               "host-telemetry",
		ExpectedResourceRevision: 1,
		Signal: hostagentdomain.TelemetryCorrelation{
			SchemaVersion: hostagentdomain.SchemaVersion,
			Service:       hostagentdomain.ServiceIdentity{Name: "host-agent", Version: "test", InstanceID: "host-test"},
			SignalKinds:   []string{"logs", "metrics", "traces"},
			SignalName:    "host.event",
			EmittedAt:     "2026-07-17T09:00:00Z",
		},
		Attributes: map[string]string{
			"operation.kind": "host-start",
			"patient.id":     "must-never-leave-host",
		},
	}
	emitOperation, rejection, admissionFailure := telemetry.EmitHostTelemetrySignal(context.Background(), emitCommand)
	if rejection != nil || admissionFailure != nil || emitOperation.State != "succeeded" || len(emitOperation.EvidenceReferences) != 1 {
		t.Fatalf("emit operation=%+v rejection=%+v admissionFailure=%+v", emitOperation, rejection, admissionFailure)
	}
	if evidence := emitOperation.EvidenceReferences[0]; evidence.Kind != "telemetry-emission-receipt" {
		t.Fatalf("unexpected evidence=%+v", evidence)
	}
	receiptRead := telemetry.ReadHostTelemetryEmissionReceipt(context.Background(), emitOperation.EvidenceReferences[0].ID)
	if receiptRead.State != "available" {
		t.Fatalf("receipt read=%+v", receiptRead)
	}
	receipt := receiptRead.Value.(hostagentdomain.TelemetryEmissionReceipt)
	if receipt.Outcome != "exported" || receipt.ExportedAttributeCount != 1 || !containsHost(receipt.RedactedAttributeKeys, "patient.id") {
		t.Fatalf("receipt=%+v", receipt)
	}
	encoded, err := json.Marshal(receipt)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "must-never-leave-host") {
		t.Fatalf("receipt retained sensitive value=%s", encoded)
	}
}

func TestHostUnknownTimeProbeDoesNotCreateClockQuality(t *testing.T) {
	repository := configuredRepository(t)
	probe, err := timeprovider.NewConfiguredHostTimeAuthorityOutcomeProfile(timeprovider.ModeOutcomeUnknown)
	if err != nil {
		t.Fatal(err)
	}
	service, err := hostagentapplication.NewHostTimeAuthorityApplicationService(repository, probe, hostOperationalClock(), &sequentialIdentifiers{}, hostNode(), "host-time")
	if err != nil {
		t.Fatal(err)
	}
	operation, rejection, admissionFailure := service.ApplyHostTimeAuthorityCommand(context.Background(), hostTimeCommand("host-time-unknown"))
	if rejection != nil || admissionFailure != nil || operation.State != "running" {
		t.Fatalf("unknown operation=%+v rejection=%+v admissionFailure=%+v", operation, rejection, admissionFailure)
	}
	if read := service.ReadHostTimeAuthority(context.Background(), "host-time"); read.State != "missing" {
		t.Fatalf("unknown Host time probe wrote ClockQuality=%+v", read)
	}
}

func containsHost(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}
