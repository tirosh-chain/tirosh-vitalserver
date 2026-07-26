package owner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func TestPlatformWorkflowOwnerRequiresCompletedSupportArtifactEvidence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "platform-workflow.json")
	completed := contract.PlatformWorkflowOperation{
		SchemaVersion: 1,
		OperationID:   "workflow-0123456789abcdef0123456789abcdef",
		Kind:          "support-export",
		State:         "completed",
		StartedAt:     "2026-07-11T00:00:00Z",
		UpdatedAt:     "2026-07-11T00:00:01Z",
		Artifact: &contract.PlatformWorkflowArtifact{
			Path:      "/var/lib/vitalserver/support/vitalserver-support.tar.gz",
			SHA256:    strings.Repeat("a", 64),
			SizeBytes: 42,
		},
	}
	if err := WritePlatformWorkflow(path, completed); err != nil {
		t.Fatal(err)
	}
	resource := ReadPlatformWorkflow(path)
	if resource.State != "loaded" || resource.Operation == nil || resource.Operation.Artifact == nil || resource.Operation.Artifact.SizeBytes != 42 {
		t.Fatalf("support artifact evidence was not preserved: %+v", resource)
	}

	completed.Artifact = nil
	if err := WritePlatformWorkflow(path, completed); err == nil {
		t.Fatal("completed support export without artifact evidence must be rejected")
	}
	completed.Artifact = &contract.PlatformWorkflowArtifact{Path: "relative.zip", SHA256: strings.Repeat("a", 64), SizeBytes: 42}
	if err := WritePlatformWorkflow(path, completed); err == nil {
		t.Fatal("support export artifact with relative path must be rejected")
	}
}

func TestPlatformWorkflowOwnerPreservesExplicitLifecycle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "platform-workflow.json")
	accepted := contract.PlatformWorkflowOperation{
		SchemaVersion: 1,
		OperationID:   "update-1",
		Kind:          "update-apply",
		State:         "accepted",
		StartedAt:     "2026-07-11T00:00:00Z",
		UpdatedAt:     "2026-07-11T00:00:00Z",
	}
	if err := WritePlatformWorkflow(path, accepted); err != nil {
		t.Fatal(err)
	}
	resource := ReadPlatformWorkflow(path)
	if resource.State != "loaded" || resource.Operation == nil || resource.Operation.State != "accepted" {
		t.Fatalf("accepted workflow was not preserved: %+v", resource)
	}

	failed := accepted
	failed.State = "failed"
	failed.UpdatedAt = "2026-07-11T00:00:01Z"
	failed.Failure = &contract.PlatformCommandFailure{Kind: "updateApplyFailed", Message: "installer failed"}
	if err := WritePlatformWorkflow(path, failed); err != nil {
		t.Fatal(err)
	}
	resource = ReadPlatformWorkflow(path)
	if resource.Operation == nil || resource.Operation.Failure == nil || resource.Operation.Failure.Kind != "updateApplyFailed" {
		t.Fatalf("failed workflow evidence was not preserved: %+v", resource)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("workflow owner permissions=%o", info.Mode().Perm())
	}
}

func TestPlatformWorkflowOwnerRejectsInvalidTransitionsDocuments(t *testing.T) {
	path := filepath.Join(t.TempDir(), "platform-workflow.json")
	invalid := contract.PlatformWorkflowOperation{
		SchemaVersion: 1,
		OperationID:   "update-1",
		Kind:          "update-apply",
		State:         "failed",
		StartedAt:     "2026-07-11T00:00:00Z",
		UpdatedAt:     "2026-07-11T00:00:01Z",
	}
	if err := WritePlatformWorkflow(path, invalid); err == nil {
		t.Fatal("failed workflow without failure evidence must be rejected")
	}
	invalid.State = "completed"
	invalid.Failure = &contract.PlatformCommandFailure{Kind: "unexpected", Message: "must be absent"}
	if err := WritePlatformWorkflow(path, invalid); err == nil {
		t.Fatal("completed workflow with failure evidence must be rejected")
	}
}
