// Package unixhoststagedreleaseactivation owns the C68 compare-and-swap
// activation effect for macOS and Linux. C48 explicitly selects the
// symbolic-link mechanism; Windows uses a distinct directory-junction
// adapter rather than sharing this implementation.
package unixhoststagedreleaseactivation

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type Activator struct{}

func (Activator) ActivateStagedHostProductRelease(_ context.Context, active, target hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	if !unixSymbolicLinkManifest(active) || !unixSymbolicLinkManifest(target) {
		return fmt.Errorf("C68 staged activation requires macOS or Linux symbolic-link manifests")
	}
	if active.Platform != target.Platform || active.Activation.CurrentReleaseLinkPath != target.Activation.CurrentReleaseLinkPath {
		return fmt.Errorf("C68 staged activation link differs between releases")
	}
	info, err := os.Lstat(active.Activation.CurrentReleaseLinkPath)
	if err != nil || info.Mode()&os.ModeSymlink == 0 {
		return fmt.Errorf("C68 current release link is missing or non-symbolic")
	}
	resolved, err := filepath.EvalSymlinks(active.Activation.CurrentReleaseLinkPath)
	if err != nil {
		return fmt.Errorf("resolve C68 active current link: %w", err)
	}
	activeExpected, err := filepath.EvalSymlinks(active.Activation.ExpectedReleaseRootPath)
	if err != nil {
		return fmt.Errorf("resolve C68 declared active release root: %w", err)
	}
	if filepath.Clean(resolved) != filepath.Clean(activeExpected) {
		return fmt.Errorf("C68 current release changed before activation")
	}
	targetResolved, err := filepath.EvalSymlinks(target.Activation.ExpectedReleaseRootPath)
	if err != nil {
		return fmt.Errorf("resolve C68 target release root: %w", err)
	}
	targetInfo, err := os.Lstat(targetResolved)
	if err != nil || !targetInfo.IsDir() || targetInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C68 target release root is missing, non-directory, or symbolic")
	}
	nonce := make([]byte, 16)
	if _, err := rand.Read(nonce); err != nil {
		return fmt.Errorf("create C68 activation nonce: %w", err)
	}
	temporary := active.Activation.CurrentReleaseLinkPath + ".updating-" + hex.EncodeToString(nonce)
	if err := os.Symlink(target.Activation.ExpectedReleaseRootPath, temporary); err != nil {
		return fmt.Errorf("create C68 next current link: %w", err)
	}
	defer os.Remove(temporary)
	if err := os.Rename(temporary, active.Activation.CurrentReleaseLinkPath); err != nil {
		return fmt.Errorf("replace C68 current link atomically: %w", err)
	}
	return nil
}

func unixSymbolicLinkManifest(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) bool {
	return (manifest.Platform == "macos" || manifest.Platform == "linux") && manifest.Activation.ReferenceKind == "symbolic-link"
}
