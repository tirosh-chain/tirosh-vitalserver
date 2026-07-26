package hostinstallationmanagerdomain

import (
	"fmt"
	"path"
	"strings"
)

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
	if installationTransactionRequiresExplicitRecovery(footprint.InstallationTransaction) {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "unfinished-installation-transaction", Message: "an earlier installation transaction remains active; recover it explicitly before another package install"}), nil
	}
	if footprint.PackageReceipt.State == "installed" && footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "a version-changing package install is not an update; it requires a configured staged Host Updater execution boundary"}), nil
	}
	if footprint.Activation.State == "points-to-other-release" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "the active release differs from this package release; it requires a configured staged Host Updater execution boundary"}), nil
	}
	if cleanHostInstallationFootprint(footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "clean-install", Effects: []string{"write-preflight-journal", "install-immutable-release-slot", "activate-current-release"}}, nil
	}
	if packageUnpackedInstallFootprint(manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "package-unpacked-install", Effects: []string{"write-preflight-journal", "verify-delivered-immutable-release-slot", "activate-current-release"}}, nil
	}
	if windowsMSIPayloadInstallFootprint(request, manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "windows-msi-payload-install", Effects: []string{"write-preflight-journal", "verify-delivered-immutable-release-slot", "activate-current-release"}}, nil
	}
	if legacyBlockedPreflightReceiptFootprint(manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "clean-install-migrate-blocked-preflight-receipt", Effects: []string{"replace-legacy-blocked-preflight-receipt", "write-preflight-journal", "install-immutable-release-slot", "activate-current-release"}}, nil
	}
	if preflightOnlyCleanRetryFootprint(manifest, footprint) {
		return HostInstallationDecision{State: "admitted", Mode: "clean-install-retry", Effects: []string{"replace-preflight-journal", "install-immutable-release-slot", "activate-current-release"}}, nil
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
	if ValidateHostInstallationJournal(journal) != nil || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID || journal.State != HostInstallationJournalActivationPending {
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
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "direct-version-upgrade-requires-staged-updater", Message: "activation would replace a different active release; it requires a configured staged Host Updater execution boundary"}), nil
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
	if ValidateHostInstallationJournal(journal) != nil || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID || journal.State != HostInstallationJournalPreflightVerified {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "service-quiescence-without-preflight-journal", Message: "service quiescence requires the exact preflight-verified installation journal"}), nil
	}
	return HostInstallationDecision{State: "admitted", Mode: "quiesce-services", Effects: []string{"mark-services-quiescing", "bootout-declared-host-services", "mark-installation-activation-pending"}}, nil
}

// DecideHostProductServiceFinalization admits service registration only after
// the exact transaction has atomically activated its immutable release. The
// package script never decides or executes launchd bootstrap itself.
func DecideHostProductServiceFinalization(request HostInstallationRequest, manifest HostProductInstallationManifest, journal HostInstallationJournal) (HostInstallationDecision, error) {
	if request.Operation != HostInstallationOperationFinalizeServices || !validHostInstallationRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, fmt.Errorf("Host service finalization request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, err
	}
	if ValidateHostInstallationJournal(journal) != nil || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID || journal.State != HostInstallationJournalActivated {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "service-finalization-without-activated-journal", Message: "service finalization requires the exact activated installation journal"}), nil
	}
	return HostInstallationDecision{State: "admitted", Mode: "finalize-services", Effects: []string{"reconcile-declared-host-services", "complete-installation-journal"}}, nil
}

