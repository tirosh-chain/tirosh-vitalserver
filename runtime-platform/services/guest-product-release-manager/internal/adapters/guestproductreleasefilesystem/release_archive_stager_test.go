package guestproductreleasefilesystem_test

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleasefilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

func TestReleaseArchiveStagerPublishesOnlyVerifiedReleaseAndSupportsSafeRelativeLinks(t *testing.T) {
	configuration := filesystemConfiguration(t)
	stager, err := guestproductreleasefilesystem.NewReleaseArchiveFilesystemStager(configuration)
	if err != nil {
		t.Fatal(err)
	}
	archive := releaseArchive(t, []tarEntry{{name: "bin/", mode: 0o755, kind: tar.TypeDir}, {name: "bin/guest-runtime", contents: "runtime", mode: 0o755, kind: tar.TypeReg}, {name: "bin/current-runtime", target: "guest-runtime", mode: 0o777, kind: tar.TypeSymlink}})
	command := archiveCommand(configuration, archive)
	if failure := stager.StageReleaseArchive(context.Background(), command, bytes.NewReader(archive)); failure != nil {
		t.Fatalf("stage release: %#v", failure)
	}
	releaseDirectory := command.TargetRelease.ReleaseDirectory
	contents, err := os.ReadFile(filepath.Join(releaseDirectory, "bin", "guest-runtime"))
	if err != nil || string(contents) != "runtime" {
		t.Fatalf("contents=%q err=%v", contents, err)
	}
	target, err := os.Readlink(filepath.Join(releaseDirectory, "bin", "current-runtime"))
	if err != nil || target != "guest-runtime" {
		t.Fatalf("link=%q err=%v", target, err)
	}
}

func TestReleaseArchiveStagerRejectsTraversalWithoutPublishingRelease(t *testing.T) {
	configuration := filesystemConfiguration(t)
	stager, err := guestproductreleasefilesystem.NewReleaseArchiveFilesystemStager(configuration)
	if err != nil {
		t.Fatal(err)
	}
	archive := releaseArchive(t, []tarEntry{{name: "../escaped", contents: "no", mode: 0o644, kind: tar.TypeReg}})
	command := archiveCommand(configuration, archive)
	failure := stager.StageReleaseArchive(context.Background(), command, bytes.NewReader(archive))
	if failure == nil || failure.Issue.Code != "release-archive-stage-failed" {
		t.Fatalf("failure=%#v", failure)
	}
	if _, err := os.Lstat(command.TargetRelease.ReleaseDirectory); !os.IsNotExist(err) {
		t.Fatalf("unsafe archive published a release: %v", err)
	}
}

func TestCurrentReleaseLinkManagerRestoresOnlyDeclaredRelease(t *testing.T) {
	configuration := filesystemConfiguration(t)
	for _, identifier := range []string{"vitalserver-guest-product-0.2.0-dev", "vitalserver-guest-product-0.2.1"} {
		if err := os.MkdirAll(filepath.Join(configuration.ReleaseDirectoryRoot, identifier), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(configuration.ReleaseDirectoryRoot, "vitalserver-guest-product-0.2.0-dev"), configuration.CurrentReleaseLinkPath); err != nil {
		t.Fatal(err)
	}
	manager, err := guestproductreleasefilesystem.NewCurrentReleaseFilesystemLinkManager(configuration)
	if err != nil {
		t.Fatal(err)
	}
	active, failure := manager.ReadActiveReleaseID(context.Background())
	if failure != nil || active != "vitalserver-guest-product-0.2.0-dev" {
		t.Fatalf("active=%q failure=%#v", active, failure)
	}
	failure = manager.ActivateRelease(context.Background(), guestproductreleasemanagerdomain.ReleaseReference{ReleaseID: "vitalserver-guest-product-0.2.1", ReleaseDirectory: filepath.Join(configuration.ReleaseDirectoryRoot, "vitalserver-guest-product-0.2.1")})
	if failure != nil {
		t.Fatalf("activate=%#v", failure)
	}
	active, failure = manager.ReadActiveReleaseID(context.Background())
	if failure != nil || active != "vitalserver-guest-product-0.2.1" {
		t.Fatalf("active=%q failure=%#v", active, failure)
	}
}

type tarEntry struct {
	name, contents, target string
	mode                   int64
	kind                   byte
}

func releaseArchive(t *testing.T, entries []tarEntry) []byte {
	t.Helper()
	var compressed bytes.Buffer
	gzipWriter := gzip.NewWriter(&compressed)
	writer := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		header := &tar.Header{Name: entry.name, Mode: entry.mode, Typeflag: entry.kind, Linkname: entry.target}
		if entry.kind == tar.TypeReg {
			header.Size = int64(len(entry.contents))
		}
		if err := writer.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if entry.kind == tar.TypeReg {
			if _, err := writer.Write([]byte(entry.contents)); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}
func filesystemConfiguration(t *testing.T) guestproductreleasemanagerdomain.ManagerConfiguration {
	t.Helper()
	root := t.TempDir()
	releaseRoot := filepath.Join(root, "opt", "vitalserver", "releases")
	return guestproductreleasemanagerdomain.ManagerConfiguration{ManagerID: "guest-product-release-manager-primary", ReleaseDirectoryRoot: releaseRoot, CurrentReleaseLinkPath: filepath.Join(root, "opt", "vitalserver", "current"), StagingDirectory: filepath.Join(root, "var", "lib", "vitalserver", "guest-product-releases", "staging"), StateDirectory: filepath.Join(root, "var", "lib", "vitalserver", "guest-product-releases"), StateDirectoryMode: "0700", MaximumReleaseArtifactBytes: 1 << 20, SystemctlExecutablePath: "/usr/bin/systemctl", ManagedServiceUnitName: "vitalserver-guest-product.service", RestartTimeoutMilliseconds: 60000, HealthCheckURL: "http://127.0.0.1:18443/v1/runtime/readiness", HealthCheckTimeoutMilliseconds: 30000, HealthCheckAcceptedStatusCodes: []int{200}}
}
func archiveCommand(configuration guestproductreleasemanagerdomain.ManagerConfiguration, archive []byte) guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand {
	digest := sha256.Sum256(archive)
	identifier := "vitalserver-guest-product-0.2.1"
	return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{SchemaVersion: "v1", UpdateID: "guest-release-update-020", ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0-dev", TargetRelease: guestproductreleasemanagerdomain.ReleaseTarget{ReleaseID: identifier, ReleaseDirectory: filepath.Join(configuration.ReleaseDirectoryRoot, identifier), Artifact: guestproductreleasemanagerdomain.ReleaseArtifact{SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(archive)), MediaType: "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"}}, RequestedAt: "2026-07-20T00:00:00Z"}
}

var _ = strings.Repeat
