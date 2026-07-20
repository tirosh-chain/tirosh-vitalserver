package guestbundledupstreamimageseteffectexecutorapplication

import (
	"context"
	"errors"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

type ImageSetArtifactInspector interface { Inspect(string, string) (guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact, error) }
type ImageSetManagerClient interface { ApplyImageSetUpdate(context.Context, guestbundledupstreamimageseteffectexecutordomain.ImageSetManagerEndpoint, guestbundledupstreamimageseteffectexecutordomain.ImageSetUpdateCommand, guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact) (guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation, error) }
type Clock interface { Now() string }
type Application struct { artifactInspector ImageSetArtifactInspector; clock Clock }
func ComposeImageSetEffectApplication(inspector ImageSetArtifactInspector, clock Clock) (*Application, error) { if inspector == nil || clock == nil { return nil, fmt.Errorf("C66 artifact inspector and clock are required") }; return &Application{artifactInspector: inspector, clock: clock}, nil }
func (application *Application) ExecuteImageSetEffect(context context.Context, configuration guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration, invocation guestbundledupstreamimageseteffectexecutordomain.FixedProtocolInvocation, client ImageSetManagerClient) (guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt, error) {
	if context == nil { return guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 execution context is required") }
	if err := guestbundledupstreamimageseteffectexecutordomain.ValidateConfiguration(configuration); err != nil { return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "bundled-upstream-image-set-configuration-invalid", err.Error(), "bundled-upstream-image-set-configuration", application.clock.Now()), nil }
	if err := guestbundledupstreamimageseteffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil { return guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err }
	intent, err := guestbundledupstreamimageseteffectexecutordomain.SelectIntent(configuration, invocation)
	if err != nil { return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateUnsupported, "bundled-upstream-image-set-intent-unsupported", err.Error(), "guest-bundled-upstream-image-set-manager", application.clock.Now()), nil }
	artifact, err := application.artifactInspector.Inspect(invocation.ArtifactPath, invocation.ArtifactSHA256)
	if err != nil { return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateUnavailable, "bundled-upstream-image-set-artifact-unavailable", err.Error(), "host-update-staging", application.clock.Now()), nil }
	command, err := guestbundledupstreamimageseteffectexecutordomain.NewImageSetUpdateCommand(invocation, intent, artifact, application.clock.Now())
	if err != nil { return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "bundled-upstream-image-set-command-invalid", err.Error(), "guest-bundled-upstream-image-set-manager", application.clock.Now()), nil }
	if client == nil { return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "bundled-upstream-image-set-client-not-composed", "C64 HTTP client is not composed", "guest-bundled-upstream-image-set-manager", application.clock.Now()), nil }
	operation, err := client.ApplyImageSetUpdate(context, configuration.ImageSetManagerEndpoint, command, artifact)
	if err != nil {
		var failure guestbundledupstreamimageseteffectexecutordomain.ImageSetManagerRequestFailure
		if !errors.As(err, &failure) { return guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C64 client returned an unclassified error: %w", err) }
		if err := guestbundledupstreamimageseteffectexecutordomain.ValidateImageSetManagerRequestFailure(failure); err != nil { return guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C64 client returned an invalid typed failure: %w", err) }
		return guestbundledupstreamimageseteffectexecutordomain.FailureReceipt(invocation, failure.State, failure.Issue.Code, failure.Issue.Message, failure.Issue.Dependency, application.clock.Now()), nil
	}
	return guestbundledupstreamimageseteffectexecutordomain.OutcomeForImageSetOperation(invocation, command, operation, application.clock.Now())
}
