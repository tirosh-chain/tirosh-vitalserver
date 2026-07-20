package telemetryexporter

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// OTLPHTTPTelemetryExporter sends diagnostic-only, already-sanitized signals
// to one explicit OTLP/HTTP Collector base endpoint. It has no archive,
// delivery, Lab, or clock responsibility.
//
// The endpoint is a Collector base URL such as http://collector:4318. The
// adapter derives only the OTLP protocol routes (/v1/logs, /v1/metrics, and
// /v1/traces); it never discovers a Collector from a hostname, environment,
// or a product topology.
type OTLPHTTPTelemetryExporter struct {
	collectorBaseURL *url.URL
	httpClient       *http.Client
}

// NewOTLPHTTPTelemetryExporter constructs the live adapter from an explicit
// Collector base endpoint. A caller that cannot provide this endpoint must
// choose a different declared adapter; it must not receive an implicit local
// Collector.
func NewOTLPHTTPTelemetryExporter(collectorBaseEndpoint string, requestTimeout time.Duration) (*OTLPHTTPTelemetryExporter, error) {
	if requestTimeout <= 0 {
		return nil, fmt.Errorf("OTLP HTTP request timeout must be positive")
	}
	parsed, err := url.Parse(collectorBaseEndpoint)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return nil, fmt.Errorf("OTLP HTTP Collector endpoint must be an absolute http or https URL")
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return nil, fmt.Errorf("OTLP HTTP Collector endpoint must be a base URL without credentials, query, fragment, or path")
	}
	parsed.Path = ""
	return &OTLPHTTPTelemetryExporter{collectorBaseURL: parsed, httpClient: &http.Client{Timeout: requestTimeout}}, nil
}

// ObserveTelemetryPipeline proves that the explicitly configured Collector
// accepted a valid OTLP/HTTP logs envelope. It intentionally probes a normal
// protocol route rather than guessing readiness from a TCP connection.
func (exporter *OTLPHTTPTelemetryExporter) ObserveTelemetryPipeline(ctx context.Context, _ guestruntimedomain.NodeReference, spec guestruntimedomain.TelemetryPipelineSpec, _ string) (guestruntimedomain.TelemetryPipelineObservation, error) {
	if exporter == nil || exporter.collectorBaseURL == nil || exporter.httpClient == nil {
		issue := telemetryExporterIssue(spec, "otel-exporter-not-composed", "OTLP HTTP exporter is not composed", false)
		return guestruntimedomain.TelemetryPipelineObservation{State: "failed", Issue: &issue}, nil
	}
	if issue := guestruntimedomain.ValidateTelemetryPipelineSpec(spec); issue != nil {
		resultIssue := telemetryExporterIssue(spec, "otel-pipeline-spec-invalid", issue.Message, false)
		return guestruntimedomain.TelemetryPipelineObservation{State: "failed", Issue: &resultIssue}, nil
	}
	if err := exporter.post(ctx, "logs", otlpLogsRequest{}); err != nil {
		issue := telemetryExporterIssue(spec, telemetryProbeIssueCode(err), err.Error(), telemetryRetryable(err))
		return guestruntimedomain.TelemetryPipelineObservation{State: telemetryPipelineStateForError(err), Issue: &issue}, nil
	}
	return guestruntimedomain.TelemetryPipelineObservation{State: "ready"}, nil
}

// ExportTelemetrySignal writes each declared signal kind to the respective
// OTLP/HTTP route. The application has already applied the bounded allowlist
// and value-redaction policy before this boundary. If an earlier route was
// accepted and a later route cannot be determined, the receipt is explicitly
// unknown: retrying under the same command could otherwise duplicate evidence.
func (exporter *OTLPHTTPTelemetryExporter) ExportTelemetrySignal(ctx context.Context, pipeline guestruntimedomain.TelemetryPipeline, correlation guestruntimedomain.TelemetryCorrelation, attributes map[string]string, _ string) (guestruntimedomain.TelemetryExportResult, error) {
	if exporter == nil || exporter.collectorBaseURL == nil || exporter.httpClient == nil {
		issue := telemetryExporterIssue(pipeline.Spec, "otel-exporter-not-composed", "OTLP HTTP exporter is not composed", false)
		return guestruntimedomain.TelemetryExportResult{Outcome: "failed", Issue: &issue}, nil
	}
	if issue := guestruntimedomain.ValidateTelemetryCorrelation(correlation); issue != nil {
		resultIssue := telemetryExporterIssue(pipeline.Spec, "otel-telemetry-correlation-invalid", issue.Message, false)
		return guestruntimedomain.TelemetryExportResult{Outcome: "failed", Issue: &resultIssue}, nil
	}

	acceptedKinds := 0
	for _, signalKind := range correlation.SignalKinds {
		payload, err := newOTLPHTTPPayload(signalKind, correlation, attributes)
		if err != nil {
			issue := telemetryExporterIssue(pipeline.Spec, "otel-payload-build-failed", err.Error(), false)
			return telemetryExportFailureAfterAcceptedKinds(acceptedKinds, issue), nil
		}
		if err := exporter.post(ctx, signalKind, payload); err != nil {
			issue := telemetryExporterIssue(pipeline.Spec, telemetryExportIssueCode(err), err.Error(), telemetryRetryable(err))
			return telemetryExportFailureAfterAcceptedKinds(acceptedKinds, issue), nil
		}
		acceptedKinds++
	}
	return guestruntimedomain.TelemetryExportResult{Outcome: "exported"}, nil
}