// DecideHostInstallationRecovery makes recovery an explicit C50 transition.
// A preflight-only journal is safe to supersede because preflight performs no
// Host mutation. Any later state may have stopped services, so recovery only
// completes the declared release after C49 proves its immutable slot.
func DecideHostInstallationRecovery(request HostInstallationRequest, manifest HostProductInstallationManifest, footprint HostInstallationFootprint, journal HostInstallationJournal) (HostInstallationDecision, error) {
	if request.Operation != HostInstallationOperationRecoverInstallation || !validHostInstallationRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, fmt.Errorf("Host installation recovery request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostInstallationDecision{}, err
	}
	if ValidateHostInstallationJournal(journal) != nil || journal.RequestID != request.ID || journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "installation-recovery-without-matching-journal", Message: "recovery requires the exact installation transaction journal"}), nil
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return blockedHostInstallationDecision(*issue), nil
	}
	switch journal.State {
	case HostInstallationJournalPreflightVerified:
		return HostInstallationDecision{State: "admitted", Mode: "recover-unstarted-preflight", Effects: []string{"mark-installation-recovered"}}, nil
	case HostInstallationJournalServicesQuiescing, HostInstallationJournalActivationPending, HostInstallationJournalActivated, HostInstallationJournalFailed:
		if footprint.ImmutableRelease.State != "matching" {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "recovery-immutable-release-not-verified", Message: "recovery requires the declared immutable release slot to match its manifest"}), nil
		}
		switch footprint.Activation.State {
		case "absent", "points-to-expected-release":
			return HostInstallationDecision{State: "admitted", Mode: "recover-release-and-services", Effects: []string{"atomically-switch-current-release", "reconcile-declared-host-services", "mark-installation-recovered"}}, nil
		case "points-to-other-release":
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "recovery-would-replace-other-active-release", Message: "recovery will not replace a different active release"}), nil
		default:
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "recovery-activation-state-not-admissible", Message: "recovery requires an absent or matching current release link"}), nil
		}
	case HostInstallationJournalCompleted, HostInstallationJournalRecovered:
		return HostInstallationDecision{State: "admitted", Mode: "recovery-already-terminal", Effects: []string{}}, nil
	default:
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "installation-recovery-state-not-admissible", Message: "recovery cannot advance the observed installation transaction state"}), nil
	}
}

func validateHostInstallationFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) error {
	if footprint.SchemaVersion != HostInstallationDocumentSchemaVersion || footprint.InstallationID != manifest.InstallationID || footprint.ExpectedReleaseID != manifest.Release.ID || footprint.Platform != manifest.Platform || footprint.ObservedAt == "" {
		return fmt.Errorf("installation footprint identity does not match the declared release")
	}
	if footprint.PackageReceipt.Identifier != manifest.Package.Identifier || footprint.ReleaseCatalog.ReleaseCatalogPath != manifest.ImmutablePayload.ReleaseCatalogPath || footprint.ImmutableRelease.ReleaseRootPath != manifest.ImmutablePayload.ReleaseRootPath || footprint.Activation.CurrentReleaseLinkPath != manifest.Activation.CurrentReleaseLinkPath || footprint.InstallationTransaction.JournalPath == "" || footprint.InstallationTransaction.ReceiptPath == "" {
		return fmt.Errorf("installation footprint resources do not match the declared release")
	}
	if manifest.Platform == "macos" {
		if footprint.OperatorApplication == nil || footprint.OperatorApplication.ApplicationBundlePath != manifest.OperatorInterface.ApplicationBundlePath || !validHostInstallationOperatorApplicationObservationState(footprint.OperatorApplication.State) {
			return fmt.Errorf("installation footprint does not cover the declared macOS operator application")
		}
	} else if footprint.OperatorApplication != nil {
		return fmt.Errorf("non-macOS installation footprint must not contain a macOS operator application")
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
	if footprint.OperatorApplication != nil && footprint.OperatorApplication.State == "unreadable" {
		return withFootprintIssue("operator-application", footprint.OperatorApplication.Issue)
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
	if footprint.PackageReceipt.State != "absent" || footprint.ReleaseCatalog.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || !absentOrPreflightOnlyHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	if footprint.OperatorApplication != nil && footprint.OperatorApplication.State != "absent" {
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

// packageUnpackedInstallFootprint is the sole admission path for a Debian
// postinst initial install. dpkg has already placed the immutable release and
// unit files, while its receipt is explicitly `unpacked` or `configuring`,
// never `installed`. It is deliberately narrower than same-release repair: the
// exact C48 slot must match, activation must still be absent, no mutable data
// may exist, and only a preflight-only C50 retry is allowed.
func packageUnpackedInstallFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if manifest.Platform != "linux" || footprint.PackageReceipt.State != "installed" || (footprint.PackageReceipt.PackageManagerReceiptState != "unpacked" && footprint.PackageReceipt.PackageManagerReceiptState != "configuring") || footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion || footprint.ReleaseCatalog.State != "only-expected-release" || footprint.ImmutableRelease.State != "matching" || footprint.Activation.State != "absent" || !absentOrPreflightOnlyHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	for _, service := range footprint.RequiredServices {
		if service.DefinitionState != "matching" || (service.State != "absent" && service.State != "registered") {
			return false
		}
	}
	for _, store := range footprint.MutableStores {
		if store.State == "absent" {
			continue
		}
		if store.State != "compatible" || footprint.InstallationTransaction.State != HostInstallationJournalPreflightVerified || !isManagerOwnedTransactionStore(manifest, footprint.InstallationTransaction.JournalPath, store.ID) {
			return false
		}
	}
	return true
}

// windowsMSIPayloadInstallFootprint is the C50 admission path for an explicit
// MSI deferred installation action. MSI has delivered immutable payload files
// before it writes its uninstall registration, so C49 must report the receipt
// as absent. The custom action supplies that exact phase as request input; the
// manager never infers it from a missing registry key.
func windowsMSIPayloadInstallFootprint(request HostInstallationRequest, manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if manifest.Platform != "windows" || request.PackageManagerOperation != HostInstallationPackageManagerOperationWindowsMSIInstalling || footprint.PackageReceipt.State != "absent" || footprint.ReleaseCatalog.State != "only-expected-release" || footprint.ImmutableRelease.State != "matching" || footprint.Activation.State != "absent" || !absentOrPreflightOnlyHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "matching" {
			return false
		}
	}
	for index, store := range footprint.MutableStores {
		if store.State != "absent" && !(manifest.MutableStores[index].Owner == "host-installation-manager" && store.State == "compatible") {
			return false
		}
	}
	return true
}

// legacyBlockedPreflightReceiptFootprint is an explicit migration for only
// the historical package behavior that wrote a C50 blocked receipt before
// payload delivery. The C49 adapter reports this state only after it decoded a
// valid blocked receipt, found no journal, and proved the manager-owned data
// tree contains no other files. This is not a general stale-state fallback.
func legacyBlockedPreflightReceiptFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "absent" || footprint.ReleaseCatalog.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || footprint.InstallationTransaction.State != "legacy-blocked-preflight" {
		return false
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "absent" {
			return false
		}
	}
	for _, store := range footprint.MutableStores {
		if store.State == "absent" {
			continue
		}
		if store.State != "compatible" || !isManagerOwnedTransactionStore(manifest, footprint.InstallationTransaction.ReceiptPath, store.ID) {
			return false
		}
	}
	return true
}

// preflightOnlyCleanRetryFootprint recognizes only state created by the
// preflight itself. The journal writer necessarily creates its declared parent
// directories before Installer payload delivery. If that payload fails, those
// directories and a preflight-verified C50 journal are evidence of an
// unstarted transaction, not Host Agent or VM data that a package may erase.
//
// This is deliberately narrower than treating arbitrary compatible mutable
// stores as clean: only C48 stores owned by this manager that are ancestors of
// the explicit journal path may exist, and every non-manager store must still
// be absent.
func preflightOnlyCleanRetryFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "absent" || footprint.ReleaseCatalog.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || footprint.InstallationTransaction.State != HostInstallationJournalPreflightVerified {
		return false
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "absent" {
			return false
		}
	}
	for _, store := range footprint.MutableStores {
		if store.State == "absent" {
			continue
		}
		if store.State != "compatible" || !isManagerOwnedTransactionStore(manifest, footprint.InstallationTransaction.JournalPath, store.ID) {
			return false
		}
	}
	return true
}

