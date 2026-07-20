package releaseeffectreceiptfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadRejectsTrailingJSONDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "receipt.json")
	if err := os.WriteFile(path, []byte("{\"schemaVersion\":\"v1\"}\n{\"schemaVersion\":\"v1\"}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := read(path); err == nil {
		t.Fatal("expected C55 receipt with trailing JSON document to be rejected")
	}
}

func TestReadRejectsReceiptOverMaximumSize(t *testing.T) {
	path := filepath.Join(t.TempDir(), "receipt.json")
	if err := os.WriteFile(path, make([]byte, maximumReceiptBytes+1), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := read(path); err == nil {
		t.Fatal("expected oversized C55 receipt to be rejected")
	}
}
