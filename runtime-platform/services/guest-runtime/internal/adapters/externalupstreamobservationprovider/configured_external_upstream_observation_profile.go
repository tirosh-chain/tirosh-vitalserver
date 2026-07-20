// Package externalupstreamobservationprovider adapts an explicitly selected
// External Upstream observation profile into complete, typed observations.
//
// This is deliberately not a generic HTTP/TCP reachability adapter: endpoint
// URLs and credentials are references in the public contract, not runtime
// values this process may guess from. A deployment must select a concrete
// External Upstream probe adapter/profile. The static profile exists for
// deterministic product acceptance and starts in unsupported mode in the
// executable.
package externalupstreamobservationprovider

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

// ConfiguredExternalUpstreamObservationProfile is a certified outcome profile.
// It returns an explicit known observation for all modes except
// outcome-unknown; that mode returns an error so the application preserves its
// durable running operation.
type ConfiguredExternalUpstreamObservationProfile struct {
	reference guestruntimedomain.IntegrationProviderReference
	mode      string
}

func NewConfiguredExternalUpstreamObservationProfile(reference guestruntimedomain.IntegrationProviderReference, mode string) (*ConfiguredExternalUpstreamObservationProfile, error) {
	if !guestruntimedomain.ValidIdentifier(reference.Kind) || !guestruntimedomain.ValidIdentifier(reference.ID) || reference.CapabilityRevision < 1 {
		return nil, fmt.Errorf("External Upstream observation provider reference must be explicit and valid")
	}
	switch mode {
	case ModeAvailable, ModeUnavailable, ModeFailed, ModeUnsupported, ModeOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported External Upstream observation provider mode %q", mode)
	}
	return &ConfiguredExternalUpstreamObservationProfile{reference: reference, mode: mode}, nil
}

func (provider *ConfiguredExternalUpstreamObservationProfile) ExternalUpstreamObservationProviderReference() guestruntimedomain.IntegrationProviderReference {
	return provider.reference
}

func (provider *ConfiguredExternalUpstreamObservationProfile) ObserveExternalUpstream(_ context.Context, integrationID string, spec guestruntimedomain.ExternalUpstreamSpec, observedAt string) (guestruntimedomain.ExternalUpstreamObservation, error) {
	if !guestruntimedomain.ExternalProviderReferenceEqual(provider.reference, spec.Provider) {
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("External Upstream spec provider does not match configured observation provider")
	}
	if provider.mode == ModeOutcomeUnknown {
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("configured External Upstream observation outcome is unknown")
	}
	issue := func(code string, message string) *guestruntimedomain.Issue {
		retryable := provider.mode == ModeUnavailable
		return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: provider.reference.ID}
	}
	switch provider.mode {
	case ModeAvailable:
		capability, err := guestruntimedomain.NewExternalUpstreamCapabilityDocument(integrationID, provider.reference, observedAt)
		if err != nil {
			return guestruntimedomain.ExternalUpstreamObservation{}, err
		}
		return guestruntimedomain.ExternalUpstreamObservation{
			State:      "available",
			Connection: guestruntimedomain.ConnectionObservation{State: "reachable", ObservedAt: observedAt},
			Capability: &capability,
		}, nil
	case ModeUnavailable:
		result := issue("external-upstream-unavailable", "configured External Upstream probe reports the endpoint unavailable")
		return guestruntimedomain.ExternalUpstreamObservation{State: "unavailable", Connection: guestruntimedomain.ConnectionObservation{State: "unavailable", ObservedAt: observedAt, Issue: result}, Issue: result}, nil
	case ModeFailed:
		result := issue("external-upstream-probe-failed", "configured External Upstream probe failed")
		return guestruntimedomain.ExternalUpstreamObservation{State: "failed", Connection: guestruntimedomain.ConnectionObservation{State: "failed", ObservedAt: observedAt, Issue: result}, Issue: result}, nil
	case ModeUnsupported:
		result := issue("external-upstream-probe-unsupported", "no External Upstream probe adapter is configured")
		return guestruntimedomain.ExternalUpstreamObservation{State: "unsupported", Connection: guestruntimedomain.ConnectionObservation{State: "not-checked", ObservedAt: observedAt}, Issue: result}, nil
	default:
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("unreachable External Upstream observation provider mode %q", provider.mode)
	}
}

var _ guestruntimeapplication.GuestRuntimeExternalUpstreamProvider = (*ConfiguredExternalUpstreamObservationProfile)(nil)
