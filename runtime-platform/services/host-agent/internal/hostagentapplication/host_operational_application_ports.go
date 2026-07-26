package hostagentapplication

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// Host Time Authority and Telemetry Pipeline are separate from the Host
// lifecycle repository interface so their state owner and revision guards stay
// obvious at the composition boundary.
type HostTimeAuthorityStateRepository interface {
	ReadHostTimeAuthority(context.Context, string) (hostagentdomain.TimeAuthority, error)
	ReadHostTimeAuthorityOperationByRequestID(context.Context, string) (hostagentdomain.Operation, error)
	AdmitHostTimeAuthorityOperation(context.Context, string, int, hostagentdomain.Operation) error
	CommitHostTimeAuthorityOutcome(context.Context, hostagentdomain.TimeAuthority, hostagentdomain.Operation) error
}

type HostTimeAuthorityProvider interface {
	ObserveTimeAuthority(context.Context, hostagentdomain.NodeReference, hostagentdomain.TimeAuthoritySpec, string) (hostagentdomain.ClockQuality, error)
}

type HostTelemetryPipelineStateRepository interface {
	ReadHostTelemetryPipeline(context.Context, string) (hostagentdomain.TelemetryPipeline, error)
	ReadHostTelemetryPipelineOperationByRequestID(context.Context, string) (hostagentdomain.Operation, error)
	ReadHostTelemetryEmissionOperationByRequestID(context.Context, string) (hostagentdomain.Operation, error)
	ReadHostTelemetryEmissionReceipt(context.Context, string) (hostagentdomain.TelemetryEmissionReceipt, error)
	ReadHostTelemetryAttributeValueDigests(context.Context, string, string) ([]string, error)
	AdmitHostTelemetryPipelineOperation(context.Context, string, int, hostagentdomain.Operation) error
	CommitHostTelemetryPipelineOutcome(context.Context, hostagentdomain.TelemetryPipeline, hostagentdomain.Operation) error
	AdmitHostTelemetryEmissionOperation(context.Context, string, int, hostagentdomain.Operation) error
	CommitHostTelemetryEmissionOutcome(context.Context, hostagentdomain.TelemetryEmissionReceipt, map[string]string, hostagentdomain.Operation) error
}

type HostTelemetryExporter interface {
	ObserveTelemetryPipeline(context.Context, hostagentdomain.NodeReference, hostagentdomain.TelemetryPipelineSpec, string) (hostagentdomain.TelemetryPipelineObservation, error)
	ExportTelemetrySignal(context.Context, hostagentdomain.TelemetryPipeline, hostagentdomain.TelemetryCorrelation, map[string]string, string) (hostagentdomain.TelemetryExportResult, error)
}
