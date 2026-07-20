// Package hostinstallationfootprint owns the filesystem and durable-document
// portion of C49. Native package-manager, service-manager, and activation
// observations are injected explicitly by an OS adapter.
package hostinstallationfootprint

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type PackageReceiptObserver interface {
	ObserveHostPackageReceipt(context.Context, hostinstallationmanagerdomain.HostProductPackageIdentity) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation
}

type ServiceRegistrationObserver interface {
	ObserveHostServiceRegistration(context.Context, hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation
}

type ReleaseActivationObserver interface {
	ObserveHostReleaseActivation(hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation
}

// SymbolicLinkReleaseActivationObserver is the explicit C48 activation
// observer shared by macOS and Linux. It is not used for Windows junctions.
type SymbolicLinkReleaseActivationObserver struct{}

func (SymbolicLinkReleaseActivationObserver) ObserveHostReleaseActivation(activation hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation {
	return ObserveSymbolicLinkReleaseActivation(activation)
}

// Observer composes complete C49 observations from explicit OS protocol
// observers and the shared Host filesystem contract. It does not select an OS
// mechanism based on the executable's current platform.
type Observer struct {
	platform                    string
	packageReceiptObserver      PackageReceiptObserver
	serviceRegistrationObserver ServiceRegistrationObserver
	releaseActivationObserver   ReleaseActivationObserver
	now                         func() time.Time
}

func New(platform string, packageReceiptObserver PackageReceiptObserver, serviceRegistrationObserver ServiceRegistrationObserver, releaseActivationObserver ReleaseActivationObserver) (*Observer, error) {
	if (platform != "macos" && platform != "linux" && platform != "windows") || packageReceiptObserver == nil || serviceRegistrationObserver == nil || releaseActivationObserver == nil {
		return nil, fmt.Errorf("platform, package receipt observer, service registration observer, and release activation observer are required")
	}
	return &Observer{platform: platform, packageReceiptObserver: packageReceiptObserver, serviceRegistrationObserver: serviceRegistrationObserver, releaseActivationObserver: releaseActivationObserver, now: time.Now}, nil
}

func (observer *Observer) ObserveHostInstallationFootprint(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	if manifest.Platform != observer.platform {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("Host installation footprint observer for %s cannot observe platform %q", observer.platform, manifest.Platform)
	}
	if journalPath == "" {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("Host installation journal path is required")
	}
	if receiptPath == "" {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("Host installation receipt path is required")
	}
	packageReceipt := observer.packageReceiptObserver.ObserveHostPackageReceipt(context, manifest.Package)
	releaseCatalog := observeReleaseCatalog(manifest.ImmutablePayload, manifest.Release.ID)
	immutableRelease := ObserveImmutableRelease(manifest.ImmutablePayload)
	activation := observer.releaseActivationObserver.ObserveHostReleaseActivation(manifest.Activation)
	services := make([]hostinstallationmanagerdomain.HostInstallationServiceObservation, 0, len(manifest.RequiredServices))
	for _, service := range manifest.RequiredServices {
		services = append(services, observer.serviceRegistrationObserver.ObserveHostServiceRegistration(context, service))
	}
	stores := make([]hostinstallationmanagerdomain.HostInstallationMutableStoreObservation, 0, len(manifest.MutableStores))
	for _, store := range manifest.MutableStores {
		stores = append(stores, ObserveMutableStore(store))
	}
	return hostinstallationmanagerdomain.HostInstallationFootprint{
		SchemaVersion:           hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
		InstallationID:          manifest.InstallationID,
		ExpectedReleaseID:       manifest.Release.ID,
		Platform:                manifest.Platform,
		ObservedAt:              observer.now().UTC().Format(time.RFC3339),
		PackageReceipt:          packageReceipt,
		ReleaseCatalog:          releaseCatalog,
		ImmutableRelease:        immutableRelease,
		Activation:              activation,
		RequiredServices:        services,
		MutableStores:           stores,
		InstallationTransaction: ObserveInstallationTransaction(manifest, journalPath, receiptPath),
	}, nil
}

// observeReleaseCatalog makes residual release slots explicit before a package
// can write an expected slot. A non-empty catalog is not silently equivalent
// to a clean Host, even when the expected slot itself is absent.
func observeReleaseCatalog(payload hostinstallationmanagerdomain.HostImmutableProductPayload, expectedReleaseID string) hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation {
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(payload.ReleaseCatalogPath); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "unreadable", ReleaseCatalogPath: payload.ReleaseCatalogPath, Issue: issue("release-catalog-path-unreadable", pathError.Error(), "filesystem")}
	}
	info, statError := os.Lstat(payload.ReleaseCatalogPath)
	if errors.Is(statError, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "absent", ReleaseCatalogPath: payload.ReleaseCatalogPath}
	}
	if statError != nil {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "unreadable", ReleaseCatalogPath: payload.ReleaseCatalogPath, Issue: issue("release-catalog-read-failed", statError.Error(), "filesystem")}
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{
			State:              "contains-unexpected-entry",
			ReleaseCatalogPath: payload.ReleaseCatalogPath,
			Issue:              issue("release-catalog-is-not-directory", payload.ReleaseCatalogPath, "filesystem"),
		}
	}
	entries, err := os.ReadDir(payload.ReleaseCatalogPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "unreadable", ReleaseCatalogPath: payload.ReleaseCatalogPath, Issue: issue("release-catalog-read-failed", err.Error(), "filesystem")}
	}
	if len(entries) == 0 {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "empty", ReleaseCatalogPath: payload.ReleaseCatalogPath}
	}
	releaseIDs := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() || !validReleaseCatalogEntryName(entry.Name()) {
			return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{
				State:              "contains-unexpected-entry",
				ReleaseCatalogPath: payload.ReleaseCatalogPath,
				Issue:              issue("release-catalog-entry-invalid", entry.Name(), "filesystem"),
			}
		}
		releaseIDs = append(releaseIDs, entry.Name())
	}
	sort.Strings(releaseIDs)
	if len(releaseIDs) == 1 && releaseIDs[0] == expectedReleaseID {
		return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "only-expected-release", ReleaseCatalogPath: payload.ReleaseCatalogPath, ReleaseIDs: releaseIDs}
	}
	return hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation{State: "contains-other-releases", ReleaseCatalogPath: payload.ReleaseCatalogPath, ReleaseIDs: releaseIDs}
}

