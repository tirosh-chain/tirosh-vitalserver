package linuxhostproductremoval

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type commandCall struct{ arguments []string }

type commandRunnerFake struct{ calls []commandCall }

func (fake *commandRunnerFake) RunLinuxHostProductRemovalCommand(_ context.Context, _ string, arguments ...string) (SystemdCommandResult, error) {
	fake.calls = append(fake.calls, commandCall{arguments: append([]string(nil), arguments...)})
	return SystemdCommandResult{}, nil
}

func linuxRemovalManifest(root string) hostinstallationmanagerdomain.HostProductInstallationManifest {
	releaseID := "runtime-platform-0.2.0"
	catalog := filepath.Join(root, "releases")
	services := []hostinstallationmanagerdomain.HostProductRequiredService{
		{Role: "host-agent", Manager: "systemd", Name: "vitalserver-host-agent", DefinitionPath: filepath.Join(root, "systemd", "vitalserver-host-agent.service")},
		{Role: "host-edge-proxy", Manager: "systemd", Name: "vitalserver-host-edge-proxy", DefinitionPath: filepath.Join(root, "systemd", "vitalserver-host-edge-proxy.service")},
		{Role: "host-update-handoff-supervisor", Manager: "systemd", Name: "vitalserver-host-update-handoff-supervisor", DefinitionPath: filepath.Join(root, "systemd", "vitalserver-host-update-handoff-supervisor.service")},
	}
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		Platform: "linux", Release: hostinstallationmanagerdomain.HostProductRelease{ID: releaseID},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{ReleaseCatalogPath: catalog, ReleaseRootPath: filepath.Join(catalog, releaseID)},
		Activation:       hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: filepath.Join(root, "current"), ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: filepath.Join(catalog, releaseID)},
		RequiredServices: services,
		MutableStores:    []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{{ID: "data", Path: filepath.Join(root, "data")}},
	}
}

func TestLinuxHostProductRemoverRemovesOnlyDeclaredResourcesAndHandsPackageToDpkg(t *testing.T) {
	// /var is a symbolic link on macOS, while the production Linux paths have
	// no symlink components. Resolve the platform's temporary root so this
	// portable test exercises the same safety guard on macOS and Linux.
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	manifest := linuxRemovalManifest(root)
	if err := os.MkdirAll(manifest.ImmutablePayload.ReleaseRootPath, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(manifest.Activation.ExpectedReleaseRootPath, manifest.Activation.CurrentReleaseLinkPath); err != nil {
		t.Fatal(err)
	}
	for _, service := range manifest.RequiredServices {
		if err := os.MkdirAll(filepath.Dir(service.DefinitionPath), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(service.DefinitionPath, []byte("[Service]"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(manifest.MutableStores[0].Path, 0755); err != nil {
		t.Fatal(err)
	}
	runner := &commandRunnerFake{}
	remover, err := NewLinuxHostProductRemoverWithCommandRunner("/bin/systemctl", runner)
	if err != nil {
		t.Fatal(err)
	}
	if err := remover.RemoveHostProductServiceDefinitions(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if len(runner.calls) != 1 || len(runner.calls[0].arguments) != 1 || runner.calls[0].arguments[0] != "daemon-reload" {
		t.Fatalf("systemctl calls=%+v", runner.calls)
	}
	if err := remover.RemoveHostProductActivationLink(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if err := remover.RemoveHostProductReleaseCatalog(context.Background(), manifest); err != nil {
		t.Fatal(err)
	}
	if err := remover.RemoveHostProductMutableStores(context.Background(), manifest, manifest.MutableStores); err != nil {
		t.Fatal(err)
	}
	packageRemoval, err := remover.RemoveHostProductPackageReceipt(context.Background(), manifest)
	if err != nil || packageRemoval.State != hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager {
		t.Fatalf("packageRemoval=%+v err=%v", packageRemoval, err)
	}
	for _, path := range []string{manifest.Activation.CurrentReleaseLinkPath, manifest.ImmutablePayload.ReleaseCatalogPath, manifest.MutableStores[0].Path, manifest.RequiredServices[0].DefinitionPath} {
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Fatalf("declared path remains or is unreadable %s: %v", path, err)
		}
	}
}

func TestLinuxHostProductRemoverRejectsNonLinuxManifest(t *testing.T) {
	remover, err := NewLinuxHostProductRemoverWithCommandRunner("/bin/systemctl", &commandRunnerFake{})
	if err != nil {
		t.Fatal(err)
	}
	manifest := linuxRemovalManifest(t.TempDir())
	manifest.Platform = "macos"
	if _, err := remover.RemoveHostProductPackageReceipt(context.Background(), manifest); err == nil {
		t.Fatal("expected non-Linux manifest rejection")
	}
}
