package hostinstallationmanagerdomain

import "fmt"

// DecideHostInstallationPreflight is pure admission policy for a package
// installation attempt. An adapter supplies complete C48/C49 inputs; this
// function neither reads a Host nor changes it.
func DecideHostInstallationPreflight(request HostInstallationRequest, manifest HostProductInstallationManifest, footprint HostInstallationFootprint) (HostInstallationDecision, error) {
	if request.Operation != HostInstallationOperationPreflight || !validHostInstallationRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, fmt.Errorf("installation preflight request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostInstallationDecision{}, err
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return blockedHostInstallationDecision(*issue), nil
	}
	if footprint.InstallationTransaction.State == "active" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "unfinished-installation-transaction", Message: "an earlier installation transaction remains active; recover it explicitly before another package install"}), nil
	}
	if footprint.PackageReceipt.State == "installed" && footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "a version-changing package install is not an update; use the staged Host Updater"}), nil
	}
	if footprint.Activation.State == "points-to-other-release" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "the active release differs from this package release; use the staged Host Updater"}), nil
	}
	if cleanHostInstallationFootprint(footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "clean-install", Effects: []string{"write-preflight-journal", "install-immutable-release-slot", "activate-current-release"}}, nil
	}
	if sameReleaseReinstallFootprint(manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "same-release-reinstall", Effects: []string{"write-preflight-journal", "repair-immutable-release-slot", "verify-current-release"}}, nil
	}
	if sameReleaseRepairFootprint(manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "same-release-repair", Effects: []string{"write-preflight-journal", "repair-immutable-release-slot", "verify-current-release"}}, nil
	}
	return blockedHostInstallationDecision(HostInstallationIssue{Code: "stale-installation-footprint-requires-explicit-cleanup", Message: "existing Host installation state does not match a clean install or same-release repair; inspect or remove it through an explicit lifecycle command"}), nil
}

// DecideHostProductReleaseActivation is pure policy used only after preflight
// has admitted the exact same request and package payload has been written.
func DecideHostProductReleaseActivation(request HostInstallationRequest, manifest HostProductInstallationManifest, footprint HostInstallationFootprint, journal HostInstallationJournal) (HostInstallationDecision, error) {
	if request.Operation != HostInstallationOperationActivateRelease || !validHostInstallationRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, fmt.Errorf("installation activation request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostInstallationDecision{}, err
	}
	if journal.SchemaVersion != HostInstallationDocumentSchemaVersion || journal.DocumentKind != "host-installation-journal" || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID || journal.State != HostInstallationJournalActivationPending {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "installation-activation-without-preflight-journal", Message: "activation requires the exact preflight-verified installation journal"}), nil
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return blockedHostInstallationDecision(*issue), nil
	}
	if footprint.ImmutableRelease.State != "matching" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "immutable-release-not-verified", Message: "activation requires the declared immutable release slot to match its manifest"}), nil
	}
	switch footprint.Activation.State {
	case "absent", "points-to-expected-release":
		return HostInstallationDecision{State: "admitted", Mode: "activate-release", Effects: []string{"atomically-switch-current-release", "complete-installation-journal"}}, nil
	case "points-to-other-release":
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "activation would replace a different active release; use the staged Host Updater"}), nil
	default:
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "activation-state-not-admissible", Message: "activation link state is not admissible"}), nil
	}
}

// DecideHostProductServiceQuiescence admits only the exact preflight journal
// before immutable package bytes are replaced. It decides no launchd effect;
// the macOS adapter executes the returned semantic effect later.
func DecideHostProductServiceQuiescence(request HostInstallationRequest, manifest HostProductInstallationManifest, journal HostInstallationJournal) (HostInstallationDecision, error) {
	if request.Operation != HostInstallationOperationQuiesceServices || !validHostInstallationRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, fmt.Errorf("Host service quiescence request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, err
	}
	if journal.SchemaVersion != HostInstallationDocumentSchemaVersion || journal.DocumentKind != "host-installation-journal" || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID || journal.State != HostInstallationJournalPreflightVerified {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "service-quiescence-without-preflight-journal", Message: "service quiescence requires the exact preflight-verified installation journal"}), nil
	}
	return HostInstallationDecision{State: "admitted", Mode: "quiesce-services", Effects: []string{"bootout-declared-host-services", "mark-installation-activation-pending"}}, nil
}

func validateHostInstallationFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) error {
	if footprint.SchemaVersion != HostInstallationDocumentSchemaVersion || footprint.InstallationID != manifest.InstallationID || footprint.ExpectedReleaseID != manifest.Release.ID || footprint.Platform != manifest.Platform || footprint.ObservedAt == "" {
		return fmt.Errorf("installation footprint identity does not match the declared release")
	}
	if footprint.PackageReceipt.Identifier != manifest.Package.Identifier || footprint.ReleaseCatalog.ReleaseCatalogPath != manifest.ImmutablePayload.ReleaseCatalogPath || footprint.ImmutableRelease.ReleaseRootPath != manifest.ImmutablePayload.ReleaseRootPath || footprint.Activation.CurrentReleaseLinkPath != manifest.Activation.CurrentReleaseLinkPath || footprint.InstallationTransaction.JournalPath == "" {
		return fmt.Errorf("installation footprint resources do not match the declared release")
	}
	if len(footprint.RequiredServices) != len(manifest.RequiredServices) || len(footprint.MutableStores) != len(manifest.MutableStores) {
		return fmt.Errorf("installation footprint does not cover every declared resource")
	}
	for _, declared := range manifest.RequiredServices {
		if !footprintHasService(footprint, declared) {
			return fmt.Errorf("installation footprint does not cover declared service %s", declared.Name)
		}
	}
	for _, declared := range manifest.MutableStores {
		if !footprintHasMutableStore(footprint, declared.ID) {
			return fmt.Errorf("installation footprint does not cover declared mutable store %s", declared.ID)
		}
	}
	return nil
}

