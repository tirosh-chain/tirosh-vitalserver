package macoshostinstallationfootprint

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationreceiptfile"
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
		Activation:        hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: filepath.Join(root, "current"), ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot},
		OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: filepath.Join(root, "control", "runtime-console-bootstrap.json"), BootstrapConfigurationSHA256: digestHostInstallationFile([]byte("runtime-console-bootstrap"))},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: filepath.Join(root, "host-agent.plist"), DefinitionSHA256: digestHostInstallationFile([]byte("host-agent-plist"))},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: filepath.Join(root, "host-edge-proxy.plist"), DefinitionSHA256: digestHostInstallationFile([]byte("host-edge-proxy-plist"))},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: filepath.Join(root, "host-update-handoff-supervisor.plist"), DefinitionSHA256: digestHostInstallationFile([]byte("host-update-handoff-supervisor-plist"))},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "host-agent-state", Path: filepath.Join(root, "data", "host-agent"), Kind: "directory", Owner: "host-agent", Retention: "preserve-by-default"},
			{ID: "virtual-machine-runtime", Path: filepath.Join(root, "data", "virtual-machine"), Kind: "directory", Owner: "macos-virtual-machine-supervisor", Retention: "preserve-by-default"},
			{ID: "installation-manager-journal", Path: filepath.Join(root, "data", "installation-manager"), Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
		},
	}
}

func digestHostInstallationFile(bytes []byte) string {
	digest := sha256.Sum256(bytes)
	return hex.EncodeToString(digest[:])
}

func resolvedHostInstallationTestRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func observedInstallationTransactionPaths(root string) (string, string) {
	directory := filepath.Join(root, "data", "installation-manager")
	return filepath.Join(directory, "current-transaction.json"), filepath.Join(directory, "latest-installation-receipt.json")
}

func observeTestHostInstallationFootprint(context context.Context, observer *MacOSHostInstallationFootprintObserver, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, root string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	journalPath, receiptPath := observedInstallationTransactionPaths(root)
	return observer.ObserveHostInstallationFootprint(context, manifest, journalPath, receiptPath)
}

func writeLegacyBlockedPreflightReceipt(t *testing.T, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, receiptPath string) {
	t.Helper()
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-receipt",
		ID:             "historical-installation-receipt-001",
		RequestID:      "historical-installation-request-001",
		InstallationID: manifest.InstallationID,
		ReleaseID:      "runtime-platform-0.2.0-dev-build-historical",
		State:          hostinstallationmanagerdomain.HostInstallationReceiptBlocked,
		Issue:          &hostinstallationmanagerdomain.HostInstallationIssue{Code: "macos-service-observation-failed", Message: "launchctl exited with status 113", Dependency: "launchctl"},
		ObservedAt:     "2026-07-18T03:00:00Z",
	}
	if err := (hostinstallationreceiptfile.HostInstallationReceiptFileStore{}).WriteHostInstallationReceipt(context.Background(), receiptPath, receipt); err != nil {
		t.Fatal(err)
	}
}

func TestObserveHostInstallationFootprintKeepsCleanResourcesExplicitlyAbsent(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":                   {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":                     {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy":                {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-update-handoff-supervisor": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.PackageReceipt.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || footprint.RequiredServices[0].State != "absent" || footprint.MutableStores[0].State != "absent" || footprint.InstallationTransaction.State != "absent" {
		t.Fatalf("footprint=%+v", footprint)
	}
}

func TestObserveHostInstallationFootprintRecognizesOnlyLegacyBlockedPreflightReceipt(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	manifest.MutableStores = append(manifest.MutableStores, hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
		ID:        "installation-data-root",
		Path:      filepath.Join(root, "data"),
		Kind:      "directory",
		Owner:     "host-installation-manager",
		Retention: "purge-only-by-explicit-command",
	})
	_, receiptPath := observedInstallationTransactionPaths(root)
	writeLegacyBlockedPreflightReceipt(t, manifest, receiptPath)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.InstallationTransaction.State != "legacy-blocked-preflight" {
		t.Fatalf("transaction=%+v", footprint.InstallationTransaction)
	}
}

func TestObserveHostInstallationFootprintKeepsAdditionalReceiptResidueExplicit(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	manifest.MutableStores = append(manifest.MutableStores, hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
		ID:        "installation-data-root",
		Path:      filepath.Join(root, "data"),
		Kind:      "directory",
		Owner:     "host-installation-manager",
		Retention: "purge-only-by-explicit-command",
	})
	_, receiptPath := observedInstallationTransactionPaths(root)
	writeLegacyBlockedPreflightReceipt(t, manifest, receiptPath)
	if err := os.WriteFile(filepath.Join(filepath.Dir(receiptPath), "unexpected-state.json"), []byte("residue"), 0600); err != nil {
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.InstallationTransaction.State != "receipt-residue" {
		t.Fatalf("transaction=%+v", footprint.InstallationTransaction)
	}
}

