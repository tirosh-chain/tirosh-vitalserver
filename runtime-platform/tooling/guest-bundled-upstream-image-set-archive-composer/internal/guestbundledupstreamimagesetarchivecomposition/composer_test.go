package guestbundledupstreamimagesetarchivecomposition

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestComposeGuestBundledUpstreamImageSetArchiveCreatesDeterministicC64Layout(t *testing.T) {
	root := t.TempDir()
	compose := filepath.Join(root, "compose.yaml")
	image := filepath.Join(root, "vitalserver.tar")
	if err := os.WriteFile(compose, []byte("services: {}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(image, []byte("oci-image"), 0o600); err != nil {
		t.Fatal(err)
	}
	compositionPath := filepath.Join(root, "composition.json")
	composition := GuestBundledUpstreamImageSetArchiveComposition{SchemaVersion: "v1", ImageSetID: "bundled-upstream-030", ComposeFileSourcePath: compose, ImageArchiveSources: []GuestBundledUpstreamImageArchiveSource{{ArchivePath: "images/vitalserver.tar", SourcePath: image}}}
	bytes, err := json.Marshal(composition)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(compositionPath, append(bytes, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
	first, err := ComposeGuestBundledUpstreamImageSetArchive(ComposeGuestBundledUpstreamImageSetArchiveRequest{CompositionPath: compositionPath, OutputArchivePath: filepath.Join(root, "first.tar.gz")})
	if err != nil {
		t.Fatal(err)
	}
	if first.MediaType != imageSetArchiveMediaType || first.SizeBytes < 1 || len(first.SHA256) != 64 {
		t.Fatalf("archive=%+v", first)
	}
	entries := readArchive(t, first.ArchivePath)
	if string(entries["compose.yaml"]) != "services: {}\n" || string(entries["images/vitalserver.tar"]) != "oci-image" {
		t.Fatalf("archive entries=%q", entries)
	}
	var manifest imageSetManifest
	if err := json.Unmarshal(entries["image-set.json"], &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.SchemaVersion != "v1" || manifest.ImageSetID != "bundled-upstream-030" || manifest.ComposeFile != "compose.yaml" || len(manifest.ImageArchivePaths) != 1 || manifest.ImageArchivePaths[0] != "images/vitalserver.tar" {
		t.Fatalf("manifest=%+v", manifest)
	}
	second, err := ComposeGuestBundledUpstreamImageSetArchive(ComposeGuestBundledUpstreamImageSetArchiveRequest{CompositionPath: compositionPath, OutputArchivePath: filepath.Join(root, "second.tar.gz")})
	if err != nil {
		t.Fatal(err)
	}
	if first.SHA256 != second.SHA256 || first.SizeBytes != second.SizeBytes {
		t.Fatalf("archive must be deterministic first=%+v second=%+v", first, second)
	}
}

func TestComposeGuestBundledUpstreamImageSetArchiveRejectsUnsafeImageEntryPath(t *testing.T) {
	root := t.TempDir()
	compose, image := filepath.Join(root, "compose.yaml"), filepath.Join(root, "image.tar")
	if err := os.WriteFile(compose, []byte("services: {}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(image, []byte("oci-image"), 0o600); err != nil {
		t.Fatal(err)
	}
	compositionPath := filepath.Join(root, "composition.json")
	value := GuestBundledUpstreamImageSetArchiveComposition{SchemaVersion: "v1", ImageSetID: "bundled-upstream-030", ComposeFileSourcePath: compose, ImageArchiveSources: []GuestBundledUpstreamImageArchiveSource{{ArchivePath: "images/../escape.tar", SourcePath: image}}}
	bytes, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(compositionPath, bytes, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ComposeGuestBundledUpstreamImageSetArchive(ComposeGuestBundledUpstreamImageSetArchiveRequest{CompositionPath: compositionPath, OutputArchivePath: filepath.Join(root, "output.tar.gz")}); err == nil {
		t.Fatal("expected unsafe archive path rejection")
	}
}

func readArchive(t *testing.T, pathValue string) map[string][]byte {
	t.Helper()
	file, err := os.Open(pathValue)
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
	entries := map[string][]byte{}
	for {
		header, err := reader.Next()
		if err == io.EOF {
			return entries
		}
		if err != nil {
			t.Fatal(err)
		}
		contents, err := io.ReadAll(reader)
		if err != nil {
			t.Fatal(err)
		}
		entries[header.Name] = contents
	}
}
