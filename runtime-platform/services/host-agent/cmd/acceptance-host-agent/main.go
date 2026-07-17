// acceptance-host-agent is a test-only Host Agent composition used by public API acceptance tests.
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
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/guestruntimecontrolhttpclient"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/updatebootstrap"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentcontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type acceptanceProvider struct {
	clock hostagentapplication.HostAgentClock
}

type acceptanceUpdateBootstrapper struct {
	clock           hostagentapplication.HostAgentClock
	mode            string
	handoffEvidence string
}

func (bootstrapper acceptanceUpdateBootstrapper) Stage(_ context.Context, journal hostagentdomain.HostUpdateJournal, _ hostagentdomain.UpdateBootstrapEnvelope) hostagentdomain.UpdateBootstrapReceipt {
	receipt := hostagentdomain.UpdateBootstrapReceipt{SchemaVersion: hostagentdomain.SchemaVersion, UpdateID: journal.ID, RequestID: journal.RequestID, BootstrapEnvelopeID: journal.BootstrapEnvelopeID, NextUpdaterSHA256: journal.NextUpdaterSHA256, State: bootstrapper.mode, ObservedAt: hostagentdomain.Timestamp(bootstrapper.clock.Now())}
	if bootstrapper.mode == "failed" || bootstrapper.mode == "unavailable" {
		receipt.Issue = &hostagentdomain.Issue{Code: "acceptance-update-bootstrap-" + bootstrapper.mode, Message: "acceptance bootstrapper returned an explicit " + bootstrapper.mode + " outcome", Dependency: "acceptance-update-bootstrapper"}
	}
	return receipt
}

func (bootstrapper acceptanceUpdateBootstrapper) RequestHandoff(_ context.Context, journal hostagentdomain.HostUpdateJournal) *hostagentdomain.Issue {
	if bootstrapper.handoffEvidence == "" {
		return nil
	}
	file, err := os.OpenFile(bootstrapper.handoffEvidence, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return &hostagentdomain.Issue{Code: "acceptance-update-handoff-evidence-open-failed", Message: err.Error(), Dependency: "acceptance-update-bootstrapper"}
	}
	defer file.Close()
	if _, err := file.WriteString(journal.ID + "\n"); err != nil {
		return &hostagentdomain.Issue{Code: "acceptance-update-handoff-evidence-write-failed", Message: err.Error(), Dependency: "acceptance-update-bootstrapper"}
	}
	return nil
}

func (provider acceptanceProvider) Execute(_ context.Context, invocation hostagentdomain.PlatformProviderLifecycleInvocation) hostagentdomain.ProviderLifecycleResult {
	request := invocation.Lifecycle
	state := "running"
	if request.Action == "stop" {
		state = "stopped"
	}
	return hostagentdomain.ProviderLifecycleResult{
		SchemaVersion: hostagentdomain.SchemaVersion,
		RequestID:     request.RequestID,
		ProviderID:    request.ProviderID,
		ObservedState: state,
		ObservedAt:    hostagentdomain.Timestamp(provider.clock.Now()),
	}
}

