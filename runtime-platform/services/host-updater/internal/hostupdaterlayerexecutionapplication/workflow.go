// Package hostupdaterlayerexecutionapplication turns verified C26 layer
// effect receipts into one C28 report. It sequences declared effects, but it
// neither parses files nor decides how a Guest, container, or Host platform
// effect is implemented.
package hostupdaterlayerexecutionapplication

import (
	"context"
	"fmt"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

type StagedProductUpdatePlanningInputReader interface {
	Read(string) (hostupdaterdomain.StagedProductUpdatePlanningInput, error)
}

// StagedProductUpdateLayerEffectExecutor owns process, Guest, container, or
// platform interaction behind the fixed C26/C55 protocol. It must return a
// receipt even when the effect itself reports failed/unavailable/unsupported;
// a missing or unreadable receipt is an adapter failure, not an inferred layer
// outcome.
type StagedProductUpdateLayerEffectExecutor interface {
	Execute(context.Context, string, hostupdaterdomain.StagedProductUpdatePlanningInput, hostupdaterdomain.ProductUpdateLayerPlan, string, hostupdaterdomain.ProductUpdateArtifact) (hostupdaterdomain.StagedUpdateLayerEffectReceipt, error)
}

type StagedProductUpdateClock interface {
	Now() time.Time
}

type StagedProductUpdateLayerExecutionWorkflow struct {
	planningInputReader StagedProductUpdatePlanningInputReader
	effectExecutor      StagedProductUpdateLayerEffectExecutor
	clock               StagedProductUpdateClock
}

func NewStagedProductUpdateLayerExecutionWorkflow(
	planningInputReader StagedProductUpdatePlanningInputReader,
	effectExecutor StagedProductUpdateLayerEffectExecutor,
	clock StagedProductUpdateClock,
) (*StagedProductUpdateLayerExecutionWorkflow, error) {
	if planningInputReader == nil || effectExecutor == nil || clock == nil {
		return nil, fmt.Errorf("staged update planning reader, layer effect executor, and clock are required")
	}
	return &StagedProductUpdateLayerExecutionWorkflow{planningInputReader: planningInputReader, effectExecutor: effectExecutor, clock: clock}, nil
}

// ExecuteStagedProductUpdate performs each C26 declared apply effect in order.
// A non-successful receipt stops later effects and rolls previously successful
// layers back in reverse order. It always returns a correlated C28 report when
// C30/C26 can be read and planned; adapter failure is preserved as an explicit
// unavailable layer receipt rather than being converted to success.
func (workflow *StagedProductUpdateLayerExecutionWorkflow) ExecuteStagedProductUpdate(ctx context.Context, invocationPath string) (hostupdaterdomain.StagedProductUpdateExecutionReport, error) {
	input, err := workflow.planningInputReader.Read(invocationPath)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("read staged product update planning input: %w", err)
	}
	plan, err := hostupdaterdomain.PlanStagedProductUpdateExecution(input)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("plan staged product update: %w", err)
	}
	startedAt := workflow.now()
	evidence := make([]hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence, 0, len(plan.LayerPlan))
	applied := make([]hostupdaterdomain.ProductUpdateLayerPlan, 0, len(plan.LayerPlan))
	for _, layer := range plan.LayerPlan {
		receipt := workflow.executeEffect(ctx, invocationPath, input, layer, hostupdaterdomain.StagedUpdateLayerEffectOperationApply, layer.Artifact)
		evidence = append(evidence, layerEvidence(layer, receipt))
		if receipt.State == "succeeded" {
			applied = append(applied, layer)
			continue
		}
		rollback := workflow.rollbackAppliedLayers(ctx, invocationPath, input, applied)
		return validateProducedExecutionReport(input, failedReport(input, startedAt, workflow.now(), evidence, rollback, *receipt.Issue))
	}
	return validateProducedExecutionReport(input, hostupdaterdomain.StagedProductUpdateExecutionReport{
		SchemaVersion:             hostupdaterdomain.HostUpdaterDocumentSchemaVersion,
		UpdateID:                  input.Invocation.UpdateID,
		RequestID:                 input.Invocation.RequestID,
		BootstrapEnvelopeID:       input.Invocation.BootstrapEnvelopeID,
		UpdateSpecificationSHA256: input.Invocation.UpdateSpecificationSHA256,
		State:                     "succeeded",
		StartedAt:                 startedAt,
		FinishedAt:                workflow.now(),
		LayerEvidence:             evidence,
		Rollback:                  hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "not-required", ObservedAt: workflow.now()},
	})
}

func validateProducedExecutionReport(input hostupdaterdomain.StagedProductUpdatePlanningInput, report hostupdaterdomain.StagedProductUpdateExecutionReport) (hostupdaterdomain.StagedProductUpdateExecutionReport, error) {
	if err := hostupdaterdomain.ValidateStagedProductUpdateExecutionReport(input, report); err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("validate produced C28 execution report: %w", err)
	}
	return report, nil
}

