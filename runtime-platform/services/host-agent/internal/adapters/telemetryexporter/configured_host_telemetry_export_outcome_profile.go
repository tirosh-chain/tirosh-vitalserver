// Package telemetryexporter adapts a selected Host OTLP collector profile to
// diagnostic-only pipeline/export outcomes without coupling to Guest state.
package telemetryexporter

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const (
	PipelineReady          = "ready"
	PipelineUnavailable    = "unavailable"
	PipelineFailed         = "failed"
	PipelineUnsupported    = "unsupported"
	PipelineOutcomeUnknown = "outcome-unknown"
	Exported               = "exported"
	Dropped                = "dropped"
	Unavailable            = "unavailable"
	Failed                 = "failed"
	OutcomeUnknown         = "outcome-unknown"
)

// ConfiguredHostTelemetryExportOutcomeProfile is an explicit static Host OTLP
// profile. A live collector adapter must have a different, explicit name.
type ConfiguredHostTelemetryExportOutcomeProfile struct {
	pipelineMode string
	exportMode   string
}

func NewConfiguredHostTelemetryExportOutcomeProfile(pipelineMode string, exportMode string) (*ConfiguredHostTelemetryExportOutcomeProfile, error) {
	switch pipelineMode {
	case PipelineReady, PipelineUnavailable, PipelineFailed, PipelineUnsupported, PipelineOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported Host telemetry pipeline mode %q", pipelineMode)
	}
	switch exportMode {
	case Exported, Dropped, Unavailable, Failed, OutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported Host telemetry export mode %q", exportMode)
	}
	return &ConfiguredHostTelemetryExportOutcomeProfile{pipelineMode: pipelineMode, exportMode: exportMode}, nil
}

func (provider *ConfiguredHostTelemetryExportOutcomeProfile) ObserveTelemetryPipeline(_ context.Context, _ hostagentdomain.NodeReference, spec hostagentdomain.TelemetryPipelineSpec, _ string) (hostagentdomain.TelemetryPipelineObservation, error) {
	if provider.pipelineMode == PipelineOutcomeUnknown {
		return hostagentdomain.TelemetryPipelineObservation{}, fmt.Errorf("configured Host telemetry collector probe outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *hostagentdomain.Issue {
		return &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(retryable), Dependency: spec.CollectorReference.ResourceID}
	}
	switch provider.pipelineMode {
	case PipelineReady:
		return hostagentdomain.TelemetryPipelineObservation{State: "ready"}, nil
	case PipelineUnavailable:
		return hostagentdomain.TelemetryPipelineObservation{State: "unavailable", Issue: issue("otel-collector-unavailable", "configured Host OTLP collector is unavailable", true)}, nil
	case PipelineFailed:
		return hostagentdomain.TelemetryPipelineObservation{State: "failed", Issue: issue("otel-collector-probe-failed", "configured Host OTLP collector probe failed", true)}, nil
	case PipelineUnsupported:
		return hostagentdomain.TelemetryPipelineObservation{State: "unsupported", Issue: issue("otel-collector-probe-unsupported", "no Host OTLP collector adapter is configured", false)}, nil
	default:
		return hostagentdomain.TelemetryPipelineObservation{}, fmt.Errorf("unreachable Host telemetry pipeline mode %q", provider.pipelineMode)
	}
}

func (provider *ConfiguredHostTelemetryExportOutcomeProfile) ExportTelemetrySignal(_ context.Context, pipeline hostagentdomain.TelemetryPipeline, _ hostagentdomain.TelemetryCorrelation, _ map[string]string, _ string) (hostagentdomain.TelemetryExportResult, error) {
	if provider.exportMode == OutcomeUnknown {
		return hostagentdomain.TelemetryExportResult{}, fmt.Errorf("configured Host telemetry export outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *hostagentdomain.Issue {
		return &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(retryable), Dependency: pipeline.Spec.CollectorReference.ResourceID}
	}
	switch provider.exportMode {
	case Exported:
		return hostagentdomain.TelemetryExportResult{Outcome: "exported"}, nil
	case Dropped:
		return hostagentdomain.TelemetryExportResult{Outcome: "dropped", Issue: issue("otel-signal-sampled-out", "configured Host telemetry exporter dropped this diagnostic signal", false)}, nil
	case Unavailable:
		return hostagentdomain.TelemetryExportResult{Outcome: "unavailable", Issue: issue("otel-collector-unavailable", "configured Host OTLP collector is unavailable", true)}, nil
	case Failed:
		return hostagentdomain.TelemetryExportResult{Outcome: "failed", Issue: issue("otel-export-failed", "configured Host OTLP exporter failed", true)}, nil
	default:
		return hostagentdomain.TelemetryExportResult{}, fmt.Errorf("unreachable Host telemetry export mode %q", provider.exportMode)
	}
}

var _ hostagentapplication.HostTelemetryExporter = (*ConfiguredHostTelemetryExportOutcomeProfile)(nil)
