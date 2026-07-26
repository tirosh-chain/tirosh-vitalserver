package guestproductreleasearchivecomposition

import (
	"archive/tar"
	"compress/gzip"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestComposeGuestProductReleaseArchiveProducesDeterministicC59CompatibleTarGzip(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "release")
	if err := os.MkdirAll(filepath.Join(source, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "bin", "guest-runtime"), []byte("runtime"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("guest-runtime", filepath.Join(source, "bin", "current-runtime")); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(source, "config"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "config", "deployment.json"), []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	firstOutput := filepath.Join(root, "guest-product-030.tar.gz")
	first, err := ComposeGuestProductReleaseArchive(ComposeGuestProductReleaseArchiveRequest{ReleaseSourceDirectory: source, OutputArchivePath: firstOutput})
	if err != nil {
		t.Fatalf("compose first archive: %v", err)
	}
	if first.MediaType != guestProductReleaseArchiveMediaType || first.SizeBytes < 1 || len(first.SHA256) != 64 {
		t.Fatalf("unexpected archive identity: %+v", first)
	}
	entries := readArchiveEntries(t, firstOutput)
	if entries["bin/guest-runtime"] != "regular:runtime" || entries["bin/current-runtime"] != "symlink:guest-runtime" || entries["config/deployment.json"] != "regular:{\"schemaVersion\":\"v1\"}" {
		t.Fatalf("unexpected C59 archive entries: %#v", entries)
	}
	secondOutput := filepath.Join(root, "guest-product-030-second.tar.gz")
	second, err := ComposeGuestProductReleaseArchive(ComposeGuestProductReleaseArchiveRequest{ReleaseSourceDirectory: source, OutputArchivePath: secondOutput})
	if err != nil {
		t.Fatalf("compose second archive: %v", err)
	}
	if first.SHA256 != second.SHA256 || first.SizeBytes != second.SizeBytes {
		t.Fatalf("release archive is not deterministic first=%+v second=%+v", first, second)
	}
}

func TestComposeGuestProductReleaseArchiveRejectsEscapingSymbolicLink(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "release")
	if err := os.Mkdir(source, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "runtime"), []byte("runtime"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../../outside", filepath.Join(source, "escape")); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(root, "release.tar.gz")
	if _, err := ComposeGuestProductReleaseArchive(ComposeGuestProductReleaseArchiveRequest{ReleaseSourceDirectory: source, OutputArchivePath: output}); err == nil {
		t.Fatal("expected escaping symbolic link to be rejected")
	}
	if _, err := os.Lstat(output); !os.IsNotExist(err) {
		t.Fatalf("unsafe source published an archive err=%v", err)
	}
}

func readArchiveEntries(t *testing.T, path string) map[string]string {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		t.Fatal(err)
	}
	defer gzipReader.Close()
	reader := tar.NewReader(gzipReader)
	entries := map[string]string{}
	for {
		header, err := reader.Next()
		if err == io.EOF {
			return entries
		}
		if err != nil {
			t.Fatal(err)
		}
		switch header.Typeflag {
		case tar.TypeReg:
			contents, err := io.ReadAll(reader)
			if err != nil {
				t.Fatal(err)
			}
			entries[header.Name] = "regular:" + string(contents)
		case tar.TypeSymlink:
			entries[header.Name] = "symlink:" + header.Linkname
		}
	}
}