func (workflow *StagedProductUpdateLayerExecutionWorkflow) executeEffect(
	ctx context.Context,
	invocationPath string,
	input hostupdaterdomain.StagedProductUpdatePlanningInput,
	layer hostupdaterdomain.ProductUpdateLayerPlan,
	operation string,
	artifact hostupdaterdomain.ProductUpdateArtifact,
) hostupdaterdomain.StagedUpdateLayerEffectReceipt {
	receipt, err := workflow.effectExecutor.Execute(ctx, invocationPath, input, layer, operation, artifact)
	if err != nil {
		return unavailableReceipt(input, layer, operation, artifact, workflow.now(), "layer-effect-executor-receipt-unavailable", "the declared layer effect executor did not produce a readable receipt")
	}
	if err := hostupdaterdomain.ValidateStagedUpdateLayerEffectReceipt(input, layer, operation, artifact, receipt); err != nil {
		return unavailableReceipt(input, layer, operation, artifact, workflow.now(), "layer-effect-executor-receipt-invalid", "the declared layer effect executor produced an invalid receipt")
	}
	return receipt
}

func (workflow *StagedProductUpdateLayerExecutionWorkflow) rollbackAppliedLayers(ctx context.Context, invocationPath string, input hostupdaterdomain.StagedProductUpdatePlanningInput, applied []hostupdaterdomain.ProductUpdateLayerPlan) hostupdaterdomain.StagedProductUpdateRollbackEvidence {
	if len(applied) == 0 {
		return hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "not-required", ObservedAt: workflow.now()}
	}
	for index := len(applied) - 1; index >= 0; index-- {
		layer := applied[index]
		if layer.Rollback.State != "available" {
			return hostupdaterdomain.StagedProductUpdateRollbackEvidence{
				State:      "not-attempted",
				ObservedAt: workflow.now(),
				Issue:      &hostupdaterdomain.StagedProductUpdateIssue{Code: "rollback-artifact-unsupported", Message: layer.Rollback.Reason, Dependency: "staged-layer-effect-executor"},
			}
		}
		receipt := workflow.executeEffect(ctx, invocationPath, input, layer, hostupdaterdomain.StagedUpdateLayerEffectOperationRollback, *layer.Rollback.Artifact)
		if receipt.State != "succeeded" {
			return hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "failed", ObservedAt: receipt.ObservedAt, Evidence: &receipt.Evidence, Issue: receipt.Issue}
		}
	}
	return hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "succeeded", ObservedAt: workflow.now(), Evidence: &hostupdaterdomain.StagedProductUpdateEvidenceReference{Kind: "staged-update-rollback", ID: input.Invocation.UpdateID + ":rollback"}}
}

func (workflow *StagedProductUpdateLayerExecutionWorkflow) now() string {
	return workflow.clock.Now().UTC().Format(time.RFC3339)
}

func unavailableReceipt(input hostupdaterdomain.StagedProductUpdatePlanningInput, layer hostupdaterdomain.ProductUpdateLayerPlan, operation string, artifact hostupdaterdomain.ProductUpdateArtifact, observedAt string, code string, message string) hostupdaterdomain.StagedUpdateLayerEffectReceipt {
	return hostupdaterdomain.StagedUpdateLayerEffectReceipt{
		SchemaVersion:    hostupdaterdomain.HostUpdaterDocumentSchemaVersion,
		UpdateID:         input.Invocation.UpdateID,
		Layer:            layer.Layer,
		EffectExecutorID: layer.EffectExecutor.ID,
		Operation:        operation,
		ArtifactSHA256:   artifact.SHA256,
		State:            "unavailable",
		ObservedAt:       observedAt,
		Evidence:         hostupdaterdomain.StagedProductUpdateEvidenceReference{Kind: "staged-layer-effect-executor", ID: input.Invocation.UpdateID + ":" + layer.Layer + ":" + operation},
		Issue:            &hostupdaterdomain.StagedProductUpdateIssue{Code: code, Message: message, Retryable: boolPointer(true), Dependency: "staged-layer-effect-executor"},
	}
}

func layerEvidence(layer hostupdaterdomain.ProductUpdateLayerPlan, receipt hostupdaterdomain.StagedUpdateLayerEffectReceipt) hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence {
	return hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence{Layer: layer.Layer, State: receipt.State, ArtifactSHA256: receipt.ArtifactSHA256, ObservedAt: receipt.ObservedAt, Evidence: receipt.Evidence, Issue: receipt.Issue}
}

func failedReport(input hostupdaterdomain.StagedProductUpdatePlanningInput, startedAt string, finishedAt string, evidence []hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence, rollback hostupdaterdomain.StagedProductUpdateRollbackEvidence, failure hostupdaterdomain.StagedProductUpdateIssue) hostupdaterdomain.StagedProductUpdateExecutionReport {
	return hostupdaterdomain.StagedProductUpdateExecutionReport{
		SchemaVersion:             hostupdaterdomain.HostUpdaterDocumentSchemaVersion,
		UpdateID:                  input.Invocation.UpdateID,
		RequestID:                 input.Invocation.RequestID,
		BootstrapEnvelopeID:       input.Invocation.BootstrapEnvelopeID,
		UpdateSpecificationSHA256: input.Invocation.UpdateSpecificationSHA256,
		State:                     "failed",
		StartedAt:                 startedAt,
		FinishedAt:                finishedAt,
		LayerEvidence:             evidence,
		Rollback:                  rollback,
		Failure:                   &failure,
	}
}

func boolPointer(value bool) *bool { return &value }