func telemetryExportFailureAfterAcceptedKinds(acceptedKinds int, issue guestruntimedomain.Issue) guestruntimedomain.TelemetryExportResult {
	if acceptedKinds > 0 {
		issue.Code = "otel-export-partial-outcome-unknown"
		issue.Message = "one or more OTLP signal kinds were accepted before a later signal result became unavailable or failed: " + issue.Message
		return guestruntimedomain.TelemetryExportResult{Outcome: "unknown", Issue: &issue}
	}
	if issue.Code == "otel-collector-unavailable" {
		return guestruntimedomain.TelemetryExportResult{Outcome: "unavailable", Issue: &issue}
	}
	return guestruntimedomain.TelemetryExportResult{Outcome: "failed", Issue: &issue}
}

func (exporter *OTLPHTTPTelemetryExporter) post(ctx context.Context, signalKind string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode OTLP %s payload: %w", signalKind, err)
	}
	endpoint := *exporter.collectorBaseURL
	endpoint.Path = "/v1/" + signalKind
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("construct OTLP %s request: %w", signalKind, err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := exporter.httpClient.Do(request)
	if err != nil {
		return fmt.Errorf("send OTLP %s request: %w", signalKind, err)
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return otlpHTTPStatusError{signalKind: signalKind, statusCode: response.StatusCode}
	}
	return nil
}

type otlpHTTPStatusError struct {
	signalKind string
	statusCode int
}

func (err otlpHTTPStatusError) Error() string {
	return fmt.Sprintf("OTLP %s endpoint returned HTTP %d", err.signalKind, err.statusCode)
}

func telemetryPipelineStateForError(err error) string {
	if telemetryRetryable(err) {
		return "unavailable"
	}
	return "failed"
}

func telemetryProbeIssueCode(err error) string {
	if telemetryRetryable(err) {
		return "otel-collector-unavailable"
	}
	return "otel-collector-probe-failed"
}

func telemetryExportIssueCode(err error) string {
	if telemetryRetryable(err) {
		return "otel-collector-unavailable"
	}
	return "otel-export-failed"
}

func telemetryRetryable(err error) bool {
	var statusError otlpHTTPStatusError
	if err != nil && !strings.Contains(err.Error(), "HTTP ") {
		return true
	}
	if !asOTLPHTTPStatusError(err, &statusError) {
		return true
	}
	return statusError.statusCode >= http.StatusInternalServerError || statusError.statusCode == http.StatusTooManyRequests
}

func asOTLPHTTPStatusError(err error, target *otlpHTTPStatusError) bool {
	value, ok := err.(otlpHTTPStatusError)
	if !ok {
		return false
	}
	*target = value
	return true
}

func telemetryExporterIssue(spec guestruntimedomain.TelemetryPipelineSpec, code string, message string, retryable bool) guestruntimedomain.Issue {
	return guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: spec.CollectorReference.ResourceID}
}

