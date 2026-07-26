package hostagentdomain

import (
	"testing"
	"time"
)

func TestScheduledGuestOperationalStateBackupIsDeterministicWithinUTCSlot(
	t *testing.T,
) {
	schedule := HostOperationalStateBackupSchedule{
		ScheduleID:      "daily-primary",
		IntervalSeconds: 86400,
		DestinationReference: ResourceReference{
			ResourceType: GuestOperationalStateBackupDestinationType,
			ResourceID:   "guest-local-operational-state",
		},
		RetentionPolicy: HostOperationalStateBackupRetentionRetainAll,
	}
	first, next, err := PlanScheduledGuestOperationalStateBackup(
		schedule,
		time.Date(2026, 7, 24, 12, 30, 0, 0, time.FixedZone("KST", 9*3600)),
	)
	if err != nil {
		t.Fatal(err)
	}
	restarted, restartedNext, err := PlanScheduledGuestOperationalStateBackup(
		schedule,
		time.Date(2026, 7, 24, 23, 59, 59, 0, time.UTC),
	)
	if err != nil {
		t.Fatal(err)
	}
	if first != restarted || !next.Equal(restartedNext) {
		t.Fatalf(
			"same UTC schedule slot changed after restart: first=%+v restarted=%+v",
			first,
			restarted,
		)
	}
	if first.RequestedAt != "2026-07-24T00:00:00Z" ||
		!next.Equal(time.Date(2026, 7, 25, 0, 0, 0, 0, time.UTC)) {
		t.Fatalf("slot command=%+v next=%s", first, next)
	}
}

func TestScheduledGuestOperationalStateBackupRejectsImplicitRetention(t *testing.T) {
	schedule := HostOperationalStateBackupSchedule{
		ScheduleID:      "daily-primary",
		IntervalSeconds: 86400,
		DestinationReference: ResourceReference{
			ResourceType: GuestOperationalStateBackupDestinationType,
			ResourceID:   "guest-local-operational-state",
		},
	}
	if _, _, err := PlanScheduledGuestOperationalStateBackup(
		schedule,
		time.Now(),
	); err == nil {
		t.Fatal("missing retention policy must not become retain-all")
	}
}
