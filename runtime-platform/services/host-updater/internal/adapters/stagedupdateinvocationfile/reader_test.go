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
	guestRuntime := []byte("guest-runtime-release-020")
	hostPlatform := []byte("host-platform-release-020")
	if err := os.WriteFile(filepath.Join(root, "payload", "guest-runtime.tar"), guestRuntime, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "payload", "host-platform.pkg"), hostPlatform, 0o600); err != nil {
		t.Fatal(err)
	}
	guestDigest := sha256.Sum256(guestRuntime)
	hostDigest := sha256.Sum256(hostPlatform)
	guestExecutor := []byte("guest-runtime-effect-executor")
	hostExecutor := []byte("host-platform-effect-executor")
	guestExecutorConfiguration := []byte(`{"schemaVersion":"v1","executorId":"guest-runtime-executor"}`)
	hostExecutorConfiguration := []byte(`{"schemaVersion":"v1","executorId":"host-platform-executor"}`)
	if err := os.Mkdir(filepath.Join(root, "payload", "executors"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "payload", "executors", "guest-runtime-update"), guestExecutor, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "payload", "executors", "host-platform-update"), hostExecutor, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "payload", "executors", "guest-runtime-update.json"), guestExecutorConfiguration, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "payload", "executors", "host-platform-update.json"), hostExecutorConfiguration, 0o600); err != nil {
		t.Fatal(err)
	}
	guestExecutorDigest := sha256.Sum256(guestExecutor)
	hostExecutorDigest := sha256.Sum256(hostExecutor)
	guestExecutorConfigurationDigest := sha256.Sum256(guestExecutorConfiguration)
	hostExecutorConfigurationDigest := sha256.Sum256(hostExecutorConfiguration)
	specification := hostupdaterdomain.ProductUpdateSpecification{
		SchemaVersion: "v1", ID: "product-update-020", BootstrapEnvelopeID: "release-bootstrap-020",
		LayerPlan: []hostupdaterdomain.ProductUpdateLayerPlan{
			{
				Layer: hostupdaterdomain.ProductUpdateLayerGuestRuntime, DependsOn: []string{},
				Artifact:       hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime", RelativePath: "payload/guest-runtime.tar", SHA256: hex.EncodeToString(guestDigest[:]), SizeBytes: int64(len(guestRuntime)), MediaType: "application/x-tar"},
				EffectExecutor: hostupdaterdomain.ProductUpdateLayerEffectExecutor{ID: "guest-runtime-executor", RelativePath: "payload/executors/guest-runtime-update", SHA256: hex.EncodeToString(guestExecutorDigest[:]), SizeBytes: int64(len(guestExecutor)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-executor", ConfigurationArtifact: hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime-executor-configuration", RelativePath: "payload/executors/guest-runtime-update.json", SHA256: hex.EncodeToString(guestExecutorConfigurationDigest[:]), SizeBytes: int64(len(guestExecutorConfiguration)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"}},
				Rollback:       hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "no rollback artifact"},
			},
			{
				Layer: hostupdaterdomain.ProductUpdateLayerHostPlatform, DependsOn: []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime},
				Artifact:       hostupdaterdomain.ProductUpdateArtifact{ID: "host-platform", RelativePath: "payload/host-platform.pkg", SHA256: hex.EncodeToString(hostDigest[:]), SizeBytes: int64(len(hostPlatform)), MediaType: "application/vnd.apple.installer+xml"},
				EffectExecutor: hostupdaterdomain.ProductUpdateLayerEffectExecutor{ID: "host-platform-executor", RelativePath: "payload/executors/host-platform-update", SHA256: hex.EncodeToString(hostExecutorDigest[:]), SizeBytes: int64(len(hostExecutor)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-executor", ConfigurationArtifact: hostupdaterdomain.ProductUpdateArtifact{ID: "host-platform-executor-configuration", RelativePath: "payload/executors/host-platform-update.json", SHA256: hex.EncodeToString(hostExecutorConfigurationDigest[:]), SizeBytes: int64(len(hostExecutorConfiguration)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"}},
				Rollback:       hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "no rollback artifact"},
			},
		},
	}
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

func TestReadStagedProductUpdatePlanningInputRejectsMissingDeclaredLayerArtifact(t *testing.T) {
	invocationPath, _ := stagedProductUpdateInput(t)
	if err := os.Remove(filepath.Join(filepath.Dir(invocationPath), "payload", "guest-runtime.tar")); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStagedProductUpdatePlanningInput(invocationPath); err == nil {
		t.Fatal("expected missing declared layer artifact to be rejected")
	}
}

func TestReadStagedProductUpdatePlanningInputRejectsChangedDeclaredLayerArtifact(t *testing.T) {
	invocationPath, _ := stagedProductUpdateInput(t)
	if err := os.WriteFile(filepath.Join(filepath.Dir(invocationPath), "payload", "guest-runtime.tar"), []byte("different bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStagedProductUpdatePlanningInput(invocationPath); err == nil {
		t.Fatal("expected changed declared layer artifact to be rejected")
	}
}

func TestReadStagedProductUpdatePlanningInputRejectsSymlinkedLayerArtifactPath(t *testing.T) {
	invocationPath, _ := stagedProductUpdateInput(t)
	payload := filepath.Join(filepath.Dir(invocationPath), "payload")
	if err := os.Rename(filepath.Join(payload, "guest-runtime.tar"), filepath.Join(filepath.Dir(invocationPath), "guest-runtime.tar")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(filepath.Dir(invocationPath), "guest-runtime.tar"), filepath.Join(payload, "guest-runtime.tar")); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadStagedProductUpdatePlanningInput(invocationPath); err == nil {
		t.Fatal("expected symbolic layer artifact to be rejected")
	}
}
