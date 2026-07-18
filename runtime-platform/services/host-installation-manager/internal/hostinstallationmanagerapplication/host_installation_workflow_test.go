package hostinstallationmanagerapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type hostInstallationManifestReaderFake struct {
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest
}

func (fake hostInstallationManifestReaderFake) ReadHostProductInstallationManifest(context.Context, string) (hostinstallationmanagerdomain.HostProductInstallationManifest, error) {
	return fake.manifest, nil
}

type hostInstallationFootprintObserverFake struct {
	footprint hostinstallationmanagerdomain.HostInstallationFootprint
}

func (fake hostInstallationFootprintObserverFake) ObserveHostInstallationFootprint(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest, string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	return fake.footprint, nil
}

type hostInstallationJournalStoreFake struct {
	journal hostinstallationmanagerdomain.HostInstallationJournal
	writes  []hostinstallationmanagerdomain.HostInstallationJournal
}

func (fake *hostInstallationJournalStoreFake) ReadHostInstallationJournal(context.Context, string) (hostinstallationmanagerdomain.HostInstallationJournal, error) {
	if fake.journal.State == "" {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, errors.New("journal is absent")
	}
	return fake.journal, nil
}

func (fake *hostInstallationJournalStoreFake) WriteHostInstallationJournal(_ context.Context, _ string, journal hostinstallationmanagerdomain.HostInstallationJournal) error {
	fake.journal = journal
	fake.writes = append(fake.writes, journal)
	return nil
}

type hostInstallationReceiptStoreFake struct {
	writes []hostinstallationmanagerdomain.HostInstallationReceipt
}

func (fake *hostInstallationReceiptStoreFake) WriteHostInstallationReceipt(_ context.Context, _ string, receipt hostinstallationmanagerdomain.HostInstallationReceipt) error {
	fake.writes = append(fake.writes, receipt)
	return nil
}

type hostProductReleaseActivatorFake struct{ calls int }

func (fake *hostProductReleaseActivatorFake) ActivateHostProductRelease(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return nil
}

type hostProductServiceQuiescerFake struct {
	calls int
	err   error
}

func (fake *hostProductServiceQuiescerFake) QuiesceHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return fake.err
}

type fixedHostInstallationClock struct{}

func (fixedHostInstallationClock) Now() time.Time {
	return time.Date(2026, 7, 18, 3, 0, 0, 0, time.UTC)
}

func workflowManifest() hostinstallationmanagerdomain.HostProductInstallationManifest {
	return hostinstallationmanagerdomain.HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "macos",
		Release:        hostinstallationmanagerdomain.HostProductRelease{ID: "runtime-platform-0.2.0-dev-build-001", ProductVersion: "0.2.0-dev", RuntimeVersion: "0.2.0"},
		Package:        hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.2.0-dev"},
		ImmutablePayload: hostinstallationmanagerdomain.HostImmutableProductPayload{
			ReleaseCatalogPath: "/Library/Application Support/VitalServerRuntimePlatform/releases",
			ReleaseRootPath:    "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001",
			ManifestPath:       "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001/installation-manifest.json",
			Entries:            []hostinstallationmanagerdomain.HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Executable: true}},
		},
		Activation: hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001"},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "host-agent-state", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/host-agent"},
			{ID: "virtual-machine-runtime", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/virtual-machine"},
			{ID: "installation-manager-journal", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager"},
		},
	}
}

func workflowFootprint(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) hostinstallationmanagerdomain.HostInstallationFootprint {
	return hostinstallationmanagerdomain.HostInstallationFootprint{
		SchemaVersion:     "v1",
		InstallationID:    manifest.InstallationID,
		ExpectedReleaseID: manifest.Release.ID,
		Platform:          "macos",
		ObservedAt:        "2026-07-18T03:00:00Z",
		PackageReceipt:    hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: manifest.Package.Identifier},
		ReleaseCatalog:    hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "absent", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath},
		ImmutableRelease:  hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "absent", ReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath},
		Activation:        hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "absent", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath},
		RequiredServices: []hostinstallationmanagerdomain.HostInstallationServiceObservation{
			{Role: "host-agent", Name: "com.tirosh.vitalserver.host-agent", State: "absent", DefinitionState: "absent"},
			{Role: "host-edge-proxy", Name: "com.tirosh.vitalserver.host-edge-proxy", State: "absent", DefinitionState: "absent"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{
			{ID: "host-agent-state", State: "absent"},
			{ID: "virtual-machine-runtime", State: "absent"},
			{ID: "installation-manager-journal", State: "absent"},
		},
		InstallationTransaction: hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "absent", JournalPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json"},
	}
}