func validReleaseCatalogEntryName(value string) bool {
	if value == "" || len(value) > 128 || !((value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= 'a' && value[0] <= 'z') || (value[0] >= '0' && value[0] <= '9')) {
		return false
	}
	for _, character := range value {
		if !((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == ':' || character == '-') {
			return false
		}
	}
	return true
}

func ObserveImmutableRelease(payload hostinstallationmanagerdomain.HostImmutableProductPayload) hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation {
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(payload.ReleaseRootPath); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-path-unreadable", pathError.Error(), "filesystem")}
	}
	info, err := os.Lstat(payload.ReleaseRootPath)
	if errors.Is(err, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "absent", ReleaseRootPath: payload.ReleaseRootPath}
	}
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-read-failed", err.Error(), "filesystem")}
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-root-is-not-directory", "declared immutable release root is not a directory", "filesystem")}
	}
	for _, entry := range payload.Entries {
		entryPath := filepath.Join(payload.ReleaseRootPath, entry.RelativePath)
		if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(entryPath); pathError != nil {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-path-unreadable", pathError.Error(), "filesystem")}
		}
		entryInfo, entryError := os.Lstat(entryPath)
		if errors.Is(entryError, os.ErrNotExist) {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-missing", entry.RelativePath, "filesystem")}
		}
		if entryError != nil {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-read-failed", entryError.Error(), "filesystem")}
		}
		if !entryInfo.Mode().IsRegular() {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-not-regular-file", entry.RelativePath, "filesystem")}
		}
		if executable := entryInfo.Mode().Perm()&0111 != 0; executable != entry.Executable {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-executable-mode-mismatch", entry.RelativePath, "filesystem")}
		}
		digest, digestError := sha256File(entryPath)
		if digestError != nil {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-digest-failed", digestError.Error(), "filesystem")}
		}
		if digest != entry.SHA256 {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-digest-mismatch", entry.RelativePath, "filesystem")}
		}
	}
	if inventoryIssue, inventoryError := verifyImmutableReleaseInventory(payload); inventoryError != nil {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-inventory-read-failed", inventoryError.Error(), "filesystem")}
	} else if inventoryIssue != nil {
		return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: inventoryIssue}
	}
	return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "matching", ReleaseRootPath: payload.ReleaseRootPath}
}

