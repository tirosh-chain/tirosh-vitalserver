package guestproductreleasefilesystem

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

// ReleaseArchiveFilesystemStager verifies and extracts one immutable release
// archive. Archive entry paths never choose a Guest destination: C59 selects
// the complete target release directory before this adapter reads a byte.
type ReleaseArchiveFilesystemStager struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
}

func NewReleaseArchiveFilesystemStager(configuration guestproductreleasemanagerdomain.ManagerConfiguration) (*ReleaseArchiveFilesystemStager, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(configuration.StagingDirectory, 0o700); err != nil {
		return nil, fmt.Errorf("create C59 staging directory: %w", err)
	}
	if err := requireDirectory(configuration.StagingDirectory); err != nil {
		return nil, fmt.Errorf("validate C59 staging directory: %w", err)
	}
	if err := os.MkdirAll(configuration.ReleaseDirectoryRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create C59 release directory root: %w", err)
	}
	if err := requireDirectory(configuration.ReleaseDirectoryRoot); err != nil {
		return nil, fmt.Errorf("validate C59 release directory root: %w", err)
	}
	return &ReleaseArchiveFilesystemStager{configuration: configuration}, nil
}

func (stager *ReleaseArchiveFilesystemStager) StageReleaseArchive(context context.Context, command guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, archive io.Reader) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	if context.Err() != nil {
		return unavailable("release-stage-context-cancelled", context.Err(), "guest-product-release-manager")
	}
	if err := guestproductreleasemanagerdomain.ValidateReleaseUpdateCommand(stager.configuration, command); err != nil {
		return failed("release-command-invalid", err, "guest-product-release-manager")
	}
	if archive == nil {
		return failed("release-archive-missing", fmt.Errorf("release archive is required"), "release-archive")
	}
	archivePath := filepath.Join(stager.configuration.StagingDirectory, command.UpdateID+"-"+command.TargetRelease.Artifact.SHA256+".tar.gz")
	if err := copyNewVerifiedArchive(archivePath, archive, command.TargetRelease.Artifact); err != nil {
		return classifyArchiveError(err)
	}
	if err := extractNewReleaseArchive(archivePath, command.TargetRelease.ReleaseDirectory); err != nil {
		return classifyArchiveError(err)
	}
	return nil
}

func copyNewVerifiedArchive(destination string, source io.Reader, artifact guestproductreleasemanagerdomain.ReleaseArtifact) error {
	if _, err := os.Lstat(destination); err == nil {
		return fmt.Errorf("release staging archive already exists")
	} else if !os.IsNotExist(err) {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".release-archive.*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	digest := sha256.New()
	reader := io.LimitReader(source, artifact.SizeBytes+1)
	written, err := io.Copy(io.MultiWriter(temporary, digest), reader)
	if err != nil {
		temporary.Close()
		return err
	}
	if written != artifact.SizeBytes {
		temporary.Close()
		return fmt.Errorf("release archive size differs from declaration")
	}
	if hex.EncodeToString(digest.Sum(nil)) != artifact.SHA256 {
		temporary.Close()
		return fmt.Errorf("release archive sha256 differs from declaration")
	}
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, destination)
}

func extractNewReleaseArchive(archivePath string, destination string) error {
	if info, err := os.Lstat(destination); err == nil || !os.IsNotExist(err) {
		if err == nil && info != nil {
			return fmt.Errorf("target release directory already exists")
		}
		return err
	}
	parent := filepath.Dir(destination)
	temporary, err := os.MkdirTemp(parent, "."+filepath.Base(destination)+".extract-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)
	archive, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer archive.Close()
	gzipReader, err := gzip.NewReader(archive)
	if err != nil {
		return fmt.Errorf("open release archive gzip stream: %w", err)
	}
	defer gzipReader.Close()
	tarReader := tar.NewReader(gzipReader)
	regularPaths := map[string]struct{}{}
	type deferredLink struct {
		path   string
		target string
	}
	links := []deferredLink{}
	entryCount := 0
	for {
		header, readErr := tarReader.Next()
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return fmt.Errorf("read release archive entry: %w", readErr)
		}
		entryCount++
		if entryCount > 100000 || !safeArchivePath(header.Name) {
			return fmt.Errorf("release archive entry path is invalid")
		}
		output := filepath.Join(temporary, filepath.FromSlash(header.Name))
		if !containedPath(temporary, output) {
			return fmt.Errorf("release archive entry escapes destination")
		}
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(output, os.FileMode(header.Mode)&0o755); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
				return err
			}
			file, err := os.OpenFile(output, os.O_WRONLY|os.O_CREATE|os.O_EXCL, os.FileMode(header.Mode)&0o755)
			if err != nil {
				return err
			}
			if _, err := io.Copy(file, tarReader); err != nil {
				file.Close()
				return err
			}
			if err := file.Close(); err != nil {
				return err
			}
			regularPaths[path.Clean(header.Name)] = struct{}{}
		case tar.TypeSymlink:
			if !safeArchiveLinkTarget(header.Linkname) {
				return fmt.Errorf("release archive symbolic link target is invalid")
			}
			links = append(links, deferredLink{path: header.Name, target: header.Linkname})
		default:
			return fmt.Errorf("release archive entry type is unsupported")
		}
	}
	if entryCount == 0 || len(regularPaths) == 0 {
		return fmt.Errorf("release archive has no regular payload files")
	}
	for _, link := range links {
		target := path.Clean(path.Join(path.Dir(link.path), link.target))
		if _, exists := regularPaths[target]; !exists {
			return fmt.Errorf("release archive symbolic link does not target a declared regular file")
		}
		output := filepath.Join(temporary, filepath.FromSlash(link.path))
		if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
			return err
		}
		if err := os.Symlink(link.target, output); err != nil {
			return err
		}
	}
	return os.Rename(temporary, destination)
}

func safeArchivePath(value string) bool {
	normalized := strings.TrimSuffix(value, "/")
	return normalized != "" && !strings.HasPrefix(normalized, "/") && path.Clean(normalized) == normalized && !strings.Contains(normalized, "..")
}
func safeArchiveLinkTarget(value string) bool {
	return value != "" && !strings.HasPrefix(value, "/") && path.Clean(value) == value && !strings.Contains(value, "..")
}
func containedPath(root string, candidate string) bool {
	relative, err := filepath.Rel(root, candidate)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}
func classifyArchiveError(err error) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	return failed("release-archive-stage-failed", err, "release-archive")
}
func failed(code string, err error, dependency string) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	return &guestproductreleasemanagerapplication.ReleaseManagementFailure{State: guestproductreleasemanagerdomain.OperationStateFailed, Issue: guestproductreleasemanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}}
}
func unavailable(code string, err error, dependency string) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	return &guestproductreleasemanagerapplication.ReleaseManagementFailure{State: guestproductreleasemanagerdomain.OperationStateUnavailable, Issue: guestproductreleasemanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}}
}

var _ guestproductreleasemanagerapplication.ReleaseArchiveStager = (*ReleaseArchiveFilesystemStager)(nil)
