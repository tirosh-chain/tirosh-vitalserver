package recorderassignmentresolution

import (
	"context"
	"errors"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type assignmentOwnerStub struct {
	resolution guestruntimedomain.RecorderAssignmentResolution
	err        error
}

func (owner assignmentOwnerStub) ResolveRecorderAssignment(
	context.Context,
	string,
	string,
) (guestruntimedomain.RecorderAssignmentResolution, error) {
	return owner.resolution, owner.err
}

func TestRecorderAssignmentOwnerResolverUsesCompleteOwnerCandidateSet(t *testing.T) {
	resolution, err := guestruntimedomain.ResolveRecorderAssignment(
		"OR-01",
		"2026-07-24T14:00:00Z",
		[]guestruntimedomain.RecorderAssignmentEvidence{
			recorderAssignmentEvidence("assignment-evidence-a", "recorder-a"),
			recorderAssignmentEvidence("assignment-evidence-b", "recorder-b"),
		},
		"2026-07-24T14:00:01Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewRecorderAssignmentOwnerAttributionResolver(
		assignmentOwnerStub{resolution: resolution},
	)
	if err != nil {
		t.Fatal(err)
	}
	input, err := resolver.ResolveRecorderArtifactAttribution(
		context.Background(),
		recorderUploadSourceReceipt(),
		"archive-artifact-1",
		"2026-07-24T14:00:02Z",
	)
	if err != nil {
		t.Fatal(err)
	}
	attribution, err := guestruntimedomain.ResolveRecorderArtifactAttribution(input)
	if err != nil {
		t.Fatal(err)
	}
	if attribution.Outcome != guestruntimedomain.AmbiguousRecorderAttributionOutcome ||
		attribution.AssignmentEvidenceReference == nil ||
		attribution.AssignmentEvidenceReference.ID != resolution.ResolutionID {
		t.Fatalf("attribution=%#v", attribution)
	}
}

func TestRecorderAssignmentOwnerFailureDoesNotBecomeUnresolved(t *testing.T) {
	resolver, err := NewRecorderAssignmentOwnerAttributionResolver(
		assignmentOwnerStub{err: errors.New("assignment database unavailable")},
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := resolver.ResolveRecorderArtifactAttribution(
		context.Background(),
		recorderUploadSourceReceipt(),
		"archive-artifact-1",
		"2026-07-24T14:00:02Z",
	); err == nil {
		t.Fatal("assignment owner failure must remain an error")
	}
}

func recorderUploadSourceReceipt() guestruntimedomain.RecorderVitalUploadSourceReceipt {
	return guestruntimedomain.RecorderVitalUploadSourceReceipt{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		ID:               "recorder-vital-upload-1",
		SourceKind:       guestruntimedomain.RecorderUploadArchiveSourceKind,
		UploadID:         "upload-1",
		OriginalFileName: "OR-01.vital",
		MediaType:        "application/x-vital",
		ByteSize:         20,
		SHA256:           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		ReportedBedName:  "OR-01",
		State:            "admitted",
		ContentReference: guestruntimedomain.ResourceReference{
			ResourceType: "recorder-vital-upload-content",
			ResourceID:   "recorder-vital-upload-1",
		},
		ReceivedAt:  "2026-07-24T14:00:00Z",
		FinalizedAt: "2026-07-24T14:00:00Z",
	}
}

func recorderAssignmentEvidence(
	evidenceID string,
	recorderID string,
) guestruntimedomain.RecorderAssignmentEvidence {
	return guestruntimedomain.RecorderAssignmentEvidence{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		EvidenceID:    evidenceID,
		RecorderID:    recorderID,
		BedName:       "OR-01",
		EffectiveFrom: "2026-07-24T13:00:00Z",
		ObservedAt:    "2026-07-24T13:00:00Z",
		PersistedAt:   "2026-07-24T13:00:01Z",
		SourceKind:    guestruntimedomain.RecorderAssignmentAdministratorSourceKind,
		SourceReference: guestruntimedomain.EvidenceReference{
			Kind: "administrator-command",
			ID:   evidenceID,
		},
	}
}
