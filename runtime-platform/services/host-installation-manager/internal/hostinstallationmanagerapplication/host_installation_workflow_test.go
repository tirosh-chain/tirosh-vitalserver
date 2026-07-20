package hostinstallationmanagerapplication

import (
	"context"
	"errors"
	"os"
	"reflect"
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
	footprint  hostinstallationmanagerdomain.HostInstallationFootprint
	footprints []hostinstallationmanagerdomain.HostInstallationFootprint
	calls      *int
	paths      *[2]string
}

func (fake hostInstallationFootprintObserverFake) ObserveHostInstallationFootprint(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	if fake.paths != nil {
		*fake.paths = [2]string{journalPath, receiptPath}
	}
	if len(fake.footprints) == 0 {
		return fake.footprint, nil
	}
	if fake.calls == nil {
		return fake.footprints[0], nil
	}
	*fake.calls++
	index := *fake.calls - 1
	if index >= len(fake.footprints) {
		index = len(fake.footprints) - 1
	}
	return fake.footprints[index], nil
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

type hostProductRemovalJournalStoreFake struct {
	journal hostinstallationmanagerdomain.HostProductRemovalJournal
	writes  []hostinstallationmanagerdomain.HostProductRemovalJournal
}

func (fake *hostProductRemovalJournalStoreFake) ReadHostProductRemovalJournal(context.Context, string) (hostinstallationmanagerdomain.HostProductRemovalJournal, error) {
	if fake.journal.State == "" {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, os.ErrNotExist
	}
	return fake.journal, nil
}

func (fake *hostProductRemovalJournalStoreFake) WriteHostProductRemovalJournal(_ context.Context, _ string, journal hostinstallationmanagerdomain.HostProductRemovalJournal) error {
	fake.journal = journal
	fake.writes = append(fake.writes, journal)
	return nil
}

type hostProductRemovalReceiptStoreFake struct {
	writes []hostinstallationmanagerdomain.HostProductRemovalReceipt
}

func (fake *hostProductRemovalReceiptStoreFake) WriteHostProductRemovalReceipt(_ context.Context, _ string, receipt hostinstallationmanagerdomain.HostProductRemovalReceipt) error {
	fake.writes = append(fake.writes, receipt)
	return nil
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

type hostProductServiceReconcilerFake struct {
	calls int
	err   error
}

type hostProductRemovalEffectsFake struct {
	completionTransport      hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport
	completionTransportCalls int
	serviceDefinitions       int
	activationLink           int
	releaseCatalog           int
	mutableStores            []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration
	packageReceipt           int
	packageReceiptRemoval    hostinstallationmanagerdomain.HostProductPackageReceiptRemoval
	serviceDefinitionError   error
}

func (fake *hostProductRemovalEffectsFake) PrepareHostProductPackageManagerCompletionTransport(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, transport hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport) error {
	fake.completionTransportCalls++
	fake.completionTransport = transport
	return nil
}

func (fake *hostProductRemovalEffectsFake) RemoveHostProductServiceDefinitions(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.serviceDefinitions++
	return fake.serviceDefinitionError
}

func (fake *hostProductRemovalEffectsFake) RemoveHostProductActivationLink(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.activationLink++
	return nil
}

func (fake *hostProductRemovalEffectsFake) RemoveHostProductReleaseCatalog(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.releaseCatalog++
	return nil
}

func (fake *hostProductRemovalEffectsFake) RemoveHostProductMutableStores(_ context.Context, _ hostinstallationmanagerdomain.HostProductInstallationManifest, stores []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) error {
	fake.mutableStores = append([]hostinstallationmanagerdomain.HostProductMutableStoreDeclaration(nil), stores...)
	return nil
}

func (fake *hostProductRemovalEffectsFake) RemoveHostProductPackageReceipt(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) (hostinstallationmanagerdomain.HostProductPackageReceiptRemoval, error) {
	fake.packageReceipt++
	if fake.packageReceiptRemoval.State == "" {
		// The base fake models the native macOS pkgutil protocol. Tests that
		// exercise dpkg/MSI hand-off set the outcome explicitly.
		return hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByManager}, nil
	}
	return fake.packageReceiptRemoval, nil
}

func (fake *hostProductServiceReconcilerFake) ReconcileHostProductServices(context.Context, hostinstallationmanagerdomain.HostProductInstallationManifest) error {
	fake.calls++
	return fake.err
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
		Activation:        hostinstallationmanagerdomain.HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001"},
		OperatorInterface: hostinstallationmanagerdomain.HostProductOperatorInterface{BootstrapConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"},
		RequiredServices: []hostinstallationmanagerdomain.HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", DefinitionSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostProductMutableStoreDeclaration{
			{ID: "host-agent-state", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/host-agent", Kind: "directory", Owner: "host-agent", Retention: "preserve-by-default"},
			{ID: "virtual-machine-runtime", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/virtual-machine", Kind: "directory", Owner: "macos-virtual-machine-supervisor", Retention: "preserve-by-default"},
			{ID: "installation-manager-journal", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
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
			{Role: "host-update-handoff-supervisor", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", State: "absent", DefinitionState: "absent"},
		},
		MutableStores: []hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{
			{ID: "host-agent-state", State: "absent"},
			{ID: "virtual-machine-runtime", State: "absent"},
			{ID: "installation-manager-journal", State: "absent"},
		},
		InstallationTransaction: hostinstallationmanagerdomain.HostInstallationTransactionObservation{
			State:       "absent",
			JournalPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json",
			ReceiptPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-installation-receipt.json",
		},
	}
}

func TestObserveHostInstallationFootprintReturnsOnlyHostObservation(t *testing.T) {
	manifest := workflowManifest()
	observed := workflowFootprint(manifest)
	journalStore := &hostInstallationJournalStoreFake{}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	reconciler := &hostProductServiceReconcilerFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: observed},
		journalStore,
		receiptStore,
		activator,
		quiescer,
		reconciler,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	observedPaths := [2]string{}
	workflow.footprintObserver = hostInstallationFootprintObserverFake{footprint: observed, paths: &observedPaths}
	footprint, err := workflow.ObserveDeclaredHostInstallationFootprint(context.Background(), "/declared/installation-manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(footprint, observed) {
		t.Fatalf("footprint = %#v, want %#v", footprint, observed)
	}
	if len(journalStore.writes) != 0 || len(receiptStore.writes) != 0 || activator.calls != 0 || quiescer.calls != 0 || reconciler.calls != 0 {
		t.Fatalf("observation must not create or reconcile Host state: journal=%d receipt=%d activation=%d quiescence=%d reconciliation=%d", len(journalStore.writes), len(receiptStore.writes), activator.calls, quiescer.calls, reconciler.calls)
	}
	wantPaths := [2]string{
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-installation-receipt.json",
	}
	if observedPaths != wantPaths {
		t.Fatalf("C49 paths = %#v, want %#v", observedPaths, wantPaths)
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
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, &hostProductServiceReconcilerFake{}, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), workflowPreflightRequest(manifest), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptPreflightAdmitted || len(journalStore.writes) != 1 || len(receiptStore.writes) != 1 || activator.calls != 0 {
		t.Fatalf("receipt=%+v journalWrites=%d receiptWrites=%d activations=%d err=%v", receipt, len(journalStore.writes), len(receiptStore.writes), activator.calls, err)
	}
}

func TestExecuteHostInstallationPreflightReplacesOnlyAdmittedLegacyBlockedReceipt(t *testing.T) {
	manifest := workflowManifest()
	footprint := workflowFootprint(manifest)
	footprint.InstallationTransaction.State = "legacy-blocked-preflight"
	footprint.MutableStores[2].State = "compatible"
	journalStore := &hostInstallationJournalStoreFake{}
	receiptStore := &hostInstallationReceiptStoreFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: footprint},
		journalStore,
		receiptStore,
		&hostProductReleaseActivatorFake{},
		&hostProductServiceQuiescerFake{},
		&hostProductServiceReconcilerFake{},
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), workflowPreflightRequest(manifest), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptPreflightAdmitted || len(journalStore.writes) != 1 || len(receiptStore.writes) != 1 {
		t.Fatalf("receipt=%+v journalWrites=%d receiptWrites=%d err=%v", receipt, len(journalStore.writes), len(receiptStore.writes), err)
	}
}

func TestExecuteHostInstallationPreflightBlocksDirectUpdateWithoutPersistingProductState(t *testing.T) {
	manifest := workflowManifest()
	footprint := workflowFootprint(manifest)
	footprint.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: "0.1.0"}
	footprint.ImmutableRelease.State = "matching"
	footprint.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.1.0"}
	journalStore := &hostInstallationJournalStoreFake{}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: footprint}, journalStore, receiptStore, activator, quiescer, &hostProductServiceReconcilerFake{}, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), workflowPreflightRequest(manifest), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.Issue == nil || receipt.Issue.Code != "direct-version-upgrade-requires-staged-updater" || len(journalStore.writes) != 0 || len(receiptStore.writes) != 0 || activator.calls != 0 {
		t.Fatalf("receipt=%+v journalWrites=%d receiptWrites=%d activations=%d err=%v", receipt, len(journalStore.writes), len(receiptStore.writes), activator.calls, err)
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
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, &hostProductServiceReconcilerFake{}, fixedHostInstallationClock{})
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.ExecuteHostProductServiceQuiescence(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptServicesQuiesced || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalActivationPending || len(journalStore.writes) != 2 || journalStore.writes[0].State != hostinstallationmanagerdomain.HostInstallationJournalServicesQuiescing || quiescer.calls != 1 || len(receiptStore.writes) != 1 {
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
	workflow, err := NewHostInstallationWorkflow(hostInstallationManifestReaderFake{manifest: manifest}, hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)}, journalStore, receiptStore, activator, quiescer, &hostProductServiceReconcilerFake{}, fixedHostInstallationClock{})
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
		&hostProductServiceReconcilerFake{},
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

