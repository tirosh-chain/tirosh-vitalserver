package hostagentapplication

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const guestOperationalStateBackupAdmissionPath = "/v1/runtime/operational-state/backups"

type GuestOperationalStateBackupCommandForwarder interface {
	ForwardGuestRuntimeControlCommand(
		context.Context,
		string,
		[]byte,
		string,
		string,
	) (GuestRuntimeControlCommandForwardOutcome, error)
}

type HostOperationalStateBackupScheduler struct {
	schedule      hostagentdomain.HostOperationalStateBackupSchedule
	retryInterval time.Duration
	forwarder     GuestOperationalStateBackupCommandForwarder
	clock         HostAgentClock
}

func NewHostOperationalStateBackupScheduler(
	schedule hostagentdomain.HostOperationalStateBackupSchedule,
	retryInterval time.Duration,
	forwarder GuestOperationalStateBackupCommandForwarder,
	clock HostAgentClock,
) (*HostOperationalStateBackupScheduler, error) {
	if retryInterval < 10*time.Second ||
		retryInterval > time.Hour ||
		forwarder == nil ||
		clock == nil {
		return nil, fmt.Errorf(
			"Host operational-state backup scheduler configuration is incomplete",
		)
	}
	if _, _, err := hostagentdomain.PlanScheduledGuestOperationalStateBackup(
		schedule,
		clock.Now(),
	); err != nil {
		return nil, err
	}
	return &HostOperationalStateBackupScheduler{
		schedule:      schedule,
		retryInterval: retryInterval,
		forwarder:     forwarder,
		clock:         clock,
	}, nil
}

// AdmitCurrentSlot emits only the deterministic C76 command for the current
// UTC slot. A repeated call after Host restart carries the same request and
// operation IDs; Guest-owned admission decides duplicate/current operation
// state.
func (scheduler *HostOperationalStateBackupScheduler) AdmitCurrentSlot(
	ctx context.Context,
) (
	hostagentdomain.GuestOperationalStateBackupCommand,
	time.Time,
	error,
) {
	command, nextSlot, err :=
		hostagentdomain.PlanScheduledGuestOperationalStateBackup(
			scheduler.schedule,
			scheduler.clock.Now(),
		)
	if err != nil {
		return command, nextSlot, err
	}
	body, err := json.Marshal(command)
	if err != nil {
		return command, nextSlot,
			fmt.Errorf("encode scheduled Guest backup command: %w", err)
	}
	outcome, err := scheduler.forwarder.ForwardGuestRuntimeControlCommand(
		ctx,
		guestOperationalStateBackupAdmissionPath,
		body,
		"application/json",
		command.RequestID,
	)
	if err != nil {
		return command, nextSlot,
			fmt.Errorf("forward scheduled Guest backup command: %w", err)
	}
	if outcome.Rejected != nil {
		return command, nextSlot, fmt.Errorf(
			"scheduled Guest backup command was rejected: %s",
			outcome.Rejected.Issue.Code,
		)
	}
	if outcome.Failure != nil {
		return command, nextSlot, fmt.Errorf(
			"scheduled Guest backup admission outcome is unknown: %s",
			outcome.Failure.Issue.Code,
		)
	}
	if outcome.Response == nil ||
		outcome.Response.StatusCode != http.StatusAccepted {
		return command, nextSlot, fmt.Errorf(
			"scheduled Guest backup admission returned no accepted operation",
		)
	}
	var operation struct {
		SchemaVersion        string                            `json:"schemaVersion"`
		ID                   string                            `json:"id"`
		RequestID            string                            `json:"requestId"`
		Kind                 string                            `json:"kind"`
		DestinationReference hostagentdomain.ResourceReference `json:"destinationReference"`
	}
	if err := json.Unmarshal(outcome.Response.Body, &operation); err != nil {
		return command, nextSlot, fmt.Errorf(
			"decode scheduled Guest backup operation: %w",
			err,
		)
	}
	if operation.SchemaVersion != command.SchemaVersion ||
		operation.ID != command.OperationID ||
		operation.RequestID != command.RequestID ||
		operation.Kind != "guest-operational-state-backup" ||
		operation.DestinationReference != command.DestinationReference {
		return command, nextSlot, fmt.Errorf(
			"scheduled Guest backup operation does not match its command",
		)
	}
	return command, nextSlot, nil
}

func (scheduler *HostOperationalStateBackupScheduler) RetryInterval() time.Duration {
	return scheduler.retryInterval
}
