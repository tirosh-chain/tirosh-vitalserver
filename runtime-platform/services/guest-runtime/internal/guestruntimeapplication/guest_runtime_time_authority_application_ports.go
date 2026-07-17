package guestruntimeapplication

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeTimeAuthorityStateRepository owns Guest-node TimeAuthority resources. It is not
// shared with Host time state even when both use SQLite on their own nodes.
type GuestRuntimeTimeAuthorityStateRepository interface {
	ReadTimeAuthority(context.Context, string) (guestruntimedomain.TimeAuthority, error)
	ReadTimeAuthorityOperationByRequestID(context.Context, string) (guestruntimedomain.Operation, error)
	AdmitTimeAuthorityOperation(context.Context, string, int, guestruntimedomain.Operation) error
	CommitTimeAuthorityOutcome(context.Context, guestruntimedomain.TimeAuthority, guestruntimedomain.Operation) error
}

// GuestRuntimeTimeAuthorityProvider observes the explicitly configured NTP source. An
// error means the probe outcome is unknown; callers must retain running state.
type GuestRuntimeTimeAuthorityProvider interface {
	ObserveTimeAuthority(context.Context, guestruntimedomain.NodeReference, guestruntimedomain.TimeAuthoritySpec, string) (guestruntimedomain.ClockQuality, error)
}
