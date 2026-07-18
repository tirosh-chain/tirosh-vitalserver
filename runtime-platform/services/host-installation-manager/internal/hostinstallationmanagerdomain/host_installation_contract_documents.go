// Package hostinstallationmanagerdomain owns pure C48/C49/C50 validation and
// preflight/activation decisions. It has no filesystem, process, launchd, or
// package-manager dependency.
package hostinstallationmanagerdomain

import (
	"fmt"
	"path"
	"regexp"
	"time"
)

const HostInstallationDocumentSchemaVersion = "v1"

const (
	HostInstallationOperationPreflight       = "preflight"
	HostInstallationOperationQuiesceServices = "quiesce-services"
	HostInstallationOperationActivateRelease = "activate-release"
)

const (
	HostInstallationReceiptPreflightAdmitted = "preflight-admitted"
	HostInstallationReceiptServicesQuiesced  = "services-quiesced"
	HostInstallationReceiptActivated         = "activated"
	HostInstallationReceiptBlocked           = "blocked"
	HostInstallationReceiptFailed            = "failed"
)

const (
	HostInstallationJournalPreflightVerified = "preflight-verified"
	HostInstallationJournalActivationPending = "activation-pending"
	HostInstallationJournalActivated         = "activated"
	HostInstallationJournalFailed            = "failed"
)

var hostInstallationIdentifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)

// HostProductInstallationManifest is C48. It declares immutable product
// content and externally managed mutable locations; it is not an observation.
type HostProductInstallationManifest struct {
	SchemaVersion    string                               `json:"schemaVersion"`
	InstallationID   string                               `json:"installationId"`
	Platform         string                               `json:"platform"`
	Release          HostProductRelease                   `json:"release"`
	Package          HostProductPackageIdentity           `json:"package"`
	ImmutablePayload HostImmutableProductPayload          `json:"immutablePayload"`
	Activation       HostProductReleaseActivation         `json:"activation"`
	RequiredServices []HostProductRequiredService         `json:"requiredServices"`
	MutableStores    []HostProductMutableStoreDeclaration `json:"mutableStores"`
}

type HostProductRelease struct {
	ID             string `json:"id"`
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
}

type HostProductPackageIdentity struct {
	Identifier     string `json:"identifier"`
	ProductVersion string `json:"productVersion"`
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
	ExpectedReleaseRootPath string `json:"expectedReleaseRootPath"`
}

type HostProductRequiredService struct {
	Role             string `json:"role"`
	Manager          string `json:"manager"`
	Name             string `json:"name"`
	DefinitionPath   string `json:"definitionPath"`
	DefinitionSHA256 string `json:"definitionSha256"`
}

type HostProductMutableStoreDeclaration struct {
	ID        string `json:"id"`
	Path      string `json:"path"`
	Owner     string `json:"owner"`
	Retention string `json:"retention"`
}

// HostInstallationFootprint is C49. Each state comes from an adapter
// observation; the domain must not manufacture it from a missing detail.
type HostInstallationFootprint struct {
	SchemaVersion           string                                      `json:"schemaVersion"`
	InstallationID          string                                      `json:"installationId"`
	ExpectedReleaseID       string                                      `json:"expectedReleaseId"`
	Platform                string                                      `json:"platform"`
	ObservedAt              string                                      `json:"observedAt"`
	PackageReceipt          HostInstallationPackageReceiptObservation   `json:"packageReceipt"`
	ReleaseCatalog          HostInstallationReleaseCatalogObservation   `json:"releaseCatalog"`
	ImmutableRelease        HostInstallationImmutableReleaseObservation `json:"immutableRelease"`
	Activation              HostInstallationActivationObservation       `json:"activation"`
	RequiredServices        []HostInstallationServiceObservation        `json:"requiredServices"`
	MutableStores           []HostInstallationMutableStoreObservation   `json:"mutableStores"`
	InstallationTransaction HostInstallationTransactionObservation      `json:"installationTransaction"`
}

