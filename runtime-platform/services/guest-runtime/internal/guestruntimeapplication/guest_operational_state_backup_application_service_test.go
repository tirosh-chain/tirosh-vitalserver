package guestruntimeapplication_test

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestGuestOperationalStateBackupApplicationCompletesOnlyFromExplicitReceipts(t *testing.T) {
	repository := newMemoryGuestStateBackupRepository()
	executor := &scriptedGuestStateBackupExecutor{
		results: map[string]guestruntimeapplication.GuestOperationalStateBackupStageResult{},
	}
	for index, stage := range []string{
		guestruntimedomain.GuestStateBackupSQLiteSnapshotStage,
		guestruntimedomain.GuestStateBackupPostgreSQLSnapshotStage,
		guestruntimedomain.GuestStateBackupArtifactInventoryStage,
	} {
		receipt := guestStateBackupApplicationReceipt(
			stage,
			time.Date(2026, 7, 24, 20, 0, index+2, 0, time.UTC),
		)
		executor.results[stage] = guestruntimeapplication.GuestOperationalStateBackupStageResult{
			Outcome: guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded,
			Receipt: &receipt,
		}
	}
	manifestReference := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-manifest",
		ResourceID:   "backup-manifest-1",
	}
	manifestReceipt := guestStateBackupApplicationReceipt(
		guestruntimedomain.GuestStateBackupManifestPublicationStage,
		time.Date(2026, 7, 24, 20, 0, 5, 0, time.UTC),
	)
	manifestReceipt.EvidenceReference = manifestReference
	manifestReceipt.EvidenceSHA256 = "b3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01"
	executor.results[guestruntimedomain.GuestStateBackupManifestPublicationStage] =
		guestruntimeapplication.GuestOperationalStateBackupStageResult{
			Outcome:           guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded,
			Receipt:           &manifestReceipt,
			ManifestReference: &manifestReference,
			ManifestSHA256:    manifestReceipt.EvidenceSHA256,
		}
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		repository,
		executor,
		fixedGuestStateBackupClock{now: time.Date(2026, 7, 24, 20, 0, 1, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	operation, err := service.AdmitBackup(
		context.Background(),
		guestruntimedomain.GuestOperationalStateBackupCommand{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			RequestID:     "backup-request-1",
			OperationID:   "backup-operation-1",
			DestinationReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-destination",
				ResourceID:   "backup-destination-1",
			},
			RequestedAt: "2026-07-24T20:00:00Z",
		},
	)
	if err != nil || operation.State != guestruntimedomain.GuestStateBackupRequestedState {
		t.Fatalf("admitted operation=%+v err=%v", operation, err)
	}
	for index := 0; index < 5; index++ {
		var ran bool
		operation, ran, err = service.RunNextPendingEffect(context.Background())
		if err != nil || !ran {
			t.Fatalf("run %d operation=%+v ran=%t err=%v", index, operation, ran, err)
		}
	}
	if operation.State != guestruntimedomain.GuestStateBackupSucceededState ||
		operation.ManifestReference == nil ||
		len(operation.StageReceipts) != 4 {
		t.Fatalf("terminal backup operation=%+v", operation)
	}
	if _, ran, err := service.RunNextPendingEffect(context.Background()); err != nil || ran {
		t.Fatalf("terminal pending effect ran=%t err=%v", ran, err)
	}
}

