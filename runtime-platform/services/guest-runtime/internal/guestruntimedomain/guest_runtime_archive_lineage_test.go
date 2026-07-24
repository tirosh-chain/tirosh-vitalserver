package guestruntimedomain

import "testing"

func TestFinalizedArchiveArtifactAttributionKeepsBedNameAsEvidence(t *testing.T) {
	finalizedAt := "2026-07-24T09:00:00Z"
	matchedRecorderID := "recorder-1"
	reportedBedName := "OR-01"
	artifact := validArchiveArtifactForTest(finalizedAt)
	attribution := RecorderArtifactAttribution{
		SchemaVersion:        SchemaVersion,
		ArtifactID:           artifact.ArtifactID,
		ReportedBedName:      &reportedBedName,
		EvidenceObservedAt:   finalizedAt,
		CandidateRecorderIDs: []string{matchedRecorderID},
		Outcome:              MatchedRecorderAttributionOutcome,
		MatchedRecorderID:    &matchedRecorderID,
		PolicyVersion:        "bed-assignment-v1",
		ResolvedAt:           finalizedAt,
	}
	if err := ValidateFinalizedArchiveArtifact(artifact, attribution); err != nil {
		t.Fatalf("expected explicit matched attribution to validate: %v", err)
	}

	attribution.CandidateRecorderIDs = []string{"recorder-2"}
	if err := ValidateFinalizedArchiveArtifact(artifact, attribution); err == nil {
		t.Fatal("reported bed name must not permit a mismatched Recorder identity")
	}
}

func TestArchiveUploadAndIndexingOutcomesStayIndependent(t *testing.T) {
	finishedAt := "2026-07-24T09:01:00Z"
	attempt := ArchiveUploadAttempt{
		SchemaVersion: SchemaVersion,
		AttemptID:     "attempt-1",
		RequestID:     "request-1",
		ArtifactID:    "artifact-1",
		Provider: ArchiveProviderReference{
			Kind:               "vitalserver-indexed-library",
			ID:                 "archive-provider-1",
			CapabilityRevision: 1,
		},
		State:      "succeeded",
		StartedAt:  "2026-07-24T09:00:00Z",
		FinishedAt: &finishedAt,
	}
	if err := ValidateArchiveUploadAttempt(attempt); err != nil {
		t.Fatalf("expected succeeded upload attempt to validate: %v", err)
	}
	receipt := ArchiveIndexingReceipt{
		SchemaVersion:   SchemaVersion,
		ReceiptID:       "index-receipt-1",
		ArtifactID:      attempt.ArtifactID,
		UploadAttemptID: attempt.AttemptID,
		Outcome:         "not-indexed",
		Issue:           &Issue{Code: "provider-index-missing", Message: "provider did not report an index entry"},
		ObservedAt:      finishedAt,
		PersistedAt:     finishedAt,
	}
	if err := ValidateArchiveIndexingReceipt(receipt); err != nil {
		t.Fatalf("upload success must permit an explicit non-indexed receipt: %v", err)
	}
}

func TestRecorderVitalUploadSourceReceiptKeepsRecorderDeclarationsAsEvidence(t *testing.T) {
	declaredRecorderID := "recorder-claimed"
	declaredRecorderCode := "VR-01"
	receipt := validRecorderVitalUploadSourceReceiptForTest()
	receipt.DeclaredRecorderID = &declaredRecorderID
	receipt.DeclaredRecorderCode = &declaredRecorderCode

	if err := ValidateRecorderVitalUploadSourceReceipt(receipt); err != nil {
		t.Fatalf("expected complete Gateway source receipt to validate: %v", err)
	}

	input := RecorderAttributionResolutionInput{
		ArtifactID:           "artifact-1",
		ReportedBedName:      &receipt.ReportedBedName,
		EvidenceObservedAt:   receipt.FinalizedAt,
		CandidateRecorderIDs: nil,
		PolicyVersion:        "assignment-owner-v1",
		ResolvedAt:           receipt.FinalizedAt,
	}
	attribution, err := ResolveRecorderArtifactAttribution(input)
	if err != nil {
		t.Fatal(err)
	}
	if attribution.Outcome != UnresolvedRecorderAttributionOutcome ||
		attribution.MatchedRecorderID != nil {
		t.Fatalf(
			"declared Recorder identity and bed name must not create attribution: %#v",
			attribution,
		)
	}
}

