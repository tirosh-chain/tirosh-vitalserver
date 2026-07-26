// Package linuxhostproductreleaseactivation owns the Linux current-release
// symbolic-link effect. The C48 referenceKind makes this filesystem contract
// explicit; this adapter never substitutes another link mechanism.
package linuxhostproductreleaseactivation

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type LinuxHostProductReleaseActivator struct{}

func (LinuxHostProductReleaseActivator) ActivateHostProductRelease(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if manifest.Platform != "linux" {
		return fmt.Errorf("Linux release activator cannot activate platform %q", manifest.Platform)
	}
	if manifest.Activation.ReferenceKind != "symbolic-link" {
		return fmt.Errorf("Linux release activator requires symbolic-link activation, got %q", manifest.Activation.ReferenceKind)
	}
	currentPath := manifest.Activation.CurrentReleaseLinkPath
	expectedReleaseRootPath := manifest.Activation.ExpectedReleaseRootPath
	if info, err := os.Lstat(currentPath); err == nil {
		if info.Mode()&os.ModeSymlink == 0 {
			return fmt.Errorf("current release activation path is not a symbolic link")
		}
		resolved, resolveError := filepath.EvalSymlinks(currentPath)
		if resolveError != nil {
			return fmt.Errorf("resolve current release activation path: %w", resolveError)
		}
		expectedResolved, expectedResolveError := filepath.EvalSymlinks(expectedReleaseRootPath)
		if expectedResolveError != nil {
			return fmt.Errorf("resolve expected immutable release root: %w", expectedResolveError)
		}
		if filepath.Clean(resolved) != filepath.Clean(expectedResolved) {
			return fmt.Errorf("current release activation points at a different release")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect current release activation path: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(currentPath), 0755); err != nil {
		return fmt.Errorf("create current release activation directory: %w", err)
	}
	temporaryPath, err := temporaryActivationPath(currentPath)
	if err != nil {
		return err
	}
	if err := os.Symlink(expectedReleaseRootPath, temporaryPath); err != nil {
		return fmt.Errorf("create next current-release link: %w", err)
	}
	defer os.Remove(temporaryPath)
	if err := os.Rename(temporaryPath, currentPath); err != nil {
		return fmt.Errorf("replace current-release link atomically: %w", err)
	}
	return nil
}

func temporaryActivationPath(currentPath string) (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("create current-release activation nonce: %w", err)
	}
	return currentPath + ".installing-" + hex.EncodeToString(bytes), nil
}
