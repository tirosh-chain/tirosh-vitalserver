package hostupdaterdomain

import "testing"

func TestValidateStagedUpdateLayerEffectReceiptAcceptsCorrelatedSucceededReceipt(t *testing.T) {
	input := stagedProductUpdatePlanningInput()
	input.Invocation.LayerOrder = []string{ProductUpdateLayerGuestRuntime}
	input.Specification.LayerPlan = input.Specification.LayerPlan[:1]
	layer := input.Specification.LayerPlan[0]
	receipt := StagedUpdateLayerEffectReceipt{
		SchemaVersion:    HostUpdaterDocumentSchemaVersion,
		UpdateID:         input.Invocation.UpdateID,
		Layer:            layer.Layer,
		EffectExecutorID: layer.EffectExecutor.ID,
		Operation:        StagedUpdateLayerEffectOperationApply,
		ArtifactSHA256:   layer.Artifact.SHA256,
		State:            "succeeded",
		ObservedAt:       "2026-07-19T00:00:00Z",
		Evidence:         StagedProductUpdateEvidenceReference{Kind: "layer-effect-receipt", ID: "receipt-guest-runtime"},
	}

	if err := ValidateStagedUpdateLayerEffectReceipt(input, layer, StagedUpdateLayerEffectOperationApply, layer.Artifact, receipt); err != nil {
		t.Fatalf("validate receipt: %v", err)
	}
}

func TestValidateStagedUpdateLayerEffectReceiptRejectsDifferentExecutor(t *testing.T) {
	input := stagedProductUpdatePlanningInput()
	input.Invocation.LayerOrder = []string{ProductUpdateLayerGuestRuntime}
	input.Specification.LayerPlan = input.Specification.LayerPlan[:1]
	layer := input.Specification.LayerPlan[0]
	receipt := StagedUpdateLayerEffectReceipt{
		SchemaVersion:    HostUpdaterDocumentSchemaVersion,
		UpdateID:         input.Invocation.UpdateID,
		Layer:            layer.Layer,
		EffectExecutorID: "different-executor",
		Operation:        StagedUpdateLayerEffectOperationApply,
		ArtifactSHA256:   layer.Artifact.SHA256,
		State:            "succeeded",
		ObservedAt:       "2026-07-19T00:00:00Z",
		Evidence:         StagedProductUpdateEvidenceReference{Kind: "layer-effect-receipt", ID: "receipt-guest-runtime"},
	}

	if err := ValidateStagedUpdateLayerEffectReceipt(input, layer, StagedUpdateLayerEffectOperationApply, layer.Artifact, receipt); err == nil {
		t.Fatal("expected mismatched executor to fail validation")
	}
}
