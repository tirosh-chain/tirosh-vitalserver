package hostagentdomain

import (
	"fmt"
	"time"
)

const (
	HostOperationalStateBackupRetentionRetainAll = "retain-all"
	GuestOperationalStateBackupDestinationType   = "guest-backup-destination"
)

// HostOperationalStateBackupSchedule is Host-owned desired timing and
// destination state. It does not describe Guest files, tables, manifests, or
// backup success.
type HostOperationalStateBackupSchedule struct {
	ScheduleID           string
	IntervalSeconds      int
	DestinationReference ResourceReference
	RetentionPolicy      string
}

// GuestOperationalStateBackupCommand is the explicit C76 command emitted for
// one UTC interval slot. Deterministic IDs let Guest-owned admission provide
// restart-safe idempotency without Host inference from Guest files or logs.
type GuestOperationalStateBackupCommand struct {
	SchemaVersion        string            `json:"schemaVersion"`
	RequestID            string            `json:"requestId"`
	OperationID          string            `json:"operationId"`
	DestinationReference ResourceReference `json:"destinationReference"`
	RequestedAt          string            `json:"requestedAt"`
}

func PlanScheduledGuestOperationalStateBackup(
	schedule HostOperationalStateBackupSchedule,
	now time.Time,
) (GuestOperationalStateBackupCommand, time.Time, error) {
	if !ValidIdentifier(schedule.ScheduleID) ||
		schedule.IntervalSeconds < 300 ||
		schedule.IntervalSeconds > 604800 ||
		schedule.DestinationReference.ResourceType !=
			GuestOperationalStateBackupDestinationType ||
		!ValidIdentifier(schedule.DestinationReference.ResourceID) ||
		schedule.RetentionPolicy !=
			HostOperationalStateBackupRetentionRetainAll {
		return GuestOperationalStateBackupCommand{}, time.Time{},
			fmt.Errorf("Host operational-state backup schedule is invalid")
	}
	utcNow := now.UTC()
	interval := time.Duration(schedule.IntervalSeconds) * time.Second
	slot := utcNow.Truncate(interval)
	slotUnix := slot.Unix()
	requestID := fmt.Sprintf(
		"scheduled-backup-%s-%d",
		schedule.ScheduleID,
		slotUnix,
	)
	operationID := fmt.Sprintf(
		"scheduled-backup-operation-%s-%d",
		schedule.ScheduleID,
		slotUnix,
	)
	if !ValidIdentifier(requestID) || !ValidIdentifier(operationID) {
		return GuestOperationalStateBackupCommand{}, time.Time{},
			fmt.Errorf("Host operational-state backup schedule identifiers are too long")
	}
	return GuestOperationalStateBackupCommand{
		SchemaVersion:        "v1",
		RequestID:            requestID,
		OperationID:          operationID,
		DestinationReference: schedule.DestinationReference,
		RequestedAt:          Timestamp(slot),
	}, slot.Add(interval), nil
}