func workflowPreflightRequest(manifest hostinstallationmanagerdomain.HostProductInstallationManifest) hostinstallationmanagerdomain.HostInstallationRequest {
	return hostinstallationmanagerdomain.HostInstallationRequest{
		SchemaVersion:     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		DocumentKind:      "host-installation-request",
		ID:                "install-request-1",
		InstallationID:    manifest.InstallationID,
		Operation:         hostinstallationmanagerdomain.HostInstallationOperationPreflight,
		ExpectedReleaseID: manifest.Release.ID,
		RequestedAt:       "2026-07-18T03:00:00Z",
	}
}

func TestExecuteHostInstallationPreflightWritesJournalOnlyForAdmittedCleanInstall(t *testing.T) {
	manifest := workflowManifest()
	journalStore := &hostInstallationJournalStoreFake{}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), workflowPreflightRequest(manifest), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptPreflightAdmitted || len(journalStore.writes) != 1 || len(receiptStore.writes) != 1 || activator.calls != 0 {
		t.Fatalf("receipt=%+v journalWrites=%d receiptWrites=%d activations=%d err=%v", receipt, len(journalStore.writes), len(receiptStore.writes), activator.calls, err)
	}
}

func TestExecuteHostInstallationPreflightBlocksDirectUpdateWithoutJournal(t *testing.T) {
	manifest := workflowManifest()
	footprint := workflowFootprint(manifest)
	footprint.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: "0.1.0"}
	footprint.ImmutableRelease.State = "matching"
	footprint.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.1.0"}
	journalStore := &hostInstallationJournalStoreFake{}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: footprint}, journalStore, receiptStore, activator, quiescer, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), workflowPreflightRequest(manifest), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.Issue == nil || receipt.Issue.Code != "direct-version-upgrade-requires-staged-updater" || len(journalStore.writes) != 0 || activator.calls != 0 {
		t.Fatalf("receipt=%+v journalWrites=%d activations=%d err=%v", receipt, len(journalStore.writes), activator.calls, err)
	}
}

func TestExecuteHostProductServiceQuiescenceAdvancesOnlyPreflightVerifiedJournal(t *testing.T) {
	manifest := workflowManifest()
	journalStore := &hostInstallationJournalStoreFake{journal: hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "install-request-1-journal",
		RequestID:      "install-request-1",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostProductServiceQuiescence(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptServicesQuiesced || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalActivationPending || quiescer.calls != 1 || len(receiptStore.writes) != 1 {
		t.Fatalf("receipt=%+v journal=%+v calls=%d receiptWrites=%d err=%v", receipt, journalStore.journal, quiescer.calls, len(receiptStore.writes), err)
	}
}

func TestExecuteHostProductServiceQuiescencePersistsFailure(t *testing.T) {
	manifest := workflowManifest()
	journalStore := &hostInstallationJournalStoreFake{journal: hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "install-request-1-journal",
		RequestID:      "install-request-1",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{err: errors.New("launchctl failed")}
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostProductServiceQuiescence(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptFailed || receipt.Issue == nil || receipt.Issue.Code != "service-quiescence-failed" || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalFailed || quiescer.calls != 1 {
		t.Fatalf("receipt=%+v journal=%+v calls=%d err=%v", receipt, journalStore.journal, quiescer.calls, err)
	}
}

func TestExecuteHostProductReleaseActivationCompletesExactQuiescedTransaction(t *testing.T) {
	manifest := workflowManifest()
	footprint := workflowFootprint(manifest)
	footprint.ImmutableRelease.State = "matching"
	journalStore := &hostInstallationJournalStoreFake{journal: hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "install-request-1-journal",
		RequestID:      "install-request-1",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalActivationPending,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: footprint},
		journalStore,
		receiptStore,
		activator,
		quiescer,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	receipt, err := workflow.ExecuteHostProductReleaseActivation(
		context.Background(),
		"manifest",
		"journal",
		"receipt",
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptActivated || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalActivated || activator.calls != 1 || len(receiptStore.writes) != 1 {
		t.Fatalf("receipt=%+v journal=%+v activations=%d receiptWrites=%d err=%v", receipt, journalStore.journal, activator.calls, len(receiptStore.writes), err)
	}
}
