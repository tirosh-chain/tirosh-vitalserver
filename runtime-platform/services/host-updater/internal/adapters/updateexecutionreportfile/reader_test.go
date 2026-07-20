package updateexecutionreportfile

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestStagedProductUpdateExecutionReportFileReaderRejectsUnknownC28Fields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "report.json")
	report := map[string]any{"schemaVersion": "v1", "unknown": true}
	contents, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := (StagedProductUpdateExecutionReportFileReader{}).Read(path); err == nil {
		t.Fatal("expected unknown C28 field to be rejected")
	}
}

func TestStagedProductUpdateExecutionReportFileReaderReadsOneExplicitC28Document(t *testing.T) {
	path := filepath.Join(t.TempDir(), "report.json")
	report := hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-001"}
	contents, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	actual, err := (StagedProductUpdateExecutionReportFileReader{}).Read(path)
	if err != nil || actual.UpdateID != report.UpdateID {
		t.Fatalf("report=%+v err=%v", actual, err)
	}
}

func TestWriteStagedProductUpdateExecutionReportWritesOneIdempotentDocument(t *testing.T) {
	directory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatalf("resolve temporary directory: %v", err)
	}
	path := filepath.Join(directory, "written-report.json")
	report := hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-001"}
	if err := WriteStagedProductUpdateExecutionReport(path, report); err != nil {
		t.Fatalf("write C28 report: %v", err)
	}
	if err := WriteStagedProductUpdateExecutionReport(path, report); err != nil {
		t.Fatalf("repeat identical C28 report: %v", err)
	}
	actual, err := (StagedProductUpdateExecutionReportFileReader{}).Read(path)
	if err != nil || actual.UpdateID != report.UpdateID {
		t.Fatalf("read written C28 report=%+v err=%v", actual, err)
	}
}

func TestWriteStagedProductUpdateExecutionReportRejectsReplacementWithDifferentEvidence(t *testing.T) {
	directory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatalf("resolve temporary directory: %v", err)
	}
	path := filepath.Join(directory, "report.json")
	if err := WriteStagedProductUpdateExecutionReport(path, hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-001"}); err != nil {
		t.Fatal(err)
	}
	if err := WriteStagedProductUpdateExecutionReport(path, hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-002"}); err == nil {
		t.Fatal("expected different C28 evidence to be rejected")
	}
}

func TestWriteStagedProductUpdateExecutionReportRequiresAbsoluteHostOwnedPath(t *testing.T) {
	if err := WriteStagedProductUpdateExecutionReport("report.json", hostupdaterdomain.StagedProductUpdateExecutionReport{}); err == nil {
		t.Fatal("expected relative C28 report output path to be rejected")
	}
}