// verifyImmutableReleaseInventory proves that no ordinary file or symbolic
// link was added below C48's immutable release root. C48 cannot hash itself,
// so its manifest path is the one explicitly named non-entry file.
func verifyImmutableReleaseInventory(payload hostinstallationmanagerdomain.HostImmutableProductPayload) (*hostinstallationmanagerdomain.HostInstallationIssue, error) {
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(payload.ReleaseRootPath); err != nil {
		return nil, fmt.Errorf("inspect immutable release root path: %w", err)
	}
	manifestRelativePath, err := filepath.Rel(payload.ReleaseRootPath, payload.ManifestPath)
	if err != nil || manifestRelativePath == "." || strings.HasPrefix(manifestRelativePath, ".."+string(filepath.Separator)) || filepath.IsAbs(manifestRelativePath) {
		return nil, fmt.Errorf("C48 manifest path does not stay below immutable release root")
	}
	expectedFiles := map[string]bool{filepath.ToSlash(manifestRelativePath): true}
	for _, entry := range payload.Entries {
		expectedFiles[entry.RelativePath] = true
	}
	observedFiles := map[string]bool{}
	var inventoryIssue *hostinstallationmanagerdomain.HostInstallationIssue
	walkError := filepath.WalkDir(payload.ReleaseRootPath, func(candidate string, entry os.DirEntry, walkError error) error {
		if walkError != nil {
			return walkError
		}
		if candidate == payload.ReleaseRootPath {
			return nil
		}
		relativePath, relativeError := filepath.Rel(payload.ReleaseRootPath, candidate)
		if relativeError != nil {
			return relativeError
		}
		relativePath = filepath.ToSlash(relativePath)
		if entry.Type()&os.ModeSymlink != 0 {
			inventoryIssue = issue("immutable-release-inventory-symbolic-link", relativePath, "filesystem")
			return filepath.SkipDir
		}
		if entry.IsDir() {
			return nil
		}
		if !entry.Type().IsRegular() {
			inventoryIssue = issue("immutable-release-inventory-entry-not-regular-file", relativePath, "filesystem")
			return filepath.SkipDir
		}
		if !expectedFiles[relativePath] {
			inventoryIssue = issue("immutable-release-inventory-extra-file", relativePath, "filesystem")
			return filepath.SkipDir
		}
		observedFiles[relativePath] = true
		return nil
	})
	if walkError != nil {
		return nil, walkError
	}
	if inventoryIssue != nil {
		return inventoryIssue, nil
	}
	for expectedPath := range expectedFiles {
		if !observedFiles[expectedPath] {
			return issue("immutable-release-inventory-entry-missing", expectedPath, "filesystem"), nil
		}
	}
	return nil, nil
}

func sha256File(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

// ObserveSymbolicLinkReleaseActivation verifies the POSIX activation mechanism
// declared by C48. Windows provides its directory-junction observer instead.
func ObserveSymbolicLinkReleaseActivation(activation hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation {
	if activation.ReferenceKind != "symbolic-link" {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-reference-kind-incompatible", activation.ReferenceKind, "filesystem")}
	}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(filepath.Dir(activation.CurrentReleaseLinkPath)); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-parent-path-unreadable", pathError.Error(), "filesystem")}
	}
	info, err := os.Lstat(activation.CurrentReleaseLinkPath)
	if errors.Is(err, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "absent", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath}
	}
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-read-failed", err.Error(), "filesystem")}
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-is-not-symbolic-link", "current release activation path is not a symbolic link", "filesystem")}
	}
	linkTarget, linkTargetError := os.Readlink(activation.CurrentReleaseLinkPath)
	if linkTargetError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-target-read-failed", linkTargetError.Error(), "filesystem")}
	}
	observedTargetPath := linkTarget
	if !filepath.IsAbs(observedTargetPath) {
		observedTargetPath = filepath.Join(filepath.Dir(activation.CurrentReleaseLinkPath), observedTargetPath)
	}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(observedTargetPath); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-target-path-unreadable", pathError.Error(), "filesystem")}
	}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(activation.ExpectedReleaseRootPath); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("expected-release-root-path-unreadable", pathError.Error(), "filesystem")}
	}
	target, err := filepath.EvalSymlinks(activation.CurrentReleaseLinkPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-target-read-failed", err.Error(), "filesystem")}
	}
	expectedTarget := filepath.Clean(activation.ExpectedReleaseRootPath)
	if expectedInfo, expectedStatError := os.Lstat(activation.ExpectedReleaseRootPath); expectedStatError == nil {
		if expectedInfo.Mode()&os.ModeSymlink != 0 || !expectedInfo.IsDir() {
			return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("expected-release-root-is-not-directory", activation.ExpectedReleaseRootPath, "filesystem")}
		}
		resolvedExpectedTarget, expectedTargetError := filepath.EvalSymlinks(activation.ExpectedReleaseRootPath)
		if expectedTargetError != nil {
			return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("expected-release-root-read-failed", expectedTargetError.Error(), "filesystem")}
		}
		expectedTarget = filepath.Clean(resolvedExpectedTarget)
	} else if !errors.Is(expectedStatError, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("expected-release-root-read-failed", expectedStatError.Error(), "filesystem")}
	}
	if filepath.Clean(target) == filepath.Clean(expectedTarget) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: target}
	}
	return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: target}
}

