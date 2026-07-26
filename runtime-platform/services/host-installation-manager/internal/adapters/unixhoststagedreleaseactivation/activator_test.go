package unixhoststagedreleaseactivation

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestActivateStagedHostProductReleaseMovesLinuxCurrentLink(t *testing.T) {
	root := t.TempDir()
	activeRoot := filepath.Join(root, "releases", "release-020")
	targetRoot := filepath.Join(root, "releases", "release-030")
	if err := os.MkdirAll(activeRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(targetRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	current := filepath.Join(root, "current")
	if err := os.Symlink(activeRoot, current); err != nil {
		t.Fatal(err)
	}
	active := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux", Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: current, ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: activeRoot}}
	target := active
	target.Activation.ExpectedReleaseRootPath = targetRoot
	if err := (Activator{}).ActivateStagedHostProductRelease(context.Background(), active, target); err != nil {
		t.Fatalf("activate Linux staged release: %v", err)
	}
	resolved, err := filepath.EvalSymlinks(current)
	canonicalTarget, targetErr := filepath.EvalSymlinks(targetRoot)
	if err != nil || targetErr != nil || filepath.Clean(resolved) != filepath.Clean(canonicalTarget) {
		t.Fatalf("current link resolved=%q err=%v target=%q targetErr=%v", resolved, err, canonicalTarget, targetErr)
	}
}
