package guestbundledupstreamimagesetfilesystem

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

func TestImageSetArchiveStagerPublishesOnlyVerifiedDeclaredLayout(t *testing.T) {
	archive := imageSetArchive(t)
	digest := sha256.Sum256(archive)
	configuration := configuration(t)
	stager, err := NewImageSetArchiveFilesystemStager(configuration)
	if err != nil {
		t.Fatal(err)
	}
	command := guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{SchemaVersion: "v1", UpdateID: "update-030", ExpectedActiveImageSet: guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: "active", ImageSetID: "bundled-upstream-020"}, TargetImageSet: guestbundledupstreamimagesetmanagerdomain.ImageSetTarget{ImageSetID: "bundled-upstream-030", Artifact: guestbundledupstreamimagesetmanagerdomain.ImageSetArtifact{SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(archive)), MediaType: guestbundledupstreamimagesetmanagerdomain.ImageSetArchiveMediaType}}, RequestedAt: "2026-07-20T00:00:00Z"}
	directory, failure := stager.StageImageSetArchive(context.Background(), command, bytes.NewReader(archive))
	if failure != nil {
		t.Fatalf("stage failure=%+v", failure)
	}
	composeFile, imageArchives, err := ReadStagedImageSetManifest(directory)
	if err != nil {
		t.Fatal(err)
	}
	if composeFile != "compose.yaml" || len(imageArchives) != 1 || imageArchives[0] != "images/vitalserver.tar" {
		t.Fatalf("compose=%q images=%v", composeFile, imageArchives)
	}
	if info, err := os.Lstat(filepath.Join(directory, "images", "vitalserver.tar")); err != nil || !info.Mode().IsRegular() {
		t.Fatalf("staged image archive missing: %v info=%v", err, info)
	}
}

func TestActiveImageSetRepositoryRequiresExplicitInitialProvisioning(t *testing.T) {
	configuration := configuration(t)
	repository, err := NewActiveImageSetFileRepository(configuration)
	if err != nil {
		t.Fatal(err)
	}
	if _, failure := repository.ReadActiveImageSet(context.Background()); failure == nil || failure.Issue.Code != "active-image-set-state-missing" {
		t.Fatalf("missing state was accepted: %+v", failure)
	}
	if failure := repository.InitializeActiveImageSet(context.Background(), guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned}); failure != nil {
		t.Fatalf("initialize failure=%+v", failure)
	}
	selection, failure := repository.ReadActiveImageSet(context.Background())
	if failure != nil || selection.State != guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned {
		t.Fatalf("explicit selection=%+v failure=%+v", selection, failure)
	}
	if failure := repository.InitializeActiveImageSet(context.Background(), guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned}); failure == nil || failure.Issue.Code != "initial-active-image-set-already-provisioned" {
		t.Fatalf("duplicate initialization was accepted: %+v", failure)
	}
	if err := os.WriteFile(filepath.Join(configuration.StateDirectory, "active-image-set.json"), []byte(`{"state":"unknown"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, failure = repository.ReadActiveImageSet(context.Background()); failure == nil || failure.Issue.Code != "active-image-set-state-invalid" {
		t.Fatalf("invalid state was accepted: %+v", failure)
	}
}

func configuration(t *testing.T) guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration {
	t.Helper()
	root := t.TempDir()
	return guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration{ManagerID: "bundled-upstream-image-set-manager", StateDirectory: filepath.Join(root, "state"), StagingDirectory: filepath.Join(root, "state", "staging"), StateDirectoryMode: "0700", MaximumImageSetArtifactBytes: 1024 * 1024, ContainerEngineExecutablePath: "/usr/bin/docker", ContainerEngineComposeProjectID: "vitalserver-bundled-upstream"}
}
func imageSetArchive(t *testing.T) []byte {
	t.Helper()
	var contents bytes.Buffer
	gzipWriter := gzip.NewWriter(&contents)
	tarWriter := tar.NewWriter(gzipWriter)
	entries := []struct {
		name string
		body []byte
	}{{"image-set.json", []byte(`{"schemaVersion":"v1","imageSetId":"bundled-upstream-030","composeFile":"compose.yaml","imageArchivePaths":["images/vitalserver.tar"]}`)}, {"compose.yaml", []byte("services: {}\n")}, {"images/vitalserver.tar", []byte("docker-image")}}
	for _, entry := range entries {
		if err := tarWriter.WriteHeader(&tar.Header{Name: entry.name, Mode: 0o600, Size: int64(len(entry.body))}); err != nil {
			t.Fatal(err)
		}
		if _, err := tarWriter.Write(entry.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return contents.Bytes()
}