func ObserveRequiredServiceDefinition(service hostinstallationmanagerdomain.HostProductRequiredService) (string, *hostinstallationmanagerdomain.HostInstallationIssue) {
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(service.DefinitionPath); pathError != nil {
		return "unreadable", issue("service-definition-path-unreadable", pathError.Error(), "filesystem")
	}
	info, err := os.Lstat(service.DefinitionPath)
	if errors.Is(err, os.ErrNotExist) {
		return "absent", nil
	}
	if err != nil {
		return "unreadable", issue("service-definition-read-failed", err.Error(), "filesystem")
	}
	if !info.Mode().IsRegular() {
		return "diverged", issue("service-definition-not-regular-file", service.DefinitionPath, "filesystem")
	}
	digest, digestError := sha256File(service.DefinitionPath)
	if digestError != nil {
		return "unreadable", issue("service-definition-digest-failed", digestError.Error(), "filesystem")
	}
	if digest != service.DefinitionSHA256 {
		return "diverged", issue("service-definition-digest-mismatch", service.DefinitionPath, "filesystem")
	}
	return "matching", nil
}

func ObserveMutableStore(store hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) hostinstallationmanagerdomain.HostInstallationMutableStoreObservation {
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(store.Path); pathError != nil {
		return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "unreadable", Issue: issue("mutable-store-path-unreadable", pathError.Error(), "filesystem")}
	}
	info, err := os.Lstat(store.Path)
	if errors.Is(err, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "absent"}
	}
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "unreadable", Issue: issue("mutable-store-read-failed", err.Error(), "filesystem")}
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "unreadable", Issue: issue("mutable-store-is-symbolic-link", store.Path, "filesystem")}
	}
	if store.Kind != "directory" || !info.IsDir() {
		return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "incompatible", Issue: issue("mutable-store-kind-incompatible", store.Path, "filesystem")}
	}
	return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "compatible"}
}

func ObserveInstallationTransaction(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string, receiptPath string) hostinstallationmanagerdomain.HostInstallationTransactionObservation {
	base := hostinstallationmanagerdomain.HostInstallationTransactionObservation{JournalPath: journalPath, ReceiptPath: receiptPath}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(journalPath); pathError != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-path-unreadable", pathError.Error(), "filesystem")
		return base
	}
	info, statError := os.Lstat(journalPath)
	if errors.Is(statError, os.ErrNotExist) {
		return observeReceiptOnlyInstallationTransaction(manifest, base)
	}
	if statError != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-read-failed", statError.Error(), "filesystem")
		return base
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-is-not-regular-file", journalPath, "filesystem")
		return base
	}
	file, err := os.Open(journalPath)
	if err != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-read-failed", err.Error(), "filesystem")
		return base
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, 1024*1024+1))
	decoder.DisallowUnknownFields()
	var journal hostinstallationmanagerdomain.HostInstallationJournal
	if err := decoder.Decode(&journal); err != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-decode-failed", err.Error(), "filesystem")
		return base
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-decode-failed", "journal must contain one JSON document", "filesystem")
		return base
	}
	if err := hostinstallationmanagerdomain.ValidateHostInstallationJournal(journal); err != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-invalid", err.Error(), "filesystem")
		return base
	}
	if journal.InstallationID != manifest.InstallationID || journal.ReleaseID != manifest.Release.ID {
		base.State = "unreadable"
		base.Issue = issue("installation-journal-identity-mismatch", "journal does not identify the declared installation release", "filesystem")
		return base
	}
	switch journal.State {
	case hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified,
		hostinstallationmanagerdomain.HostInstallationJournalServicesQuiescing,
		hostinstallationmanagerdomain.HostInstallationJournalActivationPending,
		hostinstallationmanagerdomain.HostInstallationJournalActivated,
		hostinstallationmanagerdomain.HostInstallationJournalCompleted,
		hostinstallationmanagerdomain.HostInstallationJournalRecovered,
		hostinstallationmanagerdomain.HostInstallationJournalFailed:
		base.State = journal.State
		return base
	default:
		base.State = "unreadable"
		base.Issue = issue("installation-journal-state-invalid", "journal state is not recognized", "filesystem")
		return base
	}
}

