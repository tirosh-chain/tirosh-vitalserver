package hostinstallationmanagerdomain

import (
	"strings"
	"testing"
)

func hostInstallationDigest(value string) string { return strings.Repeat(value, 64) }

func declaredHostProductInstallationManifest() HostProductInstallationManifest {
	return HostProductInstallationManifest{
		SchemaVersion:  "v1",
		InstallationID: "vitalserver-runtime-platform",
		Platform:       "macos",
		Release:        HostProductRelease{ID: "runtime-platform-0.2.0-dev-build-001", ProductVersion: "0.2.0-dev", RuntimeVersion: "0.2.0"},
		Package:        HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", ProductVersion: "0.2.0-dev"},
		ImmutablePayload: HostImmutableProductPayload{
			ReleaseCatalogPath: "/Library/Application Support/VitalServerRuntimePlatform/releases",
			ReleaseRootPath:    "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001",
			ManifestPath:       "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001/installation-manifest.json",
			Entries:            []HostImmutableProductPayloadEntry{{RelativePath: "bin/host-agent", SHA256: hostInstallationDigest("a"), Executable: true}},
		},
		Activation: HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001"},
		RequiredServices: []HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: hostInstallationDigest("b")},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: hostInstallationDigest("c")},
		},
		MutableStores: []HostProductMutableStoreDeclaration{
			{ID: "host-agent-state", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/host-agent", Owner: "host-agent", Retention: "preserve-by-default"},
			{ID: "virtual-machine-runtime", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/virtual-machine", Owner: "macos-virtual-machine-supervisor", Retention: "preserve-by-default"},
			{ID: "installation-manager-journal", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
		},
	}
}

func cleanHostInstallationFootprintFor(manifest HostProductInstallationManifest) HostInstallationFootprint {
	return HostInstallationFootprint{
		SchemaVersion:     "v1",
		InstallationID:    manifest.InstallationID,
		ExpectedReleaseID: manifest.Release.ID,
		Platform:          manifest.Platform,
		ObservedAt:        "2026-07-18T03:00:00Z",
		PackageReceipt:    HostInstallationPackageReceiptObservation{State: "absent", Identifier: manifest.Package.Identifier},
		ReleaseCatalog:    HostInstallationReleaseCatalogObservation{State: "absent", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath},
		ImmutableRelease:  HostInstallationImmutableReleaseObservation{State: "absent", ReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath},
		Activation:        HostInstallationActivationObservation{State: "absent", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath},
		RequiredServices: []HostInstallationServiceObservation{
			{Role: "host-agent", Name: "com.tirosh.vitalserver.host-agent", State: "absent", DefinitionState: "absent"},
			{Role: "host-edge-proxy", Name: "com.tirosh.vitalserver.host-edge-proxy", State: "absent", DefinitionState: "absent"},
		},
		MutableStores: []HostInstallationMutableStoreObservation{
			{ID: "host-agent-state", State: "absent"},
			{ID: "virtual-machine-runtime", State: "absent"},
			{ID: "installation-manager-journal", State: "absent"},
		},
		InstallationTransaction: HostInstallationTransactionObservation{State: "absent", JournalPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json"},
	}
}

func preflightHostInstallationRequest(manifest HostProductInstallationManifest) HostInstallationRequest {
	return HostInstallationRequest{
		SchemaVersion:     HostInstallationDocumentSchemaVersion,
		DocumentKind:      "host-installation-request",
		ID:                "installation-request-001",
		InstallationID:    manifest.InstallationID,
		Operation:         HostInstallationOperationPreflight,
		ExpectedReleaseID: manifest.Release.ID,
		RequestedAt:       "2026-07-18T03:00:00Z",
	}
}

func TestDecideHostInstallationPreflightAdmitsCleanHost(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, cleanHostInstallationFootprintFor(manifest))
	if err != nil || decision.State != "admitted" || decision.Mode != "clean-install" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightBlocksDirectVersionChange(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: "0.1.0"}
	footprint.ImmutableRelease.State = "matching"
	footprint.Activation = HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.1.0"}
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].State = "registered"
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "direct-version-upgrade-requires-staged-updater" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightBlocksStaleMutableStoreWithoutReceipt(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.MutableStores[0].State = "present-unknown"
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightBlocksResidualReleaseCatalogWithoutReceipt(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{
		State:              "contains-other-releases",
		ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath,
		ReleaseIDs:         []string{"runtime-platform-0.1.0-build-001"},
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightBlocksResidualServiceDefinitionWithoutReceipt(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.RequiredServices[0].DefinitionState = "diverged"
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightAdmitsSameReleaseRepairWithoutTouchingPersistentData(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.ImmutableRelease.State = "diverged"
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.Activation = HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.ImmutablePayload.ReleaseRootPath}
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].State = "registered"
		footprint.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range footprint.MutableStores {
		footprint.MutableStores[index].State = "present-unknown"
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "same-release-repair" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightAdmitsSameReleaseServiceDefinitionRepair(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.ImmutableRelease.State = "matching"
	footprint.Activation = HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.ImmutablePayload.ReleaseRootPath}
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].State = "registered"
		footprint.RequiredServices[index].DefinitionState = "matching"
	}
	footprint.RequiredServices[1].DefinitionState = "diverged"
	for index := range footprint.MutableStores {
		footprint.MutableStores[index].State = "present-unknown"
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "same-release-repair" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostProductReleaseActivationRequiresMatchingImmutableSlotAndJournal(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.ImmutableRelease.State = "matching"
	request := preflightHostInstallationRequest(manifest)
	request.Operation = HostInstallationOperationActivateRelease
	journal := HostInstallationJournal{SchemaVersion: "v1", DocumentKind: "host-installation-journal", ID: "journal-001", RequestID: request.ID, InstallationID: manifest.InstallationID, ReleaseID: manifest.Release.ID, State: HostInstallationJournalActivationPending}
	decision, err := DecideHostProductReleaseActivation(request, manifest, footprint, journal)
	if err != nil || decision.State != "admitted" || decision.Mode != "activate-release" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostProductServiceQuiescenceRequiresExactPreflightJournal(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	request := preflightHostInstallationRequest(manifest)
	request.Operation = HostInstallationOperationQuiesceServices
	journal := HostInstallationJournal{SchemaVersion: "v1", DocumentKind: "host-installation-journal", ID: "journal-001", RequestID: request.ID, InstallationID: manifest.InstallationID, ReleaseID: manifest.Release.ID, State: HostInstallationJournalPreflightVerified}
	decision, err := DecideHostProductServiceQuiescence(request, manifest, journal)
	if err != nil || decision.State != "admitted" || decision.Mode != "quiesce-services" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostProductReleaseActivationBlocksMissingJournal(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.ImmutableRelease.State = "matching"
	request := preflightHostInstallationRequest(manifest)
	request.Operation = HostInstallationOperationActivateRelease
	decision, err := DecideHostProductReleaseActivation(request, manifest, footprint, HostInstallationJournal{})
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "installation-activation-without-preflight-journal" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}
