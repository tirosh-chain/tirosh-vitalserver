package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/guestruntimecontrolhttpclient"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/platformproviderprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/updatebootstrap"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentcontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func main() {
	deploymentConfiguration, exitCode := loadHostAgentDeploymentConfiguration(os.Args[1:], os.Stderr)
	if exitCode != 0 {
		os.Exit(exitCode)
	}

	context, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context, deploymentConfiguration.Control.StateDatabasePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent state initialization failed: %v\n", err)
		os.Exit(1)
	}
	defer repository.Close()
	clock := hostagentapplication.SystemHostAgentClock{}
	providerProcessCommand, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(deploymentConfiguration.SelectedPlatformProviderProcessDeployment())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent provider deployment configuration failed: %v\n", err)
		os.Exit(2)
	}
	var provider hostagentapplication.PlatformProviderLifecycleClient
	var persistentProvider *platformproviderprocess.PersistentPlatformProviderProcessRunner
	if deploymentConfiguration.Provider.Kind == hostagentdomain.MacOSVirtualizationProviderKind {
		persistentProvider, err = platformproviderprocess.StartPersistentPlatformProviderProcessRunner(context, providerProcessCommand)
		if err == nil {
			provider, err = platformproviderprocess.NewSelectedPlatformProviderProcessClientWithRunner(deploymentConfiguration.Provider.Kind, persistentProvider, clock)
		}
	} else {
		provider, err = platformproviderprocess.NewSelectedPlatformProviderProcessClient(deploymentConfiguration.Provider.Kind, providerProcessCommand, clock)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent provider initialization failed: %v\n", err)
		os.Exit(1)
	}
	if persistentProvider != nil {
		defer persistentProvider.Close()
	}
	guest, err := guestruntimecontrolhttpclient.NewGuestRuntimeControlHTTPClient(&http.Client{Timeout: deploymentConfiguration.GuestTimeout()})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent Guest control initialization failed: %v\n", err)
		os.Exit(1)
	}
	service, err := hostagentapplication.NewHostAgentControlApplicationService(repository, provider, guest, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent service initialization failed: %v\n", err)
		os.Exit(1)
	}
	if err := service.InitializeHostAgentControlState(context, hostagentapplication.HostAgentControlStateInitialization{
		InstallationID:                deploymentConfiguration.Installation.InstallationID,
		ProductVersion:                deploymentConfiguration.Installation.ProductVersion,
		RuntimeVersion:                deploymentConfiguration.Installation.RuntimeVersion,
		DataDirectory:                 deploymentConfiguration.Installation.DataDirectory,
		GuestRuntimeControlEndpointID: deploymentConfiguration.GuestRuntimeControlEndpoint.ID,
		GuestRuntimeControlHTTPScheme: deploymentConfiguration.GuestRuntimeControlEndpoint.Scheme,
		GuestRuntimeControlHTTPHost:   deploymentConfiguration.GuestRuntimeControlEndpoint.Host,
		GuestRuntimeControlHTTPPort:   deploymentConfiguration.GuestRuntimeControlEndpoint.Port,
		ProviderKind:                  deploymentConfiguration.Provider.Kind,
		ProviderID:                    deploymentConfiguration.Provider.ID,
	}); err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent configuration failed: %v\n", err)
		os.Exit(1)
	}
	bootstrapper := hostagentapplication.HostUpdateBootstrapper(updatebootstrap.Unavailable{Clock: clock})
	if deploymentConfiguration.UpdateBootstrap.Mode == "staged" {
		stagedBundleBootstrapper, bootstrapperErr := updatebootstrap.NewStagedBundleBootstrapper(updatebootstrap.StagedBundleBootstrapperConfig{
			BundleStoreDirectory: deploymentConfiguration.UpdateBootstrap.BundleStoreDirectory,
			StagingDirectory:     deploymentConfiguration.UpdateBootstrap.StagingDirectory,
			TrustStorePath:       deploymentConfiguration.UpdateBootstrap.TrustStorePath,
			Clock:                clock,
		})
		if bootstrapperErr != nil {
			fmt.Fprintf(os.Stderr, "Host update bootstrapper initialization failed: %v\n", bootstrapperErr)
			os.Exit(1)
		}
		bootstrapper = stagedBundleBootstrapper
	}
	updates, err := hostagentapplication.NewHostUpdateApplicationService(repository, bootstrapper, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host update service initialization failed: %v\n", err)
		os.Exit(1)
	}
	if err := updates.RecoverDurableHostUpdateHandoffs(context); err != nil {
		fmt.Fprintf(os.Stderr, "Host update handoff recovery failed: %v\n", err)
		os.Exit(1)
	}
	node := hostagentdomain.NodeReference{Kind: "host", ID: deploymentConfiguration.Time.HostNodeID}
	timeProbe, err := timeprovider.NewConfiguredHostTimeAuthorityOutcomeProfile(deploymentConfiguration.Time.ProviderMode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Time Authority provider initialization failed: %v\n", err)
		os.Exit(1)
	}
	timeAuthority, err := hostagentapplication.NewHostTimeAuthorityApplicationService(repository, timeProbe, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{}, node, deploymentConfiguration.Time.TimeAuthorityID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Time Authority initialization failed: %v\n", err)
		os.Exit(1)
	}
	telemetryExporter, err := telemetryexporter.NewConfiguredHostTelemetryExportOutcomeProfile(deploymentConfiguration.Telemetry.PipelineMode, deploymentConfiguration.Telemetry.ExportMode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Telemetry exporter initialization failed: %v\n", err)
		os.Exit(1)
	}
	telemetry, err := hostagentapplication.NewHostTelemetryPipelineApplicationService(repository, telemetryExporter, clock, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{}, node)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Telemetry Pipeline initialization failed: %v\n", err)
		os.Exit(1)
	}
	listener, err := net.Listen("tcp", deploymentConfiguration.Control.ListenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Agent listen failed: %v\n", err)
		os.Exit(1)
	}
	server := &http.Server{Handler: hostagentcontrolhttpapi.NewHostAgentControlHTTPServerWithModules(hostagentcontrolhttpapi.HostAgentControlHTTPModules{Lifecycle: service, Update: updates, Time: timeAuthority, Telemetry: telemetry})}
	fmt.Printf("host-agent listening address=%s\n", listener.Addr().String())
	go func() {
		<-context.Done()
		_ = server.Shutdown(context)
	}()
	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "Host Agent server failed: %v\n", err)
		os.Exit(1)
	}
}