// observeReceiptOnlyInstallationTransaction recognizes the one legacy C50
// state created by packages that wrote a blocked receipt before payload
// delivery. It must prove that the receipt is valid and is the only file below
// the manager-owned mutable root; all other receipt residue remains explicit
// stale state.
func observeReceiptOnlyInstallationTransaction(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, base hostinstallationmanagerdomain.HostInstallationTransactionObservation) hostinstallationmanagerdomain.HostInstallationTransactionObservation {
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(base.ReceiptPath); pathError != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-receipt-path-unreadable", pathError.Error(), "filesystem")
		return base
	}
	info, statError := os.Lstat(base.ReceiptPath)
	if errors.Is(statError, os.ErrNotExist) {
		base.State = "absent"
		return base
	}
	if statError != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-receipt-read-failed", statError.Error(), "filesystem")
		return base
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		base.State = "unreadable"
		base.Issue = issue("installation-receipt-is-not-regular-file", base.ReceiptPath, "filesystem")
		return base
	}
	receipt, err := (hostinstallationreceiptfile.HostInstallationReceiptFileStore{}).ReadHostInstallationReceipt(context.Background(), base.ReceiptPath)
	if err != nil {
		base.State = "unreadable"
		base.Issue = issue("installation-receipt-decode-failed", err.Error(), "filesystem")
		return base
	}
	if receipt.InstallationID != manifest.InstallationID {
		base.State = "unreadable"
		base.Issue = issue("installation-receipt-installation-identity-mismatch", "receipt does not identify the declared installation", "filesystem")
		return base
	}
	if receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked {
		onlyReceipt, inventoryError := hasOnlyBlockedPreflightReceiptResidue(manifest, base.ReceiptPath)
		if inventoryError != nil {
			base.State = "unreadable"
			base.Issue = issue("installation-receipt-residue-read-failed", inventoryError.Error(), "filesystem")
			return base
		}
		if onlyReceipt {
			base.State = "legacy-blocked-preflight"
			return base
		}
	}
	base.State = "receipt-residue"
	return base
}

// hasOnlyBlockedPreflightReceiptResidue keeps the historical migration
// narrower than a generic data-directory cleanup. It accepts one blocked C50
// receipt and its ancestor directories below the highest matching
// manager-owned mutable store; every other file, directory, special entry, or
// symbolic link keeps the footprint as stale residue.
func hasOnlyBlockedPreflightReceiptResidue(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, receiptPath string) (bool, error) {
	var root string
	for _, store := range manifest.MutableStores {
		if store.Owner != "host-installation-manager" || store.Retention != "purge-only-by-explicit-command" || !pathContains(store.Path, receiptPath) {
			continue
		}
		if root == "" || len(store.Path) < len(root) {
			root = store.Path
		}
	}
	if root == "" {
		return false, nil
	}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(root); pathError != nil {
		return false, pathError
	}
	receiptFound := false
	walkError := filepath.WalkDir(root, func(candidate string, entry os.DirEntry, walkError error) error {
		if walkError != nil {
			return walkError
		}
		if candidate == root {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return errLegacyBlockedPreflightReceiptResidue
		}
		if entry.IsDir() {
			if pathContains(candidate, receiptPath) {
				return nil
			}
			return errLegacyBlockedPreflightReceiptResidue
		}
		if !entry.Type().IsRegular() || filepath.Clean(candidate) != filepath.Clean(receiptPath) {
			return errLegacyBlockedPreflightReceiptResidue
		}
		receiptFound = true
		return nil
	})
	if errors.Is(walkError, errLegacyBlockedPreflightReceiptResidue) {
		return false, nil
	}
	if walkError != nil {
		return false, walkError
	}
	return receiptFound, nil
}

var errLegacyBlockedPreflightReceiptResidue = errors.New("legacy blocked preflight receipt residue contains undeclared state")

func pathContains(directory string, candidate string) bool {
	cleanDirectory := filepath.Clean(directory)
	cleanCandidate := filepath.Clean(candidate)
	return cleanDirectory != string(filepath.Separator) && (cleanDirectory == cleanCandidate || strings.HasPrefix(cleanCandidate, cleanDirectory+string(filepath.Separator)))
}

func issue(code string, message string, dependency string) *hostinstallationmanagerdomain.HostInstallationIssue {
	return &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: message, Dependency: dependency}
}
