package guestruntimeapplication

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeTelemetryPipelineStateRepository owns the Guest Runtime's
// telemetry configuration and emission evidence. It never owns product
// delivery, Archive Export, Lab, or Time Authority state.
type GuestRuntimeTelemetryPipelineStateRepository interface {
	ReadTelemetryPipeline(context.Context, string) (guestruntimedomain.TelemetryPipeline, error)
	ReadTelemetryPipelineOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	ReadTelemetrySignalEmissionOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	ReadTelemetryEmissionReceipt(context.Context, string) (guestruntimedomain.TelemetryEmissionReceipt, error)
	ReadTelemetryAttributeValueDigests(context.Context, string, string) ([]string, error)
	AdmitTelemetryPipelineOperation(context.Context, string, int, guestruntimedomain.Operation) error
	CommitTelemetryPipelineOutcome(context.Context, guestruntimedomain.TelemetryPipeline, guestruntimedomain.Operation) error
	AdmitTelemetryEmissionOperation(context.Context, string, int, guestruntimedomain.Operation) error
	CommitTelemetryEmissionOutcome(context.Context, guestruntimedomain.TelemetryEmissionReceipt, map[string]string, guestruntimedomain.Operation) error
}

// GuestRuntimeTelemetryExporter owns only diagnostic collector facts. It never returns or
// mutates a product delivery, archive, Lab, or clock outcome.
type GuestRuntimeTelemetryExporter interface {
	ObserveTelemetryPipeline(context.Context, guestruntimedomain.NodeReference, guestruntimedomain.TelemetryPipelineSpec, string) (guestruntimedomain.TelemetryPipelineObservation, error)
	ExportTelemetrySignal(context.Context, guestruntimedomain.TelemetryPipeline, guestruntimedomain.TelemetryCorrelation, map[string]string, string) (guestruntimedomain.TelemetryExportResult, error)
}
