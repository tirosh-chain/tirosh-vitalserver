// Package guestruntimecontrolhttpapplication composes the Guest Runtime
// application services that own the versioned Guest Runtime Control HTTP
// contract. It deliberately owns no TCP or virtio-socket listener: those
// transport bindings belong to distinct process entry points.
package guestruntimecontrolhttpapplication

import (
	"context"
	"fmt"
	"net/http"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/archiveprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/externalupstreamobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/outboundrelayobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeControlHTTPApplicationDeployment is the complete desired input
// required to compose Guest Runtime application services behind the control
// HTTP contract. It is not a process transport declaration or a readiness
// observation.
type GuestRuntimeControlHTTPApplicationDeployment struct {
	GuestRuntimeStateDatabasePath                  string
	GuestRuntimeServiceVersion                     string
	GuestRuntimeInstanceID                         string
	ArchiveExportProviderReference                 guestruntimedomain.ArchiveProviderReference
	ArchiveExportProviderOutcomeMode               string
	ExternalUpstreamObservationProviderReference   guestruntimedomain.IntegrationProviderReference
	ExternalUpstreamObservationProviderOutcomeMode string
	OutboundRelayObservationProviderReference      guestruntimedomain.IntegrationProviderReference
	OutboundRelayObservationProviderOutcomeMode    string
	GuestRuntimeNode                               guestruntimedomain.NodeReference
	GuestTimeAuthorityID                           string
	GuestTimeAuthorityProbeOutcomeMode             string
	GuestTelemetryCollectorProbeOutcomeMode        string
	GuestTelemetryExportOutcomeMode                string
}

// GuestRuntimeControlHTTPApplication exposes the composed HTTP handler and
// owns the lifecycle of the Guest Runtime SQLite repository it opened.
type GuestRuntimeControlHTTPApplication struct {
	ControlHTTPHandler          http.Handler
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository
}

// OpenGuestRuntimeControlHTTPApplication opens the explicitly named Guest
// Runtime state owner and assembles its control HTTP application modules. It
// does not bind a transport listener or infer any provider outcome.
func OpenGuestRuntimeControlHTTPApplication(
	compositionContext context.Context,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*GuestRuntimeControlHTTPApplication, error) {
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err != nil {
		return nil, err
	}
	guestRuntimeStateRepository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		compositionContext,
		deployment.GuestRuntimeStateDatabasePath,
	)
	if err != nil {
		return nil, fmt.Errorf("open Guest Runtime state repository: %w", err)
	}

	controlHTTPHandler, err := assembleGuestRuntimeControlHTTPHandler(
		guestRuntimeStateRepository,
		deployment,
	)
	if err != nil {
		_ = guestRuntimeStateRepository.Close()
		return nil, err
	}
	return &GuestRuntimeControlHTTPApplication{
		ControlHTTPHandler:          controlHTTPHandler,
		guestRuntimeStateRepository: guestRuntimeStateRepository,
	}, nil
}

// CloseGuestRuntimeControlHTTPApplication closes the Guest Runtime state
// repository opened during composition. It does not make an operation-state
// claim about the Guest Runtime process.
func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) CloseGuestRuntimeControlHTTPApplication() error {
	if controlHTTPApplication == nil || controlHTTPApplication.guestRuntimeStateRepository == nil {
		return fmt.Errorf("Guest Runtime control application has no opened Guest Runtime state repository")
	}
	return controlHTTPApplication.guestRuntimeStateRepository.Close()
}

func validateGuestRuntimeControlHTTPApplicationDeployment(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	if deployment.GuestRuntimeStateDatabasePath == "" || deployment.GuestRuntimeServiceVersion == "" || deployment.GuestRuntimeInstanceID == "" {
		return fmt.Errorf("Guest Runtime state database path, service version, and instance ID are required")
	}
	if deployment.GuestRuntimeNode.Kind == "" || deployment.GuestRuntimeNode.ID == "" || deployment.GuestTimeAuthorityID == "" {
		return fmt.Errorf("Guest Runtime node and Time Authority ID are required")
	}
	if deployment.ArchiveExportProviderOutcomeMode == "" || deployment.ExternalUpstreamObservationProviderOutcomeMode == "" || deployment.OutboundRelayObservationProviderOutcomeMode == "" || deployment.GuestTimeAuthorityProbeOutcomeMode == "" || deployment.GuestTelemetryCollectorProbeOutcomeMode == "" || deployment.GuestTelemetryExportOutcomeMode == "" {
		return fmt.Errorf("Guest Runtime selected provider outcome modes are required")
	}
	if deployment.ArchiveExportProviderReference.CapabilityRevision < 1 || deployment.ExternalUpstreamObservationProviderReference.CapabilityRevision < 1 || deployment.OutboundRelayObservationProviderReference.CapabilityRevision < 1 {
		return fmt.Errorf("Guest Runtime selected provider capability revisions must be at least one")
	}
	return nil
}

