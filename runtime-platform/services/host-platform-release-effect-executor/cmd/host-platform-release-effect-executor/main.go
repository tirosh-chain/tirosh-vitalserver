// host-platform-release-effect-executor is the C67 C55 executable. It sends a
// verified archive to the installed Host Installation Manager and writes C55.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/adapters/hostinstallationmanagerprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/adapters/hostplatformreleaseartifactfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/adapters/hostplatformreleaseeffectconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/adapters/hostplatformreleaseeffectreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

func main() {
	invocation, exitCode := parseFixedProtocolInvocation(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	configuration, err := hostplatformreleaseeffectconfigurationfile.Load(invocation.EffectConfigurationPath)
	if err != nil {
		writeFailureOrExit(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateFailed, "host-platform-release-effect-configuration-invalid", err.Error(), "host-platform-release-effect-configuration")
		return
	}
	application, err := hostplatformreleaseeffectexecutorapplication.ComposeHostPlatformReleaseEffectApplication(artifactInspector{}, wallClock{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure C67 effect executor: %v\n", err)
		os.Exit(1)
	}
	executionContext, cancel := context.WithTimeout(context.Background(), time.Duration(configuration.HostInstallationManager.RequestTimeoutMilliseconds)*time.Millisecond)
	defer cancel()
	receipt, err := application.ExecuteHostPlatformReleaseEffect(executionContext, configuration, invocation, hostinstallationmanagerprocess.Client{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "execute C67 effect: %v\n", err)
		os.Exit(1)
	}
	if err := hostplatformreleaseeffectreceiptfile.Write(invocation.ReceiptPath, receipt); err != nil {
		fmt.Fprintf(os.Stderr, "write C55 C67 receipt: %v\n", err)
		os.Exit(1)
	}
}

func parseFixedProtocolInvocation(arguments []string) (hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation, int) {
	flags := flag.NewFlagSet("host-platform-release-effect-executor", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	invocation := hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation{}
	flags.StringVar(&invocation.ProtocolVersion, "protocol-version", "", "required fixed protocol version")
	flags.StringVar(&invocation.EffectExecutorID, "effect-executor-id", "", "required C26 effect executor id")
	flags.StringVar(&invocation.EffectConfigurationPath, "effect-configuration-path", "", "required absolute C26 configuration artifact path")
	flags.StringVar(&invocation.ReceiptPath, "receipt-path", "", "required absolute C55 receipt path")
	flags.StringVar(&invocation.UpdateID, "update-id", "", "required C30 update id")
	flags.StringVar(&invocation.Layer, "layer", "", "required C26 layer")
	flags.StringVar(&invocation.Operation, "operation", "", "required C26 operation")
	flags.StringVar(&invocation.ArtifactPath, "artifact-path", "", "required absolute verified artifact path")
	flags.StringVar(&invocation.ArtifactSHA256, "artifact-sha256", "", "required C26 artifact sha256")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 {
		return hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation{}, 2
	}
	if err := hostplatformreleaseeffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation{}, 2
	}
	return invocation, 0
}
func writeFailureOrExit(invocation hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation, state, code, message, dependency string) {
	if err := hostplatformreleaseeffectreceiptfile.Write(invocation.ReceiptPath, hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, state, code, message, dependency, time.Now().UTC().Format(time.RFC3339Nano))); err != nil {
		fmt.Fprintf(os.Stderr, "write C55 C67 failure receipt: %v\n", err)
		os.Exit(1)
	}
}

type artifactInspector struct{}

func (artifactInspector) Inspect(path, sha256 string) (hostplatformreleaseeffectexecutordomain.ReleaseArtifact, error) {
	return hostplatformreleaseartifactfile.Inspect(path, sha256)
}

type wallClock struct{}

func (wallClock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