func TestExecuteHostProductServiceFinalizationCompletesActivatedTransaction(t *testing.T) {
	manifest := workflowManifest()
	journalStore := &hostInstallationJournalStoreFake{journal: hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "install-request-1-journal",
		RequestID:      "install-request-1",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalActivated,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	reconciler := &hostProductServiceReconcilerFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)},
		journalStore,
		receiptStore,
		activator,
		quiescer,
		reconciler,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	receipt, err := workflow.ExecuteHostProductServiceFinalization(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptCompleted || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalCompleted || reconciler.calls != 1 || activator.calls != 0 {
		t.Fatalf("receipt=%+v journal=%+v reconciliations=%d activations=%d err=%v", receipt, journalStore.journal, reconciler.calls, activator.calls, err)
	}
}

func TestExecuteHostInstallationRecoveryCompletesInterruptedServiceQuiescence(t *testing.T) {
	manifest := workflowManifest()
	footprint := workflowFootprint(manifest)
	footprint.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.ReleaseCatalog = hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.ImmutableRelease.State = "matching"
	journalStore := &hostInstallationJournalStoreFake{journal: hostinstallationmanagerdomain.HostInstallationJournal{
		SchemaVersion:  "v1",
		DocumentKind:   "host-installation-journal",
		ID:             "install-request-1-journal",
		RequestID:      "install-request-1",
		InstallationID: manifest.InstallationID,
		ReleaseID:      manifest.Release.ID,
		State:          hostinstallationmanagerdomain.HostInstallationJournalServicesQuiescing,
		CreatedAt:      "2026-07-18T03:00:00Z",
		UpdatedAt:      "2026-07-18T03:00:00Z",
	}}
	receiptStore := &hostInstallationReceiptStoreFake{}
	activator := &hostProductReleaseActivatorFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	reconciler := &hostProductServiceReconcilerFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: footprint},
		journalStore,
		receiptStore,
		activator,
		quiescer,
		reconciler,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	receipt, err := workflow.ExecuteHostInstallationRecovery(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptRecovered || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalRecovered || activator.calls != 1 || reconciler.calls != 1 {
		t.Fatalf("receipt=%+v journal=%+v activations=%d reconciliations=%d err=%v", receipt, journalStore.journal, activator.calls, reconciler.calls, err)
	}
}

