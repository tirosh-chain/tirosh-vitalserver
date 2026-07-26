package telemetryexporter

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// OTLPHTTPTelemetryExporter writes already-sanitized Host diagnostic signals
// to one explicitly configured OTLP/HTTP collector.  A base URL is required:
// this adapter never finds a Collector through a hostname, environment, or
// installation layout.
type OTLPHTTPTelemetryExporter struct {
	collectorBaseURL *url.URL
	httpClient       *http.Client
}

func NewOTLPHTTPTelemetryExporter(collectorBaseEndpoint string, requestTimeout time.Duration) (*OTLPHTTPTelemetryExporter, error) {
	if requestTimeout <= 0 {
		return nil, fmt.Errorf("OTLP HTTP request timeout must be positive")
	}
	endpoint, err := url.Parse(collectorBaseEndpoint)
	if err != nil || endpoint.Scheme == "" || endpoint.Host == "" || (endpoint.Scheme != "http" && endpoint.Scheme != "https") {
		return nil, fmt.Errorf("OTLP HTTP Collector endpoint must be an absolute http or https URL")
	}
	if endpoint.User != nil || endpoint.RawQuery != "" || endpoint.Fragment != "" || (endpoint.Path != "" && endpoint.Path != "/") {
		return nil, fmt.Errorf("OTLP HTTP Collector endpoint must be a base URL without credentials, query, fragment, or path")
	}
	endpoint.Path = ""
	return &OTLPHTTPTelemetryExporter{collectorBaseURL: endpoint, httpClient: &http.Client{Timeout: requestTimeout}}, nil
}

// ObserveTelemetryPipeline proves protocol acceptance through a valid empty
// OTLP logs request.  A TCP connection alone is not a ready Collector.
func (exporter *OTLPHTTPTelemetryExporter) ObserveTelemetryPipeline(ctx context.Context, _ hostagentdomain.NodeReference, spec hostagentdomain.TelemetryPipelineSpec, _ string) (hostagentdomain.TelemetryPipelineObservation, error) {
	if exporter == nil || exporter.collectorBaseURL == nil || exporter.httpClient == nil {
		issue := hostTelemetryIssue(spec, "otel-exporter-not-composed", "OTLP HTTP exporter is not composed", false)
		return hostagentdomain.TelemetryPipelineObservation{State: "failed", Issue: &issue}, nil
	}
	if issue := hostagentdomain.ValidateTelemetryPipelineSpec(spec); issue != nil {
		resultIssue := hostTelemetryIssue(spec, "otel-pipeline-spec-invalid", issue.Message, false)
		return hostagentdomain.TelemetryPipelineObservation{State: "failed", Issue: &resultIssue}, nil
	}
	if err := exporter.post(ctx, "logs", map[string]any{}); err != nil {
		issue := hostTelemetryIssue(spec, hostTelemetryIssueCode(err, "otel-collector-unavailable", "otel-collector-probe-failed"), err.Error(), hostTelemetryRetryable(err))
		state := "failed"
		if hostTelemetryRetryable(err) {
			state = "unavailable"
		}
		return hostagentdomain.TelemetryPipelineObservation{State: state, Issue: &issue}, nil
	}
	return hostagentdomain.TelemetryPipelineObservation{State: "ready"}, nil
}

// ExportTelemetrySignal emits every explicitly requested signal kind.  If a
// prior route accepted data but a later route cannot be confirmed, the result
// is unknown rather than a false success or retry-safe failure.
func (exporter *OTLPHTTPTelemetryExporter) ExportTelemetrySignal(ctx context.Context, pipeline hostagentdomain.TelemetryPipeline, correlation hostagentdomain.TelemetryCorrelation, attributes map[string]string, _ string) (hostagentdomain.TelemetryExportResult, error) {
	if exporter == nil || exporter.collectorBaseURL == nil || exporter.httpClient == nil {
		issue := hostTelemetryIssue(pipeline.Spec, "otel-exporter-not-composed", "OTLP HTTP exporter is not composed", false)
		return hostagentdomain.TelemetryExportResult{Outcome: "failed", Issue: &issue}, nil
	}
	if issue := hostagentdomain.ValidateTelemetryCorrelation(correlation); issue != nil {
		resultIssue := hostTelemetryIssue(pipeline.Spec, "otel-telemetry-correlation-invalid", issue.Message, false)
		return hostagentdomain.TelemetryExportResult{Outcome: "failed", Issue: &resultIssue}, nil
	}

	accepted := 0
	for _, signalKind := range correlation.SignalKinds {
		payload, err := hostOTLPPayload(signalKind, correlation, attributes)
		if err == nil {
			err = exporter.post(ctx, signalKind, payload)
		}
		if err != nil {
			issue := hostTelemetryIssue(pipeline.Spec, hostTelemetryIssueCode(err, "otel-collector-unavailable", "otel-export-failed"), err.Error(), hostTelemetryRetryable(err))
			if accepted > 0 {
				issue.Code = "otel-export-partial-outcome-unknown"
				issue.Message = "one or more OTLP signal kinds were accepted before a later signal result became unavailable or failed: " + issue.Message
				return hostagentdomain.TelemetryExportResult{Outcome: "unknown", Issue: &issue}, nil
			}
			if hostTelemetryRetryable(err) {
				return hostagentdomain.TelemetryExportResult{Outcome: "unavailable", Issue: &issue}, nil
			}
			return hostagentdomain.TelemetryExportResult{Outcome: "failed", Issue: &issue}, nil
		}
		accepted++
	}
	return hostagentdomain.TelemetryExportResult{Outcome: "exported"}, nil
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
		return hostOTLPHTTPStatusError{signalKind: signalKind, statusCode: response.StatusCode}
	}
	return nil
}

