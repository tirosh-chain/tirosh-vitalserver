// Package guestproductreleaseeffectexecutorapplication orchestrates one fixed
// C26 Guest Product release effect without owning filesystem, HTTP, or receipt
// persistence.
package guestproductreleaseeffectexecutorapplication

import (
	"context"
	"errors"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

type ReleaseArtifactInspector interface {
	Inspect(string, string) (guestproductreleaseeffectexecutordomain.ReleaseArtifact, error)
}

type GuestProductReleaseManagerClient interface {
	ApplyReleaseUpdate(context.Context, guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint, guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand, guestproductreleaseeffectexecutordomain.ReleaseArtifact) (guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation, error)
}

type Clock interface{ Now() string }

type Application struct {
	artifactInspector ReleaseArtifactInspector
	clock             Clock
}

func ComposeGuestProductReleaseEffectApplication(artifactInspector ReleaseArtifactInspector, clock Clock) (*Application, error) {
	if artifactInspector == nil || clock == nil {
		return nil, fmt.Errorf("C61 artifact inspector and clock are required")
	}
	return &Application{artifactInspector: artifactInspector, clock: clock}, nil
}

// ExecuteGuestProductReleaseEffect produces a C55 value for every effect state it can classify. A
// failed C61 archive inspection or Host-local C32/C59 transport is
// unavailable—not a synthetic guest release failure.
func (application *Application) ExecuteGuestProductReleaseEffect(
	context context.Context,
	configuration guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration,
	invocation guestproductreleaseeffectexecutordomain.FixedProtocolInvocation,
	client GuestProductReleaseManagerClient,
) (guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt, error) {
	if context == nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 execution context is required")
	}
	if err := guestproductreleaseeffectexecutordomain.ValidateConfiguration(configuration); err != nil {
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "guest-product-release-configuration-invalid", err.Error(), "guest-product-release-configuration", application.clock.Now()), nil
	}
	if err := guestproductreleaseeffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	intent, err := guestproductreleaseeffectexecutordomain.SelectIntent(configuration, invocation)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateUnsupported, "guest-product-release-intent-unsupported", err.Error(), "guest-product-release-manager", application.clock.Now()), nil
	}
	artifact, err := application.artifactInspector.Inspect(invocation.ArtifactPath, invocation.ArtifactSHA256)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable, "guest-product-release-artifact-unavailable", err.Error(), "host-update-staging", application.clock.Now()), nil
	}
	command, err := guestproductreleaseeffectexecutordomain.NewGuestProductReleaseUpdateCommand(invocation, intent, artifact, application.clock.Now())
	if err != nil {
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "guest-product-release-command-invalid", err.Error(), "guest-product-release-manager", application.clock.Now()), nil
	}
	if client == nil {
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "guest-product-release-client-not-composed", "C59 HTTP client is not composed for this release effect", "guest-product-release-manager", application.clock.Now()), nil
	}
	operation, err := client.ApplyReleaseUpdate(context, configuration.GuestProductReleaseManagerEndpoint, command, artifact)
	if err != nil {
		var requestFailure guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerRequestFailure
		if !errors.As(err, &requestFailure) {
			return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 client returned an unclassified error: %w", err)
		}
		if validationErr := guestproductreleaseeffectexecutordomain.ValidateGuestProductReleaseManagerRequestFailure(requestFailure); validationErr != nil {
			return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C59 client returned an invalid typed failure: %w", validationErr)
		}
		return guestproductreleaseeffectexecutordomain.FailureReceipt(invocation, requestFailure.State, requestFailure.Issue.Code, requestFailure.Issue.Message, requestFailure.Issue.Dependency, application.clock.Now()), nil
	}
	return guestproductreleaseeffectexecutordomain.OutcomeForGuestProductReleaseOperation(invocation, command, operation, application.clock.Now())
}
