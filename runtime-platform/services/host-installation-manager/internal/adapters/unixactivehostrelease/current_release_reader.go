// Package unixactivehostrelease owns C68 observation for the two Host
// platforms whose C48 activation contract is a symbolic `current` link.
// It does not infer a platform from the local OS; C48 supplies it.
package unixactivehostrelease

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

type CurrentReleaseReader struct{}

func (CurrentReleaseReader) ReadActiveHostRelease(ctx context.Context, activeManifestPath string) (hostplatformstagedreleaseupdatedomain.ActiveHostRelease, error) {
	if ctx == nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active release observation context is required")
	}
	if activeManifestPath == "" || !filepath.IsAbs(activeManifestPath) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active C48 manifest path is invalid")
	}
	manifest, err := (hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{}).ReadHostProductInstallationManifest(ctx, activeManifestPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("read C68 active C48: %w", err)
	}
	if (manifest.Platform != "macos" && manifest.Platform != "linux") || manifest.Activation.ReferenceKind != "symbolic-link" {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active release does not declare a Unix symbolic-link activation")
	}
	info, err := os.Lstat(manifest.Activation.CurrentReleaseLinkPath)
	if err != nil || info.Mode()&os.ModeSymlink == 0 {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 current release link is missing or not symbolic")
	}
	resolved, err := filepath.EvalSymlinks(manifest.Activation.CurrentReleaseLinkPath)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("resolve C68 active current link: %w", err)
	}
	if filepath.Dir(filepath.Clean(resolved)) != filepath.Clean(manifest.ImmutablePayload.ReleaseCatalogPath) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 current release points outside the declared release catalog")
	}
	if filepath.Clean(manifest.ImmutablePayload.ReleaseRootPath) != filepath.Clean(resolved) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 current release does not match its active C48 root")
	}
	resolvedManifestPath, err := filepath.EvalSymlinks(activeManifestPath)
	if err != nil || filepath.Clean(resolvedManifestPath) != filepath.Clean(manifest.ImmutablePayload.ManifestPath) {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, fmt.Errorf("C68 active manifest path does not resolve to its declared immutable C48 path")
	}
	if err := verifyManifestBytes(manifest); err != nil {
		return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{}, err
	}
	return hostplatformstagedreleaseupdatedomain.ActiveHostRelease{Manifest: manifest}, nil
}

func verifyManifestBytes(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	for _, entry := range manifest.ImmutablePayload.Entries {
		if err := verifySHA256(filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, filepath.FromSlash(entry.RelativePath)), entry.SHA256); err != nil {
			return fmt.Errorf("verify active C48 immutable entry %s: %w", entry.RelativePath, err)
		}
	}
	for _, service := range manifest.RequiredServices {
		if err := verifySHA256(service.DefinitionPath, service.DefinitionSHA256); err != nil {
			return fmt.Errorf("verify active C48 service definition %s: %w", service.Role, err)
		}
	}
	if err := verifySHA256(manifest.OperatorInterface.BootstrapConfigurationPath, manifest.OperatorInterface.BootstrapConfigurationSHA256); err != nil {
		return fmt.Errorf("verify active C48 operator bootstrap: %w", err)
	}
	return nil
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
