package stagedupdateinvocationfile

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func encoded(t *testing.T, value any) []byte {
	t.Helper()
	contents, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return contents
}

func stagedProductUpdateInput(t *testing.T) (string, hostupdaterdomain.StagedProductUpdateInvocation) {
	t.Helper()
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "payload"), 0o700); err != nil {
		t.Fatal(err)
	}
	specification := hostupdaterdomain.ProductUpdateSpecification{SchemaVersion: "v1", ID: "product-update-020", BootstrapEnvelopeID: "release-bootstrap-020", LayerPlan: []hostupdaterdomain.ProductUpdateLayerPlan{{Layer: hostupdaterdomain.ProductUpdateLayerGuestRuntime, DependsOn: []string{}, Artifact: hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime", RelativePath: "payload/guest-runtime.tar", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MediaType: "application/x-tar"}, Rollback: hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "no rollback artifact"}}, {Layer: hostupdaterdomain.ProductUpdateLayerHostPlatform, DependsOn: []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime}, Artifact: hostupdaterdomain.ProductUpdateArtifact{ID: "host-platform", RelativePath: "payload/host-platform.pkg", SHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", SizeBytes: 1, MediaType: "application/vnd.apple.installer+xml"}, Rollback: hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "no rollback artifact"}}}}
	specificationBytes := encoded(t, specification)
	if err := os.WriteFile(filepath.Join(root, "payload", "product-update.json"), specificationBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(specificationBytes)
	invocation := hostupdaterdomain.StagedProductUpdateInvocation{SchemaVersion: "v1", UpdateID: "update-020", RequestID: "update-request-020", ExpectedHandoffJournalRevision: 3, BootstrapEnvelopeID: "release-bootstrap-020", UpdateSpecificationSHA256: hex.EncodeToString(digest[:]), LayerOrder: []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime, hostupdaterdomain.ProductUpdateLayerHostPlatform}, SpecificationRelativePath: "payload/product-update.json"}
	invocationPath := filepath.Join(root, "invocation.json")
	if err := os.WriteFile(invocationPath, encoded(t, invocation), 0o600); err != nil {
		t.Fatal(err)
	}
	return invocationPath, invocation
}

func TestReadStagedProductUpdatePlanningInputReadsC30AndVerifiedC26(t *testing.T) {
	invocationPath, _ := stagedProductUpdateInput(t)
	input, err := ReadStagedProductUpdatePlanningInput(invocationPath)
	if err != nil || input.Specification.ID != "product-update-020" || input.Invocation.UpdateID != "update-020" {
		t.Fatalf("input=%+v err=%v", input, err)
	}
	if _, err := hostupdaterdomain.PlanStagedProductUpdateExecution(input); err != nil {
		t.Fatalf("plan verified staged input: %v", err)
	}
}

func TestReadStagedProductUpdatePlanningInputRejectsChangedSpecificationAfterHandoff(t *testing.T) {
	invocationPath, _ := stagedProductUpdateInput(t)
	if err := os.WriteFile(filepath.Join(filepath.Dir(invocationPath), "payload", "product-update.json"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStagedProductUpdatePlanningInput(invocationPath); err == nil {
		t.Fatal("expected changed C26 artifact to be rejected")
	}
}

func TestReadStagedProductUpdatePlanningInputRejectsTraversalBeforeSpecificationRead(t *testing.T) {
	invocationPath, invocation := stagedProductUpdateInput(t)
	invocation.SpecificationRelativePath = "payload/../product-update.json"
	if err := os.WriteFile(invocationPath, encoded(t, invocation), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStagedProductUpdatePlanningInput(invocationPath); err == nil {
		t.Fatal("expected traversal C30 to be rejected")
	}
}
