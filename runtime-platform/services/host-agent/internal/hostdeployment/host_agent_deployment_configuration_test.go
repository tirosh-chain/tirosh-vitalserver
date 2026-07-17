package hostdeployment_test

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func validMacOSDeploymentConfiguration() hostdeployment.HostAgentDeploymentConfiguration {
	return hostdeployment.HostAgentDeploymentConfiguration{
		SchemaVersion: "v1",
		Control: hostdeployment.HostAgentControlConfiguration{
			ListenAddress: "127.0.0.1:18280", StateDatabasePath: "/var/lib/vitalserver/host-agent.sqlite", GuestTimeoutMilliseconds: 5000,
		},
		Installation: hostdeployment.HostInstallationConfiguration{
			InstallationID: "vitalserver-macos", ProductVersion: "0.1.0-dev", RuntimeVersion: "0.1.0-dev", DataDirectory: "/var/lib/vitalserver/data",
		},
		GuestRuntimeControlEndpoint: hostdeployment.GuestRuntimeControlEndpointConfiguration{ID: "vitalserver-guest", Scheme: "http", Host: "192.168.64.2", Port: 18443},
		Provider: hostdeployment.SelectedProviderConfiguration{
			Kind: "macos-virtualization", ID: "vitalserver-macos-provider", MacOSVirtualMachineSupervisorExecutablePath: "/opt/vitalserver/macos-virtual-machine-supervisor", MacOSVirtualMachineConfigurationPath: "/opt/vitalserver/config/macos-vm.json",
		},
		Time:            hostdeployment.HostTimeConfiguration{HostNodeID: "vitalserver-macos-host", TimeAuthorityID: "vitalserver-host-time", ProviderMode: "unsupported"},
		Telemetry:       hostdeployment.HostTelemetryConfiguration{PipelineMode: "unsupported", ExportMode: "unavailable"},
		UpdateBootstrap: hostdeployment.HostUpdateBootstrapConfiguration{Mode: "unavailable"},
	}
}

func writeDeploymentConfiguration(t *testing.T, configuration hostdeployment.HostAgentDeploymentConfiguration) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "host-agent-deployment.json")
	encoded, err := json.Marshal(configuration)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadHostAgentDeploymentConfigurationReturnsExplicitMacOSDeployment(t *testing.T) {
	path := writeDeploymentConfiguration(t, validMacOSDeploymentConfiguration())
	configuration, err := hostdeployment.LoadHostAgentDeploymentConfiguration(path)
	if err != nil {
		t.Fatal(err)
	}
	if configuration.GuestTimeout() != 5*time.Second {
		t.Fatalf("Guest timeout = %s", configuration.GuestTimeout())
	}
	command, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(configuration.SelectedPlatformProviderProcessDeployment())
	if err != nil {
		t.Fatal(err)
	}
	if len(command.Arguments) != 2 || command.Arguments[1] != "/opt/vitalserver/config/macos-vm.json" {
		t.Fatalf("macOS bridge command = %#v", command)
	}
}

func TestLoadHostAgentDeploymentConfigurationRejectsMacOSProviderWithoutC32(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Provider.MacOSVirtualMachineConfigurationPath = ""
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration))
	var invalid hostdeployment.DeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("error = %v, want invalid deployment configuration", err)
	}
}

func TestLoadHostAgentDeploymentConfigurationRejectsProviderInputsFromAnotherPlatform(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Provider.NativeProviderBridgeExecutablePath = "/opt/vitalserver/linux-provider-bridge"
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration))
	var invalid hostdeployment.DeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("macOS configuration error = %v, want invalid deployment configuration", err)
	}

	configuration = validMacOSDeploymentConfiguration()
	configuration.Provider = hostdeployment.SelectedProviderConfiguration{
		Kind:                               "linux-kvm-libvirt-systemd",
		ID:                                 "vitalserver-linux-provider",
		NativeProviderBridgeExecutablePath: "/opt/vitalserver/linux-provider-bridge",
		NativeVirtualMachineName:           "vitalserver-guest",
		HostServiceName:                    "vitalserver-host-agent.service",
		MacOSVirtualMachineSupervisorExecutablePath: "/opt/vitalserver/macos-virtual-machine-supervisor",
	}
	_, err = hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration))
	if !errors.As(err, &invalid) {
		t.Fatalf("native configuration error = %v, want invalid deployment configuration", err)
	}
}

func TestLoadHostAgentDeploymentConfigurationReportsMissingDocumentAsUnavailable(t *testing.T) {
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(filepath.Join(t.TempDir(), "missing.json"))
	var unavailable hostdeployment.DeploymentConfigurationUnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("error = %v, want unavailable deployment configuration", err)
	}
}
