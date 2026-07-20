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
	authorizedUserID := 501
	return hostdeployment.HostAgentDeploymentConfiguration{
		SchemaVersion: "v1",
		Control: hostdeployment.HostAgentControlConfiguration{
			LocalAdministration: hostdeployment.HostLocalAdministrationConfiguration{
				Transport: "unix-domain-socket", EndpointAddress: "/var/lib/vitalserver/control/host-agent.sock", DescriptorPath: "/var/lib/vitalserver/control/host-agent.local.json", AuthorizedUserID: &authorizedUserID,
			},
			LoopbackHTTP:      hostdeployment.HostAgentLoopbackHTTPConfiguration{Mode: "development-loopback", ListenAddress: "127.0.0.1:18280"},
			StateDatabasePath: "/var/lib/vitalserver/host-agent.sqlite", GuestTimeoutMilliseconds: 5000,
		},
		Installation: hostdeployment.HostInstallationConfiguration{
			InstallationID: "vitalserver-macos", ProductVersion: "0.1.0-dev", RuntimeVersion: "0.1.0-dev", DataDirectory: "/var/lib/vitalserver/data",
		},
		GuestRuntimeControlEndpoint: hostdeployment.GuestRuntimeControlEndpointConfiguration{ID: "vitalserver-guest", Scheme: "http", Host: "192.168.64.2", Port: 18443},
		Provider: hostdeployment.SelectedProviderConfiguration{
			Kind: "macos-virtualization", ID: "vitalserver-macos-provider", MacOSVirtualMachineSupervisorExecutablePath: "/opt/vitalserver/macos-virtual-machine-supervisor", MacOSVirtualMachineConfigurationPath: "/opt/vitalserver/config/macos-vm.json",
		},
		Time:            hostdeployment.HostTimeConfiguration{HostNodeID: "vitalserver-macos-host", TimeAuthorityID: "vitalserver-host-time", Kind: "time-authority-outcome-profile", ProviderMode: "unsupported"},
		Telemetry:       hostdeployment.HostTelemetryConfiguration{Kind: "telemetry-export-outcome-profile", PipelineMode: "unsupported", ExportMode: "unavailable"},
		UpdateBootstrap: hostdeployment.HostUpdateBootstrapConfiguration{Mode: "unavailable"},
	}
}

func TestHostTelemetryOTLPConfigurationRequiresOnlyAnExplicitBaseEndpointAndTimeout(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Telemetry = hostdeployment.HostTelemetryConfiguration{Kind: "otlp-http", CollectorBaseEndpoint: "http://collector.internal:4318", RequestTimeoutMilliseconds: 5000}
	if err := configuration.Validate(); err != nil {
		t.Fatalf("valid OTLP configuration: %v", err)
	}
	configuration.Telemetry.CollectorBaseEndpoint = "http://collector.internal:4318/v1/logs"
	if err := configuration.Validate(); err == nil {
		t.Fatal("accepted a Collector route instead of a base endpoint")
	}
}

func TestHostNTPUDPTimeConfigurationRequiresAnExplicitEndpointAndSource(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Time = hostdeployment.HostTimeConfiguration{HostNodeID: "vitalserver-macos-host", TimeAuthorityID: "vitalserver-host-time", Kind: "ntp-udp-quality-probe", NTPServerAddress: "ntp.internal:123", SourceProfile: "enterprise-ntp", SourceID: "hospital-ntp-primary", RequestTimeoutMilliseconds: 5000, MaximumOffsetMilliseconds: 100, MaximumUncertaintyMilliseconds: 100}
	if err := configuration.Validate(); err != nil {
		t.Fatalf("valid NTP UDP configuration: %v", err)
	}
	configuration.Time.NTPServerAddress = "ntp.internal"
	if err := configuration.Validate(); err == nil {
		t.Fatal("accepted an implicit NTP port")
	}
}

func TestLoadHostAgentDeploymentConfigurationRejectsMissingLocalAdministrationAuthorization(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Control.LocalAdministration.AuthorizedUserID = nil
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration))
	var invalid hostdeployment.DeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("error = %v, want invalid deployment configuration", err)
	}
}

func TestLoadHostAgentDeploymentConfigurationAcceptsWindowsNamedPipeWithExplicitDACL(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Control.LocalAdministration = hostdeployment.HostLocalAdministrationConfiguration{
		Transport: "windows-named-pipe", EndpointAddress: `\\.\pipe\VitalServerRuntimePlatform.HostAgent`, DescriptorPath: `C:\ProgramData\VitalServerRuntimePlatform\host-agent.local.json`, SecurityDescriptor: "D:P(A;;GA;;;SY)(A;;GA;;;BA)",
	}
	configuration.Control.LoopbackHTTP = hostdeployment.HostAgentLoopbackHTTPConfiguration{Mode: "disabled"}
	configuration.Installation.DataDirectory = `C:\ProgramData\VitalServerRuntimePlatform\data`
	configuration.Provider = hostdeployment.SelectedProviderConfiguration{
		Kind: "windows-hyperv-scm", ID: "vitalserver-windows-provider", NativeProviderBridgeExecutablePath: `C:\Program Files\VitalServerRuntimePlatform\current\bin\windows-provider-bridge.exe`, NativeVirtualMachineName: "vitalserver-guest", HostServiceName: "VitalServerRuntimePlatformHostAgent", NativeGuestMachineOwnership: "externally-provisioned",
	}
	path := writeDeploymentConfiguration(t, configuration)
	if _, err := hostdeployment.LoadHostAgentDeploymentConfiguration(path); err != nil {
		t.Fatalf("LoadHostAgentDeploymentConfiguration() error = %v", err)
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

func TestLoadHostAgentDeploymentConfigurationRequiresExplicitNativeGuestOwnership(t *testing.T) {
	configuration := validMacOSDeploymentConfiguration()
	configuration.Provider = hostdeployment.SelectedProviderConfiguration{
		Kind: "linux-kvm-libvirt-systemd", ID: "vitalserver-linux-provider", NativeProviderBridgeExecutablePath: "/opt/vitalserver/linux-provider-bridge", NativeVirtualMachineName: "vitalserver-guest", HostServiceName: "vitalserver-host-agent.service",
	}
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration))
	var invalid hostdeployment.DeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("error = %v, want invalid native Guest ownership", err)
	}

	configuration.Provider.NativeGuestMachineOwnership = "runtime-platform-provisioned"
	configuration.Provider.NativeGuestMachineProvisioningConfigurationPath = "/etc/vitalserver/native-guest-machine.json"
	if _, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration)); err != nil {
		t.Fatalf("runtime-platform-provisioned native Guest configuration error = %v", err)
	}

	configuration.Provider.NativeGuestMachineOwnership = "externally-provisioned"
	if _, err := hostdeployment.LoadHostAgentDeploymentConfiguration(writeDeploymentConfiguration(t, configuration)); !errors.As(err, &invalid) {
		t.Fatalf("external native Guest with C62 path error = %v, want invalid", err)
	}
}

func TestLoadHostAgentDeploymentConfigurationReportsMissingDocumentAsUnavailable(t *testing.T) {
	_, err := hostdeployment.LoadHostAgentDeploymentConfiguration(filepath.Join(t.TempDir(), "missing.json"))
	var unavailable hostdeployment.DeploymentConfigurationUnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("error = %v, want unavailable deployment configuration", err)
	}
}
