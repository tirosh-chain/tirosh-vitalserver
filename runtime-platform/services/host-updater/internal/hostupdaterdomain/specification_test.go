package hostupdaterdomain

import (
	"strings"
	"testing"
)

func digest(value string) string { return strings.Repeat(value, 64) }

func productUpdateLayerPlan(layerName string, dependsOn ...string) ProductUpdateLayerPlan {
	return ProductUpdateLayerPlan{
		Layer:          layerName,
		DependsOn:      dependsOn,
		Artifact:       ProductUpdateArtifact{ID: "artifact-" + layerName, RelativePath: "payload/" + layerName + ".tar", SHA256: digest("a"), SizeBytes: 1, MediaType: "application/octet-stream"},
		EffectExecutor: ProductUpdateLayerEffectExecutor{ID: "executor-" + layerName, RelativePath: "payload/executors/" + layerName, SHA256: digest("c"), SizeBytes: 1, MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-executor", ConfigurationArtifact: ProductUpdateArtifact{ID: "executor-configuration-" + layerName, RelativePath: "payload/executor-configurations/" + layerName + ".json", SHA256: digest("d"), SizeBytes: 1, MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"}},
		Rollback:       ProductUpdateLayerRollbackPlan{State: "available", Artifact: &ProductUpdateArtifact{ID: "rollback-" + layerName, RelativePath: "payload/rollback-" + layerName + ".tar", SHA256: digest("b"), SizeBytes: 1, MediaType: "application/octet-stream"}},
	}
}

func stagedProductUpdateInvocation() StagedProductUpdateInvocation {
	return StagedProductUpdateInvocation{
		SchemaVersion:                  "v1",
		UpdateID:                       "host-update-1",
		RequestID:                      "host-update-request-1",
		ExpectedHandoffJournalRevision: 3,
		BootstrapEnvelopeID:            "bootstrap-1",
		UpdateSpecificationSHA256:      digest("c"),
		LayerOrder:                     []string{ProductUpdateLayerGuestRuntime, ProductUpdateLayerContainer, ProductUpdateLayerHostPlatform},
		SpecificationRelativePath:      "payload/product-update.json",
	}
}

func stagedProductUpdatePlanningInput() StagedProductUpdatePlanningInput {
	return StagedProductUpdatePlanningInput{
		Invocation: stagedProductUpdateInvocation(),
		Specification: ProductUpdateSpecification{
			SchemaVersion:       "v1",
			ID:                  "product-update-1",
			BootstrapEnvelopeID: "bootstrap-1",
			LayerPlan: []ProductUpdateLayerPlan{
				productUpdateLayerPlan(ProductUpdateLayerGuestRuntime),
				productUpdateLayerPlan(ProductUpdateLayerContainer, ProductUpdateLayerGuestRuntime),
				productUpdateLayerPlan(ProductUpdateLayerHostPlatform, ProductUpdateLayerContainer),
			},
		},
	}
}

func TestPlanStagedProductUpdateExecutionPreservesBootstrapOrderAndExplicitDependencies(t *testing.T) {
	plan, err := PlanStagedProductUpdateExecution(stagedProductUpdatePlanningInput())
	if err != nil || len(plan.LayerPlan) != 3 || plan.LayerPlan[2].Layer != ProductUpdateLayerHostPlatform {
		t.Fatalf("plan=%+v err=%v", plan, err)
	}
}

func TestPlanStagedProductUpdateExecutionRejectsHostPlatformBeforeOtherLayers(t *testing.T) {
	value := stagedProductUpdatePlanningInput()
	value.Invocation.LayerOrder = []string{ProductUpdateLayerHostPlatform, ProductUpdateLayerContainer}
	value.Specification.LayerPlan = []ProductUpdateLayerPlan{productUpdateLayerPlan(ProductUpdateLayerHostPlatform), productUpdateLayerPlan(ProductUpdateLayerContainer, ProductUpdateLayerHostPlatform)}
	if _, err := PlanStagedProductUpdateExecution(value); err == nil {
		t.Fatal("expected early host-platform layer to be rejected")
	}
}

func TestPlanStagedProductUpdateExecutionRejectsDependencyThatHasNotExecuted(t *testing.T) {
	value := stagedProductUpdatePlanningInput()
	value.Specification.LayerPlan[0].DependsOn = []string{ProductUpdateLayerContainer}
	if _, err := PlanStagedProductUpdateExecution(value); err == nil {
		t.Fatal("expected future dependency to be rejected")
	}
}