// loadHostAgentDeploymentConfiguration is the product process's single
// startup-input boundary. It does not merge flags, environment values, or
// installation-layout guesses into C33.
func loadHostAgentDeploymentConfiguration(arguments []string, diagnostics io.Writer) (hostdeployment.HostAgentDeploymentConfiguration, int) {
	flags := flag.NewFlagSet("host-agent", flag.ContinueOnError)
	flags.SetOutput(diagnostics)
	var deploymentConfigurationPath string
	flags.StringVar(&deploymentConfigurationPath, "deployment-configuration", "", "required absolute path to C33 HostAgentDeploymentConfiguration JSON")
	if err := flags.Parse(arguments); err != nil {
		return hostdeployment.HostAgentDeploymentConfiguration{}, 2
	}
	if deploymentConfigurationPath == "" {
		fmt.Fprintln(diagnostics, "Host Agent deployment configuration path is required")
		return hostdeployment.HostAgentDeploymentConfiguration{}, 2
	}
	deploymentConfiguration, err := hostdeployment.LoadHostAgentDeploymentConfiguration(deploymentConfigurationPath)
	if err != nil {
		fmt.Fprintf(diagnostics, "Host Agent deployment configuration failed: %v\n", err)
		return hostdeployment.HostAgentDeploymentConfiguration{}, 1
	}
	return deploymentConfiguration, 0
}