func TestExecuteHostInstallationRecoveryMarksPreflightOnlyTransactionRecoveredWithoutServiceEffect(t *testing.T) {
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
	reconciler := &hostProductServiceReconcilerFake{}
	workflow, err := NewHostInstallationWorkflow(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: workflowFootprint(manifest)},
		journalStore,
		receiptStore,
		activator,
		quiescer,
		reconciler,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}

	receipt, err := workflow.ExecuteHostInstallationRecovery(context.Background(), "manifest", "journal", "receipt")
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostInstallationReceiptRecovered || journalStore.journal.State != hostinstallationmanagerdomain.HostInstallationJournalRecovered || activator.calls != 0 || reconciler.calls != 0 {
		t.Fatalf("receipt=%+v journal=%+v activations=%d reconciliations=%d err=%v", receipt, journalStore.journal, activator.calls, reconciler.calls, err)
	}
}

func TestExecuteHostProductRemovalPreservesMutableDataAndProvesOnlyProductContentIsGone(t *testing.T) {
	manifest := workflowManifest()
	initial := workflowFootprint(manifest)
	initial.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "installed"}
	initial.ReleaseCatalog = hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	initial.ImmutableRelease.State = "matching"
	initial.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.Activation.ExpectedReleaseRootPath}
	initial.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range initial.RequiredServices {
		initial.RequiredServices[index].State = "registered"
		initial.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range initial.MutableStores {
		initial.MutableStores[index].State = "compatible"
	}
	completed := workflowFootprint(manifest)
	completed.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range completed.MutableStores {
		completed.MutableStores[index].State = "compatible"
	}
	observerCalls := 0
	observer := hostInstallationFootprintObserverFake{footprints: []hostinstallationmanagerdomain.HostInstallationFootprint{initial, completed}, calls: &observerCalls}
	journalStore := &hostInstallationJournalStoreFake{}
	removalJournalStore := &hostProductRemovalJournalStoreFake{}
	removalReceiptStore := &hostProductRemovalReceiptStoreFake{}
	quiescer := &hostProductServiceQuiescerFake{}
	removalEffects := &hostProductRemovalEffectsFake{}
	workflow, err := NewHostInstallationWorkflowWithRemoval(
		hostInstallationManifestReaderFake{manifest: manifest},
		observer,
		journalStore,
		&hostInstallationReceiptStoreFake{},
		&hostProductReleaseActivatorFake{},
		quiescer,
		&hostProductServiceReconcilerFake{},
		removalJournalStore,
		removalReceiptStore,
		removalEffects,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion:     "v1",
		DocumentKind:      "host-product-removal-request",
		ID:                "remove-request-1",
		InstallationID:    manifest.InstallationID,
		ExpectedReleaseID: manifest.Release.ID,
		DataDisposition:   hostinstallationmanagerdomain.HostProductRemovalDataDispositionPreserveMutableData,
		RequestedAt:       "2026-07-18T03:00:00Z",
	}
	receipt, err := workflow.ExecuteHostProductRemoval(
		context.Background(),
		request,
		"manifest",
		initial.InstallationTransaction.JournalPath,
		initial.InstallationTransaction.ReceiptPath,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json",
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostProductRemovalReceiptCompleted || len(receipt.RetainedMutableStoreIDs) != len(manifest.MutableStores) || removalJournalStore.journal.State != hostinstallationmanagerdomain.HostProductRemovalJournalCompleted || len(removalReceiptStore.writes) != 1 || quiescer.calls != 1 || removalEffects.serviceDefinitions != 1 || removalEffects.activationLink != 1 || removalEffects.releaseCatalog != 1 || removalEffects.packageReceipt != 1 || len(removalEffects.mutableStores) != 0 {
		t.Fatalf("receipt=%+v removalJournal=%+v receiptWrites=%d quiesce=%d effects=%+v err=%v", receipt, removalJournalStore.journal, len(removalReceiptStore.writes), quiescer.calls, removalEffects, err)
	}
}

func TestExecuteHostProductRemovalPurgesAllDeclaredMutableDataWithoutRecreatingEvidence(t *testing.T) {
	manifest := workflowManifest()
	initial := workflowFootprint(manifest)
	initial.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "installed"}
	initial.ReleaseCatalog = hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	initial.ImmutableRelease.State = "matching"
	initial.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.Activation.ExpectedReleaseRootPath}
	initial.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range initial.RequiredServices {
		initial.RequiredServices[index].State = "registered"
		initial.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range initial.MutableStores {
		initial.MutableStores[index].State = "compatible"
	}
	completed := workflowFootprint(manifest)
	observerCalls := 0
	removalJournalStore := &hostProductRemovalJournalStoreFake{}
	removalReceiptStore := &hostProductRemovalReceiptStoreFake{}
	removalEffects := &hostProductRemovalEffectsFake{}
	workflow, err := NewHostInstallationWorkflowWithRemoval(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprints: []hostinstallationmanagerdomain.HostInstallationFootprint{initial, completed}, calls: &observerCalls},
		&hostInstallationJournalStoreFake{},
		&hostInstallationReceiptStoreFake{},
		&hostProductReleaseActivatorFake{},
		&hostProductServiceQuiescerFake{},
		&hostProductServiceReconcilerFake{},
		removalJournalStore,
		removalReceiptStore,
		removalEffects,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion: "v1", DocumentKind: "host-product-removal-request", ID: "remove-request-purge-1",
		InstallationID: manifest.InstallationID, ExpectedReleaseID: manifest.Release.ID,
		DataDisposition: hostinstallationmanagerdomain.HostProductRemovalDataDispositionPurgeAllProductData,
		RequestedAt:     "2026-07-18T03:00:00Z",
	}
	receipt, err := workflow.ExecuteHostProductRemoval(
		context.Background(), request, "manifest", initial.InstallationTransaction.JournalPath, initial.InstallationTransaction.ReceiptPath,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json", "",
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostProductRemovalReceiptCompleted || len(receipt.RetainedMutableStoreIDs) != 0 || len(removalReceiptStore.writes) != 0 || removalJournalStore.journal.State != hostinstallationmanagerdomain.HostProductRemovalJournalMutableDataRemoving || len(removalEffects.mutableStores) != len(manifest.MutableStores) {
		t.Fatalf("receipt=%+v journal=%+v receiptWrites=%d mutableStores=%+v err=%v", receipt, removalJournalStore.journal, len(removalReceiptStore.writes), removalEffects.mutableStores, err)
	}
}

