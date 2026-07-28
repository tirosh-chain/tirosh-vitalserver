package main

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostUpdateOwnershipReaderFake struct{}

func (hostUpdateOwnershipReaderFake) ReadHostUpdateOperationOwnership(context.Context) (hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation, error) {
	return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, nil
}

func TestNewHostInstallationWorkflowForPlatformComposesDeclaredLinuxAdapters(t *testing.T) {
	workflow, err := newHostInstallationWorkflowForPlatform("linux", hostUpdateOwnershipReaderFake{}, "/usr/sbin/pkgutil", "/bin/launchctl", "/usr/bin/dpkg-query", "/usr/bin/systemctl", `C:\Windows\System32\reg.exe`, `C:\Windows\System32\sc.exe`, `C:\Windows\System32\fsutil.exe`, `C:\Windows\System32\cmd.exe`)
	if err != nil || workflow == nil {
		t.Fatalf("workflow=%v err=%v", workflow, err)
	}
}

func TestNewHostInstallationWorkflowForPlatformComposesDeclaredWindowsAdapters(t *testing.T) {
	workflow, err := newHostInstallationWorkflowForPlatform("windows", hostUpdateOwnershipReaderFake{}, "pkgutil", "launchctl", "dpkg-query", "systemctl", `C:\Windows\System32\reg.exe`, `C:\Windows\System32\sc.exe`, `C:\Windows\System32\fsutil.exe`, `C:\Windows\System32\cmd.exe`)
	if err != nil || workflow == nil {
		t.Fatalf("workflow=%v err=%v", workflow, err)
	}
}

func TestNewHostPlatformStagedReleaseWorkflowComposesEveryDeclaredPlatform(t *testing.T) {
	for _, platform := range []string{"macos", "linux", "windows"} {
		workflow, err := newHostPlatformStagedReleaseWorkflow(platform, "launchctl", "systemctl", "fsutil.exe", "cmd.exe", "sc.exe")
		if err != nil || workflow == nil {
			t.Fatalf("platform=%s workflow=%v err=%v", platform, workflow, err)
		}
	}
}

func TestValidateDeclaredC50PathsRejectsCallerSubstitution(t *testing.T) {
	manifest := declaredPathManifest()
	if err := validateDeclaredC50Paths(manifest, "/other/journal.json", "/other/receipt.json"); err == nil {
		t.Fatal("expected caller-selected C50 paths to be rejected")
	}
	if err := validateDeclaredC50Paths(
		manifest,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-installation-receipt.json",
	); err != nil {
		t.Fatalf("expected declared C50 paths to be accepted: %v", err)
	}
}

func TestStagedHostPlatformForActiveManifestPathUsesOnlyC67Contracts(t *testing.T) {
	for _, test := range []struct {
		path string
		want string
	}{
		{"/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json", "macos"},
		{"/opt/vitalserver-runtime-platform/current/installation-manifest.json", "linux"},
		{`C:\ProgramData\VitalServerRuntimePlatform\current\installation-manifest.json`, "windows"},
	} {
		got, err := stagedHostPlatformForActiveManifestPath(test.path)
		if err != nil || got != test.want {
			t.Fatalf("path %q: got=%q err=%v want=%q", test.path, got, err, test.want)
		}
	}
	if _, err := stagedHostPlatformForActiveManifestPath("/tmp/current/installation-manifest.json"); err == nil {
		t.Fatal("expected non-C67 path to be rejected")
	}
}

func declaredPathManifest() hostinstallationmanagerdomain.HostProductInstallationManifest {
	releaseRoot := "/Library/Application Support/VitalServerRuntimePlatform/releases/release-001"
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "macos",
		Release:        hostinstallationmanagerdomain.HostProductRelease{ID: "release-001", ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"},
		Package:        hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.3.0"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{
			ReleaseCatalogPath: "/Library/Application Support/VitalServerRuntimePlatform/releases",
			ReleaseRootPath:    releaseRoot,
			ManifestPath:       releaseRoot + "/installation-manifest.json",
			Entries:            []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Executable: true}},
		},
		Activation:        hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot},
		OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", ApplicationBundlePath: hostinstallationmanagerdomain.MacOSHostProductOperatorApplicationBundlePath, ApplicationBundleTreeSHA256: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", ApplicationBundleEntrypointRelativePath: hostinstallationmanagerdomain.MacOSHostProductOperatorApplicationEntrypointRelativePath},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", DefinitionSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: hostinstallationmanagerdomain.HostInstallationTransactionStoreID, Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
		},
	}
}
