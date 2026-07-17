package hostdeployment_test

import (
	"reflect"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func TestResolveSelectedPlatformProviderProcessCommandPassesC32OnlyToMacOSSupervisor(t *testing.T) {
	command, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(hostdeployment.SelectedPlatformProviderProcessDeployment{
		ProviderKind: hostagentdomain.MacOSVirtualizationProviderKind,
		ProviderID:   "vitalserver-macos-provider",
		MacOSVirtualMachineSupervisorExecutablePath: "/opt/vitalserver/macos-virtual-machine-supervisor",
		MacOSVirtualMachineConfigurationPath:        " /Library/Application Support/VitalServerRuntimePlatform/vm/macos-vm.json ",
	})
	if err != nil {
		t.Fatal(err)
	}
	if command.ExecutablePath != "/opt/vitalserver/macos-virtual-machine-supervisor" {
		t.Fatalf("bridge executable = %q", command.ExecutablePath)
	}
	wantArguments := []string{"--virtual-machine-configuration", "/Library/Application Support/VitalServerRuntimePlatform/vm/macos-vm.json"}
	if !reflect.DeepEqual(wantArguments, command.Arguments) {
		t.Fatalf("bridge arguments = %#v, want %#v", command.Arguments, wantArguments)
	}
}

func TestResolveSelectedPlatformProviderProcessCommandRejectsC32ForOtherProvider(t *testing.T) {
	_, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(hostdeployment.SelectedPlatformProviderProcessDeployment{
		ProviderKind:                         hostagentdomain.LinuxKVMlibvirtSystemdProviderKind,
		ProviderID:                           "vitalserver-linux-provider",
		NativeProviderBridgeExecutablePath:   "/opt/vitalserver/linux-provider-bridge",
		MacOSVirtualMachineConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/vm/macos-vm.json",
	})
	if err == nil {
		t.Fatal("expected deployment configuration rejection")
	}
}

func TestResolveSelectedPlatformProviderProcessCommandLeavesMissingC32ExplicitlyUnconfigured(t *testing.T) {
	command, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(hostdeployment.SelectedPlatformProviderProcessDeployment{
		ProviderKind: hostagentdomain.MacOSVirtualizationProviderKind,
		ProviderID:   "vitalserver-macos-provider",
		MacOSVirtualMachineSupervisorExecutablePath: "/opt/vitalserver/macos-virtual-machine-supervisor",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(command.Arguments) != 0 {
		t.Fatalf("bridge arguments = %#v, want no implicit C32 argument", command.Arguments)
	}
}

func TestResolveSelectedPlatformProviderProcessCommandPassesNativeResourceIdentityToLinuxBridge(t *testing.T) {
	command, err := hostdeployment.ResolveSelectedPlatformProviderProcessCommand(hostdeployment.SelectedPlatformProviderProcessDeployment{
		ProviderKind:                       hostagentdomain.LinuxKVMlibvirtSystemdProviderKind,
		ProviderID:                         "vitalserver-linux-provider",
		NativeProviderBridgeExecutablePath: "/opt/vitalserver/linux-provider-bridge",
		NativeVirtualMachineName:           "vitalserver-guest",
		HostServiceName:                    "vitalserver-host-agent.service",
	})
	if err != nil {
		t.Fatal(err)
	}
	wantArguments := []string{"--provider-id", "vitalserver-linux-provider", "--vm-name", "vitalserver-guest", "--service-name", "vitalserver-host-agent.service"}
	if !reflect.DeepEqual(wantArguments, command.Arguments) {
		t.Fatalf("bridge arguments = %#v, want %#v", command.Arguments, wantArguments)
	}
}
