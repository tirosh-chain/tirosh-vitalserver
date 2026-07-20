package guestruntimedomain

import "testing"

func TestFailedExportReceiptKeepsUploadAndIndexingFactsSeparate(t *testing.T) {
	retryable := true
	operation := Operation{ID: "guest-operation-1", RequestID: "export-1"}
	manifest := ArtifactManifest{ID: "artifact-manifest-1"}
	provider := ArchiveProviderReference{Kind: "archive-export-outcome-profile", ID: "bundled-archive", CapabilityRevision: 1}
	upload := SucceededExportStep("upload-1", "2026-07-17T00:00:00Z")
	indexing := FailedExportStep("2026-07-17T00:00:01Z", Issue{Code: "index-failed", Retryable: &retryable})

	receipt, err := NewExportReceipt("export-receipt-1", operation, manifest, provider, upload, indexing, "2026-07-17T00:00:02Z")

	if err != nil {
		t.Fatalf("new receipt: %v", err)
	}
	if receipt.Outcome != "failed" || !receipt.Retryable || receipt.Upload.State != "succeeded" || receipt.Indexing.State != "failed" {
		t.Fatalf("receipt lost independent step facts: %+v", receipt)
	}
	if receipt.Issue == nil || receipt.Issue.Code != "index-failed" {
		t.Fatalf("receipt failure = %+v", receipt.Issue)
	}
}

func TestArtifactExportCommandRequiresOneFinalizedRecorderGatewaySource(t *testing.T) {
	command := ArtifactExportCommand{
		SchemaVersion:            SchemaVersion,
		RequestID:                "archive-export-1",
		VirtualRecorderID:        "lab-recorder-1",
		ExpectedResourceRevision: 1,
		Provider:                 ArchiveProviderReference{Kind: "archive-export-outcome-profile", ID: "bundled-archive", CapabilityRevision: 1},
	}
	if issue := ValidateArtifactExportCommand(command); issue == nil || issue.Code != "invalid-artifact-export-source" {
		t.Fatalf("missing finalized Gateway source issue = %#v", issue)
	}
	command.Source = ArtifactExportSource{Kind: RecorderGatewayColdPathArtifactExportSourceKind, ColdPathFinalizationReceiptID: "cold-path-finalization-1"}
	if issue := ValidateArtifactExportCommand(command); issue != nil {
		t.Fatalf("explicit finalized Gateway source rejected: %#v", issue)
	}
}
