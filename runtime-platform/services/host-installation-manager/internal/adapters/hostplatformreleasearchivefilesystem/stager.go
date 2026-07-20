// Package hostplatformreleasearchivefilesystem owns strict C68 archive
// inspection and candidate persistence. It never activates a release or
// manipulates services.
package hostplatformreleasearchivefilesystem

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

const maximumArchiveBytes int64 = 8 * 1024 * 1024 * 1024

type InspectedReleaseArchive struct {
	Manifest                 hostinstallationmanagerdomain.HostProductInstallationManifest
	TemporaryDirectory       string
	ReleaseDirectory         string
	ServiceDefinitionSources map[string]string
	OperatorBootstrapSource  string
}

type FilesystemStager struct{}

func (FilesystemStager) InspectHostPlatformReleaseArchive(ctx context.Context, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, artifactPath string) (InspectedReleaseArchive, error) {
	if ctx == nil {
		return InspectedReleaseArchive{}, fmt.Errorf("C68 archive inspection context is required")
	}
	if err := hostplatformstagedreleaseupdatedomain.ValidateCommand(command); err != nil {
		return InspectedReleaseArchive{}, err
	}
	info, err := os.Lstat(artifactPath)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 || info.Size() != command.Artifact.SizeBytes || info.Size() > maximumArchiveBytes {
		return InspectedReleaseArchive{}, fmt.Errorf("C68 archive is missing, non-regular, symbolic, size-mismatched, or too large")
	}
	if err := verifySHA256(artifactPath, command.Artifact.SHA256); err != nil {
		return InspectedReleaseArchive{}, err
	}
	temporaryDirectory, err := os.MkdirTemp("", "vitalserver-host-platform-release-")
	if err != nil {
		return InspectedReleaseArchive{}, fmt.Errorf("create C68 temporary archive directory: %w", err)
	}
	failed := true
	defer func() {
		if failed {
			_ = os.RemoveAll(temporaryDirectory)
		}
	}()
	if err := extractStrictArchive(ctx, artifactPath, temporaryDirectory); err != nil {
		return InspectedReleaseArchive{}, err
	}
	manifestPath := filepath.Join(temporaryDirectory, "release", "installation-manifest.json")
	manifest, err := (hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{}).ReadHostProductInstallationManifest(ctx, manifestPath)
	if err != nil {
		return InspectedReleaseArchive{}, fmt.Errorf("read C68 candidate C48: %w", err)
	}
	services, operator, err := verifyArchiveLayout(temporaryDirectory, manifest)
	if err != nil {
		return InspectedReleaseArchive{}, err
	}
	failed = false
	return InspectedReleaseArchive{Manifest: manifest, TemporaryDirectory: temporaryDirectory, ReleaseDirectory: filepath.Join(temporaryDirectory, "release"), ServiceDefinitionSources: services, OperatorBootstrapSource: operator}, nil
}

func (FilesystemStager) PersistCandidate(archive InspectedReleaseArchive, active hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand) (hostplatformstagedreleaseupdatedomain.CandidateHostRelease, error) {
	if archive.TemporaryDirectory == "" || archive.ReleaseDirectory == "" {
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, fmt.Errorf("C68 inspected archive is incomplete")
	}
	storePath, err := hostInstallationManagerStorePath(active)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, err
	}
	candidateDirectory := filepath.Join(storePath, "host-platform-release-updates", "candidates", command.OperationID)
	if err := ensureNoSymbolicExistingAncestor(filepath.Dir(candidateDirectory)); err != nil {
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, err
	}
	if info, err := os.Lstat(candidateDirectory); err == nil || !errors.Is(err, os.ErrNotExist) {
		if err == nil && info != nil {
			return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, fmt.Errorf("C68 candidate directory already exists")
		}
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, fmt.Errorf("inspect C68 candidate directory: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(candidateDirectory), 0o700); err != nil {
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, fmt.Errorf("create C68 candidate parent: %w", err)
	}
	if err := copyTree(archive.TemporaryDirectory, candidateDirectory); err != nil {
		_ = os.RemoveAll(candidateDirectory)
		return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{}, fmt.Errorf("persist C68 candidate archive: %w", err)
	}
	return hostplatformstagedreleaseupdatedomain.CandidateHostRelease{Manifest: archive.Manifest, CandidateDirectory: candidateDirectory}, nil
}

