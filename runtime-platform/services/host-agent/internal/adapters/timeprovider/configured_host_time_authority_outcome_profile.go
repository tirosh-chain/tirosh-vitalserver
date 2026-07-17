// Package timeprovider adapts a selected Host NTP probe profile into explicit
// ClockQuality. It never reads Guest time state or uses a timestamp as proof.
package timeprovider

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
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

// ConfiguredHostTimeAuthorityOutcomeProfile returns one explicitly configured
// Host NTP observation outcome; it is not a live Guest or Host clock reader.
type ConfiguredHostTimeAuthorityOutcomeProfile struct{ mode string }

func NewConfiguredHostTimeAuthorityOutcomeProfile(mode string) (*ConfiguredHostTimeAuthorityOutcomeProfile, error) {
	switch mode {
	case ModeSynchronized, ModeSynchronizing, ModeUnsynchronized, ModeStale, ModeFailed, ModeUnsupported, ModeOutcomeUnknown:
		return &ConfiguredHostTimeAuthorityOutcomeProfile{mode: mode}, nil
	default:
		return nil, fmt.Errorf("unsupported Host time provider mode %q", mode)
	}
}

func (provider *ConfiguredHostTimeAuthorityOutcomeProfile) ObserveTimeAuthority(_ context.Context, node hostagentdomain.NodeReference, spec hostagentdomain.TimeAuthoritySpec, observedAt string) (hostagentdomain.ClockQuality, error) {
	if provider.mode == ModeOutcomeUnknown {
		return hostagentdomain.ClockQuality{}, fmt.Errorf("configured Host time probe outcome is unknown")
	}
	issue := func(code string, message string, retryable bool) *hostagentdomain.Issue {
		return &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(retryable), Dependency: spec.Source.SourceID}
	}
	source := spec.Source
	switch provider.mode {
	case ModeSynchronized:
		stratum, offset, uncertainty := 2, 0.25, 1.0
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "synchronized", Source: &source, Stratum: &stratum, OffsetMs: &offset, UncertaintyMs: &uncertainty, LastSyncAt: &observedAt, ObservedAt: observedAt}, nil
	case ModeSynchronizing:
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "synchronizing", Source: &source, ObservedAt: observedAt}, nil
	case ModeUnsynchronized:
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "unsynchronized", ObservedAt: observedAt, Issue: issue("ntp-source-unsynchronized", "configured Host NTP probe reports the source is unsynchronized", true)}, nil
	case ModeStale:
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "stale", ObservedAt: observedAt, Issue: issue("ntp-source-stale", "configured Host NTP probe reports stale synchronization evidence", true)}, nil
	case ModeFailed:
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "failed", ObservedAt: observedAt, Issue: issue("ntp-probe-failed", "configured Host NTP probe failed", true)}, nil
	case ModeUnsupported:
		return hostagentdomain.ClockQuality{SchemaVersion: hostagentdomain.SchemaVersion, Node: node, State: "unsupported", ObservedAt: observedAt, Issue: issue("ntp-probe-unsupported", "no Host NTP probe adapter is configured", false)}, nil
	default:
		return hostagentdomain.ClockQuality{}, fmt.Errorf("unreachable Host time provider mode %q", provider.mode)
	}
}

var _ hostagentapplication.HostTimeAuthorityProvider = (*ConfiguredHostTimeAuthorityOutcomeProfile)(nil)
