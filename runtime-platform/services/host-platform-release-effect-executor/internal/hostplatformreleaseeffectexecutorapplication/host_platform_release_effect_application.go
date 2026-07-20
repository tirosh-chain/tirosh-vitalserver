// Package hostplatformreleaseeffectexecutorapplication sequences the C67
// effect without performing Host release effects itself.
package hostplatformreleaseeffectexecutorapplication

import (
	"context"
	"errors"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

type HostPlatformReleaseArtifactInspector interface {
	Inspect(string, string) (hostplatformreleaseeffectexecutordomain.ReleaseArtifact, error)
}
type HostInstallationManagerClient interface {
	ExecuteHostPlatformStagedReleaseUpdate(context.Context, hostplatformreleaseeffectexecutordomain.HostInstallationManagerEndpoint, hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateCommand, hostplatformreleaseeffectexecutordomain.ReleaseArtifact) (hostplatformreleaseeffectexecutordomain.HostPlatformStagedReleaseUpdateOperation, error)
}
type Clock interface{ Now() string }
type Application struct {
	inspector HostPlatformReleaseArtifactInspector
	clock     Clock
}

func ComposeHostPlatformReleaseEffectApplication(inspector HostPlatformReleaseArtifactInspector, clock Clock) (*Application, error) {
	if inspector == nil || clock == nil {
		return nil, fmt.Errorf("C67 artifact inspector and clock are required")
	}
	return &Application{inspector: inspector, clock: clock}, nil
}
func (application *Application) ExecuteHostPlatformReleaseEffect(context context.Context, configuration hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration, invocation hostplatformreleaseeffectexecutordomain.FixedProtocolInvocation, client HostInstallationManagerClient) (hostplatformreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt, error) {
	if context == nil {
		return hostplatformreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 execution context is required")
	}
	if err := hostplatformreleaseeffectexecutordomain.ValidateConfiguration(configuration); err != nil {
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateFailed, "host-platform-release-effect-configuration-invalid", err.Error(), "host-platform-release-effect-configuration", application.clock.Now()), nil
	}
	if err := hostplatformreleaseeffectexecutordomain.ValidateFixedProtocolInvocation(invocation); err != nil {
		return hostplatformreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	transition, err := hostplatformreleaseeffectexecutordomain.SelectTransition(configuration, invocation)
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateUnsupported, "host-platform-release-transition-unsupported", err.Error(), "host-installation-manager", application.clock.Now()), nil
	}
	artifact, err := application.inspector.Inspect(invocation.ArtifactPath, invocation.ArtifactSHA256)
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateUnavailable, "host-platform-release-artifact-unavailable", err.Error(), "host-update-staging", application.clock.Now()), nil
	}
	command, err := hostplatformreleaseeffectexecutordomain.NewHostPlatformStagedReleaseUpdateCommand(invocation, transition, artifact, application.clock.Now())
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateFailed, "host-platform-release-command-invalid", err.Error(), "host-installation-manager", application.clock.Now()), nil
	}
	if client == nil {
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, hostplatformreleaseeffectexecutordomain.ReceiptStateFailed, "host-installation-manager-client-not-composed", "C68 client is not composed", "host-installation-manager", application.clock.Now()), nil
	}
	operation, err := client.ExecuteHostPlatformStagedReleaseUpdate(context, configuration.HostInstallationManager, command, artifact)
	if err != nil {
		var failure hostplatformreleaseeffectexecutordomain.HostPlatformReleaseManagerRequestFailure
		if !errors.As(err, &failure) {
			return hostplatformreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C68 client returned an unclassified error: %w", err)
		}
		if err := hostplatformreleaseeffectexecutordomain.ValidateHostPlatformReleaseManagerRequestFailure(failure); err != nil {
			return hostplatformreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C68 client returned an invalid typed failure: %w", err)
		}
		return hostplatformreleaseeffectexecutordomain.FailureReceipt(invocation, failure.State, failure.Issue.Code, failure.Issue.Message, failure.Issue.Dependency, application.clock.Now()), nil
	}
	return hostplatformreleaseeffectexecutordomain.OutcomeForHostPlatformOperation(invocation, command, operation, application.clock.Now())
}
