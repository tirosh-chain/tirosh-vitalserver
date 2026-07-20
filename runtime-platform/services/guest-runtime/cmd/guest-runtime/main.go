package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestpublicservicevirtiobridge"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestruntimecontrolvirtiolistener"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func main() {
	var listenAddress string
	var controlVirtioSocketPort uint
	var publicServiceVirtioSocketBridgeArguments guestPublicServiceVirtioSocketBridgeArguments
	var stateDatabase string
	var serviceVersion string
	var instanceID string
	var archiveProviderKind string
	var archiveProviderID string
	var archiveProviderRevision int
	var archiveProviderMode string
	var archiveProviderVitalServerConfigurationKind string
	var archiveProviderVitalServerConfigurationPath string
	var archiveProviderCredentialMaterialPath string
	var recorderGatewayColdPathSourceEndpoint string
	var labRecorderRunnerEndpoint string
	var externalUpstreamObservationProviderKind string
	var externalUpstreamObservationProviderID string
	var externalUpstreamObservationProviderRevision int
	var externalUpstreamObservationProviderMode string
	var externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath string
	var externalUpstreamObservationRequestTimeoutMilliseconds int
	var outboundRelayObservationProviderKind string
	var outboundRelayObservationProviderID string
	var outboundRelayObservationProviderRevision int
	var outboundRelayObservationProviderMode string
	var guestNodeID string
	var timeAuthorityID string
	var timeAdapterKind string
	var timeChronyExecutablePath string
	var timeRequestTimeoutMilliseconds int
	var timeProviderMode string
	var telemetryAdapterKind string
	var telemetryCollectorBaseEndpoint string
	var telemetryRequestTimeoutMilliseconds int
	var telemetryPipelineMode string
	var telemetryExportMode string
	flag.StringVar(&listenAddress, "listen", "", "required Guest Runtime control listen address")
	flag.UintVar(&controlVirtioSocketPort, "control-virtio-socket-port", 0, "required Guest Runtime control virtio-socket listener port")
	flag.Var(&publicServiceVirtioSocketBridgeArguments, "guest-public-service-virtio-socket-bridge", "required C37 public route as routeId,virtioSocketPort,127.0.0.1:targetPort; repeat for every route")
	flag.StringVar(&stateDatabase, "state-db", "", "required Guest Runtime-owned SQLite database path")
	flag.StringVar(&serviceVersion, "service-version", "", "required Guest Runtime release version")
	flag.StringVar(&instanceID, "instance-id", "", "required Guest Runtime instance identifier")
	flag.StringVar(&archiveProviderKind, "archive-provider-kind", "", "required Archive Export provider kind")
	flag.StringVar(&archiveProviderID, "archive-provider-id", "", "required Archive Export provider id")
	flag.IntVar(&archiveProviderRevision, "archive-provider-capability-revision", 0, "required Archive Export provider capability revision")
	flag.StringVar(&archiveProviderMode, "archive-provider-mode", "", "required only for Archive Export outcome profile")
	flag.StringVar(&archiveProviderVitalServerConfigurationKind, "archive-provider-vitalserver-configuration-kind", "", "required only for VitalServer indexed-library Archive provider: external C46 or bundled C44 configuration kind")
	flag.StringVar(&archiveProviderVitalServerConfigurationPath, "archive-provider-vitalserver-configuration", "", "required only for VitalServer indexed-library Archive provider: absolute selected C44-or-C46 configuration path")
	flag.StringVar(&archiveProviderCredentialMaterialPath, "archive-provider-credential-material-path", "", "required only for VitalServer indexed-library Archive provider: private credential material path")
	flag.StringVar(&recorderGatewayColdPathSourceEndpoint, "recorder-gateway-cold-path-source-endpoint", "", "required Recorder Gateway Guest-loopback cold-path source endpoint")
	flag.StringVar(&labRecorderRunnerEndpoint, "lab-recorder-runner-endpoint", "", "required Lab recorder Runner Guest-loopback control endpoint")
	flag.StringVar(&externalUpstreamObservationProviderKind, "external-upstream-observation-provider-kind", "", "required External Upstream observation provider kind")
	flag.StringVar(&externalUpstreamObservationProviderID, "external-upstream-observation-provider-id", "", "required External Upstream observation provider id")
	flag.IntVar(&externalUpstreamObservationProviderRevision, "external-upstream-observation-provider-capability-revision", 0, "required External Upstream observation provider capability revision")
	flag.StringVar(&externalUpstreamObservationProviderMode, "external-upstream-observation-provider-mode", "", "required only for the External Upstream outcome profile")
	flag.StringVar(&externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath, "external-upstream-observation-external-vitalserver-delivery-configuration", "", "required only for External VitalServer HTTP observation: absolute C46 configuration path")
	flag.IntVar(&externalUpstreamObservationRequestTimeoutMilliseconds, "external-upstream-observation-request-timeout-milliseconds", 0, "required only for External VitalServer HTTP observation")
	flag.StringVar(&outboundRelayObservationProviderKind, "outbound-relay-observation-provider-kind", "", "required Outbound Relay observation provider kind")
	flag.StringVar(&outboundRelayObservationProviderID, "outbound-relay-observation-provider-id", "", "required Outbound Relay observation provider id")
	flag.IntVar(&outboundRelayObservationProviderRevision, "outbound-relay-observation-provider-capability-revision", 0, "required Outbound Relay observation provider capability revision")
	flag.StringVar(&outboundRelayObservationProviderMode, "outbound-relay-observation-provider-mode", "", "required Outbound Relay observation provider outcome mode")
	flag.StringVar(&guestNodeID, "guest-node-id", "", "required Guest node identifier for time and telemetry resources")
	flag.StringVar(&timeAuthorityID, "time-authority-id", "", "required Guest TimeAuthority identifier used by clock-quality reads")
	flag.StringVar(&timeAdapterKind, "time-adapter-kind", "", "required Guest Time Authority adapter kind: time-authority-outcome-profile or chrony-tracking")
	flag.StringVar(&timeChronyExecutablePath, "time-chrony-executable-path", "", "required only for the Chrony Time Authority adapter")
	flag.IntVar(&timeRequestTimeoutMilliseconds, "time-request-timeout-milliseconds", 0, "required only for the Chrony Time Authority adapter")
	flag.StringVar(&timeProviderMode, "time-provider-mode", "", "required only for the Time Authority outcome profile")
	flag.StringVar(&telemetryAdapterKind, "telemetry-adapter-kind", "", "required Guest telemetry adapter kind: telemetry-export-outcome-profile or otlp-http")
	flag.StringVar(&telemetryCollectorBaseEndpoint, "telemetry-collector-base-endpoint", "", "required only for the OTLP HTTP telemetry adapter")
	flag.IntVar(&telemetryRequestTimeoutMilliseconds, "telemetry-request-timeout-milliseconds", 0, "required only for the OTLP HTTP telemetry adapter")
	flag.StringVar(&telemetryPipelineMode, "telemetry-pipeline-mode", "", "required only for the telemetry outcome profile")
	flag.StringVar(&telemetryExportMode, "telemetry-export-mode", "", "required only for the telemetry outcome profile")
	flag.Parse()
	if missing := missingRequiredGuestRuntimeFlags([]requiredGuestRuntimeFlag{
		{name: "--listen", value: listenAddress}, {name: "--control-virtio-socket-port", value: fmt.Sprintf("%d", controlVirtioSocketPort)}, {name: "--state-db", value: stateDatabase}, {name: "--service-version", value: serviceVersion}, {name: "--instance-id", value: instanceID},
		{name: "--archive-provider-kind", value: archiveProviderKind}, {name: "--archive-provider-id", value: archiveProviderID}, {name: "--recorder-gateway-cold-path-source-endpoint", value: recorderGatewayColdPathSourceEndpoint}, {name: "--lab-recorder-runner-endpoint", value: labRecorderRunnerEndpoint},
		{name: "--external-upstream-observation-provider-kind", value: externalUpstreamObservationProviderKind}, {name: "--external-upstream-observation-provider-id", value: externalUpstreamObservationProviderID},
		{name: "--outbound-relay-observation-provider-kind", value: outboundRelayObservationProviderKind}, {name: "--outbound-relay-observation-provider-id", value: outboundRelayObservationProviderID}, {name: "--outbound-relay-observation-provider-mode", value: outboundRelayObservationProviderMode},
		{name: "--guest-node-id", value: guestNodeID}, {name: "--time-authority-id", value: timeAuthorityID}, {name: "--time-adapter-kind", value: timeAdapterKind},
		{name: "--telemetry-adapter-kind", value: telemetryAdapterKind},
	}); len(missing) > 0 || controlVirtioSocketPort > uint(^uint16(0)) || archiveProviderRevision < 1 || externalUpstreamObservationProviderRevision < 1 || outboundRelayObservationProviderRevision < 1 || !completeArchiveProviderFlags(archiveProviderKind, archiveProviderMode, archiveProviderVitalServerConfigurationKind, archiveProviderVitalServerConfigurationPath, archiveProviderCredentialMaterialPath) || !completeExternalUpstreamObservationProviderFlags(externalUpstreamObservationProviderKind, externalUpstreamObservationProviderMode, externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath, externalUpstreamObservationRequestTimeoutMilliseconds) || !completeTimeAuthorityAdapterFlags(timeAdapterKind, timeChronyExecutablePath, timeRequestTimeoutMilliseconds, timeProviderMode) || !completeTelemetryAdapterFlags(telemetryAdapterKind, telemetryCollectorBaseEndpoint, telemetryRequestTimeoutMilliseconds, telemetryPipelineMode, telemetryExportMode) {
		fmt.Fprintln(os.Stderr, "Guest Runtime required configuration is incomplete; every provider reference, selected adapter, TCP listener, virtio-socket listener, state store, time, and telemetry setting must be explicit")
		os.Exit(2)
	}
	publicServiceVirtioSocketBridges, err := parseGuestPublicServiceVirtioSocketBridgeArguments(publicServiceVirtioSocketBridgeArguments)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime public service transport configuration is invalid: %v\n", err)
		os.Exit(2)
	}
	for _, publicServiceVirtioSocketBridge := range publicServiceVirtioSocketBridges {
		if publicServiceVirtioSocketBridge.VirtioSocketPort == uint32(controlVirtioSocketPort) {
			fmt.Fprintln(os.Stderr, "Guest Runtime public service transport cannot reuse the control virtio-socket port")
			os.Exit(2)
		}
	}

	guestRuntimeProcessContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	guestRuntimeControlApplication, err := guestruntimecontrolhttpapplication.OpenGuestRuntimeControlHTTPApplication(
		guestRuntimeProcessContext,
		guestruntimecontrolhttpapplication.GuestRuntimeControlHTTPApplicationDeployment{
			GuestRuntimeStateDatabasePath:                                           stateDatabase,
			GuestRuntimeServiceVersion:                                              serviceVersion,
			GuestRuntimeInstanceID:                                                  instanceID,
			ArchiveExportProviderReference:                                          guestruntimedomain.ArchiveProviderReference{Kind: archiveProviderKind, ID: archiveProviderID, CapabilityRevision: archiveProviderRevision},
			ArchiveExportProviderOutcomeMode:                                        archiveProviderMode,
			ArchiveProviderVitalServerConfigurationKind:                             archiveProviderVitalServerConfigurationKind,
			ArchiveProviderVitalServerConfigurationPath:                             archiveProviderVitalServerConfigurationPath,
			ArchiveProviderCredentialMaterialPath:                                   archiveProviderCredentialMaterialPath,
			RecorderGatewayColdPathSourceEndpoint:                                   recorderGatewayColdPathSourceEndpoint,
			LabRecorderRunnerEndpoint:                                               labRecorderRunnerEndpoint,
			ExternalUpstreamObservationProviderReference:                            guestruntimedomain.IntegrationProviderReference{Kind: externalUpstreamObservationProviderKind, ID: externalUpstreamObservationProviderID, CapabilityRevision: externalUpstreamObservationProviderRevision},
			ExternalUpstreamObservationProviderOutcomeMode:                          externalUpstreamObservationProviderMode,
			ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath: externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath,
			ExternalUpstreamObservationRequestTimeoutMilliseconds:                   externalUpstreamObservationRequestTimeoutMilliseconds,
			OutboundRelayObservationProviderReference:                               guestruntimedomain.IntegrationProviderReference{Kind: outboundRelayObservationProviderKind, ID: outboundRelayObservationProviderID, CapabilityRevision: outboundRelayObservationProviderRevision},
			OutboundRelayObservationProviderOutcomeMode:                             outboundRelayObservationProviderMode,
			GuestRuntimeNode:                                                        guestruntimedomain.NodeReference{Kind: "guest", ID: guestNodeID},
			GuestTimeAuthorityID:                                                    timeAuthorityID,
			GuestTimeAuthorityAdapterKind:                                           timeAdapterKind,
			GuestTimeAuthorityChronyExecutablePath:                                  timeChronyExecutablePath,
			GuestTimeAuthorityRequestTimeoutMilliseconds:                            timeRequestTimeoutMilliseconds,
			GuestTimeAuthorityProbeOutcomeMode:                                      timeProviderMode,
			GuestTelemetryAdapterKind:                                               telemetryAdapterKind,
			GuestTelemetryCollectorBaseEndpoint:                                     telemetryCollectorBaseEndpoint,
			GuestTelemetryRequestTimeoutMilliseconds:                                telemetryRequestTimeoutMilliseconds,
			GuestTelemetryCollectorProbeOutcomeMode:                                 telemetryPipelineMode,
			GuestTelemetryExportOutcomeMode:                                         telemetryExportMode,
		},
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime control application open failed: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		if closeError := guestRuntimeControlApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			fmt.Fprintf(os.Stderr, "Guest Runtime control application shutdown failed: %v\n", closeError)
		}
	}()
	if reconciliationError := guestRuntimeControlApplication.ReconcilePendingTerminalArchiveExports(guestRuntimeProcessContext); reconciliationError != nil {
		// Lab and Archive keep the underlying terminal intent durable and
		// operator-readable. Do not claim that startup repaired it; serving the
		// control API lets an operator inspect and explicitly retry the exact
		// idempotent stop/archive request after the dependency recovers.
		fmt.Fprintf(os.Stderr, "Guest Runtime terminal Archive reconciliation was not completed: %v\n", reconciliationError)
	}
	tcpListener, err := net.Listen("tcp", listenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime TCP control listener failed: %v\n", err)
		os.Exit(1)
	}
	virtioSocketListener, err := guestruntimecontrolvirtiolistener.ListenGuestRuntimeControlVirtioSocket(uint32(controlVirtioSocketPort))
	if err != nil {
		_ = tcpListener.Close()
		fmt.Fprintf(os.Stderr, "Guest Runtime virtio-socket control listener failed: %v\n", err)
		os.Exit(1)
	}
	tcpControlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	virtioSocketControlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	serveErrors := make(chan error, 2+len(publicServiceVirtioSocketBridges))
	serveGuestRuntimeControlHTTP := func(server *http.Server, listener net.Listener, boundary string) {
		if serveError := server.Serve(listener); serveError != nil && !errors.Is(serveError, http.ErrServerClosed) {
			serveErrors <- fmt.Errorf("Guest Runtime %s control server failed: %w", boundary, serveError)
		}
	}
	go serveGuestRuntimeControlHTTP(tcpControlHTTPServer, tcpListener, "TCP")
	go serveGuestRuntimeControlHTTP(virtioSocketControlHTTPServer, virtioSocketListener, "virtio-socket")
	for _, publicServiceVirtioSocketBridge := range publicServiceVirtioSocketBridges {
		go runGuestPublicServiceVirtioSocketBridge(guestRuntimeProcessContext, publicServiceVirtioSocketBridge, serveErrors)
	}
	fmt.Printf("guest-runtime TCP control listening address=%s\n", tcpListener.Addr().String())
	fmt.Printf("guest-runtime virtio-socket control listening port=%d\n", controlVirtioSocketPort)
	go func() {
		<-guestRuntimeProcessContext.Done()
		_ = tcpControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		_ = virtioSocketControlHTTPServer.Shutdown(guestRuntimeProcessContext)
	}()
	select {
	case serveError := <-serveErrors:
		_ = tcpControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		_ = virtioSocketControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		fmt.Fprintf(os.Stderr, "%v\n", serveError)
		os.Exit(1)
	case <-guestRuntimeProcessContext.Done():
	}
}

