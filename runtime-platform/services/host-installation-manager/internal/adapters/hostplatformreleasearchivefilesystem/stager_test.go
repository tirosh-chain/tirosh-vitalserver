package hostplatformreleasearchivefilesystem

import (
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestServiceDefinitionArchiveNameUsesCandidatePlatform(t *testing.T) {
	for _, test := range []struct {
		platform string
		want     string
	}{
		{platform: "macos", want: "host-agent.plist"},
		{platform: "linux", want: "host-agent.service"},
		{platform: "windows", want: "host-agent.json"},
	} {
		got, err := serviceDefinitionArchiveName(test.platform, "host-agent")
		if err != nil || got != test.want {
			t.Fatalf("platform %s: got=%q err=%v want=%q", test.platform, got, err, test.want)
		}
	}
	if _, err := serviceDefinitionArchiveName("unsupported", "host-agent"); err == nil {
		t.Fatal("expected unsupported platform to be rejected")
	}
}

func TestHostInstallationManagerStorePathUsesNamedC50Store(t *testing.T) {
	manifest := validManifestWithMultipleManagerStores()
	path, err := hostInstallationManagerStorePath(manifest)
	if err != nil || path != "/var/lib/vitalserver-runtime-platform/data/installation-manager" {
		t.Fatalf("path=%q err=%v", path, err)
	}
	manifest.MutableStores = manifest.MutableStores[:1]
	if _, err := hostInstallationManagerStorePath(manifest); err == nil {
		t.Fatal("expected missing named C50 store to be rejected")
	}
}

func validManifestWithMultipleManagerStores() hostinstallationmanagerdomain.HostProductInstallationManifest {
	sha := func(character string) string { return strings.Repeat(character, 64) }
	releaseRoot := "/opt/vitalserver-runtime-platform/releases/release-001"
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "linux",
		Release:        hostinstallationmanagerdomain.HostProductRelease{ID: "release-001", ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"},
		Package:        hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.3.0"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{
			ReleaseCatalogPath: "/opt/vitalserver-runtime-platform/releases", ReleaseRootPath: releaseRoot, ManifestPath: releaseRoot + "/installation-manifest.json",
			Entries: []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: sha("a"), Executable: true}},
		},
		Activation:        hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/opt/vitalserver-runtime-platform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot},
		OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: sha("b")},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "systemd", Name: "vitalserver-host-agent.service", DefinitionPath: "/etc/systemd/system/vitalserver-host-agent.service", DefinitionSHA256: sha("c")},
			{Role: "host-edge-proxy", Manager: "systemd", Name: "vitalserver-host-edge-proxy.service", DefinitionPath: "/etc/systemd/system/vitalserver-host-edge-proxy.service", DefinitionSHA256: sha("d")},
			{Role: "host-update-handoff-supervisor", Manager: "systemd", Name: "vitalserver-host-update-handoff-supervisor.service", DefinitionPath: "/etc/systemd/system/vitalserver-host-update-handoff-supervisor.service", DefinitionSHA256: sha("e")},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "installation-data-root", Path: "/var/lib/vitalserver-runtime-platform/data", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
			{ID: hostinstallationmanagerdomain.HostInstallationTransactionStoreID, Path: "/var/lib/vitalserver-runtime-platform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
		},
	}
}
