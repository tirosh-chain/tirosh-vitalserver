package hostinstallationtransactionfile

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func TestRecordHostInstallationTransactionWritesC50ReceiptBeforeTerminalJournal(t *testing.T) {
	root := t.TempDir()
	resolvedRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatalf("resolve temporary root: %v", err)
	}
	manifest := testManifest(resolvedRoot)
	journal := hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "update-030-host-platform-apply-installation-journal",
		RequestID:      "update-030-host-platform-apply",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalCompleted,
		CreatedAt:      "2026-07-20T00:00:00Z",
		UpdatedAt:      "2026-07-20T00:00:00Z",
	}
	receipt := hostinstallationmanagerdomain.HostInstallationReceipt{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-receipt",
		ID:             "update-030-host-platform-apply-installation-receipt",
		RequestID:      "update-030-host-platform-apply",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationReceiptCompleted,
		ObservedAt:     "2026-07-20T00:00:00Z",
	}

	if err := (Store{}).RecordHostInstallationTransaction(context.Background(), manifest, journal, receipt); err != nil {
		t.Fatal(err)
	}
	journalPath, receiptPath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionPaths(manifest)
	if err != nil {
		t.Fatal(err)
	}
	observedJournal, err := (hostinstallationjournalfile.HostInstallationJournalFileStore{}).ReadHostInstallationJournal(context.Background(), journalPath)
	if err != nil {
		t.Fatal(err)
	}
	observedReceipt, err := (hostinstallationreceiptfile.HostInstallationReceiptFileStore{}).ReadHostInstallationReceipt(context.Background(), receiptPath)
	if err != nil {
		t.Fatal(err)
	}
	if observedJournal != journal || observedReceipt != receipt {
		t.Fatalf("journal=%+v receipt=%+v", observedJournal, observedReceipt)
	}
}

func testManifest(root string) hostinstallationmanagerdomain.HostProductInstallationManifest {
	releaseRoot := filepath.Join(root, "releases", "release-030")
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "macos",
		Release:        hostinstallationmanagerdomain.HostProductRelease{ID: "release-030", ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"},
		Package:        hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.3.0"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{
			ReleaseCatalogPath: filepath.Join(root, "releases"),
			ReleaseRootPath:    releaseRoot,
			ManifestPath:       filepath.Join(releaseRoot, "installation-manifest.json"),
			Entries:            []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Executable: true}},
		},
		Activation:        hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: filepath.Join(root, "current"), ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: releaseRoot},
		OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: filepath.Join(root, "control", "runtime-console-bootstrap.json"), BootstrapConfigurationSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: filepath.Join(root, "services", "host-agent.plist"), DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: filepath.Join(root, "services", "host-edge-proxy.plist"), DefinitionSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: filepath.Join(root, "services", "host-update-handoff-supervisor.plist"), DefinitionSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "installation-data-root", Path: filepath.Join(root, "data"), Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
			{ID: hostinstallationmanagerdomain.HostInstallationTransactionStoreID, Path: filepath.Join(root, "data", "installation-manager"), Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
		},
	}
}
