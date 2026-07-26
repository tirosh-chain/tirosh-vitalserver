// Package hostinstallationmanagerdomain keeps Host product removal policy
// pure. A removal is a distinct lifecycle from package installation: it must
// name the mutable-data disposition rather than treating absent state or a
// package-manager action as permission to delete product data.
package hostinstallationmanagerdomain

import (
	"fmt"
	"sort"
	"time"
)

const (
	HostProductRemovalDataDispositionPreserveMutableData = "preserve-mutable-data"
	HostProductRemovalDataDispositionPurgeAllProductData = "purge-all-product-data"
)

const (
	HostProductRemovalJournalAdmitted                 = "removal-admitted"
	HostProductRemovalJournalServicesQuiescing        = "services-quiescing"
	HostProductRemovalJournalImmutableContentRemoving = "immutable-content-removing"
	HostProductRemovalJournalMutableDataRemoving      = "mutable-data-removing"
	// HostProductRemovalJournalAwaitingPackageManager means all Host-owned
	// product resources are gone, but the operating-system package manager
	// still owns deletion of its own receipt. Linux and Windows must preserve
	// this boundary; they may not recursively purge their package from a
	// package-maintainer hook.
	HostProductRemovalJournalAwaitingPackageManager = "awaiting-package-manager"
	HostProductRemovalJournalCompleted              = "completed"
	HostProductRemovalJournalFailed                 = "failed"
)

const (
	HostProductRemovalReceiptCompleted              = "completed"
	HostProductRemovalReceiptAwaitingPackageManager = "awaiting-package-manager"
	HostProductRemovalReceiptBlocked                = "blocked"
	HostProductRemovalReceiptFailed                 = "failed"
)

const (
	// HostProductPackageReceiptRemovedByManager is valid only when the Host
	// Installation Manager owns the receipt-removal protocol (for example,
	// macOS pkgutil --forget).
	HostProductPackageReceiptRemovedByManager = "removed-by-host-installation-manager"
	// HostProductPackageReceiptAwaitingPackageManager is the explicit result
	// for package systems that own their own database (dpkg/MSI). The package
	// hook must return to that owner and never invoke a recursive removal.
	HostProductPackageReceiptAwaitingPackageManager = "awaiting-os-package-manager"
	// HostProductPackageReceiptRemovedByOSPackageManager records the terminal
	// C54 evidence after dpkg/MSI has removed its own registration. It is
	// intentionally distinct from the pre-removal hand-off and from pkgutil's
	// manager-owned removal protocol.
	HostProductPackageReceiptRemovedByOSPackageManager = "removed-by-os-package-manager"
)

// HostProductPackageReceiptRemoval reports ownership of one C54 effect. It
// is deliberately not a boolean: completion and hand-off to the OS package
// manager are different operator-visible lifecycle states.
type HostProductPackageReceiptRemoval struct {
	State string
}

// HostProductRemovalRequest is C54 desired work. The caller must make the
// data disposition explicit; there is intentionally no implicit "safe"
// default because preserving data and making a Host clean for reinstallation
// are different operator outcomes.
type HostProductRemovalRequest struct {
	SchemaVersion                     string                                        `json:"schemaVersion"`
	DocumentKind                      string                                        `json:"documentKind"`
	ID                                string                                        `json:"id"`
	InstallationID                    string                                        `json:"installationId"`
	ExpectedReleaseID                 string                                        `json:"expectedReleaseId"`
	DataDisposition                   string                                        `json:"dataDisposition"`
	PackageManagerCompletionTransport *HostProductPackageManagerCompletionTransport `json:"packageManagerCompletionTransport,omitempty"`
	RequestedAt                       string                                        `json:"requestedAt"`
}

// HostProductPackageManagerCompletionTransport names the durable, manager-
// owned files retained only long enough for an OS package manager's post-
// removal hook to prove its own receipt has disappeared. It is a C54 input,
// never a path inferred from a package name or temporary script directory.
type HostProductPackageManagerCompletionTransport struct {
	ManagerPath  string `json:"managerPath"`
	ManifestPath string `json:"manifestPath"`
}

