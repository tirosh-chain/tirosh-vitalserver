// Package hostinstallationmanagerdomain owns pure C48/C49/C50 validation and
// preflight/activation decisions. It has no filesystem, process, launchd, or
// package-manager dependency.
package hostinstallationmanagerdomain

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const HostInstallationDocumentSchemaVersion = "v1"

// macOS product delivery installs the operator console as part of the same
// C48 package as the Host services. Keeping this location and entrypoint in
// the domain contract prevents a removal command from turning a caller-supplied
// path into an application deletion authority.
const (
	MacOSHostProductOperatorApplicationBundlePath             = "/Applications/VitalServer Runtime Platform.app"
	MacOSHostProductOperatorApplicationEntrypointRelativePath = "Contents/MacOS/VitalServer Runtime Platform"
)

// HostInstallationTransactionStoreID is the C48-declared mutable store that
// owns the one current C50 transaction. A release may declare other manager
// stores (for example C68 operation evidence), but they must never be guessed
// as the C50 journal location.
const HostInstallationTransactionStoreID = "installation-manager-journal"

const (
	HostInstallationCurrentJournalFileName = "current-transaction.json"
	HostInstallationLatestReceiptFileName  = "latest-installation-receipt.json"
)

const (
	HostInstallationOperationPreflight           = "preflight"
	HostInstallationOperationQuiesceServices     = "quiesce-services"
	HostInstallationOperationActivateRelease     = "activate-release"
	HostInstallationOperationFinalizeServices    = "finalize-services"
	HostInstallationOperationRecoverInstallation = "recover-installation"
)

const HostInstallationPackageManagerOperationWindowsMSIInstalling = "windows-msi-installing"

const (
	HostInstallationReceiptPreflightAdmitted = "preflight-admitted"
	HostInstallationReceiptServicesQuiesced  = "services-quiesced"
	HostInstallationReceiptActivated         = "activated"
	HostInstallationReceiptCompleted         = "completed"
	HostInstallationReceiptRecovered         = "recovered"
	HostInstallationReceiptBlocked           = "blocked"
	HostInstallationReceiptFailed            = "failed"
)

const (
	HostInstallationJournalPreflightVerified = "preflight-verified"
	HostInstallationJournalServicesQuiescing = "services-quiescing"
	HostInstallationJournalActivationPending = "activation-pending"
	HostInstallationJournalActivated         = "activated"
	HostInstallationJournalCompleted         = "completed"
	HostInstallationJournalRecovered         = "recovered"
	HostInstallationJournalFailed            = "failed"
)

var hostInstallationIdentifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)

// HostProductInstallationManifest is C48. It declares immutable product
// content and externally managed mutable locations; it is not an observation.
type HostProductInstallationManifest struct {
	SchemaVersion     string                               `json:"schemaVersion"`
	InstallationID    string                               `json:"installationId"`
	Platform          string                               `json:"platform"`
	Release           HostProductRelease                   `json:"release"`
	Package           HostProductPackageIdentity           `json:"package"`
	ImmutablePayload  HostImmutableProductPayload          `json:"immutablePayload"`
	Activation        HostProductReleaseActivation         `json:"activation"`
	OperatorInterface HostProductOperatorInterface         `json:"operatorInterface"`
	RequiredServices  []HostProductRequiredService         `json:"requiredServices"`
	MutableStores     []HostProductMutableStoreDeclaration `json:"mutableStores"`
}

type HostProductRelease struct {
	ID             string `json:"id"`
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
}

type HostProductPackageIdentity struct {
	Identifier               string `json:"identifier"`
	ProductVersion           string `json:"productVersion"`
	PackageManagerIdentifier string `json:"packageManagerIdentifier,omitempty"`
}

type HostImmutableProductPayload struct {
	ReleaseCatalogPath string                             `json:"releaseCatalogPath"`
	ReleaseRootPath    string                             `json:"releaseRootPath"`
	ManifestPath       string                             `json:"manifestPath"`
	Entries            []HostImmutableProductPayloadEntry `json:"entries"`
}

type HostImmutableProductPayloadEntry struct {
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	Executable   bool   `json:"executable"`
}

type HostProductReleaseActivation struct {
	CurrentReleaseLinkPath  string `json:"currentReleaseLinkPath"`
	ReferenceKind           string `json:"referenceKind"`
	ExpectedReleaseRootPath string `json:"expectedReleaseRootPath"`
}

