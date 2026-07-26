// Package telemetryexporter adapts an explicit OTLP collector profile to
// diagnostic-only pipeline and export outcomes. It never returns a product
// delivery/archive/Lab outcome and never persists signal attribute values.
package telemetryexporter

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	PipelineReady          = "ready"
	PipelineUnavailable    = "unavailable"
	PipelineFailed         = "failed"
	PipelineUnsupported    = "unsupported"
	PipelineOutcomeUnknown = "outcome-unknown"

	Exported       = "exported"
	Dropped        = "dropped"
	Unavailable    = "unavailable"
	Failed         = "failed"
	OutcomeUnknown = "outcome-unknown"
)

// ConfiguredTelemetryExportOutcomeProfile represents a configured OpenTelemetry
// Collector outcome profile.
// The profile is suitable for deterministic acceptance; a deployment that
// wants a live collector must install an adapter that makes the network probe
// explicit instead of relying on this static profile.
type ConfiguredTelemetryExportOutcomeProfile struct {
	pipelineMode string
	exportMode   string
}

func NewConfiguredTelemetryExportOutcomeProfile(pipelineMode string, exportMode string) (*ConfiguredTelemetryExportOutcomeProfile, error) {
	switch pipelineMode {
	case PipelineReady, PipelineUnavailable, PipelineFailed, PipelineUnsupported, PipelineOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported telemetry pipeline mode %q", pipelineMode)
	}
	switch exportMode {
	case Exported, Dropped, Unavailable, Failed, OutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported telemetry export mode %q", exportMode)
	}
	return &ConfiguredTelemetryExportOutcomeProfile{pipelineMode: pipelineMode, exportMode: exportMode}, nil
}

func (provider *ConfiguredTelemetryExportOutcomeProfile) ObserveTelemetryPipeline(_ context.Context, _ guestruntimedomain.NodeReference, spec guestruntimedomain.TelemetryPipelineSpec, _ string) (guestruntimedomain.TelemetryPipelineObservation, error) {
	if provider.pipelineMode == PipelineOutcomeUnknown {
		return guestruntimedomain.TelemetryPipelineObservation{}, fmt.Errorf("configured telemetry collector probe outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *guestruntimedomain.Issue {
		return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: spec.CollectorReference.ResourceID}
	}
	switch provider.pipelineMode {
	case PipelineReady:
		return guestruntimedomain.TelemetryPipelineObservation{State: "ready"}, nil
	case PipelineUnavailable:
		return guestruntimedomain.TelemetryPipelineObservation{State: "unavailable", Issue: issue("otel-collector-unavailable", "configured OTLP collector is unavailable", true)}, nil
	case PipelineFailed:
		return guestruntimedomain.TelemetryPipelineObservation{State: "failed", Issue: issue("otel-collector-probe-failed", "configured OTLP collector probe failed", true)}, nil
	case PipelineUnsupported:
		return guestruntimedomain.TelemetryPipelineObservation{State: "unsupported", Issue: issue("otel-collector-probe-unsupported", "no OTLP collector adapter is configured", false)}, nil
	default:
		return guestruntimedomain.TelemetryPipelineObservation{}, fmt.Errorf("unreachable telemetry pipeline mode %q", provider.pipelineMode)
	}
}

func (provider *ConfiguredTelemetryExportOutcomeProfile) ExportTelemetrySignal(_ context.Context, pipeline guestruntimedomain.TelemetryPipeline, _ guestruntimedomain.TelemetryCorrelation, _ map[string]string, _ string) (guestruntimedomain.TelemetryExportResult, error) {
	if provider.exportMode == OutcomeUnknown {
		return guestruntimedomain.TelemetryExportResult{}, fmt.Errorf("configured telemetry export outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *guestruntimedomain.Issue {
		return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: pipeline.Spec.CollectorReference.ResourceID}
	}
	switch provider.exportMode {
	case Exported:
		return guestruntimedomain.TelemetryExportResult{Outcome: "exported"}, nil
	case Dropped:
		return guestruntimedomain.TelemetryExportResult{Outcome: "dropped", Issue: issue("otel-signal-sampled-out", "configured telemetry exporter dropped this diagnostic signal", false)}, nil
	case Unavailable:
		return guestruntimedomain.TelemetryExportResult{Outcome: "unavailable", Issue: issue("otel-collector-unavailable", "configured OTLP collector is unavailable", true)}, nil
	case Failed:
		return guestruntimedomain.TelemetryExportResult{Outcome: "failed", Issue: issue("otel-export-failed", "configured OTLP exporter failed", true)}, nil
	default:
		return guestruntimedomain.TelemetryExportResult{}, fmt.Errorf("unreachable telemetry export mode %q", provider.exportMode)
	}
}

var _ guestruntimeapplication.GuestRuntimeTelemetryExporter = (*ConfiguredTelemetryExportOutcomeProfile)(nil)