// HostProductRemovalJournal records intent before an external removal effect.
// It is intentionally stored below a manager-owned mutable store. A purge
// removes that journal only after the final effect has completed; console
// output remains the portable completion receipt for a fully clean Host.
type HostProductRemovalJournal struct {
	SchemaVersion                     string                                        `json:"schemaVersion"`
	DocumentKind                      string                                        `json:"documentKind"`
	ID                                string                                        `json:"id"`
	RequestID                         string                                        `json:"requestId"`
	InstallationID                    string                                        `json:"installationId"`
	ReleaseID                         string                                        `json:"releaseId"`
	DataDisposition                   string                                        `json:"dataDisposition"`
	PackageManagerCompletionTransport *HostProductPackageManagerCompletionTransport `json:"packageManagerCompletionTransport,omitempty"`
	State                             string                                        `json:"state"`
	Failure                           *HostInstallationIssue                        `json:"failure,omitempty"`
	CreatedAt                         string                                        `json:"createdAt"`
	UpdatedAt                         string                                        `json:"updatedAt"`
}

// HostProductRemovalReceipt is the typed C54 outcome returned to an operator.
// `retainedMutableStoreIds` is populated only for an explicit preservation
// request. A purge has no durable in-product receipt by design: retaining it
// would itself violate the requested clean Host state.
type HostProductRemovalReceipt struct {
	SchemaVersion           string                 `json:"schemaVersion"`
	DocumentKind            string                 `json:"documentKind"`
	ID                      string                 `json:"id"`
	RequestID               string                 `json:"requestId"`
	InstallationID          string                 `json:"installationId"`
	ReleaseID               string                 `json:"releaseId"`
	DataDisposition         string                 `json:"dataDisposition"`
	State                   string                 `json:"state"`
	PackageReceiptRemoval   string                 `json:"packageReceiptRemoval,omitempty"`
	RetainedMutableStoreIDs []string               `json:"retainedMutableStoreIds,omitempty"`
	Issue                   *HostInstallationIssue `json:"issue,omitempty"`
	ObservedAt              string                 `json:"observedAt"`
}

// HostProductRemovalPlan is a pure, complete list of semantic effects. The
// application layer supplies the plan to Host adapters; adapters do not infer
// ownership from a directory, a launchd label, or a package receipt.
type HostProductRemovalPlan struct {
	DataDisposition                          string
	PreparePackageManagerCompletionTransport bool
	RemovePackageReceipt                     bool
	RemoveOperatorApplication                bool
	RemoveActivationLink                     bool
	RemoveReleaseCatalog                     bool
	RemoveServiceDefinitions                 []HostProductRequiredService
	RemoveMutableStores                      []HostProductMutableStoreDeclaration
}

func validHostProductRemovalRequest(request HostProductRemovalRequest) bool {
	if request.SchemaVersion != HostInstallationDocumentSchemaVersion || request.DocumentKind != "host-product-removal-request" || !validHostInstallationIdentifier(request.ID) || !validHostInstallationIdentifier(request.InstallationID) || !validHostInstallationIdentifier(request.ExpectedReleaseID) || !validHostProductRemovalDataDisposition(request.DataDisposition) {
		return false
	}
	_, err := time.Parse(time.RFC3339, request.RequestedAt)
	return err == nil
}

func validateHostProductPackageManagerCompletionTransport(manifest HostProductInstallationManifest, transport *HostProductPackageManagerCompletionTransport) error {
	if manifest.Platform == "macos" {
		if transport != nil {
			return fmt.Errorf("macOS product removal must not retain an OS package-manager completion transport")
		}
		return nil
	}
	if transport == nil || transport.ManagerPath == "" || transport.ManifestPath == "" {
		return fmt.Errorf("OS package-manager product removal requires a completion transport")
	}
	if transport.ManagerPath == transport.ManifestPath || hostInstallationPathBase(transport.ManagerPath, manifest.Platform) != packageManagerCompletionManagerBaseName(manifest.Platform) || hostInstallationPathBase(transport.ManifestPath, manifest.Platform) != "package-manager-removal-manifest.json" {
		return fmt.Errorf("OS package-manager completion transport paths are invalid")
	}
	if err := validateHostProductRemovalDocumentPath(manifest, transport.ManagerPath, packageManagerCompletionManagerBaseName(manifest.Platform)); err != nil {
		return fmt.Errorf("OS package-manager completion manager path is invalid: %w", err)
	}
	if err := validateHostProductRemovalDocumentPath(manifest, transport.ManifestPath, "package-manager-removal-manifest.json"); err != nil {
		return fmt.Errorf("OS package-manager completion manifest path is invalid: %w", err)
	}
	return nil
}

