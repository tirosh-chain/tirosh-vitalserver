package hostagentapplication

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type scheduledBackupForwarder struct {
	commands []hostagentdomain.GuestOperationalStateBackupCommand
}

func (forwarder *scheduledBackupForwarder) ForwardGuestRuntimeControlCommand(
	_ context.Context,
	path string,
	body []byte,
	contentType string,
	requestID string,
) (GuestRuntimeControlCommandForwardOutcome, error) {
	var command hostagentdomain.GuestOperationalStateBackupCommand
	if err := json.Unmarshal(body, &command); err != nil {
		return GuestRuntimeControlCommandForwardOutcome{}, err
	}
	forwarder.commands = append(forwarder.commands, command)
	response, err := json.Marshal(map[string]any{
		"schemaVersion":        command.SchemaVersion,
		"id":                   command.OperationID,
		"requestId":            command.RequestID,
		"kind":                 "guest-operational-state-backup",
		"state":                "requested",
		"resourceRevision":     1,
		"destinationReference": command.DestinationReference,
		"stageReceipts":        []any{},
		"createdAt":            command.RequestedAt,
		"updatedAt":            command.RequestedAt,
	})
	if err != nil {
		return GuestRuntimeControlCommandForwardOutcome{}, err
	}
	if path != guestOperationalStateBackupAdmissionPath ||
		contentType != "application/json" ||
		requestID != command.RequestID {
		return GuestRuntimeControlCommandForwardOutcome{}, context.Canceled
	}
	return GuestRuntimeControlCommandForwardOutcome{
		Response: &GuestRuntimeControlHTTPForwardedResponse{
			StatusCode:  202,
			ContentType: "application/json",
			Body:        response,
		},
	}, nil
}

func TestHostBackupSchedulerReusesGuestAdmissionIdentityAfterRestart(t *testing.T) {
	forwarder := &scheduledBackupForwarder{}
	clock := fixedHostAgentClock{
		now: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC),
	}
	schedule := hostagentdomain.HostOperationalStateBackupSchedule{
		ScheduleID:      "daily-primary",
		IntervalSeconds: 86400,
		DestinationReference: hostagentdomain.ResourceReference{
			ResourceType: hostagentdomain.GuestOperationalStateBackupDestinationType,
			ResourceID:   "guest-local-operational-state",
		},
		RetentionPolicy: hostagentdomain.HostOperationalStateBackupRetentionRetainAll,
	}
	first, err := NewHostOperationalStateBackupScheduler(
		schedule,
		time.Minute,
		forwarder,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	firstCommand, _, err := first.AdmitCurrentSlot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	restarted, err := NewHostOperationalStateBackupScheduler(
		schedule,
		time.Minute,
		forwarder,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	restartedCommand, _, err := restarted.AdmitCurrentSlot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if firstCommand != restartedCommand ||
		len(forwarder.commands) != 2 ||
		forwarder.commands[0] != forwarder.commands[1] {
		t.Fatalf(
			"Host restart changed Guest idempotency identity: %#v",
			forwarder.commands,
		)
	}
}

type fixedHostAgentClock struct{ now time.Time }

func (clock fixedHostAgentClock) Now() time.Time { return clock.now }