func TestExecuteHostProductRemovalHandsPackageReceiptBackToOperatingSystemOwner(t *testing.T) {
	manifest := workflowManifest()
	manifest.Platform = "linux"
	manifest.Activation.ReferenceKind = "symbolic-link"
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "systemd"
		manifest.RequiredServices[index].DefinitionPath = "/etc/systemd/system/" + manifest.RequiredServices[index].Name + ".service"
	}
	initial := workflowFootprint(manifest)
	initial.Platform = "linux"
	initial.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "installed"}
	initial.ReleaseCatalog = hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	initial.ImmutableRelease.State = "matching"
	initial.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.Activation.ExpectedReleaseRootPath}
	initial.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range initial.RequiredServices {
		initial.RequiredServices[index].State = "registered"
		initial.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range initial.MutableStores {
		initial.MutableStores[index].State = "compatible"
	}
	pending := workflowFootprint(manifest)
	pending.Platform = "linux"
	pending.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "removing"}
	pending.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range pending.MutableStores {
		pending.MutableStores[index].State = "compatible"
	}
	observerCalls := 0
	removalJournalStore := &hostProductRemovalJournalStoreFake{}
	removalReceiptStore := &hostProductRemovalReceiptStoreFake{}
	removalEffects := &hostProductRemovalEffectsFake{packageReceiptRemoval: hostinstallationmanagerdomain.HostProductPackageReceiptRemoval{State: hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager}}
	workflow, err := NewHostInstallationWorkflowWithRemoval(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprints: []hostinstallationmanagerdomain.HostInstallationFootprint{initial, pending}, calls: &observerCalls},
		&hostInstallationJournalStoreFake{}, &hostInstallationReceiptStoreFake{}, &hostProductReleaseActivatorFake{},
		&hostProductServiceQuiescerFake{}, &hostProductServiceReconcilerFake{}, removalJournalStore,
		removalReceiptStore, removalEffects, fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion: "v1", DocumentKind: "host-product-removal-request", ID: "remove-request-linux-1",
		InstallationID: manifest.InstallationID, ExpectedReleaseID: manifest.Release.ID,
		DataDisposition:                   hostinstallationmanagerdomain.HostProductRemovalDataDispositionPreserveMutableData,
		PackageManagerCompletionTransport: &hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport{ManagerPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/package-manager-removal-completion", ManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/package-manager-removal-manifest.json"},
		RequestedAt:                       "2026-07-18T03:00:00Z",
	}
	receipt, err := workflow.ExecuteHostProductRemoval(
		context.Background(), request, "manifest", initial.InstallationTransaction.JournalPath, initial.InstallationTransaction.ReceiptPath,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json",
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostProductRemovalReceiptAwaitingPackageManager || receipt.PackageReceiptRemoval != hostinstallationmanagerdomain.HostProductPackageReceiptAwaitingPackageManager || removalJournalStore.journal.State != hostinstallationmanagerdomain.HostProductRemovalJournalAwaitingPackageManager || len(removalReceiptStore.writes) != 1 || len(receipt.RetainedMutableStoreIDs) != len(manifest.MutableStores) || removalEffects.packageReceipt != 1 || removalEffects.completionTransportCalls != 1 || removalJournalStore.journal.PackageManagerCompletionTransport == nil {
		t.Fatalf("receipt=%+v journal=%+v writes=%d effects=%+v err=%v", receipt, removalJournalStore.journal, len(removalReceiptStore.writes), removalEffects, err)
	}
}

