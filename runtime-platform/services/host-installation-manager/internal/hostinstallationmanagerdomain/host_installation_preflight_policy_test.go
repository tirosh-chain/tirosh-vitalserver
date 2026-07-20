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
		Activation:        HostProductReleaseActivation{CurrentReleaseLinkPath: "/Library/Application Support/VitalServerRuntimePlatform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-0.2.0-dev-build-001"},
		OperatorInterface: HostProductOperatorInterface{BootstrapConfigurationPath: "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json", BootstrapConfigurationSHA256: hostInstallationDigest("d")},
		RequiredServices: []HostProductRequiredService{
			{Role: "host-agent", Manager: "launchd", Name: "com.tirosh.vitalserver.host-agent", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", DefinitionSHA256: hostInstallationDigest("b")},
			{Role: "host-edge-proxy", Manager: "launchd", Name: "com.tirosh.vitalserver.host-edge-proxy", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", DefinitionSHA256: hostInstallationDigest("c")},
			{Role: "host-update-handoff-supervisor", Manager: "launchd", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", DefinitionPath: "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", DefinitionSHA256: hostInstallationDigest("e")},
		},
		MutableStores: []HostProductMutableStoreDeclaration{
			{ID: "installation-data-root", Path: "/Library/Application Support/VitalServerRuntimePlatform/data", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
			{ID: "host-agent-state", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/host-agent", Kind: "directory", Owner: "host-agent", Retention: "preserve-by-default"},
			{ID: "virtual-machine-runtime", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/virtual-machine", Kind: "directory", Owner: "macos-virtual-machine-supervisor", Retention: "preserve-by-default"},
			{ID: "installation-manager-journal", Path: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", Kind: "directory", Owner: "host-installation-manager", Retention: "purge-only-by-explicit-command"},
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
			{Role: "host-update-handoff-supervisor", Name: "com.tirosh.vitalserver.host-update-handoff-supervisor", State: "absent", DefinitionState: "absent"},
		},
		MutableStores: []HostInstallationMutableStoreObservation{
			{ID: "installation-data-root", State: "absent"},
			{ID: "host-agent-state", State: "absent"},
			{ID: "virtual-machine-runtime", State: "absent"},
			{ID: "installation-manager-journal", State: "absent"},
		},
		InstallationTransaction: HostInstallationTransactionObservation{
			State:       "absent",
			JournalPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json",
			ReceiptPath: "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-installation-receipt.json",
		},
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

func TestDecideHostInstallationPreflightAdmitsOnlyExactLinuxUnpackedPackagePayload(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.Platform = "linux"
	manifest.ImmutablePayload.ReleaseCatalogPath = "/opt/vitalserver-runtime-platform/releases"
	manifest.ImmutablePayload.ReleaseRootPath = "/opt/vitalserver-runtime-platform/releases/" + manifest.Release.ID
	manifest.ImmutablePayload.ManifestPath = manifest.ImmutablePayload.ReleaseRootPath + "/installation-manifest.json"
	manifest.Activation = HostProductReleaseActivation{CurrentReleaseLinkPath: "/opt/vitalserver-runtime-platform/current", ReferenceKind: "symbolic-link", ExpectedReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath}
	manifest.OperatorInterface.BootstrapConfigurationPath = "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json"
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "systemd"
		manifest.RequiredServices[index].DefinitionPath = "/etc/systemd/system/" + manifest.RequiredServices[index].Name + ".service"
	}
	for index := range manifest.MutableStores {
		manifest.MutableStores[index].Path = strings.Replace(manifest.MutableStores[index].Path, "/Library/Application Support/VitalServerRuntimePlatform", "/var/lib/vitalserver-runtime-platform", 1)
	}
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion, PackageManagerReceiptState: "unpacked"}
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.ImmutableRelease.State = "matching"
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].DefinitionState = "matching"
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "package-unpacked-install" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
	footprint.PackageReceipt.PackageManagerReceiptState = ""
	decision, err = DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
	footprint.PackageReceipt.PackageManagerReceiptState = "unpacked"
	footprint.RequiredServices[0].DefinitionState = "absent"
	decision, err = DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightAdmitsOnlyExplicitWindowsMSIPayloadPhase(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.Platform = "windows"
	manifest.Package.PackageManagerIdentifier = "{12345678-1234-1234-1234-1234567890AB}"
	manifest.ImmutablePayload.ReleaseCatalogPath = `C:\ProgramData\VitalServerRuntimePlatform\releases`
	manifest.ImmutablePayload.ReleaseRootPath = manifest.ImmutablePayload.ReleaseCatalogPath + `\` + manifest.Release.ID
	manifest.ImmutablePayload.ManifestPath = manifest.ImmutablePayload.ReleaseRootPath + `\installation-manifest.json`
	manifest.Activation = HostProductReleaseActivation{CurrentReleaseLinkPath: `C:\ProgramData\VitalServerRuntimePlatform\current`, ReferenceKind: "directory-junction", ExpectedReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath}
	manifest.OperatorInterface.BootstrapConfigurationPath = `C:\ProgramData\VitalServerRuntimePlatform\control\runtime-console-bootstrap.json`
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "windows-scm"
		manifest.RequiredServices[index].DefinitionPath = `C:\ProgramData\VitalServerRuntimePlatform\services\` + manifest.RequiredServices[index].Name + `.json`
		manifest.RequiredServices[index].WindowsSCMRegistration = &HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-service-runner.exe`, Arguments: []string{"--service-definition", manifest.RequiredServices[index].DefinitionPath}, StartMode: "automatic", Account: "LocalSystem"}
	}
	manifest.ImmutablePayload.Entries = append(manifest.ImmutablePayload.Entries, HostImmutableProductPayloadEntry{RelativePath: "bin/host-service-runner.exe", SHA256: hostInstallationDigest("f"), Executable: true})
	for index := range manifest.MutableStores {
		manifest.MutableStores[index].Path = strings.Replace(manifest.MutableStores[index].Path, "/Library/Application Support/VitalServerRuntimePlatform", `C:\ProgramData\VitalServerRuntimePlatform`, 1)
	}
	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected Windows C48 to reject a non-MSI package receipt version")
	}
	manifest.Release.ProductVersion = "0.2.0"
	manifest.Package.ProductVersion = "0.2.0"
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.Platform = "windows"
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.ImmutableRelease = HostInstallationImmutableReleaseObservation{State: "matching", ReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath}
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].DefinitionState = "matching"
	}
	request := preflightHostInstallationRequest(manifest)
	request.PackageManagerOperation = HostInstallationPackageManagerOperationWindowsMSIInstalling
	decision, err := DecideHostInstallationPreflight(request, manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "windows-msi-payload-install" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
	request.PackageManagerOperation = ""
	decision, err = DecideHostInstallationPreflight(request, manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightCanSupersedeAnUnstartedPreflightJournal(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = HostInstallationJournalPreflightVerified
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "clean-install" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightRetriesOnlyItsPreflightJournalFootprint(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = HostInstallationJournalPreflightVerified
	for index := range footprint.MutableStores {
		switch footprint.MutableStores[index].ID {
		case "installation-data-root", "installation-manager-journal":
			footprint.MutableStores[index].State = "compatible"
		}
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "clean-install-retry" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightMigratesOnlyHistoricalBlockedReceiptFootprint(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = "legacy-blocked-preflight"
	for index := range footprint.MutableStores {
		switch footprint.MutableStores[index].ID {
		case "installation-data-root", "installation-manager-journal":
			footprint.MutableStores[index].State = "compatible"
		}
	}

	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "admitted" || decision.Mode != "clean-install-migrate-blocked-preflight-receipt" || len(decision.Effects) == 0 || decision.Effects[0] != "replace-legacy-blocked-preflight-receipt" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightDoesNotMigrateBlockedReceiptWhenRuntimeStateExists(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = "legacy-blocked-preflight"
	for index := range footprint.MutableStores {
		switch footprint.MutableStores[index].ID {
		case "installation-data-root", "installation-manager-journal", "host-agent-state":
			footprint.MutableStores[index].State = "compatible"
		}
	}

	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightDoesNotTreatRuntimeDataAsPreflightOnlyFootprint(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = HostInstallationJournalPreflightVerified
	for index := range footprint.MutableStores {
		switch footprint.MutableStores[index].ID {
		case "installation-data-root", "installation-manager-journal", "host-agent-state":
			footprint.MutableStores[index].State = "compatible"
		}
	}
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "stale-installation-footprint-requires-explicit-cleanup" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationPreflightBlocksJournalThatMayHaveStoppedServices(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.InstallationTransaction.State = HostInstallationJournalServicesQuiescing
	decision, err := DecideHostInstallationPreflight(preflightHostInstallationRequest(manifest), manifest, footprint)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "unfinished-installation-transaction" {
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
	footprint.MutableStores[0].State = "incompatible"
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
		footprint.MutableStores[index].State = "compatible"
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
		footprint.MutableStores[index].State = "compatible"
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
	journal := HostInstallationJournal{SchemaVersion: "v1", DocumentKind: "host-installation-journal", ID: "journal-001", RequestID: request.ID, InstallationID: manifest.InstallationID, ReleaseID: manifest.Release.ID, State: HostInstallationJournalActivationPending, CreatedAt: "2026-07-18T03:00:00Z", UpdatedAt: "2026-07-18T03:00:00Z"}
	decision, err := DecideHostProductReleaseActivation(request, manifest, footprint, journal)
	if err != nil || decision.State != "admitted" || decision.Mode != "activate-release" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostProductServiceQuiescenceRequiresExactPreflightJournal(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	request := preflightHostInstallationRequest(manifest)
	request.Operation = HostInstallationOperationQuiesceServices
	journal := HostInstallationJournal{SchemaVersion: "v1", DocumentKind: "host-installation-journal", ID: "journal-001", RequestID: request.ID, InstallationID: manifest.InstallationID, ReleaseID: manifest.Release.ID, State: HostInstallationJournalPreflightVerified, CreatedAt: "2026-07-18T03:00:00Z", UpdatedAt: "2026-07-18T03:00:00Z"}
	decision, err := DecideHostProductServiceQuiescence(request, manifest, journal)
	if err != nil || decision.State != "admitted" || decision.Mode != "quiesce-services" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostInstallationRecoveryRequiresVerifiedImmutableSlotAfterServiceEffectsBegin(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	journal := HostInstallationJournal{SchemaVersion: "v1", DocumentKind: "host-installation-journal", ID: "journal-001", RequestID: "installation-request-001", InstallationID: manifest.InstallationID, ReleaseID: manifest.Release.ID, State: HostInstallationJournalServicesQuiescing, CreatedAt: "2026-07-18T03:00:00Z", UpdatedAt: "2026-07-18T03:00:00Z"}
	request := preflightHostInstallationRequest(manifest)
	request.Operation = HostInstallationOperationRecoverInstallation
	decision, err := DecideHostInstallationRecovery(request, manifest, footprint, journal)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "recovery-immutable-release-not-verified" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestValidateHostProductInstallationManifestRejectsPlatformServiceManagerMismatch(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.RequiredServices[0].Manager = "systemd"
	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected platform service manager mismatch to be rejected")
	}
}

func TestValidateHostProductInstallationManifestRequiresExplicitPlatformActivationReference(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.Activation.ReferenceKind = "directory-junction"
	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected macOS C48 to reject a Windows directory-junction activation")
	}
}

func TestValidateHostProductInstallationManifestAcceptsWindowsPathsWithoutHostOSPathInference(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.Platform = "windows"
	manifest.Package.PackageManagerIdentifier = "{12345678-1234-1234-1234-1234567890AB}"
	manifest.Release.ProductVersion = "0.2.0"
	manifest.Package.ProductVersion = "0.2.0"
	manifest.ImmutablePayload = HostImmutableProductPayload{
		ReleaseCatalogPath: `C:\ProgramData\VitalServerRuntimePlatform\releases`,
		ReleaseRootPath:    `C:\ProgramData\VitalServerRuntimePlatform\releases\runtime-platform-0.2.0-dev-build-001`,
		ManifestPath:       `C:\ProgramData\VitalServerRuntimePlatform\releases\runtime-platform-0.2.0-dev-build-001\installation-manifest.json`,
		Entries:            manifest.ImmutablePayload.Entries,
	}
	manifest.Activation = HostProductReleaseActivation{
		CurrentReleaseLinkPath:  `C:\ProgramData\VitalServerRuntimePlatform\current`,
		ReferenceKind:           "symbolic-link",
		ExpectedReleaseRootPath: manifest.ImmutablePayload.ReleaseRootPath,
	}
	manifest.OperatorInterface = HostProductOperatorInterface{
		BootstrapConfigurationPath:   `C:\ProgramData\VitalServerRuntimePlatform\control\runtime-console-bootstrap.json`,
		BootstrapConfigurationSHA256: hostInstallationDigest("d"),
	}
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "windows-scm"
		manifest.RequiredServices[index].DefinitionPath = `C:\ProgramData\VitalServerRuntimePlatform\services\` + manifest.RequiredServices[index].Role + `.xml`
		manifest.RequiredServices[index].WindowsSCMRegistration = &HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-service-runner.exe`, Arguments: []string{"--service-definition", manifest.RequiredServices[index].DefinitionPath}, StartMode: "automatic", Account: "LocalSystem"}
	}
	manifest.ImmutablePayload.Entries = append(manifest.ImmutablePayload.Entries, HostImmutableProductPayloadEntry{RelativePath: "bin/host-service-runner.exe", SHA256: hostInstallationDigest("f"), Executable: true})
	for index := range manifest.MutableStores {
		manifest.MutableStores[index].Path = `C:\ProgramData\VitalServerRuntimePlatform\data\` + manifest.MutableStores[index].ID
	}
	manifest.MutableStores[2].Owner = "native-platform-provider"
	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected explicit Windows C48 to reject symbolic-link activation")
	}
	manifest.Activation.ReferenceKind = "directory-junction"
	if err := ValidateHostProductInstallationManifest(manifest); err != nil {
		t.Fatalf("expected explicit Windows C48 path grammar to validate: %v", err)
	}
	manifest.RequiredServices[0].WindowsSCMRegistration.ExecutablePath = `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`
	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected Windows C48 to reject direct Host executable SCM registration")
	}
}

func TestValidateHostProductInstallationManifestRejectsUnknownMutableStoreOwner(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.MutableStores[0].Owner = "installer-script"

	if err := ValidateHostProductInstallationManifest(manifest); err == nil {
		t.Fatal("expected an undeclared mutable-store owner to be rejected")
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

func TestDeclaredHostInstallationTransactionPathsUseOnlyNamedC48Store(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	storePath, err := DeclaredHostInstallationTransactionStorePath(manifest)
	if err != nil || storePath != "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager" {
		t.Fatalf("store=%q err=%v", storePath, err)
	}
	journalPath, receiptPath, err := DeclaredHostInstallationTransactionPaths(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if journalPath != "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-transaction.json" || receiptPath != "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-installation-receipt.json" {
		t.Fatalf("journal=%q receipt=%q", journalPath, receiptPath)
	}
}

func TestDeclaredHostInstallationTransactionPathsRejectMissingNamedC48Store(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.MutableStores[3].ID = "another-manager-store"
	if _, _, err := DeclaredHostInstallationTransactionPaths(manifest); err == nil {
		t.Fatal("expected C48 without the named transaction store to be rejected")
	}
}
