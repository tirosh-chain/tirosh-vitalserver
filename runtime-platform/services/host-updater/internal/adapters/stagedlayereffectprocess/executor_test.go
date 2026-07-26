package stagedlayereffectprocess

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestStagedLayerEffectProcessExecutorAcceptsAReceiptFromTheFixedProtocol(t *testing.T) {
	stage := t.TempDir()
	receipts := t.TempDir()
	if err := os.MkdirAll(filepath.Join(stage, "payload", "executors"), 0o700); err != nil {
		t.Fatal(err)
	}
	artifactBytes := []byte("guest-runtime-artifact")
	artifact := hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime-020", RelativePath: "payload/guest-runtime.tar", SHA256: digest(artifactBytes), SizeBytes: int64(len(artifactBytes)), MediaType: "application/x-tar"}
	if err := os.WriteFile(filepath.Join(stage, artifact.RelativePath), artifactBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	const executorID = "guest-runtime-executor"
	executorRelativePath := "payload/executors/guest-runtime-update"
	if runtime.GOOS == "windows" {
		executorRelativePath += ".exe"
	}
	executorPath := filepath.Join(stage, executorRelativePath)
	executorBytes := writeLayerEffectExecutorFixture(t, executorPath, executorID)
	configurationBytes := []byte(`{"schemaVersion":"v1","executorId":"guest-runtime-executor"}`)
	executor := hostupdaterdomain.ProductUpdateLayerEffectExecutor{ID: executorID, RelativePath: executorRelativePath, SHA256: digest(executorBytes), SizeBytes: int64(len(executorBytes)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-executor", ConfigurationArtifact: hostupdaterdomain.ProductUpdateArtifact{ID: "guest-runtime-executor-configuration", RelativePath: "payload/executor-configurations/guest-runtime.json", SHA256: digest(configurationBytes), SizeBytes: int64(len(configurationBytes)), MediaType: "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"}}
	if err := os.MkdirAll(filepath.Join(stage, "payload", "executor-configurations"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stage, executor.ConfigurationArtifact.RelativePath), configurationBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	layer := hostupdaterdomain.ProductUpdateLayerPlan{Layer: hostupdaterdomain.ProductUpdateLayerGuestRuntime, Artifact: artifact, EffectExecutor: executor, Rollback: hostupdaterdomain.ProductUpdateLayerRollbackPlan{State: "unsupported", Reason: "fixture rollback unavailable"}}
	input := hostupdaterdomain.StagedProductUpdatePlanningInput{Invocation: hostupdaterdomain.StagedProductUpdateInvocation{SchemaVersion: "v1", UpdateID: "update-020", RequestID: "request-020", ExpectedHandoffJournalRevision: 3, BootstrapEnvelopeID: "bootstrap-020", UpdateSpecificationSHA256: digest([]byte("specification")), LayerOrder: []string{hostupdaterdomain.ProductUpdateLayerGuestRuntime}, SpecificationRelativePath: "payload/product-update.json"}, Specification: hostupdaterdomain.ProductUpdateSpecification{SchemaVersion: "v1", ID: "specification-020", BootstrapEnvelopeID: "bootstrap-020", LayerPlan: []hostupdaterdomain.ProductUpdateLayerPlan{layer}}}
	invocationPath := filepath.Join(stage, "invocation.json")
	if err := os.WriteFile(invocationPath, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	process, err := NewStagedLayerEffectProcessExecutor(StagedLayerEffectProcessExecutorConfig{StagingDirectory: stage, ReceiptDirectory: receipts})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := process.Execute(context.Background(), invocationPath, input, layer, hostupdaterdomain.StagedUpdateLayerEffectOperationApply, artifact)
	if err != nil {
		t.Fatalf("execute fixed layer effect protocol: %v", err)
	}
	if err := hostupdaterdomain.ValidateStagedUpdateLayerEffectReceipt(input, layer, hostupdaterdomain.StagedUpdateLayerEffectOperationApply, artifact, receipt); err != nil {
		t.Fatalf("validate C55: %v receipt=%+v", err, receipt)
	}
}

func writeLayerEffectExecutorFixture(t *testing.T, path string, executorID string) []byte {
	t.Helper()
	if runtime.GOOS == "windows" {
		_, testFile, _, ok := runtime.Caller(0)
		if !ok {
			t.Fatal("resolve staged layer effect fixture source directory")
		}
		command := exec.Command("go", "build", "-trimpath", "-o", path, "./testdata/layer-effect-executor")
		command.Dir = filepath.Dir(testFile)
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("build Windows staged layer effect fixture: %v output=%s", err, output)
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read Windows staged layer effect fixture: %v", err)
		}
		return contents
	}
	script := fmt.Sprintf(`#!/bin/sh
	if [ "$1" != "--protocol-version" ] || [ "$2" != "v1" ] || [ "$3" != "--effect-executor-id" ] || [ "$4" != "%s" ] || [ "$5" != "--effect-configuration-path" ] || [ "$7" != "--receipt-path" ] || [ "$9" != "--update-id" ] || [ "${11}" != "--layer" ] || [ "${13}" != "--operation" ] || [ "${15}" != "--artifact-path" ] || [ "${17}" != "--artifact-sha256" ]; then
  exit 73
fi
printf '{"schemaVersion":"v1","updateId":"%%s","layer":"%%s","effectExecutorId":"%s","operation":"%%s","artifactSha256":"%%s","state":"succeeded","observedAt":"2026-07-19T00:00:00Z","evidence":{"kind":"layer-effect-receipt","id":"%%s-%%s"}}\n' "${10}" "${12}" "${14}" "${18}" "${12}" "${14}" > "$8"
`, executorID, executorID)
	executorBytes := []byte(script)
	if err := os.WriteFile(path, executorBytes, 0o700); err != nil {
		t.Fatalf("write POSIX staged layer effect fixture: %v", err)
	}
	return executorBytes
}

func digest(contents []byte) string {
	value := sha256.Sum256(contents)
	return hex.EncodeToString(value[:])
}
