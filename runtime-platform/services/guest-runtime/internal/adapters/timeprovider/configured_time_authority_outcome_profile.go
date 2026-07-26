// Package timeprovider adapts an explicitly selected NTP probe profile to a
// complete Guest ClockQuality. It does not read a host default time daemon or
// promote a local timestamp into synchronization evidence.
package timeprovider

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	ModeSynchronized   = "synchronized"
	ModeSynchronizing  = "synchronizing"
	ModeUnsynchronized = "unsynchronized"
	ModeStale          = "stale"
	ModeFailed         = "failed"
	ModeUnsupported    = "unsupported"
	ModeOutcomeUnknown = "outcome-unknown"
)

// ConfiguredTimeAuthorityOutcomeProfile is an explicit NTP probe outcome
// profile. It is intentionally
// static until a deployment supplies an actual, separately certified NTP
// probe adapter; its default executable mode is unsupported.
type ConfiguredTimeAuthorityOutcomeProfile struct {
	mode string
}

func NewConfiguredTimeAuthorityOutcomeProfile(mode string) (*ConfiguredTimeAuthorityOutcomeProfile, error) {
	switch mode {
	case ModeSynchronized, ModeSynchronizing, ModeUnsynchronized, ModeStale, ModeFailed, ModeUnsupported, ModeOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported time provider mode %q", mode)
	}
	return &ConfiguredTimeAuthorityOutcomeProfile{mode: mode}, nil
}

func (provider *ConfiguredTimeAuthorityOutcomeProfile) ObserveTimeAuthority(_ context.Context, node guestruntimedomain.NodeReference, spec guestruntimedomain.TimeAuthoritySpec, observedAt string) (guestruntimedomain.ClockQuality, error) {
	if provider.mode == ModeOutcomeUnknown {
		return guestruntimedomain.ClockQuality{}, fmt.Errorf("configured time probe outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *guestruntimedomain.Issue {
		return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: spec.Source.SourceID}
	}
	source := spec.Source
	switch provider.mode {
	case ModeSynchronized:
		stratum := 2
		offset := 0.25
		uncertainty := 1.0
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "synchronized", Source: &source, Stratum: &stratum, OffsetMs: &offset, UncertaintyMs: &uncertainty, LastSyncAt: &observedAt, ObservedAt: observedAt}, nil
	case ModeSynchronizing:
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "synchronizing", Source: &source, ObservedAt: observedAt}, nil
	case ModeUnsynchronized:
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "unsynchronized", ObservedAt: observedAt, Issue: issue("ntp-source-unsynchronized", "configured NTP probe reports the source is unsynchronized", true)}, nil
	case ModeStale:
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "stale", ObservedAt: observedAt, Issue: issue("ntp-source-stale", "configured NTP probe reports stale synchronization evidence", true)}, nil
	case ModeFailed:
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "failed", ObservedAt: observedAt, Issue: issue("ntp-probe-failed", "configured NTP probe failed", true)}, nil
	case ModeUnsupported:
		return guestruntimedomain.ClockQuality{SchemaVersion: guestruntimedomain.SchemaVersion, Node: node, State: "unsupported", ObservedAt: observedAt, Issue: issue("ntp-probe-unsupported", "no NTP probe adapter is configured", false)}, nil
	default:
		return guestruntimedomain.ClockQuality{}, fmt.Errorf("unreachable time provider mode %q", provider.mode)
	}
}

var _ guestruntimeapplication.GuestRuntimeTimeAuthorityProvider = (*ConfiguredTimeAuthorityOutcomeProfile)(nil)