func packageManagerCompletionManagerBaseName(platform string) string {
	if platform == "windows" {
		return "package-manager-removal-completion.exe"
	}
	return "package-manager-removal-completion"
}

func validHostProductRemovalDataDisposition(value string) bool {
	return value == HostProductRemovalDataDispositionPreserveMutableData || value == HostProductRemovalDataDispositionPurgeAllProductData
}

func validateHostProductRemovalDocumentPath(manifest HostProductInstallationManifest, value string, requiredBase string) error {
	if !validAbsoluteHostInstallationPath(value, manifest.Platform) || hostInstallationPathBase(value, manifest.Platform) != requiredBase {
		return fmt.Errorf("Host product removal document path is invalid")
	}
	for _, store := range manifest.MutableStores {
		if store.Owner != "host-installation-manager" || store.Retention != "purge-only-by-explicit-command" {
			continue
		}
		if hostInstallationPathContainsForPlatform(store.Path, value, manifest.Platform) {
			return nil
		}
	}
	return fmt.Errorf("Host product removal document path is not below a manager-owned mutable store")
}

// ValidateHostProductRemovalJournal validates one durable removal transition
// before an adapter uses it as recovery evidence.
func ValidateHostProductRemovalJournal(journal HostProductRemovalJournal) error {
	if journal.SchemaVersion != HostInstallationDocumentSchemaVersion || journal.DocumentKind != "host-product-removal-journal" || !validHostInstallationIdentifier(journal.ID) || !validHostInstallationIdentifier(journal.RequestID) || !validHostInstallationIdentifier(journal.InstallationID) || !validHostInstallationIdentifier(journal.ReleaseID) || !validHostProductRemovalDataDisposition(journal.DataDisposition) {
		return fmt.Errorf("Host product removal journal identity is invalid")
	}
	createdAt, err := time.Parse(time.RFC3339, journal.CreatedAt)
	if err != nil {
		return fmt.Errorf("Host product removal journal createdAt is invalid")
	}
	updatedAt, err := time.Parse(time.RFC3339, journal.UpdatedAt)
	if err != nil {
		return fmt.Errorf("Host product removal journal updatedAt is invalid")
	}
	if updatedAt.Before(createdAt) {
		return fmt.Errorf("Host product removal journal updatedAt precedes createdAt")
	}
	if journal.PackageManagerCompletionTransport != nil {
		if journal.PackageManagerCompletionTransport.ManagerPath == "" || journal.PackageManagerCompletionTransport.ManifestPath == "" || journal.PackageManagerCompletionTransport.ManagerPath == journal.PackageManagerCompletionTransport.ManifestPath {
			return fmt.Errorf("Host product removal journal completion transport is invalid")
		}
	}
	switch journal.State {
	case HostProductRemovalJournalAdmitted,
		HostProductRemovalJournalServicesQuiescing,
		HostProductRemovalJournalImmutableContentRemoving,
		HostProductRemovalJournalMutableDataRemoving,
		HostProductRemovalJournalAwaitingPackageManager,
		HostProductRemovalJournalCompleted:
		if journal.Failure != nil {
			return fmt.Errorf("non-failed Host product removal journal must not contain failure")
		}
	case HostProductRemovalJournalFailed:
		if journal.Failure == nil || journal.Failure.Code == "" {
			return fmt.Errorf("failed Host product removal journal requires failure")
		}
	default:
		return fmt.Errorf("Host product removal journal state is invalid")
	}
	return nil
}