func completeArchiveProviderFlags(kind string, outcomeMode string, vitalServerConfigurationKind string, vitalServerConfigurationPath string, credentialMaterialPath string) bool {
	switch kind {
	case "archive-export-outcome-profile":
		return outcomeMode != "" && vitalServerConfigurationKind == "" && vitalServerConfigurationPath == "" && credentialMaterialPath == ""
	case "vitalserver-indexed-library":
		return outcomeMode == "" && (vitalServerConfigurationKind == "external-vitalserver-delivery-configuration" || vitalServerConfigurationKind == "bundled-vitalserver-topology-deployment") && vitalServerConfigurationPath != "" && credentialMaterialPath != ""
	default:
		return false
	}
}

func completeExternalUpstreamObservationProviderFlags(kind string, outcomeMode string, externalVitalServerDeliveryConfigurationPath string, requestTimeoutMilliseconds int) bool {
	switch kind {
	case "external-capability-profile":
		return outcomeMode != "" && externalVitalServerDeliveryConfigurationPath == "" && requestTimeoutMilliseconds == 0
	case "external-vitalserver-http":
		return outcomeMode == "" && externalVitalServerDeliveryConfigurationPath != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000
	default:
		return false
	}
}

func completeTelemetryAdapterFlags(kind string, collectorBaseEndpoint string, requestTimeoutMilliseconds int, pipelineMode string, exportMode string) bool {
	switch kind {
	case "telemetry-export-outcome-profile":
		return collectorBaseEndpoint == "" && requestTimeoutMilliseconds == 0 && pipelineMode != "" && exportMode != ""
	case "otlp-http":
		return collectorBaseEndpoint != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000 && pipelineMode == "" && exportMode == ""
	default:
		return false
	}
}

func completeTimeAuthorityAdapterFlags(kind string, chronyExecutablePath string, requestTimeoutMilliseconds int, outcomeMode string) bool {
	switch kind {
	case "time-authority-outcome-profile":
		return chronyExecutablePath == "" && requestTimeoutMilliseconds == 0 && outcomeMode != ""
	case "chrony-tracking":
		return chronyExecutablePath != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000 && outcomeMode == ""
	default:
		return false
	}
}

func runGuestPublicServiceVirtioSocketBridge(context context.Context, configuration guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration, serveErrors chan<- error) {
	if err := guestpublicservicevirtiobridge.RunGuestPublicServiceVirtioSocketBridge(context, configuration); err != nil && context.Err() == nil {
		serveErrors <- fmt.Errorf("Guest public service route %s transport failed: %w", configuration.RouteID, err)
	}
}

type requiredGuestRuntimeFlag struct {
	name  string
	value string
}

func missingRequiredGuestRuntimeFlags(flags []requiredGuestRuntimeFlag) []string {
	missing := make([]string, 0)
	for _, candidate := range flags {
		if candidate.value == "" {
			missing = append(missing, candidate.name)
		}
	}
	return missing
}
