package guestbundledupstreamimagesetfilesystem

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

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

// ImageSetArchiveFilesystemStager validates the byte identity and archive
// layout before it publishes a new immutable Guest image-set directory. The
// archive cannot select a target path and symlinks are intentionally rejected.
type ImageSetArchiveFilesystemStager struct { configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration }

type imageSetManifest struct {
	SchemaVersion      string   `json:"schemaVersion"`
	ImageSetID         string   `json:"imageSetId"`
	ComposeFile        string   `json:"composeFile"`
	ImageArchivePaths  []string `json:"imageArchivePaths"`
}

func NewImageSetArchiveFilesystemStager(configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration) (*ImageSetArchiveFilesystemStager, error) {
	if err := ensureStateRoots(configuration); err != nil { return nil, err }
	if err := os.MkdirAll(configuration.StagingDirectory, 0o700); err != nil { return nil, fmt.Errorf("create C64 staging directory: %w", err) }
	if err := requireDirectory(configuration.StagingDirectory); err != nil { return nil, fmt.Errorf("validate C64 staging directory: %w", err) }
	imageSets := filepath.Join(configuration.StateDirectory, "image-sets")
	if err := os.MkdirAll(imageSets, 0o700); err != nil { return nil, fmt.Errorf("create C64 image-set directory: %w", err) }
	if err := requireDirectory(imageSets); err != nil { return nil, fmt.Errorf("validate C64 image-set directory: %w", err) }
	return &ImageSetArchiveFilesystemStager{configuration: configuration}, nil
}

func (stager *ImageSetArchiveFilesystemStager) StageImageSetArchive(context context.Context, command guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, archive io.Reader) (string, *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure) {
	if context.Err() != nil { return "", unavailable("image-set-stage-context-cancelled", context.Err(), "guest-bundled-upstream-image-set-manager") }
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateImageSetUpdateCommand(stager.configuration, command); err != nil { return "", failed("image-set-command-invalid", err, "guest-bundled-upstream-image-set-manager") }
	if archive == nil { return "", failed("image-set-archive-missing", fmt.Errorf("image-set archive is required"), "image-set-archive") }
	archivePath := filepath.Join(stager.configuration.StagingDirectory, command.UpdateID+"-"+command.TargetImageSet.Artifact.SHA256+".tar.gz")
	if err := copyNewVerifiedArchive(archivePath, archive, command.TargetImageSet.Artifact); err != nil { return "", failed("image-set-archive-stage-failed", err, "image-set-archive") }
	destination := filepath.Join(stager.configuration.StateDirectory, "image-sets", command.TargetImageSet.ImageSetID)
	if err := extractNewImageSetArchive(archivePath, destination, command.TargetImageSet.ImageSetID); err != nil { return "", failed("image-set-archive-stage-failed", err, "image-set-archive") }
	return destination, nil
}

func copyNewVerifiedArchive(destination string, source io.Reader, artifact guestbundledupstreamimagesetmanagerdomain.ImageSetArtifact) error {
	if _, err := os.Lstat(destination); err == nil { return fmt.Errorf("image-set staging archive already exists") } else if !os.IsNotExist(err) { return err }
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".image-set-archive.*.tmp")
	if err != nil { return err }
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	digest := sha256.New()
	written, err := io.Copy(io.MultiWriter(temporary, digest), io.LimitReader(source, artifact.SizeBytes+1))
	if err != nil { temporary.Close(); return err }
	if written != artifact.SizeBytes { temporary.Close(); return fmt.Errorf("image-set archive size differs from declaration") }
	if hex.EncodeToString(digest.Sum(nil)) != artifact.SHA256 { temporary.Close(); return fmt.Errorf("image-set archive sha256 differs from declaration") }
	if err := temporary.Chmod(0o600); err != nil { temporary.Close(); return err }
	if err := temporary.Sync(); err != nil { temporary.Close(); return err }
	if err := temporary.Close(); err != nil { return err }
	return os.Rename(temporaryPath, destination)
}

