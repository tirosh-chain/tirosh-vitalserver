// Package hostdeployment composes Host-owned deployment inputs into the
// selected Platform Provider process command. It is deliberately outside Host domain
// policy: it maps explicit installation configuration and never observes or
// infers Guest state.
package hostdeployment

import (
	"fmt"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/platformproviderprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// SelectedPlatformProviderProcessDeployment names the Host installation inputs needed to invoke
// exactly one selected Platform Provider process. C32 is only meaningful to the macOS
// virtual machine supervisor. The Windows/Linux native provider bridge requires its own explicit native
// resource names; it must not receive a macOS configuration path.
type SelectedPlatformProviderProcessDeployment struct {
	ProviderKind                                string
	ProviderID                                  string
	NativeProviderBridgeExecutablePath          string
	MacOSVirtualMachineSupervisorExecutablePath string
	MacOSVirtualMachineConfigurationPath        string
	NativeVirtualMachineName                    string
	HostServiceName                             string
}

// ResolveSelectedPlatformProviderProcessCommand returns the single provider process
// command implied by explicit Host deployment configuration. It does not load
// C32: macOS-specific VM semantics remain owned by the macOS virtual machine supervisor.
func ResolveSelectedPlatformProviderProcessCommand(deployment SelectedPlatformProviderProcessDeployment) (platformproviderprocess.SelectedPlatformProviderProcessCommand, error) {
	executablePath := deployment.NativeProviderBridgeExecutablePath
	if deployment.ProviderKind == hostagentdomain.MacOSVirtualizationProviderKind {
		executablePath = deployment.MacOSVirtualMachineSupervisorExecutablePath
	}
	command := platformproviderprocess.SelectedPlatformProviderProcessCommand{ExecutablePath: executablePath}
	configurationPath := strings.TrimSpace(deployment.MacOSVirtualMachineConfigurationPath)
	switch deployment.ProviderKind {
	case hostagentdomain.MacOSVirtualizationProviderKind:
		if configurationPath == "" {
			return command, nil
		}
		command.Arguments = []string{"--virtual-machine-configuration", configurationPath}
		return command, nil
	case hostagentdomain.WindowsHyperVSCMProviderKind, hostagentdomain.LinuxKVMlibvirtSystemdProviderKind:
		if configurationPath != "" {
			return platformproviderprocess.SelectedPlatformProviderProcessCommand{}, fmt.Errorf("macOS virtual machine configuration is valid only with the macos-virtualization provider")
		}
		providerID := strings.TrimSpace(deployment.ProviderID)
		virtualMachineName := strings.TrimSpace(deployment.NativeVirtualMachineName)
		hostServiceName := strings.TrimSpace(deployment.HostServiceName)
		if providerID == "" || virtualMachineName == "" || hostServiceName == "" {
			return platformproviderprocess.SelectedPlatformProviderProcessCommand{}, fmt.Errorf("native Platform Provider bridge requires explicit provider ID, virtual machine name, and Host service name")
		}
		command.Arguments = []string{"--provider-id", providerID, "--vm-name", virtualMachineName, "--service-name", hostServiceName}
		return command, nil
	default:
		return platformproviderprocess.SelectedPlatformProviderProcessCommand{}, fmt.Errorf("selected Platform Provider kind is unsupported")
	}
}