func TestCompleteHostProductRemovalAfterPackageManagerWritesTerminalLinuxEvidence(t *testing.T) {
	manifest := workflowManifest()
	manifest.Platform = "linux"
	manifest.Activation.ReferenceKind = "symbolic-link"
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "systemd"
		manifest.RequiredServices[index].DefinitionPath = "/etc/systemd/system/" + manifest.RequiredServices[index].Name + ".service"
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion: "v1", DocumentKind: "host-product-removal-request", ID: "remove-request-linux-complete-1",
		InstallationID: manifest.InstallationID, ExpectedReleaseID: manifest.Release.ID,
		DataDisposition:                   hostinstallationmanagerdomain.HostProductRemovalDataDispositionPreserveMutableData,
		PackageManagerCompletionTransport: &hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport{ManagerPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/package-manager-removal-completion", ManifestPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/package-manager-removal-manifest.json"},
		RequestedAt:                       "2026-07-18T03:00:00Z",
	}
	footprint := workflowFootprint(manifest)
	footprint.Platform = "linux"
	footprint.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "removed"}
	footprint.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range footprint.MutableStores {
		footprint.MutableStores[index].State = "compatible"
	}
	removalJournalPath := "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json"
	removalReceiptPath := "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json"
	removalJournalStore := &hostProductRemovalJournalStoreFake{journal: hostProductRemovalJournal(request, manifest, hostinstallationmanagerdomain.HostProductRemovalJournalAwaitingPackageManager, nil, request.RequestedAt, request.RequestedAt)}
	removalReceiptStore := &hostProductRemovalReceiptStoreFake{}
	workflow, err := NewHostInstallationWorkflowWithRemoval(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: footprint},
		&hostInstallationJournalStoreFake{}, &hostInstallationReceiptStoreFake{}, &hostProductReleaseActivatorFake{},
		&hostProductServiceQuiescerFake{}, &hostProductServiceReconcilerFake{}, removalJournalStore,
		removalReceiptStore, &hostProductRemovalEffectsFake{}, fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	receipt, err := workflow.CompleteHostProductRemovalAfterPackageManager(
		context.Background(), "manifest", footprint.InstallationTransaction.JournalPath, footprint.InstallationTransaction.ReceiptPath,
		removalJournalPath, removalReceiptPath,
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostProductRemovalReceiptCompleted || receipt.PackageReceiptRemoval != hostinstallationmanagerdomain.HostProductPackageReceiptRemovedByOSPackageManager || removalJournalStore.journal.State != hostinstallationmanagerdomain.HostProductRemovalJournalCompleted || len(removalReceiptStore.writes) != 1 || len(receipt.RetainedMutableStoreIDs) != len(manifest.MutableStores) {
		t.Fatalf("receipt=%+v journal=%+v receiptWrites=%d err=%v", receipt, removalJournalStore.journal, len(removalReceiptStore.writes), err)
	}
}

