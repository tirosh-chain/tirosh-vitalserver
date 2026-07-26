package updateexecutionreportfile

import (
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestWriteStagedProductUpdateExecutionReportPublishesAndReusesIdenticalEvidence(t *testing.T) {
	path := filepath.Join(resolvedTemporaryDirectory(t), "execution-report.json")
	report := hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-020", RequestID: "request-020", BootstrapEnvelopeID: "bootstrap-020", UpdateSpecificationSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", State: "succeeded", StartedAt: "2026-07-19T00:00:00Z", FinishedAt: "2026-07-19T00:01:00Z", LayerEvidence: []hostupdaterdomain.StagedProductUpdateLayerExecutionEvidence{{Layer: "guest-runtime", State: "succeeded", ArtifactSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", ObservedAt: "2026-07-19T00:01:00Z", Evidence: hostupdaterdomain.StagedProductUpdateEvidenceReference{Kind: "layer-effect-receipt", ID: "receipt-020"}}}, Rollback: hostupdaterdomain.StagedProductUpdateRollbackEvidence{State: "not-required", ObservedAt: "2026-07-19T00:01:00Z"}}
	if err := WriteStagedProductUpdateExecutionReport(path, report); err != nil {
		t.Fatalf("write report: %v", err)
	}
	if err := WriteStagedProductUpdateExecutionReport(path, report); err != nil {
		t.Fatalf("reuse identical report: %v", err)
	}
	read, err := (StagedProductUpdateExecutionReportFileReader{}).Read(path)
	if err != nil || read.UpdateID != report.UpdateID {
		t.Fatalf("read published report=%+v err=%v", read, err)
	}
}

func TestWriteStagedProductUpdateExecutionReportRefusesDifferentEvidenceAtSamePath(t *testing.T) {
	path := filepath.Join(resolvedTemporaryDirectory(t), "execution-report.json")
	first := hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-020"}
	if err := WriteStagedProductUpdateExecutionReport(path, first); err != nil {
		t.Fatalf("write first report: %v", err)
	}
	second := first
	second.UpdateID = "update-021"
	if err := WriteStagedProductUpdateExecutionReport(path, second); err == nil {
		t.Fatal("expected different C28 evidence to be rejected")
	}
}

func resolvedTemporaryDirectory(t *testing.T) string {
	t.Helper()
	directory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatalf("resolve temporary directory: %v", err)
	}
	return directory
}