func (FilesystemStager) RemoveInspectedArchive(archive InspectedReleaseArchive) error {
	if archive.TemporaryDirectory == "" {
		return nil
	}
	return os.RemoveAll(archive.TemporaryDirectory)
}

func verifyArchiveLayout(root string, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) (map[string]string, string, error) {
	expected := map[string]bool{"release/installation-manifest.json": true}
	for _, entry := range manifest.ImmutablePayload.Entries {
		expected[path.Join("release", entry.RelativePath)] = true
	}
	services := map[string]string{}
	for _, service := range manifest.RequiredServices {
		archiveName, err := serviceDefinitionArchiveName(manifest.Platform, service.Role)
		if err != nil {
			return nil, "", err
		}
		relative := path.Join("service-definitions", archiveName)
		expected[relative] = true
		services[service.Role] = filepath.Join(root, filepath.FromSlash(relative))
	}
	operatorRelative := "operator-interface/runtime-console-bootstrap.json"
	expected[operatorRelative] = true
	seen := map[string]bool{}
	err := filepath.WalkDir(root, func(filePath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if filePath == root {
			return nil
		}
		relative, err := filepath.Rel(root, filePath)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 || !entry.Type().IsRegular() {
			return fmt.Errorf("C68 archive contains a non-regular file %s", relative)
		}
		if !expected[relative] {
			return fmt.Errorf("C68 archive contains unexpected file %s", relative)
		}
		seen[relative] = true
		return nil
	})
	if err != nil {
		return nil, "", fmt.Errorf("verify C68 archive layout: %w", err)
	}
	for relative := range expected {
		if !seen[relative] {
			return nil, "", fmt.Errorf("C68 archive is missing required file %s", relative)
		}
	}
	for _, entry := range manifest.ImmutablePayload.Entries {
		if err := verifySHA256(filepath.Join(root, "release", filepath.FromSlash(entry.RelativePath)), entry.SHA256); err != nil {
			return nil, "", fmt.Errorf("verify C68 immutable entry %s: %w", entry.RelativePath, err)
		}
	}
	for _, service := range manifest.RequiredServices {
		if err := verifySHA256(services[service.Role], service.DefinitionSHA256); err != nil {
			return nil, "", fmt.Errorf("verify C68 service definition %s: %w", service.Role, err)
		}
	}
	operator := filepath.Join(root, filepath.FromSlash(operatorRelative))
	if err := verifySHA256(operator, manifest.OperatorInterface.BootstrapConfigurationSHA256); err != nil {
		return nil, "", fmt.Errorf("verify C68 operator bootstrap: %w", err)
	}
	return services, operator, nil
}