// HostProductOperatorInterface declares the installer-written C53 file that a
// packaged desktop shell reads. On macOS, it also declares the immutable
// application bundle delivered by the same C48 package. Neither declaration
// claims that C52 currently exists or that the user was authorized.
type HostProductOperatorInterface struct {
	BootstrapConfigurationPath              string `json:"bootstrapConfigurationPath"`
	BootstrapConfigurationSHA256            string `json:"bootstrapConfigurationSha256"`
	ApplicationBundlePath                   string `json:"applicationBundlePath,omitempty"`
	ApplicationBundleTreeSHA256             string `json:"applicationBundleTreeSha256,omitempty"`
	ApplicationBundleEntrypointRelativePath string `json:"applicationBundleEntrypointRelativePath,omitempty"`
}

type HostProductRequiredService struct {
	Role                   string                             `json:"role"`
	Manager                string                             `json:"manager"`
	Name                   string                             `json:"name"`
	DefinitionPath         string                             `json:"definitionPath"`
	DefinitionSHA256       string                             `json:"definitionSha256"`
	WindowsSCMRegistration *HostProductWindowsSCMRegistration `json:"windowsScmRegistration,omitempty"`
}

// HostProductWindowsSCMRegistration is C48 desired service registration. It
// names a launch command and service-manager values, not process liveness.
// Windows adapters render it as an exact SCM command line without invoking a
// shell.
type HostProductWindowsSCMRegistration struct {
	ExecutablePath string   `json:"executablePath"`
	Arguments      []string `json:"arguments"`
	StartMode      string   `json:"startMode"`
	Account        string   `json:"account"`
}

type HostProductMutableStoreDeclaration struct {
	ID        string `json:"id"`
	Path      string `json:"path"`
	Kind      string `json:"kind"`
	Owner     string `json:"owner"`
	Retention string `json:"retention"`
}

// HostInstallationFootprint is C49. Each state comes from an adapter
// observation; the domain must not manufacture it from a missing detail.
type HostInstallationFootprint struct {
	SchemaVersion           string                                          `json:"schemaVersion"`
	InstallationID          string                                          `json:"installationId"`
	ExpectedReleaseID       string                                          `json:"expectedReleaseId"`
	Platform                string                                          `json:"platform"`
	ObservedAt              string                                          `json:"observedAt"`
	PackageReceipt          HostInstallationPackageReceiptObservation       `json:"packageReceipt"`
	ReleaseCatalog          HostInstallationReleaseCatalogObservation       `json:"releaseCatalog"`
	ImmutableRelease        HostInstallationImmutableReleaseObservation     `json:"immutableRelease"`
	Activation              HostInstallationActivationObservation           `json:"activation"`
	OperatorApplication     *HostInstallationOperatorApplicationObservation `json:"operatorApplication,omitempty"`
	RequiredServices        []HostInstallationServiceObservation            `json:"requiredServices"`
	MutableStores           []HostInstallationMutableStoreObservation       `json:"mutableStores"`
	InstallationTransaction HostInstallationTransactionObservation          `json:"installationTransaction"`
}