// ValidateHostProductRemovalReceipt keeps removal proof distinct from install
// proof, including whether data was explicitly preserved or purged.
func ValidateHostProductRemovalReceipt(receipt HostProductRemovalReceipt) error {
	if receipt.SchemaVersion != HostInstallationDocumentSchemaVersion || receipt.DocumentKind != "host-product-removal-receipt" || !validHostInstallationIdentifier(receipt.ID) || !validHostInstallationIdentifier(receipt.RequestID) || !validHostInstallationIdentifier(receipt.InstallationID) || !validHostInstallationIdentifier(receipt.ReleaseID) || !validHostProductRemovalDataDisposition(receipt.DataDisposition) {
		return fmt.Errorf("Host product removal receipt identity is invalid")
	}
	if _, err := time.Parse(time.RFC3339, receipt.ObservedAt); err != nil {
		return fmt.Errorf("Host product removal receipt observedAt is invalid")
	}
	seenStoreIDs := map[string]bool{}
	for _, storeID := range receipt.RetainedMutableStoreIDs {
		if !validHostInstallationIdentifier(storeID) || seenStoreIDs[storeID] {
			return fmt.Errorf("Host product removal receipt retained mutable stores are invalid")
		}
		seenStoreIDs[storeID] = true
	}
	switch receipt.State {
	case HostProductRemovalReceiptCompleted:
		if receipt.Issue != nil || (receipt.PackageReceiptRemoval != HostProductPackageReceiptRemovedByManager && receipt.PackageReceiptRemoval != HostProductPackageReceiptRemovedByOSPackageManager) {
			return fmt.Errorf("completed Host product removal receipt must not contain issue")
		}
		if receipt.DataDisposition == HostProductRemovalDataDispositionPurgeAllProductData && len(receipt.RetainedMutableStoreIDs) != 0 {
			return fmt.Errorf("purged Host product removal receipt must not retain mutable stores")
		}
	case HostProductRemovalReceiptAwaitingPackageManager:
		if receipt.Issue != nil || receipt.PackageReceiptRemoval != HostProductPackageReceiptAwaitingPackageManager {
			return fmt.Errorf("awaiting-package-manager Host product removal receipt is invalid")
		}
		if receipt.DataDisposition == HostProductRemovalDataDispositionPurgeAllProductData && len(receipt.RetainedMutableStoreIDs) != 0 {
			return fmt.Errorf("purged Host product removal receipt must not retain mutable stores")
		}
	case HostProductRemovalReceiptBlocked, HostProductRemovalReceiptFailed:
		if receipt.Issue == nil || receipt.Issue.Code == "" {
			return fmt.Errorf("blocked or failed Host product removal receipt requires issue")
		}
		if len(receipt.RetainedMutableStoreIDs) != 0 || receipt.PackageReceiptRemoval != "" {
			return fmt.Errorf("blocked or failed Host product removal receipt must not claim retained stores")
		}
	default:
		return fmt.Errorf("Host product removal receipt state is invalid")
	}
	return nil
}

// DecideHostProductRemovalAwaitingPackageManager proves the state just before
// dpkg/MSI removes its receipt. Linux reaches this boundary after dpkg deleted
// immutable payload; Windows reaches it from a pre-RemoveFiles custom action
// and therefore leaves the one exact declared immutable release for MSI to
// delete. Only the declared, matching package receipt may remain in its
// package-manager-owned installed or removing state. This makes the hand-off
// explicit instead of claiming that a package-owned database has already
// changed.
func DecideHostProductRemovalAwaitingPackageManager(
	request HostProductRemovalRequest,
	manifest HostProductInstallationManifest,
	footprint HostInstallationFootprint,
) (HostInstallationDecision, []string, error) {
	if !validHostProductRemovalRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, nil, fmt.Errorf("Host product removal pending request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostProductPackageManagerCompletionTransport(manifest, request.PackageManagerCompletionTransport); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return blockedHostInstallationDecision(*issue), nil, nil
	}
	if !packageReceiptAwaitingRemoval(manifest, footprint.PackageReceipt) {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "package-receipt-not-awaiting-declared-package-manager", Message: "OS package-manager hand-off requires the declared package receipt to remain installed until the package operation completes"}), nil, nil
	}
	if !immutablePayloadIsReadyForPackageManagerRemoval(manifest, footprint) || footprint.Activation.State != "absent" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-removal-not-ready-for-package-manager", Message: "immutable release catalog or activation remains before OS package-manager hand-off"}), nil, nil
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "absent" {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-removal-not-ready-for-package-manager", Message: "declared Host service remains before OS package-manager hand-off: " + service.Name}), nil, nil
		}
	}
	retainedStoreIDs := []string{}
	for _, store := range footprint.MutableStores {
		if request.DataDisposition == HostProductRemovalDataDispositionPurgeAllProductData {
			if store.State != "absent" {
				return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-data-purge-not-complete", Message: "declared mutable store remains before OS package-manager hand-off: " + store.ID}), nil, nil
			}
			continue
		}
		if store.State != "absent" {
			if store.State != "compatible" {
				return blockedHostInstallationDecision(HostInstallationIssue{Code: "preserved-product-data-not-compatible", Message: "preserved mutable store is not compatible: " + store.ID}), nil, nil
			}
			retainedStoreIDs = append(retainedStoreIDs, store.ID)
		}
	}
	sort.Strings(retainedStoreIDs)
	return HostInstallationDecision{State: "admitted", Mode: HostProductPackageReceiptAwaitingPackageManager, Effects: []string{"return-control-to-os-package-manager"}}, retainedStoreIDs, nil
}