func TestObserveHostInstallationFootprintRecognizesMacOS26ExplicitMissingServiceResponse(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform": {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent": {
				ExitCode: 113,
				Stderr:   "Bad request.\nCould not find service \"com.tirosh.vitalserver.host-agent\" in domain for system\n",
			},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {
				ExitCode: 113,
				Stderr:   "Bad request.\nCould not find service \"com.tirosh.vitalserver.host-edge-proxy\" in domain for system\n",
			},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.RequiredServices[0].State != "absent" || footprint.RequiredServices[1].State != "absent" {
		t.Fatalf("services=%+v", footprint.RequiredServices)
	}
}

func TestObserveHostInstallationFootprintDoesNotTreatGenericMacOS26Status113AsAbsent(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform": {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent": {
				ExitCode: 113,
				Stderr:   "Bad request.\nCould not find service \"another.service\" in domain for system\n",
			},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	service := footprint.RequiredServices[0]
	if service.State != "failed" || service.Issue == nil || service.Issue.Code != "macos-service-observation-failed" {
		t.Fatalf("service=%+v", service)
	}
}

func TestObserveHostInstallationFootprintDoesNotConvertPackageCommandFailureToAbsence(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.PackageReceipt.State != "failed" || footprint.PackageReceipt.Issue == nil || footprint.PackageReceipt.Issue.Code != "macos-package-receipt-observation-failed" {
		t.Fatalf("package receipt=%+v", footprint.PackageReceipt)
	}
}

func TestObserveHostInstallationFootprintVerifiesEveryDeclaredImmutablePayloadByte(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ImmutableRelease.State != "diverged" || footprint.ImmutableRelease.Issue == nil || footprint.ImmutableRelease.Issue.Code != "immutable-release-entry-digest-mismatch" {
		t.Fatalf("immutable release=%+v", footprint.ImmutableRelease)
	}
}

func TestObserveHostInstallationFootprintReportsOtherReleaseSlotsExplicitly(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ReleaseCatalog.State != "contains-other-releases" || len(footprint.ReleaseCatalog.ReleaseIDs) != 1 || footprint.ReleaseCatalog.ReleaseIDs[0] != "release-previous" {
		t.Fatalf("releaseCatalog=%+v", footprint.ReleaseCatalog)
	}
}

func TestObserveHostInstallationFootprintDoesNotTreatResidualServiceDefinitionAsAbsent(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.RequiredServices[0].DefinitionState != "diverged" || footprint.RequiredServices[0].DefinitionIssue == nil || footprint.RequiredServices[0].DefinitionIssue.Code != "service-definition-digest-mismatch" {
		t.Fatalf("service=%+v", footprint.RequiredServices[0])
	}
}

func TestObserveHostInstallationFootprintDoesNotFollowReleaseCatalogSymbolicLink(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.ReleaseCatalog.State != "unreadable" || footprint.ReleaseCatalog.Issue == nil || footprint.ReleaseCatalog.Issue.Code != "release-catalog-path-unreadable" {
		t.Fatalf("releaseCatalog=%+v", footprint.ReleaseCatalog)
	}
}

func TestObserveHostInstallationFootprintDoesNotTreatMutableStoreSymbolicLinkAsCompatible(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
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
	footprint, err := observeTestHostInstallationFootprint(context.Background(), observer, manifest, root)
	if err != nil {
		t.Fatal(err)
	}
	if footprint.MutableStores[0].State != "unreadable" || footprint.MutableStores[0].Issue == nil || footprint.MutableStores[0].Issue.Code != "mutable-store-path-unreadable" {
		t.Fatalf("mutableStore=%+v", footprint.MutableStores[0])
	}
}

func TestObserveMutableStoreDoesNotFollowAnAncestorSymbolicLink(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	target := filepath.Join(root, "target")
	if err := os.MkdirAll(target, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(root, "data")); err != nil {
		t.Fatal(err)
	}

	store := observeMutableStore(manifest.MutableStores[0])
	if store.State != "unreadable" || store.Issue == nil || store.Issue.Code != "mutable-store-path-unreadable" {
		t.Fatalf("mutableStore=%+v", store)
	}
}

