// Package hostplatformstagedreleasepublisher publishes an admitted C68
// candidate into the target C48 release catalog. It is deliberately neutral
// about service managers: C48.platform determines the archive entry name;
// the later native reconciler owns launching those definitions.
package hostplatformstagedreleasepublisher

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

type Publisher struct{}

func (Publisher) PublishStagedHostProductRelease(ctx context.Context, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, candidate hostplatformstagedreleaseupdatedomain.CandidateHostRelease) error {
	if ctx == nil {
		return fmt.Errorf("C68 publishing context is required")
	}
	manifest := candidate.Manifest
	if !supportedPlatform(manifest.Platform) {
		return fmt.Errorf("C68 publisher cannot publish platform %q", manifest.Platform)
	}
	releaseSource := filepath.Join(candidate.CandidateDirectory, "release")
	info, err := os.Lstat(releaseSource)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C68 candidate release directory is missing, non-directory, or symbolic")
	}
	if err := ensureNoSymbolicExistingAncestor(filepath.Dir(manifest.ImmutablePayload.ReleaseRootPath)); err != nil {
		return err
	}
	if targetInfo, err := os.Lstat(manifest.ImmutablePayload.ReleaseRootPath); err == nil {
		if targetInfo == nil || !targetInfo.IsDir() || targetInfo.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C68 target release slot is non-directory or symbolic")
		}
		if command.Operation != hostplatformstagedreleaseupdatedomain.OperationRollback {
			return fmt.Errorf("C68 target release slot already exists")
		}
		if err := verifyPublishedRelease(manifest); err != nil {
			return fmt.Errorf("verify existing C68 rollback release: %w", err)
		}
	} else if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(manifest.ImmutablePayload.ReleaseRootPath), 0o755); err != nil {
			return fmt.Errorf("create C68 release catalog: %w", err)
		}
		if err := os.Rename(releaseSource, manifest.ImmutablePayload.ReleaseRootPath); err != nil {
			return fmt.Errorf("publish C68 immutable release slot: %w", err)
		}
		if err := verifyPublishedRelease(manifest); err != nil {
			return err
		}
	} else {
		return fmt.Errorf("inspect C68 target release slot: %w", err)
	}
	for _, service := range manifest.RequiredServices {
		if err := ctx.Err(); err != nil {
			return err
		}
		archiveName, err := serviceDefinitionArchiveName(manifest.Platform, service.Role)
		if err != nil {
			return err
		}
		if err := publishFile(filepath.Join(candidate.CandidateDirectory, "service-definitions", archiveName), service.DefinitionPath, service.DefinitionSHA256, 0o644); err != nil {
			return fmt.Errorf("publish C68 service definition %s: %w", service.Role, err)
		}
	}
	if err := publishFile(filepath.Join(candidate.CandidateDirectory, "operator-interface", "runtime-console-bootstrap.json"), manifest.OperatorInterface.BootstrapConfigurationPath, manifest.OperatorInterface.BootstrapConfigurationSHA256, 0o644); err != nil {
		return fmt.Errorf("publish C68 operator bootstrap: %w", err)
	}
	return nil
}

func verifyPublishedRelease(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	manifestPath := filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "installation-manifest.json")
	published, err := (hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{}).ReadHostProductInstallationManifest(context.Background(), manifestPath)
	if err != nil {
		return fmt.Errorf("read C68 published C48 manifest: %w", err)
	}
	if !reflect.DeepEqual(manifest, published) {
		return fmt.Errorf("C68 published C48 manifest differs from the admitted candidate")
	}
	for _, entry := range manifest.ImmutablePayload.Entries {
		if err := verifySHA256(filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, filepath.FromSlash(entry.RelativePath)), entry.SHA256); err != nil {
			return fmt.Errorf("verify C68 published immutable entry %s: %w", entry.RelativePath, err)
		}
	}
	return nil
}

func publishFile(source, target, expectedSHA256 string, mode os.FileMode) error {
	if err := verifySHA256(source, expectedSHA256); err != nil {
		return fmt.Errorf("verify source: %w", err)
	}
	if err := ensureNoSymbolicExistingAncestor(filepath.Dir(target)); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	temporary, err := os.CreateTemp(filepath.Dir(target), ".c68-publish-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode); err != nil {
		temporary.Close()
		return err
	}
	if _, err := io.Copy(temporary, input); err != nil {
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
	if err := verifySHA256(temporaryPath, expectedSHA256); err != nil {
		return err
	}
	return os.Rename(temporaryPath, target)
}

func verifySHA256(path, expected string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("file is missing, non-regular, or symbolic")
	}
	file, err := os.Open(path)
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

func serviceDefinitionArchiveName(platform, role string) (string, error) {
	switch platform {
	case "macos":
		return role + ".plist", nil
	case "linux":
		return role + ".service", nil
	case "windows":
		return role + ".json", nil
	default:
		return "", fmt.Errorf("C68 platform %q is not supported", platform)
	}
}

func supportedPlatform(platform string) bool {
	return platform == "macos" || platform == "linux" || platform == "windows"
}

func ensureNoSymbolicExistingAncestor(value string) error {
	current := filepath.Clean(value)
	for {
		info, err := os.Lstat(current)
		if err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C68 publish path has symbolic ancestor %s", current)
		}
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		current = parent
	}
}
