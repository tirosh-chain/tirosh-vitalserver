// Package guestruntimecontrolhttpapplication composes the Guest Runtime
// application services that own the versioned Guest Runtime Control HTTP
// contract. It deliberately owns no TCP or virtio-socket listener: those
// transport bindings belong to distinct process entry points.
package guestruntimecontrolhttpapplication

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/archiveprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/externalupstreamobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/labrecorderrunner"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/outboundrelayobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/recordergatewaycoldpathsource"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalartifactformation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalserverindexedlibrary"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeControlHTTPApplicationDeployment is the complete desired input
// required to compose Guest Runtime application services behind the control
// HTTP contract. It is not a process transport declaration or a readiness
// observation.
type GuestRuntimeControlHTTPApplicationDeployment struct {
	GuestRuntimeStateDatabasePath                                           string
	GuestRuntimeServiceVersion                                              string
	GuestRuntimeInstanceID                                                  string
	ArchiveExportProviderReference                                          guestruntimedomain.ArchiveProviderReference
	ArchiveExportProviderOutcomeMode                                        string
	ArchiveProviderVitalServerConfigurationKind                             string
	ArchiveProviderVitalServerConfigurationPath                             string
	ArchiveProviderCredentialMaterialPath                                   string
	RecorderGatewayColdPathSourceEndpoint                                   string
	LabRecorderRunnerEndpoint                                               string
	ExternalUpstreamObservationProviderReference                            guestruntimedomain.IntegrationProviderReference
	ExternalUpstreamObservationProviderOutcomeMode                          string
	ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath string
	ExternalUpstreamObservationRequestTimeoutMilliseconds                   int
	OutboundRelayObservationProviderReference                               guestruntimedomain.IntegrationProviderReference
	OutboundRelayObservationProviderOutcomeMode                             string
	GuestRuntimeNode                                                        guestruntimedomain.NodeReference
	GuestTimeAuthorityID                                                    string
	GuestTimeAuthorityAdapterKind                                           string
	GuestTimeAuthorityChronyExecutablePath                                  string
	GuestTimeAuthorityRequestTimeoutMilliseconds                            int
	GuestTimeAuthorityProbeOutcomeMode                                      string
	GuestTelemetryAdapterKind                                               string
	GuestTelemetryCollectorBaseEndpoint                                     string
	GuestTelemetryRequestTimeoutMilliseconds                                int
	GuestTelemetryCollectorProbeOutcomeMode                                 string
	GuestTelemetryExportOutcomeMode                                         string
}

// GuestRuntimeControlHTTPApplication exposes the composed HTTP handler and
// owns the lifecycle of the Guest Runtime SQLite repository it opened.
type GuestRuntimeControlHTTPApplication struct {
	ControlHTTPHandler          http.Handler
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository
	reconcileTerminalArchives   func(context.Context) error
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

	controlHTTPServer, err := assembleGuestRuntimeControlHTTPHandler(
		guestRuntimeStateRepository,
		deployment,
	)
	if err != nil {
		_ = guestRuntimeStateRepository.Close()
		return nil, err
	}
	return &GuestRuntimeControlHTTPApplication{
		ControlHTTPHandler:          controlHTTPServer,
		guestRuntimeStateRepository: guestRuntimeStateRepository,
		reconcileTerminalArchives:   controlHTTPServer.ReconcilePendingTerminalArchiveExports,
	}, nil
}