func extractNewImageSetArchive(archivePath string, destination string, expectedImageSetID string) error {
	if info, err := os.Lstat(destination); err == nil || !os.IsNotExist(err) { if err == nil && info != nil { return fmt.Errorf("target image-set directory already exists") }; return err }
	temporary, err := os.MkdirTemp(filepath.Dir(destination), "."+filepath.Base(destination)+".extract-*")
	if err != nil { return err }
	defer os.RemoveAll(temporary)
	archive, err := os.Open(archivePath)
	if err != nil { return err }
	defer archive.Close()
	gzipReader, err := gzip.NewReader(archive)
	if err != nil { return fmt.Errorf("open image-set archive gzip stream: %w", err) }
	defer gzipReader.Close()
	tarReader := tar.NewReader(gzipReader)
	regularPaths := map[string]struct{}{}
	entryCount := 0
	for {
		header, readErr := tarReader.Next()
		if readErr == io.EOF { break }
		if readErr != nil { return fmt.Errorf("read image-set archive entry: %w", readErr) }
		entryCount++
		if entryCount > 100000 || !safeArchivePath(header.Name) { return fmt.Errorf("image-set archive entry path is invalid") }
		output := filepath.Join(temporary, filepath.FromSlash(header.Name))
		if !containedPath(temporary, output) { return fmt.Errorf("image-set archive entry escapes destination") }
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(output, os.FileMode(header.Mode)&0o755); err != nil { return err }
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil { return err }
			file, err := os.OpenFile(output, os.O_WRONLY|os.O_CREATE|os.O_EXCL, os.FileMode(header.Mode)&0o755)
			if err != nil { return err }
			if _, err := io.Copy(file, tarReader); err != nil { file.Close(); return err }
			if err := file.Close(); err != nil { return err }
			regularPaths[path.Clean(header.Name)] = struct{}{}
		default:
			return fmt.Errorf("image-set archive entry type is unsupported")
		}
	}
	if entryCount == 0 { return fmt.Errorf("image-set archive has no entries") }
	manifestPath := filepath.Join(temporary, "image-set.json")
	manifestBytes, found, err := readRegularFile(manifestPath)
	if err != nil || !found { return fmt.Errorf("image-set archive manifest is missing or unreadable") }
	var manifest imageSetManifest
	if err := decodeOneStrictJSON(manifestBytes, &manifest); err != nil { return fmt.Errorf("image-set archive manifest is invalid: %w", err) }
	if err := validateImageSetManifest(manifest, expectedImageSetID, regularPaths); err != nil { return err }
	return os.Rename(temporary, destination)
}

func ReadStagedImageSetManifest(imageSetDirectory string) (string, []string, error) {
	if err := requireDirectory(imageSetDirectory); err != nil { return "", nil, fmt.Errorf("C64 staged image-set directory: %w", err) }
	contents, found, err := readRegularFile(filepath.Join(imageSetDirectory, "image-set.json"))
	if err != nil || !found { return "", nil, fmt.Errorf("C64 staged image-set manifest is missing or unreadable") }
	var manifest imageSetManifest
	if err := decodeOneStrictJSON(contents, &manifest); err != nil { return "", nil, fmt.Errorf("C64 staged image-set manifest is invalid: %w", err) }
	regularPaths, err := listStagedRegularFiles(imageSetDirectory)
	if err != nil { return "", nil, err }
	if err := validateImageSetManifest(manifest, manifest.ImageSetID, regularPaths); err != nil { return "", nil, err }
	return manifest.ComposeFile, append([]string(nil), manifest.ImageArchivePaths...), nil
}

func validateImageSetManifest(manifest imageSetManifest, expectedImageSetID string, regularPaths map[string]struct{}) error {
	if manifest.SchemaVersion != guestbundledupstreamimagesetmanagerdomain.SchemaVersion || manifest.ImageSetID != expectedImageSetID || !safeArchivePath(manifest.ComposeFile) || !strings.HasSuffix(manifest.ComposeFile, ".yaml") || len(manifest.ImageArchivePaths) == 0 { return fmt.Errorf("image-set archive manifest identity or layout is invalid") }
	if _, found := regularPaths[manifest.ComposeFile]; !found { return fmt.Errorf("image-set archive compose file is not a regular archive entry") }
	seen := map[string]struct{}{}
	for _, imagePath := range manifest.ImageArchivePaths {
		if !safeArchivePath(imagePath) || !strings.HasPrefix(imagePath, "images/") || !strings.HasSuffix(imagePath, ".tar") { return fmt.Errorf("image-set archive image path is invalid") }
		if _, duplicate := seen[imagePath]; duplicate { return fmt.Errorf("image-set archive image path is declared more than once") }
		if _, found := regularPaths[imagePath]; !found { return fmt.Errorf("image-set archive image path is not a regular archive entry") }
		seen[imagePath] = struct{}{}
	}
	return nil
}

func listStagedRegularFiles(root string) (map[string]struct{}, error) {
	paths := map[string]struct{}{}
	err := filepath.WalkDir(root, func(candidate string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil { return walkErr }
		if candidate == root { return nil }
		if entry.Type()&os.ModeSymlink != 0 { return fmt.Errorf("C64 staged image-set contains a symbolic link") }
		if entry.IsDir() { return nil }
		if !entry.Type().IsRegular() { return fmt.Errorf("C64 staged image-set contains a non-regular file") }
		relative, err := filepath.Rel(root, candidate)
		if err != nil || !safeArchivePath(filepath.ToSlash(relative)) { return fmt.Errorf("C64 staged image-set path is invalid") }
		paths[filepath.ToSlash(relative)] = struct{}{}
		return nil
	})
	return paths, err
}

func safeArchivePath(value string) bool { normalized := strings.TrimSuffix(value, "/"); return normalized != "" && !strings.HasPrefix(normalized, "/") && path.Clean(normalized) == normalized && !strings.Contains(normalized, "..") }
func containedPath(root string, candidate string) bool { relative, err := filepath.Rel(root, candidate); return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) }

var _ guestbundledupstreamimagesetmanagerapplication.ImageSetArchiveStager = (*ImageSetArchiveFilesystemStager)(nil)
