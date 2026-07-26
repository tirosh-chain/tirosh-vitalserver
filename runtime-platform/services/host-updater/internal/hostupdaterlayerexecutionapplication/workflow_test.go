package hostupdaterlayerexecutionapplication

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

type staticPlanningInputReader struct {
	input hostupdaterdomain.StagedProductUpdatePlanningInput
}

func (reader staticPlanningInputReader) Read(string) (hostupdaterdomain.StagedProductUpdatePlanningInput, error) {
	return reader.input, nil
}

type fixedStagedProductUpdateClock struct{ now time.Time }

func (clock fixedStagedProductUpdateClock) Now() time.Time { return clock.now }

type receiptByEffectExecutor struct {
	receipts map[string]hostupdaterdomain.StagedUpdateLayerEffectReceipt
	errors   map[string]error
}

func (executor receiptByEffectExecutor) Execute(_ context.Context, _ string, _ hostupdaterdomain.StagedProductUpdatePlanningInput, layer hostupdaterdomain.ProductUpdateLayerPlan, operation string, _ hostupdaterdomain.ProductUpdateArtifact) (hostupdaterdomain.StagedUpdateLayerEffectReceipt, error) {
	key := layer.Layer + ":" + operation
	if err := executor.errors[key]; err != nil {
		return hostupdaterdomain.StagedUpdateLayerEffectReceipt{}, err
	}
	return executor.receipts[key], nil
}

