package hostupdaterdomain

import "testing"

func successfulStagedProductUpdateExecutionReport(input StagedProductUpdatePlanningInput) StagedProductUpdateExecutionReport {
	evidence := make([]StagedProductUpdateLayerExecutionEvidence, 0, len(input.Specification.LayerPlan))
	for _, layer := range input.Specification.LayerPlan {
		evidence = append(evidence, StagedProductUpdateLayerExecutionEvidence{Layer: layer.Layer, State: "succeeded", ArtifactSHA256: layer.Artifact.SHA256, ObservedAt: "2026-07-17T00:01:00Z", Evidence: StagedProductUpdateEvidenceReference{Kind: "update-layer-proof", ID: "proof-" + layer.Layer}})
	}
	return StagedProductUpdateExecutionReport{SchemaVersion: HostUpdaterDocumentSchemaVersion, UpdateID: input.Invocation.UpdateID, RequestID: input.Invocation.RequestID, BootstrapEnvelopeID: input.Invocation.BootstrapEnvelopeID, UpdateSpecificationSHA256: input.Invocation.UpdateSpecificationSHA256, State: "succeeded", StartedAt: "2026-07-17T00:01:00Z", FinishedAt: "2026-07-17T00:02:00Z", LayerEvidence: evidence, Rollback: StagedProductUpdateRollbackEvidence{State: "not-required", ObservedAt: "2026-07-17T00:02:00Z"}}
}

func TestComposeStagedProductUpdateCompletionCommandBindsTheC30HandoffRevision(t *testing.T) {
	input := stagedProductUpdatePlanningInput()
	command, err := ComposeStagedProductUpdateCompletionCommand(input, successfulStagedProductUpdateExecutionReport(input))
	if err != nil || command.ExpectedJournalRevision != input.Invocation.ExpectedHandoffJournalRevision || command.Report.RequestID != input.Invocation.RequestID {
		t.Fatalf("command=%+v err=%v", command, err)
	}
}

func TestComposeStagedProductUpdateCompletionCommandRejectsEvidenceForAnotherArtifact(t *testing.T) {
	input := stagedProductUpdatePlanningInput()
	report := successfulStagedProductUpdateExecutionReport(input)
	report.LayerEvidence[1].ArtifactSHA256 = digest("f")
	if _, err := ComposeStagedProductUpdateCompletionCommand(input, report); err == nil {
		t.Fatal("expected artifact mismatch to be rejected")
	}
}
