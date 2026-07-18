package macoshostproductreleaseactivation

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestActivateHostProductReleaseCreatesCurrentLinkToExactDeclaredSlot(t *testing.T) {
	root := t.TempDir()
	releaseRoot := filepath.Join(root, "releases", "release-001")
	if err := os.MkdirAll(releaseRoot, 0755); err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform: "macos",
		Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{
			CurrentReleaseLinkPath:  filepath.Join(root, "current"),
			ExpectedReleaseRootPath: releaseRoot,
		},
	}
	if err := (MacOSHostProductReleaseActivator{}).ActivateHostProductRelease(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	target, err := filepath.EvalSymlinks(manifest.Activation.CurrentReleaseLinkPath)
	expectedTarget, expectedTargetError := filepath.EvalSymlinks(releaseRoot)
	if err != nil || expectedTargetError != nil || target != expectedTarget {
		t.Fatalf("target=%q expectedTarget=%q err=%v expectedTargetError=%v", target, expectedTarget, err, expectedTargetError)
	}
}

func TestActivateHostProductReleaseRefusesToReplaceOtherCurrentSlot(t *testing.T) {
	root := t.TempDir()
	oldReleaseRoot := filepath.Join(root, "releases", "release-old")
	newReleaseRoot := filepath.Join(root, "releases", "release-new")
	if err := os.MkdirAll(oldReleaseRoot, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(newReleaseRoot, 0755); err != nil {
		t.Fatal(err)
	}
	current := filepath.Join(root, "current")
	if err := os.Symlink(oldReleaseRoot, current); err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform: "macos",
		Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{
			CurrentReleaseLinkPath:  current,
			ExpectedReleaseRootPath: newReleaseRoot,
		},
	}
	if err := (MacOSHostProductReleaseActivator{}).ActivateHostProductRelease(context.Background(), manifest); err == nil {
		t.Fatal("expected activation to reject a different current slot")
	}
}
