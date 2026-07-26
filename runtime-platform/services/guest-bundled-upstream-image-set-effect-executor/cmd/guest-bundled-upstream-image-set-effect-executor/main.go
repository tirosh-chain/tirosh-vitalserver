// guest-bundled-upstream-image-set-effect-executor is the release-owned C66
// C55 executable. It sends one verified archive through C32 to C64 and emits
// one typed C55 receipt; it never invokes a Guest container engine.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/adapters/imagesetartifactfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/adapters/imageseteffectconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/adapters/imageseteffectreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/adapters/imagesetmanagerhttpclient"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

func main() {
	invocation, exitCode := parseFixedProtocolInvocation(os.Args[1:]); if exitCode != 0 { os.Exit(exitCode) }
	configuration, err := imageseteffectconfigurationfile.Load(invocation.EffectConfigurationPath)
	if err != nil { writeFailureOrExit(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "bundled-upstream-image-set-effect-configuration-invalid", err.Error(), "bundled-upstream-image-set-effect-configuration"); return }
	client, err := imagesetmanagerhttpclient.New(time.Duration(configuration.ImageSetManagerEndpoint.RequestTimeoutMilliseconds)*time.Millisecond)
	if err != nil { writeFailureOrExit(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateUnavailable, "guest-bundled-upstream-image-set-manager-unavailable", err.Error(), "guest-bundled-upstream-image-set-manager"); return }
	application, err := guestbundledupstreamimageseteffectexecutorapplication.ComposeImageSetEffectApplication(artifactInspector{}, wallClock{}); if err != nil { fmt.Fprintf(os.Stderr, "configure C66 effect executor: %v\n", err); os.Exit(1) }
	context, cancel := context.WithTimeout(context.Background(), time.Duration(configuration.ImageSetManagerEndpoint.RequestTimeoutMilliseconds)*time.Millisecond); defer cancel()
	receipt, err := application.ExecuteImageSetEffect(context, configuration, invocation, client); if err != nil { fmt.Fprintf(os.Stderr, "execute C66 effect: %v\n", err); os.Exit(1) }
	if err := imageseteffectreceiptfile.Write(invocation.ReceiptPath, receipt); err != nil { fmt.Fprintf(os.Stderr, "write C55 C66 receipt: %v\n", err); os.Exit(1) }
}

func parseFixedProtocolInvocation(arguments []string) (guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation, int) { flags := flag.NewFlagSet("guest-bundled-upstream-image-set-effect-executor", flag.ContinueOnError); flags.SetOutput(os.Stderr); invocation := guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation{}; flags.StringVar(&invocation.ProtocolVersion, "protocol-version", "", "required fixed protocol version"); flags.StringVar(&invocation.EffectExecutorID, "effect-executor-id", "", "required C26 effect executor id"); flags.StringVar(&invocation.EffectConfigurationPath, "effect-configuration-path", "", "required absolute C26 configuration artifact path"); flags.StringVar(&invocation.ReceiptPath, "receipt-path", "", "required absolute C55 receipt path"); flags.StringVar(&invocation.UpdateID, "update-id", "", "required C30 update id"); flags.StringVar(&invocation.Layer, "layer", "", "required C26 layer"); flags.StringVar(&invocation.Operation, "operation", "", "required C26 operation"); flags.StringVar(&invocation.ArtifactPath, "artifact-path", "", "required absolute verified artifact path"); flags.StringVar(&invocation.ArtifactSHA256, "artifact-sha256", "", "required C26 artifact sha256"); if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 { return guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation{}, 2 }; if err := guestbundledupstreamimageseteffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil { fmt.Fprintln(os.Stderr, err); return guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation{}, 2 }; return invocation, 0 }
func writeFailureOrExit(invocation guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation, state, code, message, dependency string) { if err := imageseteffectreceiptfile.Write(invocation.ReceiptPath, guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, state, code, message, dependency, time.Now().UTC().Format(time.RFC3339Nano))); err != nil { fmt.Fprintf(os.Stderr, "write C55 C66 failure receipt: %v\n", err); os.Exit(1) } }
type artifactInspector struct{}
func (artifactInspector) Inspect(path, sha256 string) (guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact, error) { return imagesetartifactfile.Inspect(path, sha256) }
type wallClock struct{}
func (wallClock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
