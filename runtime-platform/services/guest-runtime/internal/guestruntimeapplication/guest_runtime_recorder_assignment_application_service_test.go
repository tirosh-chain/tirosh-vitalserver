package guestruntimeapplication_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type memoryRecorderAssignmentRepository struct {
	byRequest   map[string]guestruntimeapplication.StoredRecorderAssignmentEvidence
	evidences   []guestruntimedomain.RecorderAssignmentEvidence
	resolutions map[string]guestruntimedomain.RecorderAssignmentResolution
	readError   error
}

func newMemoryRecorderAssignmentRepository() *memoryRecorderAssignmentRepository {
	return &memoryRecorderAssignmentRepository{
		byRequest:   map[string]guestruntimeapplication.StoredRecorderAssignmentEvidence{},
		resolutions: map[string]guestruntimedomain.RecorderAssignmentResolution{},
	}
}

func (repository *memoryRecorderAssignmentRepository) ReadRecorderAssignmentEvidenceByRequestID(
	_ context.Context,
	requestID string,
) (guestruntimeapplication.StoredRecorderAssignmentEvidence, error) {
	value, exists := repository.byRequest[requestID]
	if !exists {
		return guestruntimeapplication.StoredRecorderAssignmentEvidence{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *memoryRecorderAssignmentRepository) CommitRecorderAssignmentEvidence(
	_ context.Context,
	requestID string,
	commandDigest string,
	evidence guestruntimedomain.RecorderAssignmentEvidence,
) error {
	if _, exists := repository.byRequest[requestID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.byRequest[requestID] = guestruntimeapplication.StoredRecorderAssignmentEvidence{
		Evidence:      evidence,
		CommandDigest: commandDigest,
	}
	repository.evidences = append(repository.evidences, evidence)
	return nil
}

func (repository *memoryRecorderAssignmentRepository) ListEffectiveRecorderAssignmentEvidence(
	_ context.Context,
	bedName string,
	effectiveAt string,
	_ int,
) ([]guestruntimedomain.RecorderAssignmentEvidence, error) {
	if repository.readError != nil {
		return nil, repository.readError
	}
	values := make([]guestruntimedomain.RecorderAssignmentEvidence, 0)
	target, _ := time.Parse(time.RFC3339Nano, effectiveAt)
	for _, evidence := range repository.evidences {
		from, _ := time.Parse(time.RFC3339Nano, evidence.EffectiveFrom)
		if evidence.BedName != bedName || target.Before(from) {
			continue
		}
		if evidence.EffectiveUntil != nil {
			until, _ := time.Parse(time.RFC3339Nano, *evidence.EffectiveUntil)
			if !target.Before(until) {
				continue
			}
		}
		values = append(values, evidence)
	}
	return values, nil
}

func (repository *memoryRecorderAssignmentRepository) ReadRecorderAssignmentResolution(
	_ context.Context,
	resolutionID string,
) (guestruntimedomain.RecorderAssignmentResolution, error) {
	value, exists := repository.resolutions[resolutionID]
	if !exists {
		return guestruntimedomain.RecorderAssignmentResolution{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	return value, nil
}

func (repository *memoryRecorderAssignmentRepository) CommitRecorderAssignmentResolution(
	_ context.Context,
	resolution guestruntimedomain.RecorderAssignmentResolution,
) error {
	if _, exists := repository.resolutions[resolution.ResolutionID]; exists {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	repository.resolutions[resolution.ResolutionID] = resolution
	return nil
}

func TestRecorderAssignmentEvidenceAdmissionIsIdempotentAndResolutionIsTimeBounded(t *testing.T) {
	repository := newMemoryRecorderAssignmentRepository()
	service, err := guestruntimeapplication.NewGuestRuntimeRecorderAssignmentApplicationService(
		repository,
		fixedClock{now: time.Date(2026, 7, 24, 10, 5, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	command := recorderAssignmentCommand("assignment-request-1", "assignment-evidence-1", "recorder-1")
	receipt, rejection, failure := service.AdmitRecorderAssignmentEvidence(
		context.Background(),
		command,
	)
	if rejection != nil || failure != nil || receipt.Outcome != "accepted" {
		t.Fatalf("receipt=%#v rejection=%#v failure=%#v", receipt, rejection, failure)
	}
	duplicate, rejection, failure := service.AdmitRecorderAssignmentEvidence(
		context.Background(),
		command,
	)
	if rejection != nil || failure != nil || duplicate.Outcome != "duplicate" {
		t.Fatalf("duplicate=%#v rejection=%#v failure=%#v", duplicate, rejection, failure)
	}
	resolution, err := service.ResolveRecorderAssignment(
		context.Background(),
		"OR-01",
		"2026-07-24T10:30:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(resolution.CandidateRecorderIDs) != 1 ||
		resolution.CandidateRecorderIDs[0] != "recorder-1" ||
		len(resolution.EvidenceReferences) != 1 {
		t.Fatalf("resolution=%#v", resolution)
	}
}

func TestRecorderAssignmentReadFailureDoesNotBecomeUnresolved(t *testing.T) {
	repository := newMemoryRecorderAssignmentRepository()
	repository.readError = errors.New("postgres unavailable")
	service, err := guestruntimeapplication.NewGuestRuntimeRecorderAssignmentApplicationService(
		repository,
		fixedClock{now: time.Date(2026, 7, 24, 10, 5, 0, 0, time.UTC)},
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.ResolveRecorderAssignment(
		context.Background(),
		"OR-01",
		"2026-07-24T10:30:00Z",
	); err == nil {
		t.Fatal("assignment owner read failure must remain an error")
	}
}

func recorderAssignmentCommand(
	requestID string,
	evidenceID string,
	recorderID string,
) guestruntimedomain.RecorderAssignmentEvidenceCommand {
	return guestruntimedomain.RecorderAssignmentEvidenceCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     requestID,
		EvidenceID:    evidenceID,
		RecorderID:    recorderID,
		BedName:       "OR-01",
		EffectiveFrom: "2026-07-24T10:00:00Z",
		ObservedAt:    "2026-07-24T10:00:00Z",
		SourceKind:    guestruntimedomain.RecorderAssignmentAdministratorSourceKind,
		SourceReference: guestruntimedomain.EvidenceReference{
			Kind: "administrator-command",
			ID:   "operator-assignment-1",
		},
	}
}
