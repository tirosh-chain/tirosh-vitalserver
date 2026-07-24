package guestruntimedomain_test

import (
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestResolveRecorderAssignmentPreservesCompleteSortedCandidateEvidence(t *testing.T) {
	evidences := []guestruntimedomain.RecorderAssignmentEvidence{
		assignmentEvidence("evidence-b", "recorder-b", "OR-01"),
		assignmentEvidence("evidence-a", "recorder-a", "OR-01"),
		assignmentEvidence("evidence-a-duplicate-recorder", "recorder-a", "OR-01"),
	}
	resolution, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		"2026-07-24T10:30:00Z",
		evidences,
		"2026-07-24T10:31:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	if resolution.PolicyVersion != guestruntimedomain.RecorderAssignmentPolicyVersion ||
		len(resolution.CandidateRecorderIDs) != 2 ||
		resolution.CandidateRecorderIDs[0] != "recorder-a" ||
		resolution.CandidateRecorderIDs[1] != "recorder-b" ||
		len(resolution.EvidenceReferences) != 3 {
		t.Fatalf("resolution=%#v", resolution)
	}
	if err := guestruntimedomain.ValidateRecorderAssignmentResolution(resolution); err != nil {
		t.Fatal(err)
	}
	repeated, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		"2026-07-24T10:30:00Z",
		evidences,
		"2026-07-24T10:32:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	if repeated.ResolutionID != resolution.ResolutionID {
		t.Fatalf("resolution identity changed: %s != %s", repeated.ResolutionID, resolution.ResolutionID)
	}
}

func TestValidateRecorderAssignmentResolutionRejectsNonCanonicalIdentity(t *testing.T) {
	resolution, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		"2026-07-24T10:30:00Z",
		[]guestruntimedomain.RecorderAssignmentEvidence{
			assignmentEvidence("evidence-a", "recorder-a", "OR-01"),
		},
		"2026-07-24T10:31:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	resolution.ResolutionID = "assignment-resolution-tampered"
	if err := guestruntimedomain.ValidateRecorderAssignmentResolution(resolution); err == nil {
		t.Fatal("resolution identity must cover its complete evidence and candidate set")
	}
}

func TestResolveRecorderAssignmentRejectsEvidenceOutsideEffectiveWindow(t *testing.T) {
	evidence := assignmentEvidence("evidence-a", "recorder-a", "OR-01")
	effectiveUntil := "2026-07-24T11:00:00Z"
	evidence.EffectiveUntil = &effectiveUntil
	if _, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		effectiveUntil,
		[]guestruntimedomain.RecorderAssignmentEvidence{evidence},
		"2026-07-24T11:01:00Z",
	); err == nil {
		t.Fatal("effectiveUntil must be an exclusive boundary")
	}
}

func TestResolveRecorderAssignmentDoesNotCreateCandidatesFromEmptyEvidence(t *testing.T) {
	resolution, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		"2026-07-24T10:30:00Z",
		nil,
		"2026-07-24T10:31:00Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(resolution.CandidateRecorderIDs) != 0 ||
		len(resolution.EvidenceReferences) != 0 {
		t.Fatalf("resolution=%#v", resolution)
	}
}

func assignmentEvidence(
	evidenceID string,
	recorderID string,
	bedName string,
) guestruntimedomain.RecorderAssignmentEvidence {
	return guestruntimedomain.RecorderAssignmentEvidence{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		EvidenceID:    evidenceID,
		RecorderID:    recorderID,
		BedName:       bedName,
		EffectiveFrom: "2026-07-24T10:00:00Z",
		ObservedAt:    "2026-07-24T10:00:00Z",
		PersistedAt:   "2026-07-24T10:00:01Z",
		SourceKind:    guestruntimedomain.RecorderAssignmentAdministratorSourceKind,
		SourceReference: guestruntimedomain.EvidenceReference{
			Kind: "administrator-command",
			ID:   "assignment-command-1",
		},
	}
}