func TestExecuteHostProductRemovalPreservesFailureJournalAndReceipt(t *testing.T) {
	manifest := workflowManifest()
	initial := workflowFootprint(manifest)
	initial.PackageReceipt = hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	initial.ReleaseCatalog = hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	initial.ImmutableRelease.State = "matching"
	initial.Activation = hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.Activation.ExpectedReleaseRootPath}
	initial.InstallationTransaction.State = hostinstallationmanagerdomain.HostInstallationJournalCompleted
	for index := range initial.RequiredServices {
		initial.RequiredServices[index].State = "registered"
		initial.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range initial.MutableStores {
		initial.MutableStores[index].State = "compatible"
	}
	removalJournalStore := &hostProductRemovalJournalStoreFake{}
	removalReceiptStore := &hostProductRemovalReceiptStoreFake{}
	removalEffects := &hostProductRemovalEffectsFake{serviceDefinitionError: errors.New("declared plist could not be removed")}
	workflow, err := NewHostInstallationWorkflowWithRemoval(
		hostInstallationManifestReaderFake{manifest: manifest},
		hostInstallationFootprintObserverFake{footprint: initial},
		&hostInstallationJournalStoreFake{},
		&hostInstallationReceiptStoreFake{},
		&hostProductReleaseActivatorFake{},
		&hostProductServiceQuiescerFake{},
		&hostProductServiceReconcilerFake{},
		removalJournalStore,
		removalReceiptStore,
		removalEffects,
		fixedHostInstallationClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	request := hostinstallationmanagerdomain.HostProductRemovalRequest{
		SchemaVersion: "v1", DocumentKind: "host-product-removal-request", ID: "remove-request-failure-1",
		InstallationID: manifest.InstallationID, ExpectedReleaseID: manifest.Release.ID,
		DataDisposition: hostinstallationmanagerdomain.HostProductRemovalDataDispositionPreserveMutableData,
		RequestedAt:     "2026-07-18T03:00:00Z",
	}
	receipt, err := workflow.ExecuteHostProductRemoval(
		context.Background(), request, "manifest", initial.InstallationTransaction.JournalPath, initial.InstallationTransaction.ReceiptPath,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json", "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json",
	)
	if err != nil || receipt.State != hostinstallationmanagerdomain.HostProductRemovalReceiptFailed || receipt.Issue == nil || receipt.Issue.Code != "service-definition-removal-failed" || removalJournalStore.journal.State != hostinstallationmanagerdomain.HostProductRemovalJournalFailed || removalJournalStore.journal.Failure == nil || len(removalReceiptStore.writes) != 1 || removalEffects.activationLink != 0 || removalEffects.releaseCatalog != 0 || removalEffects.packageReceipt != 0 {
		t.Fatalf("receipt=%+v journal=%+v receiptWrites=%d effects=%+v err=%v", receipt, removalJournalStore.journal, len(removalReceiptStore.writes), removalEffects, err)
	}
}
