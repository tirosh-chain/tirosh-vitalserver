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
	mode := flags.String("mode", "lifecycle", "lifecycle or evidence")
	providerID := flags.String("provider-id", "", "explicit provider identifier")
	virtualMachine := flags.String("vm-name", "", "explicit virtual machine name")
	serviceName := flags.String("service-name", "", "explicit Host service name")
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
		evidence := InspectInstallation(context.Background(), kind, config, SystemExecutor{}, clock)
		if err := json.NewEncoder(output).Encode(evidence); err != nil {
			fmt.Fprintln(diagnostics, "native Platform Provider bridge could not encode C22 installation evidence")
			return 1
		}
		return 0
	default:
		fmt.Fprintln(diagnostics, "native Platform Provider bridge mode must be lifecycle or evidence")
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