func extractStrictArchive(ctx context.Context, archivePath, destination string) error {
	file, err := os.Open(archivePath)
	if err != nil {
		return fmt.Errorf("open C68 archive: %w", err)
	}
	defer file.Close()
	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		return fmt.Errorf("open C68 gzip archive: %w", err)
	}
	defer gzipReader.Close()
	reader := tar.NewReader(gzipReader)
	seen := map[string]bool{}
	var extracted int64
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("read C68 archive: %w", err)
		}
		name, err := safeArchivePath(header.Name)
		if err != nil {
			return err
		}
		if seen[name] {
			return fmt.Errorf("C68 archive has duplicate path %s", name)
		}
		seen[name] = true
		destinationPath := filepath.Join(destination, filepath.FromSlash(name))
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(destinationPath, 0o700); err != nil {
				return fmt.Errorf("create C68 archive directory: %w", err)
			}
		case tar.TypeReg, tar.TypeRegA:
			if header.Size < 0 || extracted+header.Size > maximumArchiveBytes {
				return fmt.Errorf("C68 archive extracted size exceeds limit")
			}
			if err := os.MkdirAll(filepath.Dir(destinationPath), 0o700); err != nil {
				return fmt.Errorf("create C68 archive file parent: %w", err)
			}
			output, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
			if err != nil {
				return fmt.Errorf("create C68 archive file: %w", err)
			}
			copied, copyErr := io.Copy(output, io.LimitReader(reader, header.Size+1))
			closeErr := output.Close()
			if copyErr != nil || copied != header.Size || closeErr != nil {
				return fmt.Errorf("extract C68 archive file %s", name)
			}
			extracted += copied
			mode := os.FileMode(0o644)
			if header.FileInfo().Mode()&0o111 != 0 {
				mode = 0o755
			}
			if err := os.Chmod(destinationPath, mode); err != nil {
				return fmt.Errorf("set C68 archive file mode: %w", err)
			}
		default:
			return fmt.Errorf("C68 archive entry %s has unsupported type", name)
		}
	}
	return nil
}
func safeArchivePath(value string) (string, error) {
	cleaned := path.Clean(value)
	if value == "" || cleaned == "." || strings.HasPrefix(value, "/") || strings.HasPrefix(value, "\\") || strings.HasPrefix(cleaned, "../") || cleaned == ".." || strings.Contains(value, "\\") {
		return "", fmt.Errorf("C68 archive path is invalid")
	}
	return cleaned, nil
}
func verifySHA256(filePath, expected string) error {
	info, err := os.Lstat(filePath)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("file is missing, non-regular, or symbolic")
	}
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return err
	}
	if actual := hex.EncodeToString(digest.Sum(nil)); actual != expected {
		return fmt.Errorf("SHA256 differs from declared value")
	}
	return nil
}
func hostInstallationManagerStorePath(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) (string, error) {
	storePath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionStorePath(manifest)
	if err != nil {
		return "", fmt.Errorf("resolve C48 Host Installation Manager transaction store: %w", err)
	}
	return storePath, nil
}

// serviceDefinitionArchiveName is the C68 filesystem projection of an
// explicit C48 platform contract. It never detects an extension from the
// running host or a source file name: all three products can be staged by a
// release process, while the target Host effect remains platform-specific.
func serviceDefinitionArchiveName(platform, role string) (string, error) {
	switch platform {
	case "macos":
		return role + ".plist", nil
	case "linux":
		return role + ".service", nil
	case "windows":
		return role + ".json", nil
	default:
		return "", fmt.Errorf("C68 archive platform %q is not supported", platform)
	}
}

func ensureNoSymbolicExistingAncestor(value string) error {
	current := filepath.Clean(value)
	for {
		info, err := os.Lstat(current)
		if err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C68 managed path has symbolic ancestor %s", current)
		}
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("inspect C68 managed path ancestor: %w", err)
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		current = parent
	}
}
func copyTree(source, destination string) error {
	return filepath.WalkDir(source, func(sourcePath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, sourcePath)
		if err != nil {
			return err
		}
		destinationPath := filepath.Join(destination, relative)
		if entry.IsDir() {
			return os.MkdirAll(destinationPath, 0o700)
		}
		if entry.Type()&os.ModeSymlink != 0 || !entry.Type().IsRegular() {
			return fmt.Errorf("C68 temporary archive contains non-regular file")
		}
		input, err := os.Open(sourcePath)
		if err != nil {
			return err
		}
		defer input.Close()
		info, err := entry.Info()
		if err != nil {
			return err
		}
		output, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode().Perm())
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(output, input)
		closeErr := output.Close()
		if copyErr != nil {
			return copyErr
		}
		return closeErr
	})
}
