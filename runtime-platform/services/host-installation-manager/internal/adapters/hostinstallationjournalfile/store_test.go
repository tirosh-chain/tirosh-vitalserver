package hostinstallationjournalfile

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadHostInstallationJournalRejectsSymbolicLink(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "journal-target.json")
	if err := os.WriteFile(target, []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	journalPath := filepath.Join(root, "current-transaction.json")
	if err := os.Symlink(target, journalPath); err != nil {
		t.Fatal(err)
	}

	_, err := (HostInstallationJournalFileStore{}).ReadHostInstallationJournal(
		context.Background(),
		journalPath,
	)
	if err == nil || !strings.Contains(err.Error(), "regular non-symbolic-link") {
		t.Fatalf("err=%v", err)
	}
}

func TestReadHostInstallationJournalRejectsDecodedJournalWithoutC50Identity(t *testing.T) {
	root := t.TempDir()
	journalPath := filepath.Join(root, "current-transaction.json")
	journal := `{"schemaVersion":"v1","documentKind":"host-installation-journal","id":"journal-001","requestId":"request-001","installationId":"vitalserver-runtime-platform","releaseId":"release-001","state":"completed","updatedAt":"2026-07-18T03:00:00Z"}`
	if err := os.WriteFile(journalPath, []byte(journal), 0600); err != nil {
		t.Fatal(err)
	}
	_, err := (HostInstallationJournalFileStore{}).ReadHostInstallationJournal(context.Background(), journalPath)
	if err == nil || !strings.Contains(err.Error(), "validate Host installation journal") {
		t.Fatalf("err=%v", err)
	}
}

func TestWriteHostInstallationDocumentRejectsSymbolicLinkAncestor(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "target")
	if err := os.MkdirAll(target, 0750); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	err = WriteHostInstallationDocumentJSON(filepath.Join(link, "current-transaction.json"), map[string]string{"state": "preflight-verified"})
	if err == nil || !strings.Contains(err.Error(), "symbolic link") {
		t.Fatalf("err=%v", err)
	}
}