type HostInstallationIssue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  bool   `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type HostInstallationPackageReceiptObservation struct {
	State          string                 `json:"state"`
	Identifier     string                 `json:"identifier"`
	ProductVersion string                 `json:"productVersion,omitempty"`
	Issue          *HostInstallationIssue `json:"issue,omitempty"`
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
	Issue       *HostInstallationIssue `json:"issue,omitempty"`
}

// HostInstallationRequest is C50 desired work submitted by package scripts or
// an explicit installer workflow. The operation is not inferred from a path.
type HostInstallationRequest struct {
	SchemaVersion     string `json:"schemaVersion"`
	DocumentKind      string `json:"documentKind"`
	ID                string `json:"id"`
	InstallationID    string `json:"installationId"`
	Operation         string `json:"operation"`
	ExpectedReleaseID string `json:"expectedReleaseId"`
	RequestedAt       string `json:"requestedAt"`
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
	_, err := time.Parse(time.RFC3339, request.RequestedAt)
	return err == nil
}

func validateHostProductInstallationManifest(manifest HostProductInstallationManifest) error {
	if manifest.SchemaVersion != HostInstallationDocumentSchemaVersion || !validHostInstallationIdentifier(manifest.InstallationID) || manifest.Platform == "" {
		return fmt.Errorf("installation manifest identity is invalid")
	}
	if !validHostInstallationIdentifier(manifest.Release.ID) || manifest.Release.ProductVersion == "" || manifest.Release.RuntimeVersion == "" {
		return fmt.Errorf("installation manifest release is invalid")
	}
	if manifest.Package.Identifier == "" || manifest.Package.ProductVersion == "" {
		return fmt.Errorf("installation manifest package identity is invalid")
	}
	if !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ReleaseCatalogPath) || !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ReleaseRootPath) || !validAbsoluteHostInstallationPath(manifest.ImmutablePayload.ManifestPath) || len(manifest.ImmutablePayload.Entries) == 0 {
		return fmt.Errorf("installation manifest immutable payload is invalid")
	}
	if path.Dir(manifest.ImmutablePayload.ReleaseRootPath) != manifest.ImmutablePayload.ReleaseCatalogPath || path.Dir(manifest.ImmutablePayload.ManifestPath) != manifest.ImmutablePayload.ReleaseRootPath {
		return fmt.Errorf("installation manifest immutable payload paths do not identify one release slot")
	}
	if !validAbsoluteHostInstallationPath(manifest.Activation.CurrentReleaseLinkPath) || manifest.Activation.ExpectedReleaseRootPath != manifest.ImmutablePayload.ReleaseRootPath {
		return fmt.Errorf("installation manifest activation does not name its immutable release root")
	}
	if len(manifest.RequiredServices) != 2 || len(manifest.MutableStores) == 0 {
		return fmt.Errorf("installation manifest required services or mutable stores are incomplete")
	}
	seenServiceRoles := map[string]bool{}
	for _, service := range manifest.RequiredServices {
		if (service.Role != "host-agent" && service.Role != "host-edge-proxy") || seenServiceRoles[service.Role] || service.Name == "" || !validAbsoluteHostInstallationPath(service.DefinitionPath) || !validSHA256(service.DefinitionSHA256) {
			return fmt.Errorf("installation manifest required service is invalid")
		}
		seenServiceRoles[service.Role] = true
	}
	if !seenServiceRoles["host-agent"] || !seenServiceRoles["host-edge-proxy"] {
		return fmt.Errorf("installation manifest must name Host Agent and Host Edge Proxy")
	}
	seenPayloadPaths := map[string]bool{}
	for _, entry := range manifest.ImmutablePayload.Entries {
		if !validRelativeHostInstallationPayloadPath(entry.RelativePath) || !validSHA256(entry.SHA256) || seenPayloadPaths[entry.RelativePath] {
			return fmt.Errorf("installation manifest immutable payload entry is invalid")
		}
		seenPayloadPaths[entry.RelativePath] = true
	}
	seenStoreIDs := map[string]bool{}
	for _, store := range manifest.MutableStores {
		if !validHostInstallationIdentifier(store.ID) || seenStoreIDs[store.ID] || !validAbsoluteHostInstallationPath(store.Path) {
			return fmt.Errorf("installation manifest mutable store is invalid")
		}
		seenStoreIDs[store.ID] = true
	}
	return nil
}

// ValidateHostProductInstallationManifest is the explicit pure gate used by
// adapters before they resolve any path from C48.
func ValidateHostProductInstallationManifest(manifest HostProductInstallationManifest) error {
	return validateHostProductInstallationManifest(manifest)
}

func validAbsoluteHostInstallationPath(path string) bool {
	return len(path) >= 2 && path[0] == '/' && !containsHostInstallationTraversal(path)
}

func validRelativeHostInstallationPayloadPath(path string) bool {
	return path != "" && path[0] != '/' && !containsHostInstallationTraversal(path)
}

func containsHostInstallationTraversal(path string) bool {
	for index := 0; index+1 < len(path); index++ {
		if path[index:index+2] == ".." {
			return true
		}
	}
	return false
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