func hostOTLPPayload(signalKind string, correlation hostagentdomain.TelemetryCorrelation, attributes map[string]string) (any, error) {
	timestamp, err := time.Parse(time.RFC3339Nano, correlation.EmittedAt)
	if err != nil {
		return nil, fmt.Errorf("Telemetry emittedAt is not RFC3339: %w", err)
	}
	resource := map[string]any{"attributes": hostOTLPAttributes(map[string]string{
		"service.name": correlation.Service.Name, "service.version": correlation.Service.Version, "service.instance.id": correlation.Service.InstanceID,
	})}
	when := fmt.Sprintf("%d", timestamp.UnixNano())
	span := optionalHostOTLPString(correlation.SpanID)
	trace := optionalHostOTLPString(correlation.TraceID)
	scope := map[string]any{"name": correlation.Service.Name}
	attributeValues := hostOTLPAttributes(attributes)
	switch signalKind {
	case "logs":
		return map[string]any{"resourceLogs": []any{map[string]any{"resource": resource, "scopeLogs": []any{map[string]any{"scope": scope, "logRecords": []any{map[string]any{"timeUnixNano": when, "severityText": "INFO", "body": map[string]any{"stringValue": correlation.SignalName}, "attributes": attributeValues, "traceId": trace, "spanId": span}}}}}}}, nil
	case "metrics":
		return map[string]any{"resourceMetrics": []any{map[string]any{"resource": resource, "scopeMetrics": []any{map[string]any{"scope": scope, "metrics": []any{map[string]any{"name": correlation.SignalName, "gauge": map[string]any{"dataPoints": []any{map[string]any{"timeUnixNano": when, "asDouble": 1, "attributes": attributeValues}}}}}}}}}}, nil
	case "traces":
		return map[string]any{"resourceSpans": []any{map[string]any{"resource": resource, "scopeSpans": []any{map[string]any{"scope": scope, "spans": []any{map[string]any{"traceId": trace, "spanId": span, "name": correlation.SignalName, "startTimeUnixNano": when, "endTimeUnixNano": when, "attributes": attributeValues}}}}}}}, nil
	default:
		return nil, fmt.Errorf("unsupported OTLP signal kind %q", signalKind)
	}
}

func hostOTLPAttributes(values map[string]string) []map[string]any {
	attributes := make([]map[string]any, 0, len(values))
	for key, value := range values {
		attributes = append(attributes, map[string]any{"key": key, "value": map[string]any{"stringValue": value}})
	}
	return attributes
}

func optionalHostOTLPString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

type hostOTLPHTTPStatusError struct {
	signalKind string
	statusCode int
}

func (err hostOTLPHTTPStatusError) Error() string {
	return fmt.Sprintf("OTLP %s endpoint returned HTTP %d", err.signalKind, err.statusCode)
}

func hostTelemetryRetryable(err error) bool {
	var statusError hostOTLPHTTPStatusError
	if !errors.As(err, &statusError) {
		return true
	}
	return statusError.statusCode >= http.StatusInternalServerError || statusError.statusCode == http.StatusTooManyRequests
}

func hostTelemetryIssueCode(err error, unavailable string, failed string) string {
	if hostTelemetryRetryable(err) {
		return unavailable
	}
	return failed
}

func hostTelemetryIssue(spec hostagentdomain.TelemetryPipelineSpec, code string, message string, retryable bool) hostagentdomain.Issue {
	return hostagentdomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: spec.CollectorReference.ResourceID}
}

var _ hostagentapplication.HostTelemetryExporter = (*OTLPHTTPTelemetryExporter)(nil)