func newOTLPHTTPPayload(signalKind string, correlation guestruntimedomain.TelemetryCorrelation, attributes map[string]string) (any, error) {
	timestamp, err := time.Parse(time.RFC3339Nano, correlation.EmittedAt)
	if err != nil {
		return nil, fmt.Errorf("Telemetry emittedAt is not RFC3339: %w", err)
	}
	resourceAttributes := append(otlpAttributes(attributes),
		otlpKeyValue{Key: "service.name", Value: otlpAnyValue{StringValue: correlation.Service.Name}},
		otlpKeyValue{Key: "service.version", Value: otlpAnyValue{StringValue: correlation.Service.Version}},
		otlpKeyValue{Key: "service.instance.id", Value: otlpAnyValue{StringValue: correlation.Service.InstanceID}},
	)
	when := fmt.Sprintf("%d", timestamp.UnixNano())
	traceID := optionalString(correlation.TraceID)
	spanID := optionalString(correlation.SpanID)
	switch signalKind {
	case "logs":
		return otlpLogsRequest{ResourceLogs: []otlpResourceLogs{{Resource: otlpResource{Attributes: resourceAttributes}, ScopeLogs: []otlpScopeLogs{{Scope: otlpScope{Name: correlation.Service.Name}, LogRecords: []otlpLogRecord{{TimeUnixNano: when, SeverityText: "INFO", Body: otlpAnyValue{StringValue: correlation.SignalName}, Attributes: otlpAttributes(attributes), TraceID: traceID, SpanID: spanID}}}}}}}, nil
	case "metrics":
		return otlpMetricsRequest{ResourceMetrics: []otlpResourceMetrics{{Resource: otlpResource{Attributes: resourceAttributes}, ScopeMetrics: []otlpScopeMetrics{{Scope: otlpScope{Name: correlation.Service.Name}, Metrics: []otlpMetric{{Name: correlation.SignalName, Gauge: otlpGauge{DataPoints: []otlpNumberDataPoint{{TimeUnixNano: when, AsDouble: 1, Attributes: otlpAttributes(attributes)}}}}}}}}}}, nil
	case "traces":
		return otlpTracesRequest{ResourceSpans: []otlpResourceSpans{{Resource: otlpResource{Attributes: resourceAttributes}, ScopeSpans: []otlpScopeSpans{{Scope: otlpScope{Name: correlation.Service.Name}, Spans: []otlpSpan{{TraceID: traceID, SpanID: spanID, Name: correlation.SignalName, StartTimeUnixNano: when, EndTimeUnixNano: when, Attributes: otlpAttributes(attributes)}}}}}}}, nil
	default:
		return nil, fmt.Errorf("unsupported OTLP signal kind %q", signalKind)
	}
}

func optionalString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func otlpAttributes(attributes map[string]string) []otlpKeyValue {
	result := make([]otlpKeyValue, 0, len(attributes))
	for key, value := range attributes {
		result = append(result, otlpKeyValue{Key: key, Value: otlpAnyValue{StringValue: value}})
	}
	return result
}

type otlpAnyValue struct {
	StringValue string `json:"stringValue,omitempty"`
}
type otlpKeyValue struct {
	Key   string       `json:"key"`
	Value otlpAnyValue `json:"value"`
}
type otlpResource struct {
	Attributes []otlpKeyValue `json:"attributes,omitempty"`
}
type otlpScope struct {
	Name string `json:"name"`
}
type otlpLogsRequest struct {
	ResourceLogs []otlpResourceLogs `json:"resourceLogs"`
}
type otlpResourceLogs struct {
	Resource  otlpResource    `json:"resource"`
	ScopeLogs []otlpScopeLogs `json:"scopeLogs"`
}
type otlpScopeLogs struct {
	Scope      otlpScope       `json:"scope"`
	LogRecords []otlpLogRecord `json:"logRecords"`
}
type otlpLogRecord struct {
	TimeUnixNano string         `json:"timeUnixNano"`
	SeverityText string         `json:"severityText"`
	Body         otlpAnyValue   `json:"body"`
	Attributes   []otlpKeyValue `json:"attributes,omitempty"`
	TraceID      string         `json:"traceId,omitempty"`
	SpanID       string         `json:"spanId,omitempty"`
}
type otlpMetricsRequest struct {
	ResourceMetrics []otlpResourceMetrics `json:"resourceMetrics"`
}
type otlpResourceMetrics struct {
	Resource     otlpResource       `json:"resource"`
	ScopeMetrics []otlpScopeMetrics `json:"scopeMetrics"`
}
type otlpScopeMetrics struct {
	Scope   otlpScope    `json:"scope"`
	Metrics []otlpMetric `json:"metrics"`
}
type otlpMetric struct {
	Name  string    `json:"name"`
	Gauge otlpGauge `json:"gauge"`
}
type otlpGauge struct {
	DataPoints []otlpNumberDataPoint `json:"dataPoints"`
}
type otlpNumberDataPoint struct {
	TimeUnixNano string         `json:"timeUnixNano"`
	AsDouble     float64        `json:"asDouble"`
	Attributes   []otlpKeyValue `json:"attributes,omitempty"`
}
type otlpTracesRequest struct {
	ResourceSpans []otlpResourceSpans `json:"resourceSpans"`
}
type otlpResourceSpans struct {
	Resource   otlpResource     `json:"resource"`
	ScopeSpans []otlpScopeSpans `json:"scopeSpans"`
}
type otlpScopeSpans struct {
	Scope otlpScope  `json:"scope"`
	Spans []otlpSpan `json:"spans"`
}
type otlpSpan struct {
	TraceID           string         `json:"traceId,omitempty"`
	SpanID            string         `json:"spanId,omitempty"`
	Name              string         `json:"name"`
	StartTimeUnixNano string         `json:"startTimeUnixNano"`
	EndTimeUnixNano   string         `json:"endTimeUnixNano"`
	Attributes        []otlpKeyValue `json:"attributes,omitempty"`
}

var _ guestruntimeapplication.GuestRuntimeTelemetryExporter = (*OTLPHTTPTelemetryExporter)(nil)