func isManagerOwnedTransactionStore(manifest HostProductInstallationManifest, transactionPath string, storeID string) bool {
	for _, store := range manifest.MutableStores {
		if store.ID != storeID {
			continue
		}
		return store.Owner == "host-installation-manager" && store.Retention == "purge-only-by-explicit-command" && hostInstallationPathContainsForPlatform(store.Path, transactionPath, manifest.Platform)
	}
	return false
}

func hostInstallationPathContains(directory string, candidate string) bool {
	return hostInstallationPathContainsForPlatform(directory, candidate, "macos")
}

// hostInstallationPathContainsForPlatform compares already validated Host
// paths without asking the filesystem to resolve either path. This matters for
// removal policy: a Windows declaration must not be interpreted with POSIX
// separators, and a lexical containment check must never follow a symlink.
func hostInstallationPathContainsForPlatform(directory string, candidate string, platform string) bool {
	cleanDirectory := normalizedHostInstallationPath(directory, platform)
	cleanCandidate := normalizedHostInstallationPath(candidate, platform)
	separator := "/"
	if platform == "windows" {
		separator = "\\"
		cleanDirectory = strings.ToLower(cleanDirectory)
		cleanCandidate = strings.ToLower(cleanCandidate)
	}
	if platform != "windows" {
		cleanDirectory = path.Clean(cleanDirectory)
		cleanCandidate = path.Clean(cleanCandidate)
	}
	if cleanDirectory == "" || cleanDirectory == separator || cleanDirectory == cleanCandidate {
		return false
	}
	return strings.HasPrefix(cleanCandidate, cleanDirectory+separator)
}

func sameReleaseReinstallFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "installed" || footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion || footprint.ReleaseCatalog.State != "only-expected-release" || footprint.ImmutableRelease.State != "matching" || footprint.Activation.State != "points-to-expected-release" || !terminalOrPreflightOnlyHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	return operatorApplicationMatches(manifest, footprint) && serviceDefinitionsMatch(footprint) && mutableStoresArePreservedWithoutMigration(footprint)
}

func sameReleaseRepairFootprint(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if footprint.PackageReceipt.State != "installed" || footprint.PackageReceipt.ProductVersion != manifest.Package.ProductVersion || footprint.ReleaseCatalog.State != "only-expected-release" || (footprint.ImmutableRelease.State != "matching" && footprint.ImmutableRelease.State != "diverged") || footprint.Activation.State != "points-to-expected-release" || !terminalOrPreflightOnlyHostInstallationTransaction(footprint.InstallationTransaction) {
		return false
	}
	return operatorApplicationMatches(manifest, footprint) && serviceDefinitionsAreRepairable(footprint) && sameReleaseRepairIsNeeded(footprint) && mutableStoresArePreservedWithoutMigration(footprint)
}

func validHostInstallationOperatorApplicationObservationState(state string) bool {
	return state == "absent" || state == "matching" || state == "diverged" || state == "unreadable"
}

func operatorApplicationMatches(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	return manifest.Platform != "macos" || footprint.OperatorApplication != nil && footprint.OperatorApplication.State == "matching"
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
		case "absent", "compatible":
			continue
		default:
			return false
		}
	}
	return true
}

func installationTransactionRequiresExplicitRecovery(transaction HostInstallationTransactionObservation) bool {
	switch transaction.State {
	case HostInstallationJournalServicesQuiescing, HostInstallationJournalActivationPending, HostInstallationJournalActivated, HostInstallationJournalFailed:
		return true
	default:
		return false
	}
}

func absentOrPreflightOnlyHostInstallationTransaction(transaction HostInstallationTransactionObservation) bool {
	return transaction.State == "absent" || transaction.State == HostInstallationJournalPreflightVerified
}

func terminalOrPreflightOnlyHostInstallationTransaction(transaction HostInstallationTransactionObservation) bool {
	return transaction.State == "absent" || transaction.State == HostInstallationJournalPreflightVerified || transaction.State == HostInstallationJournalCompleted || transaction.State == HostInstallationJournalRecovered
}

func blockedHostInstallationDecision(issue HostInstallationIssue) HostInstallationDecision {
	return HostInstallationDecision{State: "blocked", Issue: &issue}
}