func footprintHasService(footprint HostInstallationFootprint, declared HostProductRequiredService) bool {
	for _, observed := range footprint.RequiredServices {
		if observed.Role == declared.Role && observed.Name == declared.Name {
			return true
		}
	}
	return false
}

func footprintHasMutableStore(footprint HostInstallationFootprint, id string) bool {
	for _, observed := range footprint.MutableStores {
		if observed.ID == id {
			return true
		}
	}
	return false
}

func unavailableFootprintIssue(footprint HostInstallationFootprint) *HostInstallationIssue {
	if footprint.PackageReceipt.State == "unavailable" || footprint.PackageReceipt.State == "failed" {
		return withFootprintIssue("package-receipt", footprint.PackageReceipt.Issue)
	}
	if footprint.ReleaseCatalog.State == "unreadable" {
		return withFootprintIssue("release-catalog", footprint.ReleaseCatalog.Issue)
	}
	if footprint.ImmutableRelease.State == "unreadable" {
		return withFootprintIssue("immutable-release", footprint.ImmutableRelease.Issue)
	}
	if footprint.Activation.State == "unreadable" {
		return withFootprintIssue("release-activation", footprint.Activation.Issue)
	}
	if footprint.InstallationTransaction.State == "unreadable" {
		return withFootprintIssue("installation-transaction", footprint.InstallationTransaction.Issue)
	}
	for _, service := range footprint.RequiredServices {
		if service.State == "unavailable" || service.State == "failed" {
			return withFootprintIssue("service-"+service.Role, service.Issue)
		}
		if service.DefinitionState == "unreadable" {
			return withFootprintIssue("service-definition-"+service.Role, service.DefinitionIssue)
		}
	}
	for _, store := range footprint.MutableStores {
		if store.State == "unreadable" {
			return withFootprintIssue("mutable-store-"+store.ID, store.Issue)
		}
	}
	return nil
}

func withFootprintIssue(resource string, issue *HostInstallationIssue) *HostInstallationIssue {
	if issue != nil {
		return issue
	}
	return &HostInstallationIssue{Code: "installation-footprint-unavailable", Message: "Host Installation Manager could not observe " + resource}
}

func cleanHostInstallationFootprint(footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "absent" || footprint.ReleaseCatalog.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || footprint.InstallationTransaction.State != "absent" {
		return false
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "absent" {
			return false
		}
	}
	for _, store := range footprint.MutableStores {
		if store.State != "absent" {
			return false
		}
	}
	return true
}

func sameReleaseReinstallFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "installed" || footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion || footprint.ReleaseCatalog.State != "only-expected-release" || footprint.ImmutableRelease.State != "matching" || footprint.Activation.State != "points-to-expected-release" || !completedOrAbsentHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	return serviceDefinitionsMatch(footprint) && mutableStoresArePreservedWithoutMigration(footprint)
}

func sameReleaseRepairFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "installed" || footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion || footprint.ReleaseCatalog.State != "only-expected-release" || (footprint.ImmutableRelease.State != "matching" && footprint.ImmutableRelease.State != "diverged") || footprint.Activation.State != "points-to-expected-release" || !completedOrAbsentHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	return serviceDefinitionsAreRepairable(footprint) && sameReleaseRepairIsNeeded(footprint) && mutableStoresArePreservedWithoutMigration(footprint)
}

func serviceDefinitionsMatch(footprint HostInstallationFootprint) bool {
	for _, service := range footprint.RequiredServices {
		if service.DefinitionState != "matching" {
			return false
		}
	}
	return true
}

func serviceDefinitionsAreRepairable(footprint HostInstallationFootprint) bool {
	for _, service := range footprint.RequiredServices {
		switch service.DefinitionState {
		case "absent", "matching", "diverged":
			continue
		default:
			return false
		}
	}
	return true
}

func sameReleaseRepairIsNeeded(footprint HostInstallationFootprint) bool {
	if footprint.ImmutableRelease.State == "diverged" {
		return true
	}
	for _, service := range footprint.RequiredServices {
		if service.DefinitionState != "matching" {
			return true
		}
	}
	return false
}

func mutableStoresArePreservedWithoutMigration(footprint HostInstallationFootprint) bool {
	for _, store := range footprint.MutableStores {
		switch store.State {
		case "absent", "compatible", "present-unknown":
			continue
		default:
			return false
		}
	}
	return true
}

func completedOrAbsentHostInstallationTransaction(transaction HostInstallationTransactionObservation) bool {
	return transaction.State == "absent" || transaction.State == "completed"
}

func blockedHostInstallationDecision(issue HostInstallationIssue) HostInstallationDecision {
	return HostInstallationDecision{State: "blocked", Issue: &issue}
}