// ReconcilePendingTerminalArchiveExports repeats only already-persisted Lab
// terminal Archive intents. It is a process-start recovery operation, not an
// assertion that Lab stop or Archive upload succeeded.
func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) ReconcilePendingTerminalArchiveExports(ctx context.Context) error {
	if controlHTTPApplication == nil || controlHTTPApplication.reconcileTerminalArchives == nil {
		return fmt.Errorf("Guest Runtime terminal Archive reconciliation is not composed")
	}
	return controlHTTPApplication.reconcileTerminalArchives(ctx)
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
	if deployment.RecorderGatewayColdPathSourceEndpoint == "" || deployment.LabRecorderRunnerEndpoint == "" || deployment.OutboundRelayObservationProviderOutcomeMode == "" {
		return fmt.Errorf("Guest Runtime selected provider outcome modes are required")
	}
	if err := validateGuestRuntimeTimeAuthorityAdapter(deployment); err != nil {
		return err
	}
	if err := validateGuestRuntimeTelemetryAdapter(deployment); err != nil {
		return err
	}
	if deployment.ArchiveExportProviderReference.CapabilityRevision < 1 || deployment.ExternalUpstreamObservationProviderReference.CapabilityRevision < 1 || deployment.OutboundRelayObservationProviderReference.CapabilityRevision < 1 {
		return fmt.Errorf("Guest Runtime selected provider capability revisions must be at least one")
	}
	switch deployment.ArchiveExportProviderReference.Kind {
	case "archive-export-outcome-profile":
		if deployment.ArchiveExportProviderOutcomeMode == "" || deployment.ArchiveProviderVitalServerConfigurationKind != "" || deployment.ArchiveProviderVitalServerConfigurationPath != "" || deployment.ArchiveProviderCredentialMaterialPath != "" {
			return fmt.Errorf("Guest Runtime Archive outcome profile must provide only its explicit outcome mode")
		}
	case "vitalserver-indexed-library":
		if deployment.ArchiveExportProviderOutcomeMode != "" || !validArchiveProviderVitalServerConfigurationKind(deployment.ArchiveProviderVitalServerConfigurationKind) || deployment.ArchiveProviderVitalServerConfigurationPath == "" || deployment.ArchiveProviderCredentialMaterialPath == "" {
			return fmt.Errorf("Guest Runtime VitalServer indexed-library provider requires explicit C44-or-C46 configuration kind, configuration path, and credential material path")
		}
	default:
		return fmt.Errorf("Guest Runtime Archive provider kind is unsupported")
	}
	if err := validateGuestRuntimeExternalUpstreamObservationProvider(deployment); err != nil {
		return err
	}
	return nil
}

func assembleGuestRuntimeControlHTTPHandler(
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*guestruntimecontrolhttpapi.GuestRuntimeControlHTTPServer, error) {
	guestRuntimeApplicationClock := guestruntimeapplication.SystemGuestRuntimeClock{}
	externalUpstreamObservationProvider, err := composeGuestRuntimeExternalUpstreamObservationProvider(deployment)
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
	labRecorderRunner, err := labrecorderrunner.NewLabRecorderRunnerHTTPClient(deployment.LabRecorderRunnerEndpoint)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab recorder Runner client: %w", err)
	}
	labService, err := guestruntimeapplication.NewGuestRuntimeLabApplicationServiceWithRecorderRunner(
		guestRuntimeStateRepository,
		labRecorderRunner,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab service: %w", err)
	}
	archiveCredentialMaterialOwner, err := composeGuestRuntimeArchiveCredentialMaterialOwner(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive credential-material owner: %w", err)
	}
	var archiveCredentialMaterialService *guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialApplicationService
	if archiveCredentialMaterialOwner != nil {
		archiveCredentialMaterialService, err = guestruntimeapplication.NewGuestRuntimeArchiveCredentialMaterialApplicationService(
			archiveCredentialMaterialOwner,
			guestRuntimeApplicationClock,
		)
		if err != nil {
			return nil, fmt.Errorf("compose Guest Runtime Archive credential-material service: %w", err)
		}
	}
	archiveExportProvider, err := composeGuestRuntimeArchiveExportProvider(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive provider: %w", err)
	}
	recorderGatewayColdPathSourceReader, err := recordergatewaycoldpathsource.NewRecorderGatewayColdPathHTTPSourceReader(
		deployment.RecorderGatewayColdPathSourceEndpoint,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder Gateway cold-path source reader: %w", err)
	}
	vitalArtifactFormationProvider := vitalartifactformation.NewRecorderColdPathVitalArtifactFormationProvider()
	archiveService, err := guestruntimeapplication.NewGuestRuntimeArchiveApplicationService(
		guestRuntimeStateRepository,
		labService,
		recorderGatewayColdPathSourceReader,
		vitalArtifactFormationProvider,
		archiveExportProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive service: %w", err)
	}
	guestTimeAuthorityProvider, err := composeGuestRuntimeTimeAuthorityProvider(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Time Authority provider: %w", err)
	}
	guestTimeAuthorityService, err := guestruntimeapplication.NewGuestRuntimeTimeAuthorityApplicationService(
		guestRuntimeStateRepository,
		guestTimeAuthorityProvider,
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
	guestTelemetryExporter, err := composeGuestRuntimeTelemetryExporter(deployment)
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
		ArchiveCredentialMaterial:            archiveCredentialMaterialService,
		ExternalUpstreamIntegration:          externalUpstreamService,
		OutboundRelayTarget:                  outboundRelayService,
		GuestTimeAuthority:                   guestTimeAuthorityService,
		RecorderObservationCatalog:           recorderObservationCatalogService,
		GuestTelemetryPipeline:               guestTelemetryPipelineService,
		LabArchiveLifecycleCoordinationClock: guestRuntimeApplicationClock,
	}), nil
}