// HostInstallationOperatorApplicationObservation is the macOS-only C49
// observation of the C48-declared bundled operator application. A missing app,
// a changed app, and an unreadable app remain separate states so C54 never
// deletes an application it has not proved belongs to this product.
type HostInstallationOperatorApplicationObservation struct {
	State                 string                 `json:"state"`
	ApplicationBundlePath string                 `json:"applicationBundlePath"`
	Issue                 *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationIssue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  bool   `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type HostInstallationPackageReceiptObservation struct {
	// State is the stable cross-package-manager receipt state. The exact state
	// of a package manager that exposes one is carried separately, so adding a
	// new OS lifecycle state does not change the v1 generic contract enum.
	State                      string                 `json:"state"`
	Identifier                 string                 `json:"identifier"`
	ProductVersion             string                 `json:"productVersion,omitempty"`
	PackageManagerReceiptState string                 `json:"packageManagerReceiptState,omitempty"`
	Issue                      *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationImmutableReleaseObservation struct {
	State           string                 `json:"state"`
	ReleaseRootPath string                 `json:"releaseRootPath"`
	Issue           *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationReleaseCatalogObservation struct {
	State              string                 `json:"state"`
	ReleaseCatalogPath string                 `json:"releaseCatalogPath"`
	ReleaseIDs         []string               `json:"releaseIds,omitempty"`
	Issue              *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationActivationObservation struct {
	State                  string                 `json:"state"`
	CurrentReleaseLinkPath string                 `json:"currentReleaseLinkPath"`
	ObservedTargetPath     string                 `json:"observedTargetPath,omitempty"`
	Issue                  *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationServiceObservation struct {
	Role            string                 `json:"role"`
	Name            string                 `json:"name"`
	State           string                 `json:"state"`
	Issue           *HostInstallationIssue `json:"issue,omitempty"`
	DefinitionState string                 `json:"definitionState"`
	DefinitionIssue *HostInstallationIssue `json:"definitionIssue,omitempty"`
}

type HostInstallationMutableStoreObservation struct {
	ID    string                 `json:"id"`
	State string                 `json:"state"`
	Issue *HostInstallationIssue `json:"issue,omitempty"`
}

type HostInstallationTransactionObservation struct {
	State       string                 `json:"state"`
	JournalPath string                 `json:"journalPath"`
	ReceiptPath string                 `json:"receiptPath"`
	Issue       *HostInstallationIssue `json:"issue,omitempty"`
}

// HostInstallationRequest is C50 desired work submitted by package scripts or
// an explicit installer workflow. The operation is not inferred from a path.
type HostInstallationRequest struct {
	SchemaVersion           string `json:"schemaVersion"`
	DocumentKind            string `json:"documentKind"`
	ID                      string `json:"id"`
	InstallationID          string `json:"installationId"`
	Operation               string `json:"operation"`
	PackageManagerOperation string `json:"packageManagerOperation,omitempty"`
	ExpectedReleaseID       string `json:"expectedReleaseId"`
	RequestedAt             string `json:"requestedAt"`
}

type HostInstallationJournal struct {
	SchemaVersion  string                 `json:"schemaVersion"`
	DocumentKind   string                 `json:"documentKind"`
	ID             string                 `json:"id"`
	RequestID      string                 `json:"requestId"`
	InstallationID string                 `json:"installationId"`
	ReleaseID      string                 `json:"releaseId"`
	State          string                 `json:"state"`
	Failure        *HostInstallationIssue `json:"failure,omitempty"`
	CreatedAt      string                 `json:"createdAt"`
	UpdatedAt      string                 `json:"updatedAt"`
}

type HostInstallationReceipt struct {
	SchemaVersion  string                 `json:"schemaVersion"`
	DocumentKind   string                 `json:"documentKind"`
	ID             string                 `json:"id"`
	RequestID      string                 `json:"requestId"`
	InstallationID string                 `json:"installationId"`
	ReleaseID      string                 `json:"releaseId"`
	State          string                 `json:"state"`
	Issue          *HostInstallationIssue `json:"issue,omitempty"`
	ObservedAt     string                 `json:"observedAt"`
}

type HostInstallationDecision struct {
	State   string                 `json:"state"`
	Mode    string                 `json:"mode,omitempty"`
	Issue   *HostInstallationIssue `json:"issue,omitempty"`
	Effects []string               `json:"effects,omitempty"`
}

func validHostInstallationIdentifier(value string) bool {
	return hostInstallationIdentifierPattern.MatchString(value) && len(value) <= 128
}

func validHostInstallationRequest(request HostInstallationRequest) bool {
	if request.SchemaVersion != HostInstallationDocumentSchemaVersion || request.DocumentKind != "host-installation-request" || !validHostInstallationIdentifier(request.ID) || !validHostInstallationIdentifier(request.InstallationID) || !validHostInstallationIdentifier(request.ExpectedReleaseID) {
		return false
	}
	if request.PackageManagerOperation != "" && request.PackageManagerOperation != HostInstallationPackageManagerOperationWindowsMSIInstalling {
		return false
	}
	_, err := time.Parse(time.RFC3339, request.RequestedAt)
	return err == nil
}

func validateHostProductInstallationManifest(manifest HostProductInstallationManifest) error {
	if manifest.SchemaVersion != HostInstallationDocumentSchemaVersion || !validHostInstallationIdentifier(manifest.InstallationID) || !validHostInstallationPlatform(manifest.Platform) {
		return fmt.Errorf("installation manifest identity is invalid")
	}
	if !validHostInstallationIdentifier(manifest.Release.ID) || manifest.Release.ProductVersion == "" || manifest.Release.RuntimeVersion == "" || manifest.Package.ProductVersion != manifest.Release.ProductVersion {
		return fmt.Errorf("installation manifest release is invalid")
	}
	if manifest.Package.Identifier == "" || manifest.Package.ProductVersion == "" || (manifest.Platform == "windows" && (!validWindowsInstallerProductCode(manifest.Package.PackageManagerIdentifier) || !validWindowsInstallerProductVersion(manifest.Package.ProductVersion))) {
		return fmt.Errorf("installation manifest package identity is invalid")
	}
	if !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ReleaseCatalogPath, manifest.Platform) || !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ReleaseRootPath, manifest.Platform) || !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ManifestPath, manifest.Platform) || len(manifest.ImmutablePayload.Entries) == 0 {
		return fmt.Errorf("installation manifest immutable payload is invalid")
	}
	if hostInstallationPathDir(manifest.ImmutablePayload.ReleaseRootPath, manifest.Platform) != normalizedHostInstallationPath(manifest.ImmutablePayload.ReleaseCatalogPath, manifest.Platform) || hostInstallationPathBase(manifest.ImmutablePayload.ReleaseRootPath, manifest.Platform) != manifest.Release.ID || hostInstallationPathDir(manifest.ImmutablePayload.ManifestPath, manifest.Platform) != normalizedHostInstallationPath(manifest.ImmutablePayload.ReleaseRootPath, manifest.Platform) || hostInstallationPathBase(manifest.ImmutablePayload.ManifestPath, manifest.Platform) != "installation-manifest.json" {
		return fmt.Errorf("installation manifest immutable payload paths do not identify one release slot")
	}
	if !validAbsoluteHostInstallationPath(manifest.Activation.CurrentReleaseLinkPath, manifest.Platform) || !validHostInstallationActivationReferenceKind(manifest.Activation.ReferenceKind, manifest.Platform) || hostInstallationPathDir(manifest.Activation.CurrentReleaseLinkPath, manifest.Platform) != hostInstallationPathDir(manifest.ImmutablePayload.ReleaseCatalogPath, manifest.Platform) || normalizedHostInstallationPath(manifest.Activation.ExpectedReleaseRootPath, manifest.Platform) != normalizedHostInstallationPath(manifest.ImmutablePayload.ReleaseRootPath, manifest.Platform) {
		return fmt.Errorf("installation manifest activation does not name its immutable release root")
	}
	if !validAbsoluteHostInstallationPath(manifest.OperatorInterface.BootstrapConfigurationPath, manifest.Platform) || !validSHA256(manifest.OperatorInterface.BootstrapConfigurationSHA256) {
		return fmt.Errorf("installation manifest operator interface is invalid")
	}
	if manifest.Platform == "macos" {
		if manifest.OperatorInterface.ApplicationBundlePath != MacOSHostProductOperatorApplicationBundlePath || !validSHA256(manifest.OperatorInterface.ApplicationBundleTreeSHA256) || manifest.OperatorInterface.ApplicationBundleEntrypointRelativePath != MacOSHostProductOperatorApplicationEntrypointRelativePath {
			return fmt.Errorf("macOS installation manifest operator application is invalid")
		}
	} else if manifest.OperatorInterface.ApplicationBundlePath != "" || manifest.OperatorInterface.ApplicationBundleTreeSHA256 != "" || manifest.OperatorInterface.ApplicationBundleEntrypointRelativePath != "" {
		return fmt.Errorf("non-macOS installation manifest must not declare a macOS operator application")
	}
	if len(manifest.RequiredServices) != 3 || len(manifest.MutableStores) == 0 {
		return fmt.Errorf("installation manifest required services or mutable stores are incomplete")
	}
	seenServiceRoles := map[string]bool{}
	for _, service := range manifest.RequiredServices {
		if (service.Role != "host-agent" && service.Role != "host-edge-proxy" && service.Role != "host-update-handoff-supervisor") || seenServiceRoles[service.Role] || !validHostInstallationIdentifier(service.Name) || service.Manager != serviceManagerForHostInstallationPlatform(manifest.Platform) || !validAbsoluteHostInstallationPath(service.DefinitionPath, manifest.Platform) || !validSHA256(service.DefinitionSHA256) {
			return fmt.Errorf("installation manifest required service is invalid")
		}
		if manifest.Platform == "windows" && !validHostProductWindowsSCMRegistration(service.WindowsSCMRegistration, manifest.Activation.CurrentReleaseLinkPath, service.DefinitionPath) {
			return fmt.Errorf("Windows installation manifest service registration is invalid")
		}
		if manifest.Platform != "windows" && service.WindowsSCMRegistration != nil {
			return fmt.Errorf("non-Windows installation manifest must not declare a Windows SCM registration")
		}
		seenServiceRoles[service.Role] = true
	}
	if !seenServiceRoles["host-agent"] || !seenServiceRoles["host-edge-proxy"] || !seenServiceRoles["host-update-handoff-supervisor"] {
		return fmt.Errorf("installation manifest must name Host Agent, Host Edge Proxy, and Host Update Handoff Supervisor")
	}
	seenPayloadPaths := map[string]bool{}
	windowsServiceRunnerDeclared := false
	for _, entry := range manifest.ImmutablePayload.Entries {
		if !validRelativeHostInstallationPayloadPath(entry.RelativePath) || !validSHA256(entry.SHA256) || seenPayloadPaths[entry.RelativePath] {
			return fmt.Errorf("installation manifest immutable payload entry is invalid")
		}
		seenPayloadPaths[entry.RelativePath] = true
		if manifest.Platform == "windows" && entry.RelativePath == "bin/host-service-runner.exe" && entry.Executable {
			windowsServiceRunnerDeclared = true
		}
	}
	if manifest.Platform == "windows" && !windowsServiceRunnerDeclared {
		return fmt.Errorf("Windows installation manifest must declare the Host service runner executable")
	}
	seenStoreIDs := map[string]bool{}
	transactionStoreDeclared := false
	for _, store := range manifest.MutableStores {
		if !validHostInstallationIdentifier(store.ID) || seenStoreIDs[store.ID] || !validAbsoluteHostInstallationPath(store.Path, manifest.Platform) || store.Kind != "directory" || !validHostInstallationMutableStoreOwner(store.Owner) || !validHostInstallationMutableStoreRetention(store.Retention) {
			return fmt.Errorf("installation manifest mutable store is invalid")
		}
		if store.ID == HostInstallationTransactionStoreID {
			transactionStoreDeclared = store.Owner == "host-installation-manager" && store.Kind == "directory" && store.Retention == "purge-only-by-explicit-command"
		}
		seenStoreIDs[store.ID] = true
	}
	if !transactionStoreDeclared {
		return fmt.Errorf("installation manifest must declare the Host installation transaction store")
	}
	return nil
}

func validHostInstallationPlatform(value string) bool {
	return value == "macos" || value == "windows" || value == "linux"
}

var windowsInstallerProductCodePattern = regexp.MustCompile(`^\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$`)

func validWindowsInstallerProductCode(value string) bool {
	return windowsInstallerProductCodePattern.MatchString(value)
}

// validWindowsInstallerProductVersion is the C48 admission rule for an MSI
// package receipt. C48 keeps release and package product version identical, so
// accepting a display-only suffix such as "0.2.0-dev" would later make an MSI
// artifact impossible to compile and its C49 receipt impossible to compare.
// This is a Domain validation rule, not a formatter or a package-tool fallback.
func validWindowsInstallerProductVersion(value string) bool {
	parts := strings.Split(value, ".")
	if len(parts) != 3 {
		return false
	}
	maximums := []int{255, 255, 65535}
	for index, part := range parts {
		if part == "" || (len(part) > 1 && part[0] == '0') {
			return false
		}
		number, err := strconv.Atoi(part)
		if err != nil || number < 0 || number > maximums[index] {
			return false
		}
	}
	return true
}

func validHostProductWindowsSCMRegistration(registration *HostProductWindowsSCMRegistration, currentReleaseLinkPath string, serviceDefinitionPath string) bool {
	if registration == nil || !validAbsoluteHostInstallationPath(registration.ExecutablePath, "windows") || registration.StartMode != "automatic" || registration.Account != "LocalSystem" || len(registration.Arguments) > 64 {
		return false
	}
	expectedRunnerPath := normalizedHostInstallationPath(currentReleaseLinkPath, "windows") + `\bin\host-service-runner.exe`
	if normalizedHostInstallationPath(registration.ExecutablePath, "windows") != expectedRunnerPath || len(registration.Arguments) != 2 || registration.Arguments[0] != "--service-definition" || normalizedHostInstallationPath(registration.Arguments[1], "windows") != normalizedHostInstallationPath(serviceDefinitionPath, "windows") {
		return false
	}
	for _, argument := range registration.Arguments {
		if argument == "" || len(argument) > 4096 || strings.ContainsRune(argument, '\x00') {
			return false
		}
	}
	return true
}

func serviceManagerForHostInstallationPlatform(platform string) string {
	switch platform {
	case "macos":
		return "launchd"
	case "windows":
		return "windows-scm"
	case "linux":
		return "systemd"
	default:
		return ""
	}
}

// validHostInstallationActivationReferenceKind keeps the filesystem mechanism
// in C48 rather than letting a native adapter choose based on its own host.
// A symbolic link and an NTFS directory junction have different safety and
// replacement semantics, so they are never interchangeable defaults.
func validHostInstallationActivationReferenceKind(referenceKind string, platform string) bool {
	switch platform {
	case "macos", "linux":
		return referenceKind == "symbolic-link"
	case "windows":
		return referenceKind == "directory-junction"
	default:
		return false
	}
}

func validHostInstallationMutableStoreOwner(value string) bool {
	return value == "host-agent" || value == "macos-virtual-machine-supervisor" || value == "native-platform-provider" || value == "host-installation-manager" || value == "host-update-handoff-supervisor"
}

func validHostInstallationMutableStoreRetention(value string) bool {
	return value == "preserve-by-default" || value == "purge-only-by-explicit-command"
}

// ValidateHostProductInstallationManifest is the explicit pure gate used by
// adapters before they resolve any path from C48.
func ValidateHostProductInstallationManifest(manifest HostProductInstallationManifest) error {
	return validateHostProductInstallationManifest(manifest)
}

// DeclaredHostInstallationTransactionStorePath returns the one C48-declared
// C50 store. It is pure policy: a second manager-owned directory is never a
// compatible substitute merely because it has the same owner.
func DeclaredHostInstallationTransactionStorePath(manifest HostProductInstallationManifest) (string, error) {
	if err := validateHostProductInstallationManifest(manifest); err != nil {
		return "", err
	}
	for _, store := range manifest.MutableStores {
		if store.ID != HostInstallationTransactionStoreID {
			continue
		}
		if store.Owner != "host-installation-manager" || store.Kind != "directory" || store.Retention != "purge-only-by-explicit-command" {
			return "", fmt.Errorf("C48 Host installation transaction store declaration is invalid")
		}
		return store.Path, nil
	}
	return "", fmt.Errorf("C48 does not declare the Host installation transaction store")
}

// DeclaredHostInstallationTransactionPaths derives the two C50 document paths
// from the explicit C48 transaction-store declaration.
func DeclaredHostInstallationTransactionPaths(manifest HostProductInstallationManifest) (string, string, error) {
	storePath, err := DeclaredHostInstallationTransactionStorePath(manifest)
	if err != nil {
		return "", "", err
	}
	return hostInstallationPathJoin(storePath, HostInstallationCurrentJournalFileName, manifest.Platform), hostInstallationPathJoin(storePath, HostInstallationLatestReceiptFileName, manifest.Platform), nil
}

// ValidateHostInstallationJournal keeps C50 journal identity and terminal
// meaning explicit before an adapter reports a transaction as completed.
// Merely decoding a JSON object with an "activated" state is never enough.
func ValidateHostInstallationJournal(journal HostInstallationJournal) error {
	if journal.SchemaVersion != HostInstallationDocumentSchemaVersion || journal.DocumentKind != "host-installation-journal" || !validHostInstallationIdentifier(journal.ID) || !validHostInstallationIdentifier(journal.RequestID) || !validHostInstallationIdentifier(journal.InstallationID) || !validHostInstallationIdentifier(journal.ReleaseID) {
		return fmt.Errorf("Host installation journal identity is invalid")
	}
	createdAt, err := time.Parse(time.RFC3339, journal.CreatedAt)
	if err != nil {
		return fmt.Errorf("Host installation journal createdAt is invalid")
	}
	updatedAt, err := time.Parse(time.RFC3339, journal.UpdatedAt)
	if err != nil {
		return fmt.Errorf("Host installation journal updatedAt is invalid")
	}
	if updatedAt.Before(createdAt) {
		return fmt.Errorf("Host installation journal updatedAt precedes createdAt")
	}
	switch journal.State {
	case HostInstallationJournalPreflightVerified,
		HostInstallationJournalServicesQuiescing,
		HostInstallationJournalActivationPending,
		HostInstallationJournalActivated,
		HostInstallationJournalCompleted,
		HostInstallationJournalRecovered:
		if journal.Failure != nil {
			return fmt.Errorf("non-failed Host installation journal must not contain failure")
		}
	case HostInstallationJournalFailed:
		if journal.Failure == nil || journal.Failure.Code == "" {
			return fmt.Errorf("failed Host installation journal requires failure")
		}
	default:
		return fmt.Errorf("Host installation journal state is invalid")
	}
	return nil
}

// ValidateHostInstallationReceipt keeps the C50 receipt a typed state
// document. In particular, a historical blocked receipt can be considered by
// an explicit migration only after its identity and failure meaning decode.
func ValidateHostInstallationReceipt(receipt HostInstallationReceipt) error {
	if receipt.SchemaVersion != HostInstallationDocumentSchemaVersion || receipt.DocumentKind != "host-installation-receipt" || !validHostInstallationIdentifier(receipt.ID) || !validHostInstallationIdentifier(receipt.RequestID) || !validHostInstallationIdentifier(receipt.InstallationID) || !validHostInstallationIdentifier(receipt.ReleaseID) {
		return fmt.Errorf("Host installation receipt identity is invalid")
	}
	if _, err := time.Parse(time.RFC3339, receipt.ObservedAt); err != nil {
		return fmt.Errorf("Host installation receipt observedAt is invalid")
	}
	switch receipt.State {
	case HostInstallationReceiptPreflightAdmitted,
		HostInstallationReceiptServicesQuiesced,
		HostInstallationReceiptActivated,
		HostInstallationReceiptCompleted,
		HostInstallationReceiptRecovered:
		if receipt.Issue != nil {
			return fmt.Errorf("non-failed Host installation receipt must not contain issue")
		}
	case HostInstallationReceiptBlocked, HostInstallationReceiptFailed:
		if receipt.Issue == nil || receipt.Issue.Code == "" {
			return fmt.Errorf("blocked or failed Host installation receipt requires issue")
		}
	default:
		return fmt.Errorf("Host installation receipt state is invalid")
	}
	return nil
}

func validAbsoluteHostInstallationPath(value string, platform string) bool {
	if value == "" || strings.ContainsRune(value, '\x00') || containsHostInstallationTraversal(value) {
		return false
	}
	switch platform {
	case "windows":
		return windowsHostInstallationPathPattern.MatchString(value)
	case "macos", "linux":
		return strings.HasPrefix(value, "/") && !strings.Contains(value, "\\")
	default:
		return false
	}
}

func validRelativeHostInstallationPayloadPath(value string) bool {
	return value != "" && !strings.HasPrefix(value, "/") && !windowsHostInstallationPathPattern.MatchString(value) && !containsHostInstallationTraversal(value)
}

func containsHostInstallationTraversal(value string) bool {
	for _, segment := range strings.FieldsFunc(value, func(character rune) bool { return character == '/' || character == '\\' }) {
		if segment == ".." {
			return true
		}
	}
	return false
}

var windowsHostInstallationPathPattern = regexp.MustCompile(`^[A-Za-z]:[\\/]`)

func normalizedHostInstallationPath(value string, platform string) string {
	if platform == "windows" {
		return strings.ReplaceAll(value, "/", "\\")
	}
	return value
}

func hostInstallationPathDir(value string, platform string) string {
	normalized := normalizedHostInstallationPath(value, platform)
	separator := "/"
	if platform == "windows" {
		separator = "\\"
	}
	index := strings.LastIndex(normalized, separator)
	if index < 0 {
		return ""
	}
	if platform == "windows" && index == 2 {
		return normalized[:3]
	}
	if index == 0 {
		return separator
	}
	return normalized[:index]
}

func hostInstallationPathBase(value string, platform string) string {
	normalized := normalizedHostInstallationPath(value, platform)
	separator := "/"
	if platform == "windows" {
		separator = "\\"
	}
	index := strings.LastIndex(normalized, separator)
	if index < 0 {
		return normalized
	}
	return normalized[index+1:]
}

func hostInstallationPathJoin(root string, name string, platform string) string {
	if platform == "windows" {
		return strings.TrimRight(root, "/\\") + "\\" + name
	}
	return strings.TrimRight(root, "/") + "/" + name
}

func validSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, runeValue := range value {
		if (runeValue < 'a' || runeValue > 'f') && (runeValue < '0' || runeValue > '9') {
			return false
		}
	}
	return true
}
