package guestruntimeapplication

import "testing"

func TestNewGuestRuntimeOwnedResourceRunningOperationRecordsAdmissionBeforeObservation(t *testing.T) {
	operation, err := newGuestRuntimeOwnedResourceRunningOperation(
		"guest-operation-1",
		"time-authority.apply",
		"time-apply-1",
		"time-authority",
		"guest-time-primary",
		3,
		"2026-07-18T09:00:00Z",
		"command-digest",
	)
	if err != nil {
		t.Fatalf("construct owned-resource running operation: %v", err)
	}
	if operation.State != "running" || operation.AcceptedAt == nil || operation.StartedAt == nil {
		t.Fatalf("expected accepted and running admission evidence, got %#v", operation)
	}
	if operation.Target.ResourceType != "time-authority" || operation.Target.ResourceID != "guest-time-primary" || operation.Target.RequestedResourceRevision != 3 {
		t.Fatalf("operation lost its caller-owned resource identity: %#v", operation.Target)
	}
}