func validateGuestRuntimeExternalUpstreamObservationProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.ExternalUpstreamObservationProviderReference.Kind {
	case "external-capability-profile":
		if deployment.ExternalUpstreamObservationProviderOutcomeMode == "" || deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath != "" || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds != 0 {
			return fmt.Errorf("Guest Runtime External Upstream outcome profile requires only an explicit outcome mode")
		}
	case "external-vitalserver-http":
		if deployment.ExternalUpstreamObservationProviderOutcomeMode != "" || deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath == "" || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds < 1 || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime External VitalServer HTTP observation provider requires C46 configuration path and request timeout")
		}
	default:
		return fmt.Errorf("Guest Runtime External Upstream observation provider kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeExternalUpstreamObservationProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeExternalUpstreamProvider, error) {
	switch deployment.ExternalUpstreamObservationProviderReference.Kind {
	case "external-capability-profile":
		return externalupstreamobservationprovider.NewConfiguredExternalUpstreamObservationProfile(
			deployment.ExternalUpstreamObservationProviderReference,
			deployment.ExternalUpstreamObservationProviderOutcomeMode,
		)
	case "external-vitalserver-http":
		return externalupstreamobservationprovider.NewExternalVitalServerHTTPObservationProviderFromFile(
			deployment.ExternalUpstreamObservationProviderReference,
			deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath,
			time.Duration(deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds)*time.Millisecond,
		)
	default:
		return nil, fmt.Errorf("Guest Runtime External Upstream observation provider kind is unsupported")
	}
}

