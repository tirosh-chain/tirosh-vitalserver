package guestproductreleasefilesystem

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

// CurrentReleaseFilesystemLinkManager owns the one atomic current-release
// link. It does not select releases: the C59 command and release manager
// domain policy provide exact IDs and destinations.
type CurrentReleaseFilesystemLinkManager struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
}

func NewCurrentReleaseFilesystemLinkManager(configuration guestproductreleasemanagerdomain.ManagerConfiguration) (*CurrentReleaseFilesystemLinkManager, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	return &CurrentReleaseFilesystemLinkManager{configuration: configuration}, nil
}

func (manager *CurrentReleaseFilesystemLinkManager) ReadActiveReleaseID(_ context.Context) (string, *guestproductreleasemanagerapplication.ReleaseManagementFailure) {
	resolved, err := filepath.EvalSymlinks(manager.configuration.CurrentReleaseLinkPath)
	if err != nil {
		return "", unavailable("current-release-link-unavailable", err, "guest-product-release-link")
	}
	info, err := os.Lstat(resolved)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", failed("current-release-target-invalid", fmt.Errorf("current release target is missing, not a directory, or a symbolic link"), "guest-product-release-link")
	}
	releaseRoot, rootError := filepath.EvalSymlinks(manager.configuration.ReleaseDirectoryRoot)
	if rootError != nil || filepath.Dir(resolved) != releaseRoot {
		return "", failed("current-release-target-invalid", fmt.Errorf("current release target is outside the declared release root"), "guest-product-release-link")
	}
	identifier := filepath.Base(resolved)
	if identifier == "" || identifier == "." || identifier == ".." || strings.ContainsAny(identifier, `/\\`) {
		return "", failed("current-release-target-invalid", fmt.Errorf("current release target identifier is invalid"), "guest-product-release-link")
	}
	return identifier, nil
}

func (manager *CurrentReleaseFilesystemLinkManager) ActivateRelease(_ context.Context, target guestproductreleasemanagerdomain.ReleaseReference) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	if target.ReleaseID == "" || target.ReleaseDirectory != filepath.Join(manager.configuration.ReleaseDirectoryRoot, target.ReleaseID) {
		return failed("release-target-invalid", fmt.Errorf("release target does not belong to the configured release root"), "guest-product-release-link")
	}
	info, err := os.Lstat(target.ReleaseDirectory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return failed("release-target-unavailable", fmt.Errorf("declared target release directory is missing, not a directory, or a symbolic link"), "guest-product-release-link")
	}
	currentDirectory := filepath.Dir(manager.configuration.CurrentReleaseLinkPath)
	if err := os.MkdirAll(currentDirectory, 0o755); err != nil {
		return unavailable("current-release-parent-unavailable", err, "guest-product-release-link")
	}
	temporary, err := os.CreateTemp(currentDirectory, "."+filepath.Base(manager.configuration.CurrentReleaseLinkPath)+".*.tmp")
	if err != nil {
		return unavailable("current-release-temporary-link-unavailable", err, "guest-product-release-link")
	}
	temporaryPath := temporary.Name()
	if err := temporary.Close(); err != nil {
		os.Remove(temporaryPath)
		return unavailable("current-release-temporary-link-unavailable", err, "guest-product-release-link")
	}
	if err := os.Remove(temporaryPath); err != nil {
		return unavailable("current-release-temporary-link-unavailable", err, "guest-product-release-link")
	}
	defer os.Remove(temporaryPath)
	if err := os.Symlink(target.ReleaseDirectory, temporaryPath); err != nil {
		return unavailable("current-release-temporary-link-unavailable", err, "guest-product-release-link")
	}
	if err := os.Rename(temporaryPath, manager.configuration.CurrentReleaseLinkPath); err != nil {
		return unavailable("current-release-activation-failed", err, "guest-product-release-link")
	}
	return nil
}

var _ guestproductreleasemanagerapplication.CurrentReleaseLinkManager = (*CurrentReleaseFilesystemLinkManager)(nil)
