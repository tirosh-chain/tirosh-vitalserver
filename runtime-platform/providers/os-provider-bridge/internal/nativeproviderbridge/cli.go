package nativeproviderbridge

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"strings"
)

// RunCLI is shared by the two native executable entry points. It accepts only
// a C21 lifecycle input or an explicit C22 evidence request mode; malformed
// input exits non-zero so Host can record bridge-decode failure rather than a
// guessed Platform Provider result.
func RunCLI(kind string, arguments []string, input io.Reader, output io.Writer, diagnostics io.Writer, hostPlatform string) int {
	flags := flag.NewFlagSet(kind, flag.ContinueOnError)
	flags.SetOutput(diagnostics)
	mode := flags.String("mode", "lifecycle", "lifecycle, evidence, or provision")
	providerID := flags.String("provider-id", "", "explicit provider identifier")
	virtualMachine := flags.String("vm-name", "", "explicit virtual machine name")
	serviceName := flags.String("service-name", "", "explicit Host service name")
	machineProvisioningConfigurationPath := flags.String("native-guest-machine-provisioning-configuration", "", "explicit C62 native Guest machine provisioning configuration")
	if err := flags.Parse(arguments); err != nil {
		return 2
	}
	config := Config{ProviderID: *providerID, VirtualMachine: *virtualMachine, ServiceName: *serviceName, HostPlatform: contractHostPlatform(hostPlatform)}
	clock := systemClock{}
	switch *mode {
	case "lifecycle":
		decoder := json.NewDecoder(input)
		decoder.DisallowUnknownFields()
		var invocation PlatformProviderLifecycleInvocation
		if err := decoder.Decode(&invocation); err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not decode C21 lifecycle invocation")
			return 2
		}
		if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge requires exactly one C21 lifecycle invocation")
			return 2
		}
		if issue := ValidateConfiguredNativeGuestMachineSelection(kind, *machineProvisioningConfigurationPath, config); issue != nil {
			result := failedResult(invocation.Lifecycle, clock, *issue)
			if issue.Code == kind+"-native-guest-machine-configuration-unavailable" {
				result = unavailableResult(invocation.Lifecycle, clock, *issue)
			}
			if err := json.NewEncoder(output).Encode(result); err != nil {
				fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C10 lifecycle configuration failure")
				return 1
			}
			return 0
		}
		result := ExecuteLifecycle(context.Background(), kind, config, invocation, SystemExecutor{}, clock)
		if err := json.NewEncoder(output).Encode(result); err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C10 lifecycle result")
			return 1
		}
		return 0
	case "evidence":
		if config.ProviderID == "" {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge evidence requires an explicit provider-id")
			return 2
		}
		if issue := ValidateConfiguredNativeGuestMachineSelection(kind, *machineProvisioningConfigurationPath, config); issue != nil {
			state := "failed"
			if issue.Code == kind+"-native-guest-machine-configuration-unavailable" {
				state = "unavailable"
			}
			adapter, _ := selectedAdapter(kind)
			evidence := unavailableEvidence(ProviderInstallationEvidence{SchemaVersion: SchemaVersion, ProviderKind: kind, ProviderID: config.ProviderID, HostPlatform: config.HostPlatform, ObservedAt: timestamp(clock)}, adapter.serviceManager(), Issue{Code: issue.Code, Message: issue.Message, Retryable: issue.Retryable, Dependency: issue.Dependency})
			if state == "failed" {
				evidence.Installation.State = "failed"
				evidence.VirtualMachine.State = "failed"
				evidence.Service.State = "failed"
				for index := range evidence.Capabilities {
					evidence.Capabilities[index].State = "failed"
				}
			}
			if err := json.NewEncoder(output).Encode(evidence); err != nil {
				fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C22 installation configuration failure")
				return 1
			}
			return 0
		}
		evidence := InspectInstallation(context.Background(), kind, config, SystemExecutor{}, clock)
		if err := json.NewEncoder(output).Encode(evidence); err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C22 installation evidence")
			return 1
		}
		return 0
	case "provision":
		if strings.TrimSpace(*machineProvisioningConfigurationPath) == "" {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge provision requires an explicit C62 native Guest machine provisioning configuration")
			return 2
		}
		configuration, configurationBytes, err := LoadNativeGuestMachineProvisioningConfiguration(strings.TrimSpace(*machineProvisioningConfigurationPath))
		if err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not load C62 native Guest machine provisioning configuration:", err)
			return 2
		}
		if strings.TrimSpace(*providerID) != "" && strings.TrimSpace(*providerID) != configuration.ProviderID {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge provider-id does not match C62")
			return 2
		}
		if strings.TrimSpace(*virtualMachine) != "" && strings.TrimSpace(*virtualMachine) != configuration.GuestMachine.MachineID {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge vm-name does not match C62")
			return 2
		}
		result, err := ProvisionNativeGuestMachine(context.Background(), kind, configuration, configurationBytes, SystemExecutor{}, clock, hostPlatform)
		if err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not provision declared Guest machine:", err)
			return 1
		}
		if err := json.NewEncoder(output).Encode(result.Receipt); err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C63 native Guest machine provisioning receipt")
			return 1
		}
		return 0
	default:
		fmt.Fprintln(diagnostics, "native Platform Provider bridge mode must be lifecycle, evidence, or provision")
		return 2
	}
}

func contractHostPlatform(value string) string {
	switch strings.ToLower(value) {
	case "darwin", "macos":
		return "macos"
	case "windows":
		return "windows"
	case "linux":
		return "linux"
	default:
		return "unknown"
	}
}