// immutablePayloadIsReadyForPackageManagerRemoval distinguishes the package
// manager's removal boundary by platform. Linux invokes C54 after dpkg has
// removed the immutable payload, whereas Windows invokes the pre-remove
// custom action from that payload. Windows must therefore leave the one exact
// declared release for MSI to remove after the custom action exits.
func immutablePayloadIsReadyForPackageManagerRemoval(manifest HostProductInstallationManifest, footprint HostInstallationFootprint) bool {
	if manifest.Platform == "windows" {
		return footprint.ReleaseCatalog.State == "only-expected-release" && footprint.ImmutableRelease.State == "matching"
	}
	return footprint.ReleaseCatalog.State == "absent" && footprint.ImmutableRelease.State == "absent"
}

func packageReceiptAwaitingRemoval(manifest HostProductInstallationManifest, receipt HostInstallationPackageReceiptObservation) bool {
	if receipt.State != "installed" || receipt.ProductVersion != manifest.Package.ProductVersion {
		return false
	}
	if manifest.Platform != "linux" {
		return true
	}
	return receipt.PackageManagerReceiptState == "installed" || receipt.PackageManagerReceiptState == "removing"
}

// DecideHostProductRemoval admits removal only when every resource is an
// explicit, observable product resource. It blocks instead of deleting a
// diverged service definition, a changed immutable slot, another active
// release, an unreadable path, or an unfinished installation transaction.
func DecideHostProductRemoval(
	request HostProductRemovalRequest,
	manifest HostProductInstallationManifest,
	footprint HostInstallationFootprint,
	journalPath string,
	receiptPath string,
) (HostProductRemovalPlan, HostInstallationDecision, error) {
	if !validHostProductRemovalRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, fmt.Errorf("Host product removal request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, err
	}
	if err := validateHostProductPackageManagerCompletionTransport(manifest, request.PackageManagerCompletionTransport); err != nil {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, err
	}
	if err := validateHostProductRemovalDocumentPath(manifest, journalPath, "current-removal-transaction.json"); err != nil {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, err
	}
	if request.DataDisposition == HostProductRemovalDataDispositionPreserveMutableData {
		if err := validateHostProductRemovalDocumentPath(manifest, receiptPath, "latest-removal-receipt.json"); err != nil {
			return HostProductRemovalPlan{}, HostInstallationDecision{}, err
		}
	} else if receiptPath != "" {
		return HostProductRemovalPlan{}, HostInstallationDecision{}, fmt.Errorf("purge-all-product-data removal must not retain an in-product receipt path")
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(*issue), nil
	}
	if !hostInstallationTransactionIsRemovable(footprint.InstallationTransaction.State) {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "unfinished-installation-transaction", Message: "recover or explicitly resolve the existing installation transaction before product removal"}), nil
	}
	if !packageReceiptAwaitingRemoval(manifest, footprint.PackageReceipt) {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "package-receipt-does-not-identify-declared-release", Message: "product removal requires the installed package receipt to match the declared release"}), nil
	}
	if footprint.ReleaseCatalog.State != "absent" && footprint.ReleaseCatalog.State != "empty" && footprint.ReleaseCatalog.State != "only-expected-release" {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "release-catalog-not-exclusively-declared", Message: "product removal will not delete a release catalog that contains another or unexpected release"}), nil
	}
	if footprint.ImmutableRelease.State != "absent" && footprint.ImmutableRelease.State != "matching" {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "immutable-release-not-declared", Message: "product removal will not delete a diverged immutable release"}), nil
	}
	if footprint.Activation.State != "absent" && footprint.Activation.State != "points-to-expected-release" {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "activation-does-not-point-to-declared-release", Message: "product removal will not delete an activation link that points to another release"}), nil
	}
	if manifest.Platform == "macos" && footprint.OperatorApplication.State != "absent" && footprint.OperatorApplication.State != "matching" {
		return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "operator-application-not-declared", Message: "product removal will not delete a changed macOS operator application bundle"}), nil
	}
	for _, service := range footprint.RequiredServices {
		if service.DefinitionState != "absent" && service.DefinitionState != "matching" {
			return HostProductRemovalPlan{}, blockedHostInstallationDecision(HostInstallationIssue{Code: "service-definition-not-declared", Message: "product removal will not delete a diverged Host service definition: " + service.Name}), nil
		}
	}
	plan := HostProductRemovalPlan{
		DataDisposition:                          request.DataDisposition,
		PreparePackageManagerCompletionTransport: request.PackageManagerCompletionTransport != nil,
		RemovePackageReceipt:                     true,
		RemoveOperatorApplication:                manifest.Platform == "macos" && footprint.OperatorApplication.State == "matching",
		RemoveActivationLink:                     footprint.Activation.State == "points-to-expected-release",
		RemoveReleaseCatalog:                     manifest.Platform != "windows" && footprint.ReleaseCatalog.State != "absent",
		RemoveServiceDefinitions:                 append([]HostProductRequiredService(nil), manifest.RequiredServices...),
	}
	if request.DataDisposition == HostProductRemovalDataDispositionPurgeAllProductData {
		plan.RemoveMutableStores = topLevelMutableStores(manifest.MutableStores, manifest.Platform)
	}
	return plan, HostInstallationDecision{State: "admitted", Mode: request.DataDisposition, Effects: hostProductRemovalEffects(plan)}, nil
}