func TestExecuteStagedProductUpdateCreatesSucceededReportFromEveryCorrelatedReceipt(t *testing.T) {
	input := planningInput(t, []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime, hostupdaterdomain.ProductUpdateLayerContainer})
	receipts := map[string]hostupdaterdomain.StagedUpdateLayerEffectReceipt{}
	for _, layer := range input.Specification.LayerPlan {
		receipts[layer.Layer+":apply"] = effectReceipt(input, layer, "apply", layer.Artifact, "succeeded", nil)
	}
	workflow, err := NewStagedProductUpdateLayerExecutionWorkflow(staticPlanningInputReader{input: input}, receiptByEffectExecutor{receipts: receipts}, fixedStagedProductUpdateClock{now: time.Date(2026, 7, 19, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("configure workflow: %v", err)
	}

	report, err := workflow.ExecuteStagedProductUpdate(context.Background(), "/host/staging/invocation.json")
	if err != nil {
		t.Fatalf("execute staged update: %v", err)
	}
	if report.State != "succeeded" || len(report.LayerEvidence) != 2 || report.Rollback.State != "not-required" {
		t.Fatalf("unexpected report: %+v", report)
	}
	if err := hostupdaterdomain.ValidateStagedProductUpdateExecutionReport(input, report); err != nil {
		t.Fatalf("validate produced C28 report: %v", err)
	}
}

func TestExecuteStagedProductUpdateRollsBackAppliedLayersAfterTypedFailure(t *testing.T) {
	input := planningInput(t, []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime, hostupdaterdomain.ProductUpdateLayerContainer})
	guest := input.Specification.LayerPlan[0]
	container := input.Specification.LayerPlan[1]
	failure := &hostupdaterdomain.StagedProductUpdateIssue{Code: "container-apply-failed", Dependency: "container-runtime"}
	receipts := map[string]hostupdaterdomain.StagedUpdateLayerEffectReceipt{
		"guest-runtime:apply":    effectReceipt(input, guest, "apply", guest.Artifact, "succeeded", nil),
		"container:apply":        effectReceipt(input, container, "apply", container.Artifact, "failed", failure),
		"guest-runtime:rollback": effectReceipt(input, guest, "rollback", *guest.Rollback.Artifact, "succeeded", nil),
	}
	workflow, err := NewStagedProductUpdateLayerExecutionWorkflow(staticPlanningInputReader{input: input}, receiptByEffectExecutor{receipts: receipts}, fixedStagedProductUpdateClock{now: time.Date(2026, 7, 19, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("configure workflow: %v", err)
	}

	report, err := workflow.ExecuteStagedProductUpdate(context.Background(), "/host/staging/invocation.json")
	if err != nil {
		t.Fatalf("execute staged update: %v", err)
	}
	if report.State != "failed" || len(report.LayerEvidence) != 2 || report.LayerEvidence[1].State != "failed" || report.Rollback.State != "succeeded" {
		t.Fatalf("unexpected failed report: %+v", report)
	}
	if err := hostupdaterdomain.ValidateStagedProductUpdateExecutionReport(input, report); err != nil {
		t.Fatalf("validate produced C28 report: %v", err)
	}
}

func TestExecuteStagedProductUpdateRepresentsMissingReceiptAsUnavailable(t *testing.T) {
	input := planningInput(t, []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime})
	workflow, err := NewStagedProductUpdateLayerExecutionWorkflow(staticPlanningInputReader{input: input}, receiptByEffectExecutor{errors: map[string]error{"guest-runtime:apply": fmt.Errorf("receipt path unreadable")}}, fixedStagedProductUpdateClock{now: time.Date(2026, 7, 19, 0, 0, 0, 0, time.UTC)})
	if err != nil {
		t.Fatalf("configure workflow: %v", err)
	}

	report, err := workflow.ExecuteStagedProductUpdate(context.Background(), "/host/staging/invocation.json")
	if err != nil {
		t.Fatalf("execute staged update: %v", err)
	}
	if report.State != "failed" || report.LayerEvidence[0].State != "unavailable" || report.Failure == nil || report.Failure.Code != "layer-effect-executor-receipt-unavailable" {
		t.Fatalf("unexpected unavailable report: %+v", report)
	}
	if err := hostupdaterdomain.ValidateStagedProductUpdateExecutionReport(input, report); err != nil {
		t.Fatalf("validate produced C28 report: %v", err)
	}
}

func planningInput(t *testing.T, layers []string) hostupdaterdomain.StagedProductUpdatePlanningInput {
	t.Helper()
	input := hostupdaterdomain.StagedProductUpdatePlanningInput{
		Invocation: hostupdaterdomain.StagedProductUpdateInvocation{
			SchemaVersion: "v1", UpdateID: "update-020", RequestID: "request-020", ExpectedHandoffJournalRevision: 3,
			BootstrapEnvelopeID: "bootstrap-020", UpdateSpecificationSHA256: digest("f"), LayerOrder: layers, SpecificationRelativePath: "payload/product-update.json",
		},
		Specification: hostupdaterdomain.ProductUpdateSpecification{SchemaVersion: "v1", ID: "specification-020", BootstrapEnvelopeID: "bootstrap-020"},
	}
	for index, layerName := range layers {
		artifact := hostupdaterdomain.ProductUpdateArtifact{ID: layerName + "-artifact", RelativePath: "payload/" + layerName + ".tar", SHA256: digest(string(rune('a' + index))), SizeBytes: 1, MediaType: "application/x-tar"}
		rollback := hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "available", Artifact: &hostupdaterdomain.ProductUpdateArtifact{ID: layerName + "-rollback", RelativePath: "payload/" + layerName + "-rollback.tar", SHA256: digest(string(rune('c' + index))), SizeBytes: 1, MediaType: "application/x-tar"}}
		input.Specification.LayerPlan = append(input.Specification.LayerPlan, hostupdaterdomain.ProductUpdateLayerPlan{
			Layer: layerName,
			DependsOn: func() []string {
				if index == 0 {
					return []string{}
				}
				return []string{layers[index-1]}
			}(),
			Artifact:       artifact,
			EffectExecutor: hostupdaterdomain.ProductUpdateLayerEffectExecutor{ID: layerName + "-executor", RelativePath: "payload/executors/" + layerName, SHA256: digest(string(rune('e' + index))), SizeBytes: 1, MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-executor", ConfigurationArtifact: hostupdaterdomain.ProductUpdateArtifact{ID: layerName + "-executor-configuration", RelativePath: "payload/executor-configurations/" + layerName + ".json", SHA256: digest(string(rune('b' + index))), SizeBytes: 1, MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"}},
			Rollback:       rollback,
		})
	}
	return input
}

func effectReceipt(input hostupdaterdomain.StagedProductUpdatePlanningInput, layer hostupdaterdomain.ProductUpdateLayerPlan, operation string, artifact hostupdaterdomain.ProductUpdateArtifact, state string, issue *hostupdaterdomain.StagedProductUpdateIssue) hostupdaterdomain.StagedUpdateLayerEffectReceipt {
	return hostupdaterdomain.StagedUpdateLayerEffectReceipt{
		SchemaVersion: "v1", UpdateID: input.Invocation.UpdateID, Layer: layer.Layer, EffectExecutorID: layer.EffectExecutor.ID,
		Operation: operation, ArtifactSHA256: artifact.SHA256, State: state, ObservedAt: "2026-07-19T00:00:00Z",
		Evidence: hostupdaterdomain.StagedProductUpdateEvidenceReference{Kind: "layer-effect-receipt", ID: layer.Layer + ":" + operation}, Issue: issue,
	}
}

func digest(value string) string {
	for len(value) < 64 {
		value += value
	}
	return value[:64]
}
