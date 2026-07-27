package hostagentapplication

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// HostUpdateStateRepository is separate from the lifecycle repository because the Host
// update journal is a distinct state owner with its own recovery revision.
// Both remain in Host-owned SQLite at the infrastructure boundary.
type HostUpdateStateRepository interface {
	ReadHostPlatformInstallation(context.Context) (hostagentdomain.PlatformInstallation, error)
	ReadHostOperation(context.Context, string) (hostagentdomain.Operation, error)
	ReadHostUpdateJournal(context.Context, string) (hostagentdomain.HostUpdateJournal, error)
	ReadHostUpdateJournalByRequestID(context.Context, string) (hostagentdomain.HostUpdateJournal, error)
	ReadActiveHostUpdateJournals(context.Context) ([]hostagentdomain.HostUpdateJournal, error)
	ReadRecoverableHostUpdateJournals(context.Context) ([]hostagentdomain.HostUpdateJournal, error)
	PersistNewHostUpdate(context.Context, hostagentdomain.Operation, hostagentdomain.HostUpdateJournal) error
	PersistHostUpdateProgress(context.Context, hostagentdomain.Operation, hostagentdomain.HostUpdateJournal) error
	CommitHostUpdateOutcome(context.Context, hostagentdomain.Operation, hostagentdomain.HostUpdateJournal, *hostagentdomain.PlatformInstallation) error
}

// HostUpdateBootstrapper is platform-specific.  It verifies the C25 signature and
// staged artifact through Host-native trust/file APIs; application code never
// infers that fact from a file name, log, or exit text.
type HostUpdateBootstrapper interface {
	Stage(context.Context, hostagentdomain.HostUpdateJournal, hostagentdomain.UpdateBootstrapEnvelope) hostagentdomain.UpdateBootstrapReceipt
	RequestHandoff(context.Context, hostagentdomain.HostUpdateJournal) *hostagentdomain.Issue
}
