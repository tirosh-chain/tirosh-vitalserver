// Package outboundrelayobservationprovider adapts an explicitly selected
// Outbound Relay observation profile into complete, typed relay observations.
// It does not probe an External Upstream or report downstream business
// processing because Outbound Relay is a separate resource owner.
package outboundrelayobservationprovider

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	ModeAvailable      = "available"
	ModeUnavailable    = "unavailable"
	ModeFailed         = "failed"
	ModeUnsupported    = "unsupported"
	ModeOutcomeUnknown = "outcome-unknown"
)

// ConfiguredOutboundRelayObservationProfile is a certified outcome profile.
// It returns an explicit known observation for all modes except
// outcome-unknown; that mode returns an error so the application preserves its
// durable running operation.
type ConfiguredOutboundRelayObservationProfile struct {
	reference guestruntimedomain.IntegrationProviderReference
	mode      string
}

func NewConfiguredOutboundRelayObservationProfile(reference guestruntimedomain.IntegrationProviderReference, mode string) (*ConfiguredOutboundRelayObservationProfile, error) {
	if !guestruntimedomain.ValidIdentifier(reference.Kind) || !guestruntimedomain.ValidIdentifier(reference.ID) || reference.CapabilityRevision < 1 {
		return nil, fmt.Errorf("Outbound Relay observation provider reference must be explicit and valid")
	}
	switch mode {
	case ModeAvailable, ModeUnavailable, ModeFailed, ModeUnsupported, ModeOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported Outbound Relay observation provider mode %q", mode)
	}
	return &ConfiguredOutboundRelayObservationProfile{reference: reference, mode: mode}, nil
}

func (provider *ConfiguredOutboundRelayObservationProfile) OutboundRelayObservationProviderReference() guestruntimedomain.IntegrationProviderReference {
	return provider.reference
}

func (provider *ConfiguredOutboundRelayObservationProfile) ObserveOutboundRelay(_ context.Context, targetID string, spec guestruntimedomain.OutboundRelayTargetSpec, _ string) (guestruntimedomain.OutboundRelayObservation, error) {
	if !guestruntimedomain.ExternalProviderReferenceEqual(provider.reference, spec.Provider) {
		return guestruntimedomain.OutboundRelayObservation{}, fmt.Errorf("Outbound Relay spec provider does not match configured observation provider")
	}
	if provider.mode == ModeOutcomeUnknown {
		return guestruntimedomain.OutboundRelayObservation{}, fmt.Errorf("configured Outbound Relay observation outcome is unknown")
	}
	issue := func(code string, message string) *guestruntimedomain.Issue {
		retryable := provider.mode == ModeUnavailable
		return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: provider.reference.ID}
	}
	switch provider.mode {
	case ModeAvailable:
		return guestruntimedomain.OutboundRelayObservation{
			State:                    "available",
			AcknowledgementReference: &guestruntimedomain.EvidenceReference{Kind: "relay-acknowledgement", ID: "relay-ack-" + targetID},
		}, nil
	case ModeUnavailable:
		return guestruntimedomain.OutboundRelayObservation{State: "unavailable", Issue: issue("outbound-relay-unavailable", "configured Outbound Relay probe reports the target unavailable")}, nil
	case ModeFailed:
		return guestruntimedomain.OutboundRelayObservation{State: "failed", Issue: issue("outbound-relay-probe-failed", "configured Outbound Relay probe failed")}, nil
	case ModeUnsupported:
		return guestruntimedomain.OutboundRelayObservation{State: "unsupported", Issue: issue("outbound-relay-probe-unsupported", "no Outbound Relay probe adapter is configured")}, nil
	default:
		return guestruntimedomain.OutboundRelayObservation{}, fmt.Errorf("unreachable Outbound Relay observation provider mode %q", provider.mode)
	}
}

var _ guestruntimeapplication.GuestRuntimeOutboundRelayProvider = (*ConfiguredOutboundRelayObservationProfile)(nil)
