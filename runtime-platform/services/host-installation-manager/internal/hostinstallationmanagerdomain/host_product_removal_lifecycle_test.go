package hostinstallationmanagerdomain

import "testing"

func declaredHostProductRemovalRequest(manifest HostProductInstallationManifest, disposition string) HostProductRemovalRequest {
	return HostProductRemovalRequest{
		SchemaVersion:     "v1",
		DocumentKind:      "host-product-removal-request",
		ID:                "product-removal-request-001",
		InstallationID:    manifest.InstallationID,
		ExpectedReleaseID: manifest.Release.ID,
		DataDisposition:   disposition,
		RequestedAt:       "2026-07-18T03:00:00Z",
	}
}

func installedHostProductRemovalFootprint(manifest HostProductInstallationManifest) HostInstallationFootprint {
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID}}
	footprint.ImmutableRelease.State = "matching"
	footprint.Activation = HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: manifest.Activation.CurrentReleaseLinkPath, ObservedTargetPath: manifest.Activation.ExpectedReleaseRootPath}
	footprint.InstallationTransaction.State = HostInstallationJournalCompleted
	for index := range footprint.RequiredServices {
		footprint.RequiredServices[index].State = "registered"
		footprint.RequiredServices[index].DefinitionState = "matching"
	}
	for index := range footprint.MutableStores {
		footprint.MutableStores[index].State = "compatible"
	}
	return footprint
}

func TestDecideHostProductRemovalRequiresExplicitDataDisposition(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	request := declaredHostProductRemovalRequest(manifest, "")
	_, _, err := DecideHostProductRemoval(
		request,
		manifest,
		installedHostProductRemovalFootprint(manifest),
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json",
	)
	if err == nil {
		t.Fatal("expected removal without data disposition to be rejected")
	}
}

func TestDecideHostProductRemovalAdmitsPurgeOnlyWithOneTopLevelDataRoot(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	request := declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPurgeAllProductData)
	plan, decision, err := DecideHostProductRemoval(
		request,
		manifest,
		installedHostProductRemovalFootprint(manifest),
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json",
		"",
	)
	if err != nil || decision.State != "admitted" || plan.DataDisposition != HostProductRemovalDataDispositionPurgeAllProductData || len(plan.RemoveMutableStores) != 1 || plan.RemoveMutableStores[0].ID != "installation-data-root" {
		t.Fatalf("plan=%+v decision=%+v err=%v", plan, decision, err)
	}
}

func TestDecideHostProductRemovalUsesWindowsPathContainmentForPurge(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	manifest.Platform = "windows"
	manifest.Package.PackageManagerIdentifier = "{12345678-1234-1234-1234-1234567890AB}"
	manifest.Release.ProductVersion = "0.2.0"
	manifest.Package.ProductVersion = "0.2.0"
	manifest.ImmutablePayload.ReleaseCatalogPath = `C:\ProgramData\VitalServerRuntimePlatform\releases`
	manifest.ImmutablePayload.ReleaseRootPath = `C:\ProgramData\VitalServerRuntimePlatform\releases\runtime-platform-0.2.0-dev-build-001`
	manifest.ImmutablePayload.ManifestPath = `C:\ProgramData\VitalServerRuntimePlatform\releases\runtime-platform-0.2.0-dev-build-001\installation-manifest.json`
	manifest.Activation.CurrentReleaseLinkPath = `C:\ProgramData\VitalServerRuntimePlatform\current`
	manifest.Activation.ReferenceKind = "directory-junction"
	manifest.Activation.ExpectedReleaseRootPath = manifest.ImmutablePayload.ReleaseRootPath
	manifest.OperatorInterface.BootstrapConfigurationPath = `C:\ProgramData\VitalServerRuntimePlatform\control\runtime-console-bootstrap.json`
	for index := range manifest.RequiredServices {
		manifest.RequiredServices[index].Manager = "windows-scm"
		manifest.RequiredServices[index].DefinitionPath = `C:\ProgramData\VitalServerRuntimePlatform\services\` + manifest.RequiredServices[index].Name + `.json`
		manifest.RequiredServices[index].WindowsSCMRegistration = &HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-service-runner.exe`, Arguments: []string{"--service-definition", manifest.RequiredServices[index].DefinitionPath}, StartMode: "automatic", Account: "LocalSystem"}
	}
	manifest.ImmutablePayload.Entries = append(manifest.ImmutablePayload.Entries, HostImmutableProductPayloadEntry{RelativePath: "bin/host-service-runner.exe", SHA256: hostInstallationDigest("f"), Executable: true})
	manifest.MutableStores[0].Path = `C:\ProgramData\VitalServerRuntimePlatform\data`
	manifest.MutableStores[1].Path = `C:\ProgramData\VitalServerRuntimePlatform\data\host-agent`
	manifest.MutableStores[2].Path = `C:\ProgramData\VitalServerRuntimePlatform\data\virtual-machine`
	manifest.MutableStores[3].Path = `C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager`
	footprint := installedHostProductRemovalFootprint(manifest)
	footprint.InstallationTransaction.JournalPath = `C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager\current-transaction.json`
	footprint.InstallationTransaction.ReceiptPath = `C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager\latest-installation-receipt.json`
	request := declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPurgeAllProductData)
	request.PackageManagerCompletionTransport = &HostProductPackageManagerCompletionTransport{ManagerPath: `C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager\package-manager-removal-completion.exe`, ManifestPath: `C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager\package-manager-removal-manifest.json`}
	plan, decision, err := DecideHostProductRemoval(
		request,
		manifest,
		footprint,
		`C:\ProgramData\VitalServerRuntimePlatform\data\installation-manager\current-removal-transaction.json`,
		"",
	)
	if err != nil || decision.State != "admitted" || plan.RemoveReleaseCatalog || !plan.PreparePackageManagerCompletionTransport || len(plan.RemoveMutableStores) != 1 || plan.RemoveMutableStores[0].ID != "installation-data-root" {
		t.Fatalf("plan=%+v decision=%+v err=%v", plan, decision, err)
	}
}