func assembleGuestRuntimeControlHTTPHandler(
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (http.Handler, error) {
	guestRuntimeApplicationClock := guestruntimeapplication.SystemGuestRuntimeClock{}
	externalUpstreamObservationProvider, err := externalupstreamobservationprovider.NewConfiguredExternalUpstreamObservationProfile(
		deployment.ExternalUpstreamObservationProviderReference,
		deployment.ExternalUpstreamObservationProviderOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime External Upstream provider: %w", err)
	}
	externalUpstreamService, err := guestruntimeapplication.NewGuestRuntimeExternalUpstreamApplicationService(
		guestRuntimeStateRepository,
		externalUpstreamObservationProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime External Upstream service: %w", err)
	}

	// Relay uses its own configured observation profile because its persistent
	// resource owner and observation lifecycle are distinct from External
	// Upstream.
	outboundRelayObservationProvider, err := outboundrelayobservationprovider.NewConfiguredOutboundRelayObservationProfile(
		deployment.OutboundRelayObservationProviderReference,
		deployment.OutboundRelayObservationProviderOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Outbound Relay provider: %w", err)
	}
	outboundRelayService, err := guestruntimeapplication.NewGuestRuntimeOutboundRelayApplicationService(
		guestRuntimeStateRepository,
		outboundRelayObservationProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Outbound Relay service: %w", err)
	}

	topologyService, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationServiceWithExternalUpstreamReader(
		guestRuntimeStateRepository,
		externalUpstreamService,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeServiceVersion,
		deployment.GuestRuntimeInstanceID,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime topology service: %w", err)
	}
	labService, err := guestruntimeapplication.NewGuestRuntimeLabApplicationService(
		guestRuntimeStateRepository,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab service: %w", err)
	}
	archiveExportProvider, err := archiveprovider.NewConfiguredArchiveExportOutcomeProfile(
		deployment.ArchiveExportProviderReference,
		deployment.ArchiveExportProviderOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive provider: %w", err)
	}
	archiveService, err := guestruntimeapplication.NewGuestRuntimeArchiveApplicationService(
		guestRuntimeStateRepository,
		labService,
		archiveExportProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive service: %w", err)
	}
	guestTimeAuthorityOutcomeProfile, err := timeprovider.NewConfiguredTimeAuthorityOutcomeProfile(
		deployment.GuestTimeAuthorityProbeOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Time Authority provider: %w", err)
	}
	guestTimeAuthorityService, err := guestruntimeapplication.NewGuestRuntimeTimeAuthorityApplicationService(
		guestRuntimeStateRepository,
		guestTimeAuthorityOutcomeProfile,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeNode,
		deployment.GuestTimeAuthorityID,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Time Authority service: %w", err)
	}
	recorderObservationCatalogService, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
		guestRuntimeStateRepository,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder Observation Catalog service: %w", err)
	}
	guestTelemetryExporter, err := telemetryexporter.NewConfiguredTelemetryExportOutcomeProfile(
		deployment.GuestTelemetryCollectorProbeOutcomeMode,
		deployment.GuestTelemetryExportOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Telemetry exporter: %w", err)
	}
	guestTelemetryPipelineService, err := guestruntimeapplication.NewGuestRuntimeTelemetryPipelineApplicationService(
		guestRuntimeStateRepository,
		guestTelemetryExporter,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeNode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Telemetry Pipeline service: %w", err)
	}
	return guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(guestruntimecontrolhttpapi.GuestRuntimeControlModules{
		Topology:                             topologyService,
		Lab:                                  labService,
		Archive:                              archiveService,
		ExternalUpstreamIntegration:          externalUpstreamService,
		OutboundRelayTarget:                  outboundRelayService,
		GuestTimeAuthority:                   guestTimeAuthorityService,
		RecorderObservationCatalog:           recorderObservationCatalogService,
		GuestTelemetryPipeline:               guestTelemetryPipelineService,
		LabArchiveLifecycleCoordinationClock: guestRuntimeApplicationClock,
	}), nil
}