func validateGuestRuntimeTimeAuthorityAdapter(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.GuestTimeAuthorityAdapterKind {
	case "time-authority-outcome-profile":
		if deployment.GuestTimeAuthorityChronyExecutablePath != "" || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds != 0 || deployment.GuestTimeAuthorityProbeOutcomeMode == "" {
			return fmt.Errorf("Guest Runtime Time Authority outcome profile requires only an explicit probe outcome mode")
		}
	case "chrony-tracking":
		if deployment.GuestTimeAuthorityProbeOutcomeMode != "" || deployment.GuestTimeAuthorityChronyExecutablePath == "" || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds < 1 || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime Chrony Time Authority adapter requires only an explicit executable path and request timeout")
		}
		if _, err := timeprovider.NewChronyTrackingTimeAuthorityProvider(deployment.GuestTimeAuthorityChronyExecutablePath, time.Duration(deployment.GuestTimeAuthorityRequestTimeoutMilliseconds)*time.Millisecond); err != nil {
			return fmt.Errorf("Guest Runtime Chrony Time Authority adapter configuration is invalid: %w", err)
		}
	default:
		return fmt.Errorf("Guest Runtime Time Authority adapter kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeTimeAuthorityProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeTimeAuthorityProvider, error) {
	switch deployment.GuestTimeAuthorityAdapterKind {
	case "time-authority-outcome-profile":
		return timeprovider.NewConfiguredTimeAuthorityOutcomeProfile(deployment.GuestTimeAuthorityProbeOutcomeMode)
	case "chrony-tracking":
		return timeprovider.NewChronyTrackingTimeAuthorityProvider(deployment.GuestTimeAuthorityChronyExecutablePath, time.Duration(deployment.GuestTimeAuthorityRequestTimeoutMilliseconds)*time.Millisecond)
	default:
		return nil, fmt.Errorf("Guest Runtime Time Authority adapter kind is unsupported")
	}
}

func validateGuestRuntimeTelemetryAdapter(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.GuestTelemetryAdapterKind {
	case "telemetry-export-outcome-profile":
		if deployment.GuestTelemetryCollectorBaseEndpoint != "" || deployment.GuestTelemetryRequestTimeoutMilliseconds != 0 || deployment.GuestTelemetryCollectorProbeOutcomeMode == "" || deployment.GuestTelemetryExportOutcomeMode == "" {
			return fmt.Errorf("Guest Runtime telemetry outcome profile requires only explicit pipeline and export outcome modes")
		}
	case "otlp-http":
		if deployment.GuestTelemetryCollectorProbeOutcomeMode != "" || deployment.GuestTelemetryExportOutcomeMode != "" || deployment.GuestTelemetryCollectorBaseEndpoint == "" || deployment.GuestTelemetryRequestTimeoutMilliseconds < 1 || deployment.GuestTelemetryRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime OTLP HTTP telemetry adapter requires only an explicit Collector base endpoint and request timeout")
		}
		if _, err := telemetryexporter.NewOTLPHTTPTelemetryExporter(deployment.GuestTelemetryCollectorBaseEndpoint, time.Duration(deployment.GuestTelemetryRequestTimeoutMilliseconds)*time.Millisecond); err != nil {
			return fmt.Errorf("Guest Runtime OTLP HTTP telemetry adapter configuration is invalid: %w", err)
		}
	default:
		return fmt.Errorf("Guest Runtime telemetry adapter kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeTelemetryExporter(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeTelemetryExporter, error) {
	switch deployment.GuestTelemetryAdapterKind {
	case "telemetry-export-outcome-profile":
		return telemetryexporter.NewConfiguredTelemetryExportOutcomeProfile(deployment.GuestTelemetryCollectorProbeOutcomeMode, deployment.GuestTelemetryExportOutcomeMode)
	case "otlp-http":
		return telemetryexporter.NewOTLPHTTPTelemetryExporter(deployment.GuestTelemetryCollectorBaseEndpoint, time.Duration(deployment.GuestTelemetryRequestTimeoutMilliseconds)*time.Millisecond)
	default:
		return nil, fmt.Errorf("Guest Runtime telemetry adapter kind is unsupported")
	}
}

func composeGuestRuntimeArchiveExportProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeArchiveExportProvider, error) {
	switch deployment.ArchiveExportProviderReference.Kind {
	case "archive-export-outcome-profile":
		provider, err := archiveprovider.NewConfiguredArchiveExportOutcomeProfile(
			deployment.ArchiveExportProviderReference,
			deployment.ArchiveExportProviderOutcomeMode,
		)
		if err != nil {
			return nil, err
		}
		return provider, nil
	case "vitalserver-indexed-library":
		return vitalserverindexedlibrary.NewDeferredVitalServerIndexedLibraryHTTPArchiveExportProvider(
			deployment.ArchiveProviderVitalServerConfigurationKind,
			deployment.ArchiveProviderVitalServerConfigurationPath,
			deployment.ArchiveProviderCredentialMaterialPath,
			deployment.ArchiveExportProviderReference,
		), nil
	default:
		return nil, fmt.Errorf("Guest Runtime Archive provider kind is unsupported")
	}
}

func composeGuestRuntimeArchiveCredentialMaterialOwner(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialOwner, error) {
	if deployment.ArchiveExportProviderReference.Kind != "vitalserver-indexed-library" {
		return nil, nil
	}
	return vitalserverindexedlibrary.NewVitalServerIndexedLibraryCredentialMaterialFileOwner(
		deployment.ArchiveProviderVitalServerConfigurationKind,
		deployment.ArchiveProviderVitalServerConfigurationPath,
		deployment.ArchiveProviderCredentialMaterialPath,
		deployment.ArchiveExportProviderReference,
	)
}

func validArchiveProviderVitalServerConfigurationKind(kind string) bool {
	return kind == vitalserverindexedlibrary.ExternalVitalServerDeliveryConfigurationKind || kind == vitalserverindexedlibrary.BundledVitalServerTopologyDeploymentKind
}