func TestDecideHostProductRemovalBlocksAnotherReleaseAndNeverPlansDeletion(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := installedHostProductRemovalFootprint(manifest)
	footprint.ReleaseCatalog = HostInstallationReleaseCatalogObservation{State: "contains-other-releases", ReleaseCatalogPath: manifest.ImmutablePayload.ReleaseCatalogPath, ReleaseIDs: []string{manifest.Release.ID, "runtime-platform-0.1.0"}}
	plan, decision, err := DecideHostProductRemoval(
		declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPreserveMutableData),
		manifest,
		footprint,
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/current-removal-transaction.json",
		"/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager/latest-removal-receipt.json",
	)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "release-catalog-not-exclusively-declared" || plan.RemovePackageReceipt || len(plan.RemoveMutableStores) != 0 {
		t.Fatalf("plan=%+v decision=%+v err=%v", plan, decision, err)
	}
}

func TestDecideHostProductRemovalCompletionRequiresAllDeclaredStoresAbsentAfterPurge(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	decision, retained, err := DecideHostProductRemovalCompletion(
		declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPurgeAllProductData),
		manifest,
		footprint,
	)
	if err != nil || decision.State != "admitted" || len(retained) != 0 {
		t.Fatalf("decision=%+v retained=%v err=%v", decision, retained, err)
	}
	footprint.MutableStores[1].State = "compatible"
	decision, _, err = DecideHostProductRemovalCompletion(
		declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPurgeAllProductData),
		manifest,
		footprint,
	)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "product-data-purge-not-complete" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}

func TestDecideHostProductRemovalAwaitingPackageManagerRequiresOnlyDeclaredPackageReceiptToRemain(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	footprint := cleanHostInstallationFootprintFor(manifest)
	footprint.PackageReceipt = HostInstallationPackageReceiptObservation{State: "installed", Identifier: manifest.Package.Identifier, ProductVersion: manifest.Package.ProductVersion}
	footprint.InstallationTransaction.State = HostInstallationJournalCompleted
	for index := range footprint.MutableStores {
		footprint.MutableStores[index].State = "compatible"
	}
	decision, retained, err := DecideHostProductRemovalAwaitingPackageManager(
		declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPreserveMutableData),
		manifest,
		footprint,
	)
	if err != nil || decision.State != "admitted" || decision.Mode != HostProductPackageReceiptAwaitingPackageManager || len(retained) != len(manifest.MutableStores) {
		t.Fatalf("decision=%+v retained=%v err=%v", decision, retained, err)
	}
	footprint.PackageReceipt.State = "absent"
	decision, _, err = DecideHostProductRemovalAwaitingPackageManager(
		declaredHostProductRemovalRequest(manifest, HostProductRemovalDataDispositionPreserveMutableData),
		manifest,
		footprint,
	)
	if err != nil || decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "package-receipt-not-awaiting-declared-package-manager" {
		t.Fatalf("decision=%+v err=%v", decision, err)
	}
}
