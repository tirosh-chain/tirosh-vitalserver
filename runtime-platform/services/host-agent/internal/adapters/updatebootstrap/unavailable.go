// Package updatebootstrap reports an explicit unavailable bootstrap boundary
// until a platform product package supplies the native staged updater.
package updatebootstrap

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type Unavailable struct {
	Clock hostagentapplication.HostAgentClock
}

func (bootstrapper Unavailable) Stage(_ context.Context, journal hostagentdomain.HostUpdateJournal, _ hostagentdomain.UpdateBootstrapEnvelope) hostagentdomain.UpdateBootstrapReceipt {
	return hostagentdomain.UpdateBootstrapReceipt{
		SchemaVersion:       hostagentdomain.SchemaVersion,
		UpdateID:            journal.ID,
		RequestID:           journal.RequestID,
		BootstrapEnvelopeID: journal.BootstrapEnvelopeID,
		NextUpdaterSHA256:   journal.NextUpdaterSHA256,
		State:               "unavailable",
		ObservedAt:          hostagentdomain.Timestamp(bootstrapper.Clock.Now()),
		Issue: &hostagentdomain.Issue{
			Code:       "host-update-bootstrapper-unavailable",
			Message:    "no platform update bootstrapper is installed in this Host Agent composition",
			Retryable:  hostagentdomain.Bool(false),
			Dependency: "host-update-bootstrapper",
		},
	}
}

func (Unavailable) RequestHandoff(context.Context, hostagentdomain.HostUpdateJournal) *hostagentdomain.Issue {
	return &hostagentdomain.Issue{
		Code:       "host-update-bootstrapper-unavailable",
		Message:    "no platform update bootstrapper is installed in this Host Agent composition",
		Retryable:  hostagentdomain.Bool(false),
		Dependency: "host-update-bootstrapper",
	}
}
