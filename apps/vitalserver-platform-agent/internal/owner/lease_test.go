package owner

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestLeaseOwnerAcquireHeartbeatAndRelease(t *testing.T) {
	path := filepath.Join(t.TempDir(), "operation-lease.json")
	if err := AcquireLease(path, leaseJSON("operation-1", "2026-07-11T00:00:00Z")); err != nil {
		t.Fatal(err)
	}
	if err := AcquireLease(path, leaseJSON("operation-2", "2026-07-11T00:00:00Z")); !isLeaseKind(err, LeaseConflict) {
		t.Fatalf("second acquire must conflict: %v", err)
	}
	if err := HeartbeatLease(path, "wrong-operation", "2026-07-11T00:01:00Z", nil); !isLeaseKind(err, LeaseConflict) {
		t.Fatalf("mismatched heartbeat must conflict: %v", err)
	}
	expiresAt := "2026-07-11T00:06:00Z"
	if err := HeartbeatLease(path, "operation-1", "2026-07-11T00:01:00Z", &expiresAt); err != nil {
		t.Fatal(err)
	}
	resource := ReadOperation(path)
	var document leaseDocument
	if err := json.Unmarshal(resource.Document, &document); err != nil {
		t.Fatal(err)
	}
	if document.HeartbeatAt != "2026-07-11T00:01:00Z" || document.ExpiresAt == nil || *document.ExpiresAt != expiresAt {
		t.Fatalf("heartbeat document=%+v", document)
	}
	if err := ReleaseLease(path, "wrong-operation"); !isLeaseKind(err, LeaseConflict) {
		t.Fatalf("mismatched release must conflict: %v", err)
	}
	if err := ReleaseLease(path, "operation-1"); err != nil {
		t.Fatal(err)
	}
	if state := ReadOperation(path); state.State != "unavailable" {
		t.Fatalf("released lease state=%+v", state)
	}
	if err := ReleaseLease(path, "operation-1"); err != nil {
		t.Fatalf("idempotent missing release failed: %v", err)
	}
}

func TestLeasePresentationPreservesLoadedStaleAndInvalidExpiration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "operation-lease.json")
	expiresAt := "2026-07-11T00:05:00Z"
	document := leaseJSON("operation-1", "2026-07-11T00:00:00Z")
	var lease leaseDocument
	if err := json.Unmarshal(document, &lease); err != nil {
		t.Fatal(err)
	}
	lease.ExpiresAt = &expiresAt
	document, _ = json.Marshal(lease)
	if err := AcquireLease(path, document); err != nil {
		t.Fatal(err)
	}

	loaded := PresentOperationAt(
		ReadOperation(path),
		time.Date(2026, 7, 11, 0, 4, 59, 0, time.UTC),
	)
	if loaded.State != "loaded" || loaded.StaleReason != nil {
		t.Fatalf("loaded lease=%+v", loaded)
	}
	stale := PresentOperationAt(
		ReadOperation(path),
		time.Date(2026, 7, 11, 0, 5, 3, 0, time.UTC),
	)
	if stale.State != "stale" || stale.StaleReason == nil || *stale.StaleReason != "runtime operation lease expired operationId=operation-1 expiresAt=2026-07-11T00:05:00Z expiredSeconds=3" {
		t.Fatalf("stale lease=%+v", stale)
	}

	invalidExpiresAt := "not-a-date"
	lease.ExpiresAt = &invalidExpiresAt
	invalidData, _ := json.Marshal(lease)
	if err := writeAtomic(path, invalidData); err != nil {
		t.Fatal(err)
	}
	invalid := PresentOperationAt(ReadOperation(path), time.Now())
	if invalid.State != "failed" || invalid.ReadError == nil {
		t.Fatalf("invalid expiration lease=%+v", invalid)
	}
}

func TestConcurrentLeaseAcquireHasOneWinner(t *testing.T) {
	path := filepath.Join(t.TempDir(), "operation-lease.json")
	start := make(chan struct{})
	results := make(chan error, 2)
	var wait sync.WaitGroup
	for _, operationID := range []string{"operation-1", "operation-2"} {
		wait.Add(1)
		go func(operationID string) {
			defer wait.Done()
			<-start
			results <- AcquireLease(path, leaseJSON(operationID, "2026-07-11T00:00:00Z"))
		}(operationID)
	}
	close(start)
	wait.Wait()
	close(results)

	succeeded := 0
	conflicted := 0
	for err := range results {
		switch {
		case err == nil:
			succeeded++
		case isLeaseKind(err, LeaseConflict):
			conflicted++
		default:
			t.Fatalf("unexpected acquire error: %v", err)
		}
	}
	if succeeded != 1 || conflicted != 1 {
		t.Fatalf("succeeded=%d conflicted=%d", succeeded, conflicted)
	}
}

func leaseJSON(operationID, heartbeatAt string) json.RawMessage {
	document, _ := json.Marshal(leaseDocument{
		SchemaVersion: 1,
		OperationID:   operationID,
		Operation:     "install",
		StartedAt:     "2026-07-11T00:00:00Z",
		HeartbeatAt:   heartbeatAt,
	})
	return document
}

func isLeaseKind(err error, kind LeaseErrorKind) bool {
	var leaseError LeaseError
	return errors.As(err, &leaseError) && leaseError.Kind == kind
}
