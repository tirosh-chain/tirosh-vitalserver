package hostupdaterstagedupdatecompletionapplication

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

type stagedProductUpdatePlanningInputReader struct {
	input hostupdaterdomain.StagedProductUpdatePlanningInput
}

func (reader stagedProductUpdatePlanningInputReader) Read(string) (hostupdaterdomain.StagedProductUpdatePlanningInput, error) {
	return reader.input, nil
}

type stagedProductUpdateExecutionReportReader struct {
	report hostupdaterdomain.StagedProductUpdateExecutionReport
}

func (reader stagedProductUpdateExecutionReportReader) Read(string) (hostupdaterdomain.StagedProductUpdateExecutionReport, error) {
	return reader.report, nil
}

type stagedProductUpdateCompletionCommandPublisher struct {
	command hostupdaterdomain.StagedProductUpdateCompletionCommand
}

func (publisher *stagedProductUpdateCompletionCommandPublisher) Publish(_ context.Context, _ string, command hostupdaterdomain.StagedProductUpdateCompletionCommand) error {
	publisher.command = command
	return nil
}

func stagedProductUpdateCompletionPlanningInput() hostupdaterdomain.StagedProductUpdatePlanningInput {
	artifact := hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime", RelativePath: "payload/guest-runtime.tar", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MediaType: "application/x-tar"}
	return hostupdaterdomain.StagedProductUpdatePlanningInput{Invocation: hostupdaterdomain.StagedProductUpdateInvocation{SchemaVersion: "v1", UpdateID: "update-001", RequestID: "request-001", ExpectedHandoffJournalRevision: 3, BootstrapEnvelopeID: "bootstrap-001", UpdateSpecificationSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", LayerOrder: []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime}, SpecificationRelativePath: "payload/product-update.json"}, Specification: hostupdaterdomain.ProductUpdateSpecification{SchemaVersion: "v1", ID: "specification-001", BootstrapEnvelopeID: "bootstrap-001", LayerPlan: []hostupdaterdomain.ProductUpdateLayerPlan{{Layer: hostupdaterdomain.ProductUpdateLayerGuestRuntime, Artifact: artifact, Rollback: hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "no rollback artifact"}}}}}
}

func stagedProductUpdateCompletionExecutionReport(input hostupdaterdomain.StagedProductUpdatePlanningInput) hostupdaterdomain.StagedProductUpdateExecutionReport {
	return hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: input.Invocation.UpdateID, RequestID: input.Invocation.RequestID, BootstrapEnvelopeID: input.Invocation.BootstrapEnvelopeID, UpdateSpecificationSHA256: input.Invocation.UpdateSpecificationSHA256, State: "succeeded", StartedAt: "2026-07-17T00:00:00Z", FinishedAt: "2026-07-17T00:01:00Z", LayerEvidence: []hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence{{Layer: hostupdaterdomain.ProductUpdateLayerGuestRuntime, State: "succeeded", ArtifactSHA256: input.Specification.LayerPlan[0].Artifact.SHA256, ObservedAt: "2026-07-17T00:00:30Z", Evidence: hostupdaterdomain.StagedProductUpdateEvidenceReference{Kind: "layer-proof", ID: "proof-001"}}}, Rollback: hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "not-required", ObservedAt: "2026-07-17T00:01:00Z"}}
}

func TestPublishStagedProductUpdateCompletionBindsCommandToC30HandoffRevision(t *testing.T) {
	input := stagedProductUpdateCompletionPlanningInput()
	recorder := &stagedProductUpdateCompletionCommandPublisher{}
	workflow, err := NewStagedProductUpdateCompletionWorkflow(stagedProductUpdatePlanningInputReader{input: input}, stagedProductUpdateExecutionReportReader{report: stagedProductUpdateCompletionExecutionReport(input)}, recorder)
	if err != nil {
		t.Fatal(err)
	}
	command, err := workflow.PublishStagedProductUpdateCompletion(context.Background(), "invocation.json", "report.json", "http://127.0.0.1:18330")
	if err != nil || command.ExpectedJournalRevision != 3 || recorder.command.UpdateID != input.Invocation.UpdateID {
		t.Fatalf("command=%+v published=%+v err=%v", command, recorder.command, err)
	}
}
