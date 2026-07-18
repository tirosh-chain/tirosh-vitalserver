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
