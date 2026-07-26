// guest-product-release-effect-executor is a release-owned C26 effect
// executable. It sends exactly one verified Guest Product archive through the
// C32 Host-loopback bridge to C59, then writes exactly one C55 receipt.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/adapters/guestproductreleasemanagerhttpclient"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/adapters/releaseartifactfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/adapters/releaseeffectconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/adapters/releaseeffectreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

func main() {
	invocation, exitCode := parseFixedProtocolInvocation(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	configuration, configurationErr := releaseeffectconfigurationfile.Load(invocation.EffectConfigurationPath)
	if configurationErr != nil {
		writeFailureOrExit(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "guest-product-release-effect-configuration-invalid", configurationErr.Error(), "guest-product-release-effect-configuration")
		return
	}
	client, clientErr := guestproductreleasemanagerhttpclient.New(time.Duration(configuration.GuestProductReleaseManagerEndpoint.RequestTimeoutMilliseconds) * time.Millisecond)
	if clientErr != nil {
		writeFailureOrExit(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable, "guest-product-release-manager-unavailable", clientErr.Error(), "guest-product-release-manager")
		return
	}
	application, applicationErr := guestproductreleaseeffectexecutorapplication.ComposeGuestProductReleaseEffectApplication(artifactInspector{}, wallClock{})
	if applicationErr != nil {
		fmt.Fprintf(os.Stderr, "configure Guest Product release effect executor: %v\n", applicationErr)
		os.Exit(1)
	}
	context, cancel := context.WithTimeout(context.Background(), time.Duration(configuration.GuestProductReleaseManagerEndpoint.RequestTimeoutMilliseconds)*time.Millisecond)
	defer cancel()
	receipt, executionErr := application.ExecuteGuestProductReleaseEffect(context, configuration, invocation, client)
	if executionErr != nil {
		fmt.Fprintf(os.Stderr, "execute Guest Product release effect: %v\n", executionErr)
		os.Exit(1)
	}
	if err := releaseeffectreceiptfile.Write(invocation.ReceiptPath, receipt); err != nil {
		fmt.Fprintf(os.Stderr, "write C55 Guest Product release effect receipt: %v\n", err)
		os.Exit(1)
	}
}

func parseFixedProtocolInvocation(arguments []string) (guestproductreleaseeffectexecutordomain.FixedProtocolInvocation, int) {
	flags := flag.NewFlagSet("guest-product-release-effect-executor", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	invocation := guestproductreleaseeffectexecutordomain.FixedProtocolInvocation{}
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
		return guestproductreleaseeffectexecutordomain.FixedProtocolInvocation{}, 2
	}
	if err := guestproductreleaseeffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return guestproductreleaseeffectexecutordomain.FixedProtocolInvocation{}, 2
	}
	return invocation, 0
}

func writeFailureOrExit(invocation guestproductreleaseeffectexecutordomain.FixedProtocolInvocation, state string, code string, message string, dependency string) {
	if err := releaseeffectreceiptfile.Write(invocation.ReceiptPath, guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, state, code, message, dependency, time.Now().UTC().Format(time.RFC3339Nano))); err != nil {
		fmt.Fprintf(os.Stderr, "write C55 Guest Product release effect failure receipt: %v\n", err)
		os.Exit(1)
	}
}

type artifactInspector struct{}

func (artifactInspector) Inspect(path string, expectedSHA256 string) (guestproductreleaseeffectexecutordomain.ReleaseArtifact, error) {
	return releaseartifactfile.Inspect(path, expectedSHA256)
}

type wallClock struct{}

func (wallClock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
