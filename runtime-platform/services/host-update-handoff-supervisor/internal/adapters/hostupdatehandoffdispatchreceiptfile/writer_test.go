package hostupdatehandoffdispatchreceiptfile

import (
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

func receipt() hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt {
	return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{SchemaVersion: "v1", AttemptID: "attempt-020", UpdateID: "update-020", InvocationRelativePath: "updates/update-020/invocation.json", NextUpdaterSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ExecutionMode: "execute", State: "completion-submitted", StartedAt: "2026-07-20T00:00:00Z", FinishedAt: "2026-07-20T00:00:01Z", Evidence: hostupdatehandoffsupervisordomain.EvidenceReference{Kind: "host-update-handoff-dispatch", ID: "attempt-020"}, CompletionCommandSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
}

func TestWriteHostUpdateHandoffDispatchReceiptIsIdempotentOnlyForSameAttemptEvidence(t *testing.T) {
	temporaryDirectory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	directory := filepath.Join(temporaryDirectory, "evidence")
	first, err := WriteHostUpdateHandoffDispatchReceipt(directory, receipt())
	if err != nil {
		t.Fatal(err)
	}
	second, err := WriteHostUpdateHandoffDispatchReceipt(directory, receipt())
	if err != nil || first != second {
		t.Fatalf("first=%s second=%s err=%v", first, second, err)
	}
	different := receipt()
	different.State = "failed"
	different.CompletionCommandSHA256 = ""
	different.Issue = &hostupdatehandoffsupervisordomain.DispatchIssue{Code: "different", Dependency: "fixture"}
	if _, err := WriteHostUpdateHandoffDispatchReceipt(directory, different); err == nil {
		t.Fatal("expected different C57 evidence to be rejected")
	}
}

func TestReadHostUpdateHandoffDispatchReceiptDistinguishesMissingAndPersistedEvidence(t *testing.T) {
	temporaryDirectory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	directory := filepath.Join(temporaryDirectory, "evidence")
	if _, exists, err := ReadHostUpdateHandoffDispatchReceipt(directory, "attempt-020"); err != nil || exists {
		t.Fatalf("exists=%t err=%v", exists, err)
	}
	if _, err := WriteHostUpdateHandoffDispatchReceipt(directory, receipt()); err != nil {
		t.Fatal(err)
	}
	actual, exists, err := ReadHostUpdateHandoffDispatchReceipt(directory, "attempt-020")
	if err != nil || !exists || actual != receipt() {
		t.Fatalf("actual=%+v exists=%t err=%v", actual, exists, err)
	}
}
