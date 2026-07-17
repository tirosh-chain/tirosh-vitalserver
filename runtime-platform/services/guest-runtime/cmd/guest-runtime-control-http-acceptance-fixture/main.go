// guest-runtime-control-http-acceptance-fixture composes the real Guest
// Runtime application services behind their public HTTP contract for
// cross-host acceptance tests. It is not a production Guest process entry
// point: it deliberately does not bind the Linux-only virtio-socket transport.
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

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func main() {
	var listenAddress string
	var stateDatabase string
	var serviceVersion string
	var instanceID string
	var archiveProviderKind string
	var archiveProviderID string
	var archiveProviderRevision int
	var archiveProviderMode string
	var externalUpstreamObservationProviderKind string
	var externalUpstreamObservationProviderID string
	var externalUpstreamObservationProviderRevision int
	var externalUpstreamObservationProviderMode string
	var outboundRelayObservationProviderKind string
	var outboundRelayObservationProviderID string
	var outboundRelayObservationProviderRevision int
	var outboundRelayObservationProviderMode string
	var guestNodeID string
	var timeAuthorityID string
	var timeProviderMode string
	var telemetryPipelineMode string
	var telemetryExportMode string
	flag.StringVar(&listenAddress, "listen", "", "required acceptance fixture TCP control listen address")
	flag.StringVar(&stateDatabase, "state-db", "", "required Guest Runtime-owned SQLite database path")
	flag.StringVar(&serviceVersion, "service-version", "", "required Guest Runtime release version")
	flag.StringVar(&instanceID, "instance-id", "", "required Guest Runtime instance identifier")
	flag.StringVar(&archiveProviderKind, "archive-provider-kind", "", "required Archive Export provider kind")
	flag.StringVar(&archiveProviderID, "archive-provider-id", "", "required Archive Export provider id")
	flag.IntVar(&archiveProviderRevision, "archive-provider-capability-revision", 0, "required Archive Export provider capability revision")
	flag.StringVar(&archiveProviderMode, "archive-provider-mode", "", "required Archive Export provider outcome mode")
	flag.StringVar(&externalUpstreamObservationProviderKind, "external-upstream-observation-provider-kind", "", "required External Upstream observation provider kind")
	flag.StringVar(&externalUpstreamObservationProviderID, "external-upstream-observation-provider-id", "", "required External Upstream observation provider id")
	flag.IntVar(&externalUpstreamObservationProviderRevision, "external-upstream-observation-provider-capability-revision", 0, "required External Upstream observation provider capability revision")
	flag.StringVar(&externalUpstreamObservationProviderMode, "external-upstream-observation-provider-mode", "", "required External Upstream observation provider outcome mode")
	flag.StringVar(&outboundRelayObservationProviderKind, "outbound-relay-observation-provider-kind", "", "required Outbound Relay observation provider kind")
	flag.StringVar(&outboundRelayObservationProviderID, "outbound-relay-observation-provider-id", "", "required Outbound Relay observation provider id")
	flag.IntVar(&outboundRelayObservationProviderRevision, "outbound-relay-observation-provider-capability-revision", 0, "required Outbound Relay observation provider capability revision")
	flag.StringVar(&outboundRelayObservationProviderMode, "outbound-relay-observation-provider-mode", "", "required Outbound Relay observation provider outcome mode")
	flag.StringVar(&guestNodeID, "guest-node-id", "", "required Guest node identifier for Time and Telemetry resources")
	flag.StringVar(&timeAuthorityID, "time-authority-id", "", "required Guest Time Authority identifier used by clock-quality reads")
	flag.StringVar(&timeProviderMode, "time-provider-mode", "", "required Guest NTP probe outcome mode")
	flag.StringVar(&telemetryPipelineMode, "telemetry-pipeline-mode", "", "required Guest OTLP collector probe outcome mode")
	flag.StringVar(&telemetryExportMode, "telemetry-export-mode", "", "required Guest OTLP export outcome mode")
	flag.Parse()
	if missing := missingRequiredGuestRuntimeControlHTTPAcceptanceFixtureFlags([]requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag{
		{name: "--listen", value: listenAddress}, {name: "--state-db", value: stateDatabase}, {name: "--service-version", value: serviceVersion}, {name: "--instance-id", value: instanceID},
		{name: "--archive-provider-kind", value: archiveProviderKind}, {name: "--archive-provider-id", value: archiveProviderID}, {name: "--archive-provider-mode", value: archiveProviderMode},
		{name: "--external-upstream-observation-provider-kind", value: externalUpstreamObservationProviderKind}, {name: "--external-upstream-observation-provider-id", value: externalUpstreamObservationProviderID}, {name: "--external-upstream-observation-provider-mode", value: externalUpstreamObservationProviderMode},
		{name: "--outbound-relay-observation-provider-kind", value: outboundRelayObservationProviderKind}, {name: "--outbound-relay-observation-provider-id", value: outboundRelayObservationProviderID}, {name: "--outbound-relay-observation-provider-mode", value: outboundRelayObservationProviderMode},
		{name: "--guest-node-id", value: guestNodeID}, {name: "--time-authority-id", value: timeAuthorityID}, {name: "--time-provider-mode", value: timeProviderMode},
		{name: "--telemetry-pipeline-mode", value: telemetryPipelineMode}, {name: "--telemetry-export-mode", value: telemetryExportMode},
	}); len(missing) > 0 || archiveProviderRevision < 1 || externalUpstreamObservationProviderRevision < 1 || outboundRelayObservationProviderRevision < 1 {
		fmt.Fprintln(os.Stderr, "Guest Runtime Control HTTP acceptance fixture requires every application deployment setting explicitly; this fixture does not create a Guest virtio-socket listener")
		os.Exit(2)
	}

	acceptanceFixtureContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	guestRuntimeControlApplication, err := guestruntimecontrolhttpapplication.OpenGuestRuntimeControlHTTPApplication(
		acceptanceFixtureContext,
		guestruntimecontrolhttpapplication.GuestRuntimeControlHTTPApplicationDeployment{
			GuestRuntimeStateDatabasePath:                  stateDatabase,
			GuestRuntimeServiceVersion:                     serviceVersion,
			GuestRuntimeInstanceID:                         instanceID,
			ArchiveExportProviderReference:                 guestruntimedomain.ArchiveProviderReference{Kind: archiveProviderKind, ID: archiveProviderID, CapabilityRevision: archiveProviderRevision},
			ArchiveExportProviderOutcomeMode:               archiveProviderMode,
			ExternalUpstreamObservationProviderReference:   guestruntimedomain.IntegrationProviderReference{Kind: externalUpstreamObservationProviderKind, ID: externalUpstreamObservationProviderID, CapabilityRevision: externalUpstreamObservationProviderRevision},
			ExternalUpstreamObservationProviderOutcomeMode: externalUpstreamObservationProviderMode,
			OutboundRelayObservationProviderReference:      guestruntimedomain.IntegrationProviderReference{Kind: outboundRelayObservationProviderKind, ID: outboundRelayObservationProviderID, CapabilityRevision: outboundRelayObservationProviderRevision},
			OutboundRelayObservationProviderOutcomeMode:    outboundRelayObservationProviderMode,
			GuestRuntimeNode:                               guestruntimedomain.NodeReference{Kind: "guest", ID: guestNodeID},
			GuestTimeAuthorityID:                           timeAuthorityID,
			GuestTimeAuthorityProbeOutcomeMode:             timeProviderMode,
			GuestTelemetryCollectorProbeOutcomeMode:        telemetryPipelineMode,
			GuestTelemetryExportOutcomeMode:                telemetryExportMode,
		},
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture application open failed: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		if closeError := guestRuntimeControlApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture shutdown failed: %v\n", closeError)
		}
	}()
	controlHTTPListener, err := net.Listen("tcp", listenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture TCP listener failed: %v\n", err)
		os.Exit(1)
	}
	controlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	serveError := make(chan error, 1)
	go func() {
		if serverError := controlHTTPServer.Serve(controlHTTPListener); serverError != nil && !errors.Is(serverError, http.ErrServerClosed) {
			serveError <- fmt.Errorf("Guest Runtime Control HTTP acceptance fixture server failed: %w", serverError)
		}
	}()
	fmt.Printf("guest-runtime-control-http-acceptance-fixture TCP control listening address=%s\n", controlHTTPListener.Addr().String())
	select {
	case serverError := <-serveError:
		_ = controlHTTPServer.Shutdown(acceptanceFixtureContext)
		fmt.Fprintln(os.Stderr, serverError)
		os.Exit(1)
	case <-acceptanceFixtureContext.Done():
		_ = controlHTTPServer.Shutdown(acceptanceFixtureContext)
	}
}

type requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag struct {
	name  string
	value string
}

func missingRequiredGuestRuntimeControlHTTPAcceptanceFixtureFlags(flags []requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag) []string {
	missing := make([]string, 0)
	for _, candidate := range flags {
		if candidate.value == "" {
			missing = append(missing, candidate.name)
		}
	}
	return missing
}