func TestGuestOperationalStateBackupApplicationLeavesUnknownEffectPending(t *testing.T) {
	repository := newMemoryGuestStateBackupRepository()
	executor := &scriptedGuestStateBackupExecutor{
		errors: map[string]error{
			guestruntimedomain.GuestStateBackupSQLiteSnapshotStage: errors.New("snapshot process result unavailable"),
		},
	}
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		repository,
		executor,
		fixedGuestStateBackupClock{now: time.Date(2026, 7, 24, 21, 0, 1, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = service.AdmitBackup(
		context.Background(),
		guestruntimedomain.GuestOperationalStateBackupCommand{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			RequestID:     "backup-request-unknown-1",
			OperationID:   "backup-operation-unknown-1",
			DestinationReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-destination",
				ResourceID:   "backup-destination-unknown-1",
			},
			RequestedAt: "2026-07-24T21:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := service.RunNextPendingEffect(context.Background()); err != nil {
		t.Fatal(err)
	}
	before, err := repository.ReadOperation(context.Background(), "backup-operation-unknown-1")
	if err != nil {
		t.Fatal(err)
	}
	if _, ran, err := service.RunNextPendingEffect(context.Background()); err == nil || !ran {
		t.Fatalf("unknown effect ran=%t err=%v", ran, err)
	}
	after, err := repository.ReadOperation(context.Background(), "backup-operation-unknown-1")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(before, after) ||
		after.State != guestruntimedomain.GuestStateBackupSnapshottingSQLiteState {
		t.Fatalf("unknown outcome changed operation before=%+v after=%+v", before, after)
	}
	if len(repository.pending) != 1 ||
		repository.pending[0].Effect != guestruntimedomain.GuestStateBackupSQLiteSnapshotStage {
		t.Fatalf("unknown outcome pending effects=%+v", repository.pending)
	}
}

func TestGuestOperationalStateRestoreKnownRejectionPersistsTypedFailure(t *testing.T) {
	repository := newMemoryGuestStateBackupRepository()
	executor := &scriptedGuestStateBackupExecutor{
		results: map[string]guestruntimeapplication.GuestOperationalStateBackupStageResult{
			guestruntimedomain.GuestStateRestoreBackupValidationStage: {
				Outcome:        guestruntimeapplication.GuestStateBackupStageOutcomeRejected,
				FailureCode:    "backup-manifest-digest-mismatch",
				FailureMessage: "manifest bytes do not match the requested SHA-256",
			},
		},
	}
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		repository,
		executor,
		fixedGuestStateBackupClock{now: time.Date(2026, 7, 24, 22, 0, 1, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	_, err = service.AdmitRestore(
		context.Background(),
		guestruntimedomain.GuestOperationalStateRestoreCommand{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			RequestID:     "restore-request-1",
			OperationID:   "restore-operation-1",
			ManifestReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-manifest",
				ResourceID:   "backup-manifest-1",
			},
			ManifestSHA256: "c3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01",
			TargetReference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-restore-target",
				ResourceID:   "empty-target-1",
			},
			RequestedAt: "2026-07-24T22:00:00Z",
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := service.RunNextPendingEffect(context.Background()); err != nil {
		t.Fatal(err)
	}
	operation, ran, err := service.RunNextPendingEffect(context.Background())
	if err != nil || !ran {
		t.Fatalf("restore rejection operation=%+v ran=%t err=%v", operation, ran, err)
	}
	if operation.State != guestruntimedomain.GuestStateBackupFailedState ||
		operation.Failure == nil ||
		operation.Failure.Stage != guestruntimedomain.GuestStateRestoreBackupValidationStage ||
		operation.Failure.Code != "backup-manifest-digest-mismatch" {
		t.Fatalf("restore failure=%+v", operation)
	}
}

type fixedGuestStateBackupClock struct {
	now time.Time
}

func (clock fixedGuestStateBackupClock) Now() time.Time {
	return clock.now
}

type scriptedGuestStateBackupExecutor struct {
	results map[string]guestruntimeapplication.GuestOperationalStateBackupStageResult
	errors  map[string]error
}

func (executor *scriptedGuestStateBackupExecutor) ExecuteStage(
	_ context.Context,
	_ guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	if err := executor.errors[stage]; err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	return executor.results[stage], nil
}

type memoryGuestStateBackupRepository struct {
	mu         sync.Mutex
	operations map[string]guestruntimedomain.GuestOperationalStateBackupOperation
	byRequest  map[string]string
	pending    []guestruntimeapplication.PendingGuestOperationalStateBackupEffect
}

func newMemoryGuestStateBackupRepository() *memoryGuestStateBackupRepository {
	return &memoryGuestStateBackupRepository{
		operations: map[string]guestruntimedomain.GuestOperationalStateBackupOperation{},
		byRequest:  map[string]string{},
	}
}

func (repository *memoryGuestStateBackupRepository) ReadOperation(
	_ context.Context,
	id string,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	operation, ok := repository.operations[id]
	if !ok {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return operation, nil
}

func (repository *memoryGuestStateBackupRepository) ReadOperationByRequestID(
	_ context.Context,
	requestID string,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	id, ok := repository.byRequest[requestID]
	if !ok {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return repository.operations[id], nil
}

func (repository *memoryGuestStateBackupRepository) AdmitOperation(
	_ context.Context,
	_ string,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	effect string,
) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if _, exists := repository.operations[operation.ID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	if _, exists := repository.byRequest[operation.RequestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.operations[operation.ID] = operation
	repository.byRequest[operation.RequestID] = operation.ID
	repository.pending = append(repository.pending, guestruntimeapplication.PendingGuestOperationalStateBackupEffect{
		Operation: operation,
		Effect:    effect,
	})
	return nil
}

func (repository *memoryGuestStateBackupRepository) ListPendingEffects(
	_ context.Context,
	limit int,
) ([]guestruntimeapplication.PendingGuestOperationalStateBackupEffect, error) {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	if len(repository.pending) < limit {
		limit = len(repository.pending)
	}
	return append([]guestruntimeapplication.PendingGuestOperationalStateBackupEffect{}, repository.pending[:limit]...), nil
}

func (repository *memoryGuestStateBackupRepository) CommitTransition(
	_ context.Context,
	current guestruntimedomain.GuestOperationalStateBackupOperation,
	next guestruntimedomain.GuestOperationalStateBackupOperation,
	completedEffect string,
	nextEffect string,
) error {
	repository.mu.Lock()
	defer repository.mu.Unlock()
	stored, ok := repository.operations[current.ID]
	if !ok {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if !reflect.DeepEqual(stored, current) ||
		len(repository.pending) == 0 ||
		repository.pending[0].Effect != completedEffect ||
		!reflect.DeepEqual(repository.pending[0].Operation, current) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	repository.operations[next.ID] = next
	repository.pending = repository.pending[1:]
	if nextEffect != "" {
		repository.pending = append(repository.pending, guestruntimeapplication.PendingGuestOperationalStateBackupEffect{
			Operation: next,
			Effect:    nextEffect,
		})
	}
	return nil
}

func guestStateBackupApplicationReceipt(
	stage string,
	completedAt time.Time,
) guestruntimedomain.GuestOperationalStateBackupStageReceipt {
	return guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage: stage,
		EvidenceReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-backup-stage-receipt",
			ResourceID:   stage + "-1",
		},
		EvidenceSHA256: "a3456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01",
		CompletedAt:    guestruntimedomain.Timestamp(completedAt),
	}
}