// DecideHostProductRemovalCompletion proves the exact terminal C54 condition.
// A normal package-manager observer reports absent. A C54-bound persisted
// completion transport may prove the transient removed state while dpkg is
// still running postrm. Preserve mode deliberately permits declared mutable
// stores to remain; purge mode requires every declared mutable store to be
// absent.
func DecideHostProductRemovalCompletion(
	request HostProductRemovalRequest,
	manifest HostProductInstallationManifest,
	footprint HostInstallationFootprint,
) (HostInstallationDecision, []string, error) {
	if !validHostProductRemovalRequest(request) || request.InstallationID != manifest.InstallationID || request.ExpectedReleaseID != manifest.Release.ID {
		return HostInstallationDecision{}, nil, fmt.Errorf("Host product removal completion request does not match the declared release")
	}
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostProductPackageManagerCompletionTransport(manifest, request.PackageManagerCompletionTransport); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostInstallationFootprint(manifest, footprint); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if issue := unavailableFootprintIssue(footprint); issue != nil {
		return blockedHostInstallationDecision(*issue), nil, nil
	}
	packageReceiptRemoved := footprint.PackageReceipt.State == "absent" || (request.PackageManagerCompletionTransport != nil && manifest.Platform == "linux" && footprint.PackageReceipt.State == "installed" && footprint.PackageReceipt.PackageManagerReceiptState == "removed" && footprint.PackageReceipt.ProductVersion == manifest.Package.ProductVersion)
	if !packageReceiptRemoved || footprint.ReleaseCatalog.State != "absent" || footprint.ImmutableRelease.State != "absent" || footprint.Activation.State != "absent" || (manifest.Platform == "macos" && footprint.OperatorApplication.State != "absent") {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-removal-not-complete", Message: "package receipt, immutable release catalog, activation link, or macOS operator application remains after product removal"}), nil, nil
	}
	for _, service := range footprint.RequiredServices {
		if service.State != "absent" || service.DefinitionState != "absent" {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-removal-not-complete", Message: "declared Host service remains after product removal: " + service.Name}), nil, nil
		}
	}
	retainedStoreIDs := []string{}
	for _, store := range footprint.MutableStores {
		if request.DataDisposition == HostProductRemovalDataDispositionPurgeAllProductData {
			if store.State != "absent" {
				return blockedHostInstallationDecision(HostInstallationIssue{Code: "product-data-purge-not-complete", Message: "declared mutable store remains after requested purge: " + store.ID}), nil, nil
			}
			continue
		}
		if store.State != "absent" {
			retainedStoreIDs = append(retainedStoreIDs, store.ID)
		}
	}
	sort.Strings(retainedStoreIDs)
	return HostInstallationDecision{State: "admitted", Mode: "removal-complete"}, retainedStoreIDs, nil
}

