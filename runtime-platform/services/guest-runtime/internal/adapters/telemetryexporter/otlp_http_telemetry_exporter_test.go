package telemetryexporter

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestOTLPHTTPTelemetryExporterProbesAndExportsAllSignalKinds(t *testing.T) {
	var requestedRoutes []string
	var payloads []string
	collector := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Fatalf("read OTLP request: %v", err)
		}
		requestedRoutes = append(requestedRoutes, request.URL.Path)
		payloads = append(payloads, string(body))
		if request.Method != http.MethodPost || request.Header.Get("Content-Type") != "application/json" {
			t.Fatalf("OTLP request=%s contentType=%q", request.Method, request.Header.Get("Content-Type"))
		}
		response.WriteHeader(http.StatusAccepted)
	}))
	defer collector.Close()

	exporter, err := NewOTLPHTTPTelemetryExporter(collector.URL, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	spec := testOTLPHTTPPipelineSpec()
	observation, err := exporter.ObserveTelemetryPipeline(context.Background(), guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-a"}, spec, "2026-07-19T00:00:00Z")
	if err != nil || observation.State != "ready" {
		t.Fatalf("pipeline observation=%+v error=%v", observation, err)
	}
	pipeline := guestruntimedomain.TelemetryPipeline{Spec: spec}
	result, err := exporter.ExportTelemetrySignal(context.Background(), pipeline, testOTLPHTTPCorrelation(), map[string]string{"operation.kind": "lab-stop"}, "2026-07-19T00:00:00Z")
	if err != nil || result.Outcome != "exported" {
		t.Fatalf("export result=%+v error=%v", result, err)
	}
	if strings.Join(requestedRoutes, ",") != "/v1/logs,/v1/logs,/v1/metrics,/v1/traces" {
		t.Fatalf("OTLP routes=%v", requestedRoutes)
	}
	for _, payload := range payloads[1:] {
		if !strings.Contains(payload, "operation.kind") || !strings.Contains(payload, "lab-stop") || strings.Contains(payload, "patient.id") {
			t.Fatalf("OTLP payload did not preserve only provided sanitized attributes: %s", payload)
		}
	}
}

func TestOTLPHTTPTelemetryExporterPreservesPartialDeliveryAsUnknown(t *testing.T) {
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
	result, err := exporter.ExportTelemetrySignal(context.Background(), guestruntimedomain.TelemetryPipeline{Spec: testOTLPHTTPPipelineSpec()}, testOTLPHTTPCorrelation(), map[string]string{"operation.kind": "lab-stop"}, "2026-07-19T00:00:00Z")
	if err != nil || result.Outcome != "unknown" || result.Issue == nil || result.Issue.Code != "otel-export-partial-outcome-unknown" {
		t.Fatalf("partial OTLP export result=%+v error=%v", result, err)
	}
}

func TestOTLPHTTPTelemetryExporterReportsCollectorUnavailabilityWithoutReadyFallback(t *testing.T) {
	collector := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer collector.Close()
	exporter, err := NewOTLPHTTPTelemetryExporter(collector.URL, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	observation, err := exporter.ObserveTelemetryPipeline(context.Background(), guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-a"}, testOTLPHTTPPipelineSpec(), "2026-07-19T00:00:00Z")
	if err != nil || observation.State != "unavailable" || observation.Issue == nil || observation.Issue.Code != "otel-collector-unavailable" {
		t.Fatalf("unavailable Collector observation=%+v error=%v", observation, err)
	}
}

func TestOTLPHTTPTelemetryExporterRejectsImplicitOrDecoratedEndpoint(t *testing.T) {
	for _, endpoint := range []string{"", "collector:4318", "http://collector:4318/v1/logs", "http://collector:4318?token=secret"} {
		if _, err := NewOTLPHTTPTelemetryExporter(endpoint, time.Second); err == nil {
			t.Fatalf("endpoint %q was accepted", endpoint)
		}
	}
}

func testOTLPHTTPPipelineSpec() guestruntimedomain.TelemetryPipelineSpec {
	return guestruntimedomain.TelemetryPipelineSpec{Protocol: "otlp-http", CollectorReference: guestruntimedomain.ResourceReference{ResourceType: "otel-collector", ResourceID: "collector-a"}, SignalKinds: []string{"logs", "metrics", "traces"}, Redaction: guestruntimedomain.TelemetryRedactionPolicy{AllowedAttributeKeys: []string{"operation.kind"}, MaxAttributes: 1, MaxValueLength: 32, MaxDistinctValuesPerKey: 5}}
}

func testOTLPHTTPCorrelation() guestruntimedomain.TelemetryCorrelation {
	return guestruntimedomain.TelemetryCorrelation{SchemaVersion: guestruntimedomain.SchemaVersion, Service: guestruntimedomain.ServiceIdentity{Name: "guest-runtime", Version: "1.0.0", InstanceID: "guest-a"}, SignalKinds: []string{"logs", "metrics", "traces"}, SignalName: "lab.stop", EmittedAt: "2026-07-19T00:00:00Z"}
}
