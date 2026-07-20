package macoshostproductremoval

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostProductRemovalCommandRunnerFake struct {
	executable string
	arguments  []string
	result     HostProductRemovalCommandResult
}

func (fake *hostProductRemovalCommandRunnerFake) RunHostProductRemovalCommand(_ context.Context, executable string, arguments ...string) (HostProductRemovalCommandResult, error) {
	fake.executable = executable
	fake.arguments = append([]string(nil), arguments...)
	return fake.result, nil
}

func TestMacOSHostProductRemoverRemovesOnlyDeclaredResources(t *testing.T) {
	// On macOS t.TempDir commonly starts below /var, which is itself a
	// symbolic link to /private/var. The remover correctly rejects symbolic
	// path components, so resolve the test fixture to the physical path before
	// declaring resources in the Host manifest.
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	releaseCatalog := filepath.Join(root, "releases")
	releaseID := "runtime-platform-0.2.0-dev-build-001"
	releaseRoot := filepath.Join(releaseCatalog, releaseID)
	if err := os.MkdirAll(releaseRoot, 0755); err != nil {
		t.Fatal(err)
	}
	currentLink := filepath.Join(root, "current")
	if err := os.Symlink(releaseRoot, currentLink); err != nil {
		t.Fatal(err)
	}
	serviceDefinition := filepath.Join(root, "com.tirosh.vitalserver.host-agent.plist")
	if err := os.WriteFile(serviceDefinition, []byte("declared service"), 0644); err != nil {
		t.Fatal(err)
	}
	mutableStore := filepath.Join(root, "data")
	if err := os.MkdirAll(mutableStore, 0755); err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform:         "macos",
		Release:          hostinstallationmanagerdomain.HostProductRelease{ID: releaseID},
		Package:          hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{ReleaseCatalogPath: releaseCatalog},
		Activation:       hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: currentLink, ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{{Role: "host-agent", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: serviceDefinition}},
	}
	runner := &hostProductRemovalCommandRunnerFake{}
	remover, err := NewMacOSHostProductRemoverWithCommandRunner("/usr/sbin/pkgutil", runner)
	if err != nil {
		t.Fatal(err)
	}
	if err := remover.RemoveHostProductServiceDefinitions(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(serviceDefinition); !os.IsNotExist(err) {
		t.Fatalf("service definition remains or could not be inspected: %v", err)
	}
	if err := remover.RemoveHostProductActivationLink(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(currentLink); !os.IsNotExist(err) {
		t.Fatalf("activation link remains or could not be inspected: %v", err)
	}
	if err := remover.RemoveHostProductReleaseCatalog(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(releaseCatalog); !os.IsNotExist(err) {
		t.Fatalf("release catalog remains or could not be inspected: %v", err)
	}
	store := hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{ID: "product-data", Path: mutableStore, Kind: "directory"}
	if err := remover.RemoveHostProductMutableStores(context.Background(), manifest, []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{store}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(mutableStore); !os.IsNotExist(err) {
		t.Fatalf("mutable store remains or could not be inspected: %v", err)
	}
	removal, err := remover.RemoveHostProductPackageReceipt(context.Background(), manifest)
	if err != nil || removal.State != hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager {
		t.Fatalf("package receipt removal=%+v err=%v", removal, err)
	}
	if runner.executable != "/usr/sbin/pkgutil" || len(runner.arguments) != 2 || runner.arguments[0] != "--forget" || runner.arguments[1] != manifest.Package.Identifier {
		t.Fatalf("pkgutil invocation=%q %v", runner.executable, runner.arguments)
	}
}

func TestMacOSHostProductRemoverRefusesReleaseCatalogWithAnotherRelease(t *testing.T) {
	root := t.TempDir()
	releaseCatalog := filepath.Join(root, "releases")
	if err := os.MkdirAll(filepath.Join(releaseCatalog, "runtime-platform-0.2.0"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(releaseCatalog, "runtime-platform-0.1.0"), 0755); err != nil {
		t.Fatal(err)
	}
	remover, err := NewMacOSHostProductRemoverWithCommandRunner("pkgutil", &hostProductRemovalCommandRunnerFake{})
	if err != nil {
		t.Fatal(err)
	}
	manifest := hostinstallationmanagerdomain.HostProductInstallationManifest{Platform: "macos", Release: hostinstallationmanagerdomain.HostProductRelease{ID: "runtime-platform-0.2.0"}, ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{ReleaseCatalogPath: releaseCatalog}}
	if err := remover.RemoveHostProductReleaseCatalog(context.Background(), manifest); err == nil {
		t.Fatal("expected another release to block catalog removal")
	}
	if _, err := os.Lstat(releaseCatalog); err != nil {
		t.Fatalf("release catalog must remain after refusal: %v", err)
	}
}