// DecideHostProductRemovalCompletionAfterPackageManager is the final C54
// transition for package systems whose database is owned by dpkg/MSI. The
// earlier removal must have durably reached awaiting-package-manager, and the
// caller must explicitly prove that the package receipt is absent, or that its
// package manager has reached the C54-bound transient removed state.
// It supports preservation only: a purge removes the manager-owned documents
// needed to prove this post-package-manager transition and needs its own
// explicit operator workflow.
func DecideHostProductRemovalCompletionAfterPackageManager(
	request HostProductRemovalRequest,
	manifest HostProductInstallationManifest,
	journal HostProductRemovalJournal,
	footprint HostInstallationFootprint,
	journalPath string,
	receiptPath string,
) (HostInstallationDecision, []string, error) {
	if request.DataDisposition != HostProductRemovalDataDispositionPreserveMutableData {
		return HostInstallationDecision{}, nil, fmt.Errorf("package-manager removal completion requires preserve-mutable-data")
	}
	if err := validateHostProductPackageManagerCompletionTransport(manifest, request.PackageManagerCompletionTransport); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostProductRemovalDocumentPath(manifest, journalPath, "current-removal-transaction.json"); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := validateHostProductRemovalDocumentPath(manifest, receiptPath, "latest-removal-receipt.json"); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if err := ValidateHostProductRemovalJournal(journal); err != nil {
		return HostInstallationDecision{}, nil, err
	}
	if journal.RequestID != request.ID || journal.InstallationID != request.InstallationID || journal.ReleaseID != request.ExpectedReleaseID || journal.DataDisposition != request.DataDisposition {
		return HostInstallationDecision{}, nil, fmt.Errorf("package-manager removal completion does not match the pending C54 journal")
	}
	if journal.PackageManagerCompletionTransport == nil || *journal.PackageManagerCompletionTransport != *request.PackageManagerCompletionTransport {
		return HostInstallationDecision{}, nil, fmt.Errorf("package-manager removal completion transport does not match the pending C54 journal")
	}
	if journal.State != HostProductRemovalJournalAwaitingPackageManager {
		return HostInstallationDecision{}, nil, fmt.Errorf("package-manager removal completion requires an awaiting-package-manager C54 journal")
	}
	return DecideHostProductRemovalCompletion(request, manifest, footprint)
}

func hostInstallationTransactionIsRemovable(state string) bool {
	switch state {
	case "absent", HostInstallationJournalCompleted, HostInstallationJournalRecovered, HostInstallationJournalFailed, "legacy-blocked-preflight", "receipt-residue":
		return true
	default:
		return false
	}
}

func topLevelMutableStores(stores []HostProductMutableStoreDeclaration, platform string) []HostProductMutableStoreDeclaration {
	result := make([]HostProductMutableStoreDeclaration, 0, len(stores))
	for _, candidate := range stores {
		contained := false
		for _, other := range stores {
			if candidate.ID == other.ID {
				continue
			}
			if hostInstallationPathContainsForPlatform(other.Path, candidate.Path, platform) {
				contained = true
				break
			}
		}
		if !contained {
			result = append(result, candidate)
		}
	}
	sort.Slice(result, func(left int, right int) bool {
		return normalizedHostInstallationPath(result[left].Path, platform) < normalizedHostInstallationPath(result[right].Path, platform)
	})
	return result
}

func hostProductRemovalEffects(plan HostProductRemovalPlan) []string {
	effects := []string{"write-removal-journal", "quiesce-declared-host-services", "remove-declared-service-definitions"}
	if plan.PreparePackageManagerCompletionTransport {
		effects = append(effects, "prepare-package-manager-completion-transport")
	}
	if plan.RemoveActivationLink {
		effects = append(effects, "remove-current-release-link")
	}
	if plan.RemoveOperatorApplication {
		effects = append(effects, "remove-declared-macos-operator-application")
	}
	if plan.RemoveReleaseCatalog {
		effects = append(effects, "remove-declared-release-catalog")
	}
	if plan.RemovePackageReceipt {
		effects = append(effects, "remove-declared-package-receipt-or-await-os-package-manager")
	}
	if len(plan.RemoveMutableStores) != 0 {
		effects = append(effects, "purge-declared-mutable-stores")
	}
	return effects
}
