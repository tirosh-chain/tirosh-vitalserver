package telemetryexporter

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

func TestOTLPHTTPTelemetryExporterProbesAndExportsAllSignals(t *testing.T) {
	var routes []string
	var payloads []string
	collector := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Fatal(err)
		}
		routes = append(routes, request.URL.Path)
		payloads = append(payloads, string(body))
		response.WriteHeader(http.StatusAccepted)
	}))
	defer collector.Close()
	exporter, err := NewOTLPHTTPTelemetryExporter(collector.URL, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	observation, err := exporter.ObserveTelemetryPipeline(context.Background(), hostagentdomain.NodeReference{Kind: "host", ID: "host-a"}, hostOTLPTestSpec(), "2026-07-19T00:00:00Z")
	if err != nil || observation.State != "ready" {
		t.Fatalf("observation=%+v error=%v", observation, err)
	}
	result, err := exporter.ExportTelemetrySignal(context.Background(), hostagentdomain.TelemetryPipeline{Spec: hostOTLPTestSpec()}, hostOTLPTestCorrelation(), map[string]string{"operation.kind": "guest-start"}, "2026-07-19T00:00:00Z")
	if err != nil || result.Outcome != "exported" {
		t.Fatalf("result=%+v error=%v", result, err)
	}
	if strings.Join(routes, ",") != "/v1/logs,/v1/logs,/v1/metrics,/v1/traces" {
		t.Fatalf("routes=%v", routes)
	}
	for _, payload := range payloads[1:] {
		if !strings.Contains(payload, "operation.kind") || strings.Contains(payload, "patient.id") {
			t.Fatalf("unexpected payload=%s", payload)
		}
	}
}

func TestOTLPHTTPTelemetryExporterKeepsPartialDeliveryUnknown(t *testing.T) {
	collector := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/v1/metrics" {
			response.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		response.WriteHeader(http.StatusAccepted)
	}))
	defer collector.Close()
	exporter, err := NewOTLPHTTPTelemetryExporter(collector.URL, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	result, err := exporter.ExportTelemetrySignal(context.Background(), hostagentdomain.TelemetryPipeline{Spec: hostOTLPTestSpec()}, hostOTLPTestCorrelation(), map[string]string{"operation.kind": "guest-start"}, "2026-07-19T00:00:00Z")
	if err != nil || result.Outcome != "unknown" || result.Issue == nil || result.Issue.Code != "otel-export-partial-outcome-unknown" {
		t.Fatalf("result=%+v error=%v", result, err)
	}
}

func TestOTLPHTTPTelemetryExporterRejectsImplicitCollector(t *testing.T) {
	for _, endpoint := range []string{"", "collector:4318", "http://collector:4318/v1/logs", "http://collector:4318?secret=value"} {
		if _, err := NewOTLPHTTPTelemetryExporter(endpoint, time.Second); err == nil {
			t.Fatalf("accepted %q", endpoint)
		}
	}
}

func hostOTLPTestSpec() hostagentdomain.TelemetryPipelineSpec {
	return hostagentdomain.TelemetryPipelineSpec{Protocol: "otlp-http", CollectorReference: hostagentdomain.ResourceReference{ResourceType: "otel-collector", ResourceID: "collector-a"}, SignalKinds: []string{"logs", "metrics", "traces"}, Redaction: hostagentdomain.TelemetryRedactionPolicy{AllowedAttributeKeys: []string{"operation.kind"}, MaxAttributes: 1, MaxValueLength: 32, MaxDistinctValuesPerKey: 5}}
}

func hostOTLPTestCorrelation() hostagentdomain.TelemetryCorrelation {
	return hostagentdomain.TelemetryCorrelation{SchemaVersion: hostagentdomain.SchemaVersion, Service: hostagentdomain.ServiceIdentity{Name: "host-agent", Version: "1.0.0", InstanceID: "host-a"}, SignalKinds: []string{"logs", "metrics", "traces"}, SignalName: "guest.start", EmittedAt: "2026-07-19T00:00:00Z"}
}
