package agent

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadInstallDocumentPreservesOwnerStates(t *testing.T) {
	state, version, issue := readInstallDocument("")
	if state != "unavailable" || version != nil || issue == nil {
		t.Fatalf("unconfigured owner must be explicit: state=%s version=%v issue=%v", state, version, issue)
	}

	path := filepath.Join(t.TempDir(), "install.json")
	state, version, issue = readInstallDocument(path)
	if state != "missing" || version != nil || issue != nil {
		t.Fatalf("missing owner document must remain missing: state=%s version=%v issue=%v", state, version, issue)
	}

	if err := os.WriteFile(path, []byte(`{"schemaVersion":1,"state":"installed","platformVersion":"2.0.0"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	state, version, issue = readInstallDocument(path)
	if state != "installed" || version == nil || *version != "2.0.0" || issue != nil {
		t.Fatalf("installed owner document was not preserved: state=%s version=%v issue=%v", state, version, issue)
	}

	if err := os.WriteFile(path, []byte(`{"schemaVersion":1,"state":"installed"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	state, version, issue = readInstallDocument(path)
	if state != "invalid" || version != nil || issue == nil || !strings.Contains(issue.Message, "platformVersion") {
		t.Fatalf("invalid owner must remain invalid: state=%s version=%v issue=%v", state, version, issue)
	}
}
