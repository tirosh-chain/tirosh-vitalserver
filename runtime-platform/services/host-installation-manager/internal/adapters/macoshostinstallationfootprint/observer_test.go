package macoshostinstallationfootprint

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostInstallationCommandRunnerFake struct {
	results map[string]HostInstallationCommandResult
	errors  map[string]error
}

func (fake hostInstallationCommandRunnerFake) RunHostInstallationCommand(_ context.Context, executable string, arguments ...string) (HostInstallationCommandResult, error) {
	key := executable
	for _, argument := range arguments {
		key += "|" + argument
	}
	if err := fake.errors[key]; err != nil {
		return HostInstallationCommandResult{}, err
	}
	return fake.results[key], nil
}

func observedHostInstallationManifest(root string) hostinstallationmanagerdomain.HostProductInstallationManifest {
	releaseRoot := filepath.Join(root, "releases", "release-001")
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "macos",
		Release:        hostinstallationmanagerdomain.HostProductRelease{ID: "release-001", ProductVersion: "0.2.0-dev", RuntimeVersion: "0.2.0"},
		Package:        hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.2.0-dev"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{
			ReleaseCatalogPath: filepath.Join(root, "releases"),
			ReleaseRootPath:    releaseRoot,
			ManifestPath:       filepath.Join(releaseRoot, "installation-manifest.json"),
			Entries: []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{
				{RelativePath: "bin/host-agent", SHA256: digestHostInstallationFile([]byte("host-agent")), Executable: true},
			},
		},
		Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: filepath.Join(root, "current"), ExpectedReleaseRootPath: releaseRoot},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: filepath.Join(root, "host-agent.plist"), DefinitionSHA256: digestHostInstallationFile([]byte("host-agent-plist"))},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: filepath.Join(root, "host-edge-proxy.plist"), DefinitionSHA256: digestHostInstallationFile([]byte("host-edge-proxy-plist"))},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "host-agent-state", Path: filepath.Join(root, "data", "host-agent")},
			{ID: "virtual-machine-runtime", Path: filepath.Join(root, "data", "virtual-machine")},
			{ID: "installation-manager-journal", Path: filepath.Join(root, "data", "installation-manager")},
		},
	}
}

func digestHostInstallationFile(bytes []byte) string {
	digest := sha256.Sum256(bytes)
	return hex.EncodeToString(digest[:])
}

func TestObserveHostInstallationFootprintKeepsCleanResourcesExplicitlyAbsent(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.PackageReceipt.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || footprint.RequiredServices[0].State != "absent" || footprint.MutableStores[0].State != "absent" || footprint.InstallationTransaction.State != "absent" {
		t.Fatalf("footprint=%+v", footprint)
	}
}

func TestObserveHostInstallationFootprintDoesNotConvertPackageCommandFailureToAbsence(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{
			results: map[string]HostInstallationCommandResult{
				"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
				"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
			},
			errors: map[string]error{
				"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform": errors.New("permission denied"),
			},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.PackageReceipt.State != "failed" || footprint.PackageReceipt.Issue == nil || footprint.PackageReceipt.Issue.Code != "macos-package-receipt-observation-failed" {
		t.Fatalf("package receipt=%+v", footprint.PackageReceipt)
	}
}

func TestObserveHostInstallationFootprintVerifiesEveryDeclaredImmutablePayloadByte(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	entryPath := filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "bin", "host-agent")
	if err := os.MkdirAll(filepath.Dir(entryPath), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(entryPath, []byte("different bytes"), 0755); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ImmutableRelease.State != "diverged" || footprint.ImmutableRelease.Issue == nil || footprint.ImmutableRelease.Issue.Code != "immutable-release-entry-digest-mismatch" {
		t.Fatalf("immutable release=%+v", footprint.ImmutableRelease)
	}
}

func TestObserveHostInstallationFootprintReportsOtherReleaseSlotsExplicitly(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	if err := os.MkdirAll(filepath.Join(manifest.ImmutablePayload.ReleaseCatalogPath, "release-previous"), 0755); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ReleaseCatalog.State != "contains-other-releases" || len(footprint.ReleaseCatalog.ReleaseIDs) != 1 || footprint.ReleaseCatalog.ReleaseIDs[0] != "release-previous" {
		t.Fatalf("releaseCatalog=%+v", footprint.ReleaseCatalog)
	}
}

func TestObserveHostInstallationFootprintDoesNotTreatResidualServiceDefinitionAsAbsent(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	if err := os.WriteFile(manifest.RequiredServices[0].DefinitionPath, []byte("different launchd definition"), 0644); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.RequiredServices[0].DefinitionState != "diverged" || footprint.RequiredServices[0].DefinitionIssue == nil || footprint.RequiredServices[0].DefinitionIssue.Code != "service-definition-digest-mismatch" {
		t.Fatalf("service=%+v", footprint.RequiredServices[0])
	}
}

func TestObserveHostInstallationFootprintDoesNotFollowReleaseCatalogSymbolicLink(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	externalCatalog := filepath.Join(root, "external-catalog")
	if err := os.Mkdir(externalCatalog, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(externalCatalog, manifest.ImmutablePayload.ReleaseCatalogPath); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ReleaseCatalog.State != "contains-unexpected-entry" || footprint.ReleaseCatalog.Issue == nil || footprint.ReleaseCatalog.Issue.Code != "release-catalog-is-not-directory" {
		t.Fatalf("releaseCatalog=%+v", footprint.ReleaseCatalog)
	}
}

func TestObserveHostInstallationFootprintDoesNotTreatMutableStoreSymbolicLinkAsCompatible(t *testing.T) {
	root := t.TempDir()
	manifest := observedHostInstallationManifest(root)
	externalStore := filepath.Join(root, "external-store")
	if err := os.Mkdir(externalStore, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(manifest.MutableStores[0].Path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(externalStore, manifest.MutableStores[0].Path); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":    {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":      {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, filepath.Join(root, "data", "installation-manager", "current-transaction.json"))
	if err != nil {
		t.Fatal(err)
	}
	if footprint.MutableStores[0].State != "unreadable" || footprint.MutableStores[0].Issue == nil || footprint.MutableStores[0].Issue.Code != "mutable-store-is-symbolic-link" {
		t.Fatalf("mutableStore=%+v", footprint.MutableStores[0])
	}
}