func main() {
	var listenAddress string
	var stateDatabase string
	var installationID string
	var productVersion string
	var runtimeVersion string
	var dataDirectory string
	var guestRuntimeControlEndpointID string
	var guestRuntimeControlHTTPScheme string
	var guestRuntimeControlHTTPHost string
	var guestRuntimeControlHTTPPort int
	var providerKind string
	var providerID string
	var guestTimeout time.Duration
	var hostNodeID string
	var timeAuthorityID string
	var timeProviderMode string
	var telemetryPipelineMode string
	var telemetryExportMode string
	var updateBootstrapMode string
	var updateHandoffEvidence string
	var updateBundleStore string
	var updateStagingDirectory string
	var updateTrustStore string
	flag.StringVar(&listenAddress, "listen", "", "required Host Agent control listen address")
	flag.StringVar(&stateDatabase, "state-db", "", "required Host Agent-owned SQLite database path")
	flag.StringVar(&installationID, "installation-id", "", "required Host installation identifier")
	flag.StringVar(&productVersion, "product-version", "", "required product version")
	flag.StringVar(&runtimeVersion, "runtime-version", "", "required Guest Runtime version")
	flag.StringVar(&dataDirectory, "data-directory", "", "required Host-managed data directory")
	flag.StringVar(&guestRuntimeControlEndpointID, "guest-runtime-control-endpoint-id", "", "required configured Guest Runtime Control endpoint identifier")
	flag.StringVar(&guestRuntimeControlHTTPScheme, "guest-runtime-control-http-scheme", "", "required configured Guest Runtime Control HTTP scheme")
	flag.StringVar(&guestRuntimeControlHTTPHost, "guest-runtime-control-http-host", "", "required configured Guest Runtime Control HTTP host")
	flag.IntVar(&guestRuntimeControlHTTPPort, "guest-runtime-control-http-port", 0, "required configured Guest Runtime Control HTTP port")
	flag.StringVar(&providerKind, "provider-kind", "", "required configured Host provider kind")
	flag.StringVar(&providerID, "provider-id", "", "required configured Host provider identifier")
	flag.DurationVar(&guestTimeout, "guest-timeout", 5*time.Second, "Guest control request timeout")
	flag.StringVar(&hostNodeID, "host-node-id", "host-agent", "Host node identifier for Host-owned time and telemetry")
	flag.StringVar(&timeAuthorityID, "time-authority-id", "host-time-authority", "Host TimeAuthority resource identifier")
	flag.StringVar(&timeProviderMode, "time-provider-mode", timeprovider.ModeUnsupported, "Host time provider mode")
	flag.StringVar(&telemetryPipelineMode, "telemetry-pipeline-mode", telemetryexporter.PipelineUnsupported, "Host telemetry pipeline mode")
	flag.StringVar(&telemetryExportMode, "telemetry-export-mode", telemetryexporter.Unavailable, "Host telemetry export mode")
	flag.StringVar(&updateBootstrapMode, "update-bootstrap-mode", "staged", "Acceptance update bootstrap mode: staged, failed, unavailable, verified-staged-bundle")
	flag.StringVar(&updateHandoffEvidence, "update-handoff-evidence", "", "optional acceptance-only file written once per Host update handoff")
	flag.StringVar(&updateBundleStore, "update-bundle-store", "", "required with verified-staged-bundle: Host-owned release bundle store")
	flag.StringVar(&updateStagingDirectory, "update-staging-directory", "", "required with verified-staged-bundle: Host-owned update staging directory")
	flag.StringVar(&updateTrustStore, "update-trust-store", "", "required with verified-staged-bundle: Ed25519 release trust store")
	flag.Parse()
	if listenAddress == "" || stateDatabase == "" || installationID == "" || productVersion == "" || runtimeVersion == "" || dataDirectory == "" || guestRuntimeControlEndpointID == "" || guestRuntimeControlHTTPScheme == "" || guestRuntimeControlHTTPHost == "" || guestRuntimeControlHTTPPort == 0 || providerKind == "" || providerID == "" {
		fmt.Fprintln(os.Stderr, "all acceptance Host Agent ownership configuration flags are required")
		os.Exit(2)
	}
	if updateBootstrapMode != "staged" && updateBootstrapMode != "failed" && updateBootstrapMode != "unavailable" && updateBootstrapMode != "verified-staged-bundle" {
		fmt.Fprintln(os.Stderr, "update-bootstrap-mode must be staged, failed, unavailable, or verified-staged-bundle")
		os.Exit(2)
	}
	if updateBootstrapMode == "verified-staged-bundle" && (updateBundleStore == "" || updateStagingDirectory == "" || updateTrustStore == "") {
		fmt.Fprintln(os.Stderr, "verified-staged-bundle requires update-bundle-store, update-staging-directory, and update-trust-store")
		os.Exit(2)
	}
	if updateBootstrapMode == "verified-staged-bundle" && updateHandoffEvidence != "" {
		fmt.Fprintln(os.Stderr, "update-handoff-evidence is only valid with the deterministic acceptance bootstrapper")
		os.Exit(2)
	}
	if updateBootstrapMode != "verified-staged-bundle" && (updateBundleStore != "" || updateStagingDirectory != "" || updateTrustStore != "") {
		fmt.Fprintln(os.Stderr, "update bundle paths are only valid with verified-staged-bundle")
		os.Exit(2)
	}

	context, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context, stateDatabase)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent state initialization failed: %v\n", err)
		os.Exit(1)
	}
	defer repository.Close()
	clock := hostagentapplication.SystemHostAgentClock{}
	guest, err := guestruntimecontrolhttpclient.NewGuestRuntimeControlHTTPClient(&http.Client{Timeout: guestTimeout})
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent Guest control initialization failed: %v\n", err)
		os.Exit(1)
	}
	service, err := hostagentapplication.NewHostAgentControlApplicationService(repository, acceptanceProvider{clock: clock}, guest, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent service initialization failed: %v\n", err)
		os.Exit(1)
	}
	if err := service.InitializeHostAgentControlState(context, hostagentapplication.HostAgentControlStateInitialization{
		InstallationID: installationID, ProductVersion: productVersion, RuntimeVersion: runtimeVersion, DataDirectory: dataDirectory,
		GuestRuntimeControlEndpointID: guestRuntimeControlEndpointID, GuestRuntimeControlHTTPScheme: guestRuntimeControlHTTPScheme, GuestRuntimeControlHTTPHost: guestRuntimeControlHTTPHost, GuestRuntimeControlHTTPPort: guestRuntimeControlHTTPPort,
		ProviderKind: providerKind, ProviderID: providerID,
	}); err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent configuration failed: %v\n", err)
		os.Exit(1)
	}
	bootstrapper := hostagentapplication.HostUpdateBootstrapper(acceptanceUpdateBootstrapper{clock: clock, mode: updateBootstrapMode, handoffEvidence: updateHandoffEvidence})
	if updateBootstrapMode == "verified-staged-bundle" {
		verifiedBootstrapper, bootstrapperErr := updatebootstrap.NewStagedBundleBootstrapper(updatebootstrap.StagedBundleBootstrapperConfig{BundleStoreDirectory: updateBundleStore, StagingDirectory: updateStagingDirectory, TrustStorePath: updateTrustStore, Clock: clock})
		if bootstrapperErr != nil {
			fmt.Fprintf(os.Stderr, "acceptance verified update bootstrapper initialization failed: %v\n", bootstrapperErr)
			os.Exit(1)
		}
		bootstrapper = verifiedBootstrapper
	}
	updates, err := hostagentapplication.NewHostUpdateApplicationService(repository, bootstrapper, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host update service initialization failed: %v\n", err)
		os.Exit(1)
	}
	if err := updates.RecoverDurableHostUpdateHandoffs(context); err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host update handoff recovery failed: %v\n", err)
		os.Exit(1)
	}
	node := hostagentdomain.NodeReference{Kind: "host", ID: hostNodeID}
	timeProbe, err := timeprovider.NewConfiguredHostTimeAuthorityOutcomeProfile(timeProviderMode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Time Authority provider initialization failed: %v\n", err)
		os.Exit(1)
	}
	timeAuthority, err := hostagentapplication.NewHostTimeAuthorityApplicationService(repository, timeProbe, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{}, node, timeAuthorityID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Time Authority initialization failed: %v\n", err)
		os.Exit(1)
	}
	telemetryAdapter, err := telemetryexporter.NewConfiguredHostTelemetryExportOutcomeProfile(telemetryPipelineMode, telemetryExportMode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Telemetry provider initialization failed: %v\n", err)
		os.Exit(1)
	}
	telemetry, err := hostagentapplication.NewHostTelemetryPipelineApplicationService(repository, telemetryAdapter, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{}, node)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Telemetry Pipeline initialization failed: %v\n", err)
		os.Exit(1)
	}
	listener, err := net.Listen("tcp", listenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent listen failed: %v\n", err)
		os.Exit(1)
	}
	server := &http.Server{Handler: hostagentcontrolhttpapi.NewHostAgentControlHTTPServerWithModules(hostagentcontrolhttpapi.HostAgentControlHTTPModules{Lifecycle: service, Update: updates, Time: timeAuthority, Telemetry: telemetry})}
	fmt.Printf("acceptance-host-agent listening address=%s\n", listener.Addr().String())
	go func() {
		<-context.Done()
		_ = server.Shutdown(context)
	}()
	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "acceptance Host Agent server failed: %v\n", err)
		os.Exit(1)
	}
}
