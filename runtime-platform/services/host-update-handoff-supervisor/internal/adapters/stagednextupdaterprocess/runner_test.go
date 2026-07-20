package stagednextupdaterprocess

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

func TestValidateCompletionCommandRejectsDifferentHandoffRevision(t *testing.T) {
	input := hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{UpdateID: "update-020", ExpectedHandoffJournalRevision: 3}
	contents := []byte(`{"schemaVersion":"v1","updateId":"update-020","expectedJournalRevision":4,"report":{}}`)
	if err := validateCompletionCommand(contents, input); err == nil {
		t.Fatal("expected different C27 revision to be rejected")
	}
}

func TestRunnerUsesOnlyFixedArgumentsAndReturnsCompletionCommandDigest(t *testing.T) {
	directory := t.TempDir()
	updaterPath := filepath.Join(directory, "next-updater")
	completionDescriptor := filepath.Join(directory, "host-administration.json")
	if err := os.WriteFile(completionDescriptor, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"/tmp/host.sock"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	script := "#!/bin/sh\nif [ \"$1\" != \"--mode\" ] || [ \"$3\" != \"--invocation\" ] || [ \"$5\" != \"--report\" ]; then exit 71; fi\nif [ \"$2\" = \"execute\" ]; then\n  if [ \"$7\" != \"--layer-effect-receipt-directory\" ] || [ \"$9\" != \"--layer-effect-timeout\" ]; then exit 72; fi\n  exit 0\nfi\nif [ \"$2\" = \"complete\" ]; then\n  if [ \"$7\" != \"--completion-descriptor\" ] || [ \"$9\" != \"--completion-timeout\" ]; then exit 73; fi\n  printf '%s\\n' '{\"schemaVersion\":\"v1\",\"updateId\":\"update-020\",\"expectedJournalRevision\":3,\"report\":{}}'\n  exit 0\nfi\nexit 74\n"
	if err := os.WriteFile(updaterPath, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	input := hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{UpdateID: "update-020", InvocationRelativePath: "updates/update-020/invocation.json", InvocationPath: filepath.Join(directory, "invocation.json"), ExpectedHandoffJournalRevision: 3, NextUpdaterPath: updaterPath, NextUpdaterSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ExecutionReportPath: filepath.Join(directory, "report.json"), LayerEffectReceiptPath: filepath.Join(directory, "receipts"), CompletionDescriptorPath: completionDescriptor, LayerEffectTimeoutMilliseconds: 1000, CompletionTimeoutMilliseconds: 1000, ExecutionMode: "execute"}
	submission, err := (StagedNextUpdaterProcessRunner{}).Dispatch(context.Background(), input)
	if err != nil || submission.CompletionCommandSHA256 == "" {
		t.Fatalf("submission=%+v err=%v", submission, err)
	}
}

func TestRunnerWithDurableExecutionReportCallsOnlyCompletion(t *testing.T) {
	directory := t.TempDir()
	updaterPath := filepath.Join(directory, "next-updater")
	completionDescriptor := filepath.Join(directory, "host-administration.json")
	executionMarker := filepath.Join(directory, "layer-effects-were-replayed")
	if err := os.WriteFile(completionDescriptor, []byte(`{"schemaVersion":"v1","transport":"unix-domain-socket","address":"/tmp/host.sock"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	script := "#!/bin/sh\nif [ \"$1\" != \"--mode\" ]; then exit 71; fi\nif [ \"$2\" = \"execute\" ]; then\n  /usr/bin/touch '" + executionMarker + "'\n  exit 0\nfi\nif [ \"$2\" = \"complete\" ]; then\n  printf '%s\\n' '{\"schemaVersion\":\"v1\",\"updateId\":\"update-020\",\"expectedJournalRevision\":3,\"report\":{}}'\n  exit 0\nfi\nexit 72\n"
	if err := os.WriteFile(updaterPath, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	input := hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{UpdateID: "update-020", InvocationRelativePath: "updates/update-020/invocation.json", InvocationPath: filepath.Join(directory, "invocation.json"), ExpectedHandoffJournalRevision: 3, NextUpdaterPath: updaterPath, NextUpdaterSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ExecutionReportPath: filepath.Join(directory, "already-durable-report.json"), LayerEffectReceiptPath: filepath.Join(directory, "receipts"), CompletionDescriptorPath: completionDescriptor, LayerEffectTimeoutMilliseconds: 1000, CompletionTimeoutMilliseconds: 1000, ExecutionMode: "complete"}
	if _, err := (StagedNextUpdaterProcessRunner{}).Dispatch(context.Background(), input); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(executionMarker); !os.IsNotExist(err) {
		t.Fatalf("durable C28 recovery invoked execute again: %v", err)
	}
}
