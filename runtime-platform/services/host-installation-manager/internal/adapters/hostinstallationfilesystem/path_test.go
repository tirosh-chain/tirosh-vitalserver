package hostinstallationfilesystem

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRejectSymbolicLinkPathComponentsRejectsAnAncestorSymbolicLink(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "target")
	if err := os.MkdirAll(target, 0755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	err = RejectSymbolicLinkPathComponents(filepath.Join(link, "journal", "current-transaction.json"))
	if err == nil || !strings.Contains(err.Error(), "symbolic link") {
		t.Fatalf("err=%v", err)
	}
}

func TestRejectSymbolicLinkPathComponentsPermitsAnAbsentDescendant(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "missing", "journal", "current-transaction.json")
	if err := RejectSymbolicLinkPathComponents(path); err != nil {
		t.Fatalf("err=%v", err)
	}
}
