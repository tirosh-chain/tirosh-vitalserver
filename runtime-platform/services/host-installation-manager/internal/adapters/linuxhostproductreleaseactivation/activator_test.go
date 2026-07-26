package linuxhostproductreleaseactivation

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestActivateHostProductReleaseCreatesCurrentLinkToExactLinuxSlot(t *testing.T) {
	root := t.TempDir()
	releaseRoot := filepath.Join(root, "releases", "release-001")
	if err := os.MkdirAll(releaseRoot, 0755); err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux", Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{
		CurrentReleaseLinkPath: filepath.Join(root, "current"), ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot,
	}}
	if err := (LinuxHostProductReleaseActivator{}).ActivateHostProductRelease(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	resolved, err := filepath.EvalSymlinks(manifest.Activation.CurrentReleaseLinkPath)
	expected, expectedError := filepath.EvalSymlinks(releaseRoot)
	if err != nil || expectedError != nil || filepath.Clean(resolved) != filepath.Clean(expected) {
		t.Fatalf("resolved=%q expected=%q err=%v expectedError=%v", resolved, expected, err, expectedError)
	}
}

func TestActivateHostProductReleaseRejectsOtherLinuxActivationReference(t *testing.T) {
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "linux", Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{ReferenceKind: "directory-junction"}}
	if err := (LinuxHostProductReleaseActivator{}).ActivateHostProductRelease(context.Background(), manifest); err == nil {
		t.Fatal("expected explicit non-Linux reference kind rejection")
	}
}