func TestObserveReleaseActivationReportsOtherReleaseWhenExpectedSlotIsNotWrittenYet(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	previousRelease := filepath.Join(root, "releases", "release-previous")
	if err := os.MkdirAll(previousRelease, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(previousRelease, manifest.Activation.CurrentReleaseLinkPath); err != nil {
		t.Fatal(err)
	}
	observation := observeReleaseActivation(manifest.Activation)
	if observation.State != "points-to-other-release" || observation.ObservedTargetPath == "" {
		t.Fatalf("activation=%+v", observation)
	}
}

func TestObserveMutableStoreReportsRegularFileAsIncompatible(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	store := manifest.MutableStores[0]
	if err := os.MkdirAll(filepath.Dir(store.Path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(store.Path, []byte("not a directory"), 0644); err != nil {
		t.Fatal(err)
	}
	observation := observeMutableStore(store)
	if observation.State != "incompatible" || observation.Issue == nil || observation.Issue.Code != "mutable-store-kind-incompatible" {
		t.Fatalf("mutableStore=%+v", observation)
	}
}

func TestObserveImmutableReleaseRejectsUndeclaredFileAndExecutableModeMismatch(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	entryPath := filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "bin", "host-agent")
	if err := os.MkdirAll(filepath.Dir(entryPath), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(entryPath, []byte("host-agent"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifest.ImmutablePayload.ManifestPath, []byte("{}"), 0644); err != nil {
		t.Fatal(err)
	}
	observation := observeImmutableRelease(manifest.ImmutablePayload)
	if observation.State != "diverged" || observation.Issue == nil || observation.Issue.Code != "immutable-release-entry-executable-mode-mismatch" {
		t.Fatalf("immutableRelease=%+v", observation)
	}
	if err := os.Chmod(entryPath, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(manifest.ImmutablePayload.ReleaseRootPath, "unexpected"), []byte("extra"), 0644); err != nil {
		t.Fatal(err)
	}
	observation = observeImmutableRelease(manifest.ImmutablePayload)
	if observation.State != "diverged" || observation.Issue == nil || observation.Issue.Code != "immutable-release-inventory-extra-file" {
		t.Fatalf("immutableRelease=%+v", observation)
	}
}

func TestObserveInstallationTransactionRejectsJournalWithDifferentReleaseIdentity(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	journalPath, receiptPath := observedInstallationTransactionPaths(root)
	if err := os.MkdirAll(filepath.Dir(journalPath), 0755); err != nil {
		t.Fatal(err)
	}
	journal := `{"schemaVersion":"v1","documentKind":"host-installation-journal","id":"journal-001","requestId":"request-001","installationId":"vitalserver-runtime-platform","releaseId":"different-release","state":"completed","createdAt":"2026-07-18T03:00:00Z","updatedAt":"2026-07-18T03:00:00Z"}`
	if err := os.WriteFile(journalPath, []byte(journal), 0600); err != nil {
		t.Fatal(err)
	}
	observation := observeInstallationTransaction(manifest, journalPath, receiptPath)
	if observation.State != "unreadable" || observation.Issue == nil || observation.Issue.Code != "installation-journal-identity-mismatch" {
		t.Fatalf("transaction=%+v", observation)
	}
}

func TestPreflightOnlyJournalFootprintCanRetryAfterPayloadDeliveryDidNotStart(t *testing.T) {
	root := resolvedHostInstallationTestRoot(t)
	manifest := observedHostInstallationManifest(root)
	manifest.MutableStores = append(manifest.MutableStores, hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
		ID:        "installation-data-root",
		Path:      filepath.Join(root, "data"),
		Kind:      "directory",
		Owner:     "host-installation-manager",
		Retention: "purge-only-by-explicit-command",
	})
	journalPath, receiptPath := observedInstallationTransactionPaths(root)
	journal := hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "installation-request-001-journal",
		RequestID:      "installation-request-001",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}
	if err := (hostinstallationjournalfile.HostInstallationJournalFileStore{}).WriteHostInstallationJournal(context.Background(), journalPath, journal); err != nil {
		t.Fatal(err)
	}
	observer, err := NewMacOSHostInstallationFootprintObserverWithCommandRunner(
		"pkgutil",
		"launchctl",
		hostInstallationCommandRunnerFake{results: map[string]HostInstallationCommandResult{
			"pkgutil|--pkg-info|com.tirosh.vitalserver.runtime-platform":                   {ExitCode: 1},
			"launchctl|print|system/com.tirosh.vitalserver.host-agent":                     {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-edge-proxy":                {ExitCode: 3},
			"launchctl|print|system/com.tirosh.vitalserver.host-update-handoff-supervisor": {ExitCode: 3},
		}},
	)
	if err != nil {
		t.Fatal(err)
	}
	footprint, err := observer.ObserveHostInstallationFootprint(context.Background(), manifest, journalPath, receiptPath)
	if err != nil {
		t.Fatal(err)
	}
	request := hostinstallationmanagerdomain.HostInstallationRequest{
		SchemaVersion:     "v1",
		DocumentKind:      "host-installation-request",
		ID:                "installation-request-002",
		InstallationID:    manifest.InstallationID,
		Operation:         hostinstallationmanagerdomain.HostInstallationOperationPreflight,
		ExpectedReleaseID: manifest.Release.ID,
		RequestedAt:       "2026-07-18T03:01:00Z",
	}
	decision, err := hostinstallationmanagerdomain.DecideHostInstallationPreflight(request, manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "clean-install-retry" {
		t.Fatalf("footprint=%+v decision=%+v err=%v", footprint, decision, err)
	}
}