func TestRecorderArtifactAttributionUsesOnlyCompleteAssignmentOwnerCandidates(t *testing.T) {
	observedAt := "2026-07-24T09:00:00Z"
	evidence := EvidenceReference{
		Kind: "recorder-assignment-snapshot",
		ID:   "assignment-snapshot-1",
	}
	input := RecorderAttributionResolutionInput{
		ArtifactID:                  "artifact-1",
		EvidenceObservedAt:          observedAt,
		AssignmentEvidenceReference: &evidence,
		CandidateRecorderIDs:        []string{"recorder-1"},
		PolicyVersion:               "assignment-owner-v1",
		ResolvedAt:                  observedAt,
	}
	matched, err := ResolveRecorderArtifactAttribution(input)
	if err != nil {
		t.Fatal(err)
	}
	if matched.Outcome != MatchedRecorderAttributionOutcome ||
		matched.MatchedRecorderID == nil ||
		*matched.MatchedRecorderID != "recorder-1" {
		t.Fatalf("expected exactly one owner candidate to match: %#v", matched)
	}

	input.CandidateRecorderIDs = []string{"recorder-1", "recorder-2"}
	ambiguous, err := ResolveRecorderArtifactAttribution(input)
	if err != nil {
		t.Fatal(err)
	}
	if ambiguous.Outcome != AmbiguousRecorderAttributionOutcome ||
		ambiguous.MatchedRecorderID != nil {
		t.Fatalf("expected multiple owner candidates to remain ambiguous: %#v", ambiguous)
	}
}

func TestArchiveSourceAdmissionReceiptPreservesQuarantine(t *testing.T) {
	receipt := ArchiveSourceAdmissionReceipt{
		SchemaVersion: SchemaVersion,
		RequestID:     "archive-source-request-1",
		Outcome:       "quarantined",
		ReceivedAt:    "2026-07-24T09:00:00Z",
		PersistedAt:   "2026-07-24T09:00:01Z",
		Issue: &Issue{
			Code:    "source-content-mismatch",
			Message: "source bytes do not match the Gateway receipt",
		},
	}
	if err := ValidateArchiveSourceAdmissionReceipt(receipt); err != nil {
		t.Fatalf("expected explicit quarantine receipt to validate: %v", err)
	}
	receipt.Outcome = "accepted"
	if err := ValidateArchiveSourceAdmissionReceipt(receipt); err == nil {
		t.Fatal("accepted admission must not hide quarantine evidence")
	}
}

func validArchiveArtifactForTest(finalizedAt string) ArchiveArtifact {
	manifest := ArchiveLineageManifest{
		SchemaVersion: SchemaVersion,
		ID:            "manifest-1",
		Source: ArchiveLineageManifestSource{
			Kind:        LabExportArchiveSourceKind,
			ReceiptType: "gateway-finalization-receipt",
			ReceiptID:   "source-receipt-1",
			FinalizedAt: finalizedAt,
			EvidenceReference: EvidenceReference{
				Kind: "gateway-finalization-receipt",
				ID:   "source-receipt-1",
			},
		},
		Artifact: ArchiveLineageArtifactIdentity{
			ArtifactID: "artifact-1",
			SHA256:     "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			ByteSize:   20,
			MediaType:  "application/x-vital",
			StorageReference: ResourceReference{
				ResourceType: "guest-archive-object",
				ResourceID:   "artifact-1",
			},
		},
		CreatedAt: finalizedAt,
	}
	return ArchiveArtifact{
		SchemaVersion:     SchemaVersion,
		ArtifactID:        manifest.Artifact.ArtifactID,
		SourceKind:        LabExportArchiveSourceKind,
		SourceReceiptType: "gateway-finalization-receipt",
		SourceReceiptID:   "source-receipt-1",
		Manifest:          manifest,
		OriginalFileName:  "recorder-1.vital",
		MediaType:         "application/x-vital",
		ByteSize:          20,
		SHA256:            manifest.Artifact.SHA256,
		FinalizationState: "finalized",
		CreatedAt:         finalizedAt,
		FinalizedAt:       &finalizedAt,
	}
}

func validRecorderVitalUploadSourceReceiptForTest() RecorderVitalUploadSourceReceipt {
	return RecorderVitalUploadSourceReceipt{
		SchemaVersion:    SchemaVersion,
		ID:               "recorder-vital-upload-1",
		SourceKind:       RecorderUploadArchiveSourceKind,
		UploadID:         "upload-1",
		OriginalFileName: "OR-01.vital",
		MediaType:        "application/x-vital",
		ByteSize:         20,
		SHA256:           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		ReportedBedName:  "OR-01",
		State:            "admitted",
		ContentReference: ResourceReference{
			ResourceType: "recorder-vital-upload-content",
			ResourceID:   "recorder-vital-upload-1",
		},
		ReceivedAt:  "2026-07-24T08:59:59Z",
		FinalizedAt: "2026-07-24T09:00:00Z",
	}
}
