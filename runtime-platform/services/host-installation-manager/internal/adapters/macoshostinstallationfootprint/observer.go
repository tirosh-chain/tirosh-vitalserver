// Package macoshostinstallationfootprint owns macOS C49 observations from
// pkgutil, launchctl, and explicit filesystem paths. It never turns a command
// or decode failure into an absent resource.
package macoshostinstallationfootprint

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostInstallationCommandResult struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

type HostInstallationCommandRunner interface {
	RunHostInstallationCommand(context.Context, string, ...string) (HostInstallationCommandResult, error)
}

type macOSHostInstallationSystemCommandRunner struct{}

func (macOSHostInstallationSystemCommandRunner) RunHostInstallationCommand(context context.Context, executable string, arguments ...string) (HostInstallationCommandResult, error) {
	command := exec.CommandContext(context, executable, arguments...)
	output, err := command.Output()
	result := HostInstallationCommandResult{Stdout: string(output)}
	if err == nil {
		return result, nil
	}
	var exitError *exec.ExitError
	if errors.As(err, &exitError) {
		result.ExitCode = exitError.ExitCode()
		result.Stderr = string(exitError.Stderr)
		return result, nil
	}
	return HostInstallationCommandResult{}, fmt.Errorf("start %s: %w", executable, err)
}

type MacOSHostInstallationFootprintObserver struct {
	pkgutilExecutablePath   string
	launchctlExecutablePath string
	commandRunner           HostInstallationCommandRunner
	now                     func() time.Time
}

func NewMacOSHostInstallationFootprintObserver(pkgutilExecutablePath string, launchctlExecutablePath string) (*MacOSHostInstallationFootprintObserver, error) {
	return NewMacOSHostInstallationFootprintObserverWithCommandRunner(pkgutilExecutablePath, launchctlExecutablePath, macOSHostInstallationSystemCommandRunner{})
}

func NewMacOSHostInstallationFootprintObserverWithCommandRunner(pkgutilExecutablePath string, launchctlExecutablePath string, commandRunner HostInstallationCommandRunner) (*MacOSHostInstallationFootprintObserver, error) {
	if pkgutilExecutablePath == "" || launchctlExecutablePath == "" || commandRunner == nil {
		return nil, fmt.Errorf("pkgutil path, launchctl path, and command runner are required")
	}
	return &MacOSHostInstallationFootprintObserver{
		pkgutilExecutablePath:   pkgutilExecutablePath,
		launchctlExecutablePath: launchctlExecutablePath,
		commandRunner:           commandRunner,
		now:                     time.Now,
	}, nil
}

func (observer *MacOSHostInstallationFootprintObserver) ObserveHostInstallationFootprint(context context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath string) (hostinstallationmanagerdomain.HostInstallationFootprint, error) {
	if manifest.Platform != "macos" {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("macOS Host installation observer cannot observe platform %q", manifest.Platform)
	}
	if journalPath == "" {
		return hostinstallationmanagerdomain.HostInstallationFootprint{}, fmt.Errorf("Host installation journal path is required")
	}
	packageReceipt := observer.observePackageReceipt(context, manifest.Package)
	releaseCatalog := observeReleaseCatalog(manifest.ImmutablePayload, manifest.Release.ID)
	immutableRelease := observeImmutableRelease(manifest.ImmutablePayload)
	activation := observeReleaseActivation(manifest.Activation)
	services := make([]hostinstallationmanagerdomain.HostInstallationServiceObservation, 0, len(manifest.RequiredServices))
	for _, service := range manifest.RequiredServices {
		services = append(services, observer.observeRequiredService(context, service))
	}
	stores := make([]hostinstallationmanagerdomain.HostInstallationMutableStoreObservation, 0, len(manifest.MutableStores))
	for _, store := range manifest.MutableStores {
		stores = append(stores, observeMutableStore(store))
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
		InstallationTransaction: observeInstallationTransaction(journalPath),
	}, nil
}

// observeReleaseCatalog makes residual release slots explicit before a package
// can write an expected slot. A non-empty catalog is not silently equivalent
// to a clean Host, even when the expected slot itself is absent.
func observeReleaseCatalog(payload hostinstallationmanagerdomain.HostImmutableProductPayload, expectedReleaseID string) hostinstallationmanagerdomain.HostInstallationReleaseCatalogObservation {
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

func (observer *MacOSHostInstallationFootprintObserver) observePackageReceipt(context context.Context, packageIdentity hostinstallationmanagerdomain.HostProductPackageIdentity) hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation {
	result, err := observer.commandRunner.RunHostInstallationCommand(context, observer.pkgutilExecutablePath, "--pkg-info", packageIdentity.Identifier)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-observation-failed", err.Error(), "pkgutil")}
	}
	switch result.ExitCode {
	case 0:
		productVersion, found := packageInfoValue(result.Stdout, "version")
		if !found || productVersion == "" {
			return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-decode-failed", "pkgutil returned success without a package version", "pkgutil")}
		}
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "installed", Identifier: packageIdentity.Identifier, ProductVersion: productVersion}
	case 1:
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "absent", Identifier: packageIdentity.Identifier}
	default:
		return hostinstallationmanagerdomain.HostInstallationPackageReceiptObservation{State: "failed", Identifier: packageIdentity.Identifier, Issue: issue("macos-package-receipt-observation-failed", fmt.Sprintf("pkgutil exited with status %d", result.ExitCode), "pkgutil")}
	}
}

func packageInfoValue(output string, key string) (string, bool) {
	prefix := key + ":"
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, prefix)), true
		}
	}
	return "", false
}

func observeImmutableRelease(payload hostinstallationmanagerdomain.HostImmutableProductPayload) hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation {
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
		digest, digestError := sha256File(entryPath)
		if digestError != nil {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "unreadable", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-digest-failed", digestError.Error(), "filesystem")}
		}
		if digest != entry.SHA256 {
			return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "diverged", ReleaseRootPath: payload.ReleaseRootPath, Issue: issue("immutable-release-entry-digest-mismatch", entry.RelativePath, "filesystem")}
		}
	}
	return hostinstallationmanagerdomain.HostInstallationImmutableReleaseObservation{State: "matching", ReleaseRootPath: payload.ReleaseRootPath}
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

func observeReleaseActivation(activation hostinstallationmanagerdomain.HostProductReleaseActivation) hostinstallationmanagerdomain.HostInstallationActivationObservation {
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
	target, err := filepath.EvalSymlinks(activation.CurrentReleaseLinkPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("release-activation-target-read-failed", err.Error(), "filesystem")}
	}
	expectedTarget, expectedTargetError := filepath.EvalSymlinks(
		activation.ExpectedReleaseRootPath,
	)
	if expectedTargetError != nil {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "unreadable", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, Issue: issue("expected-release-root-read-failed", expectedTargetError.Error(), "filesystem")}
	}
	if filepath.Clean(target) == filepath.Clean(expectedTarget) {
		return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-expected-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: target}
	}
	return hostinstallationmanagerdomain.HostInstallationActivationObservation{State: "points-to-other-release", CurrentReleaseLinkPath: activation.CurrentReleaseLinkPath, ObservedTargetPath: target}
}

func (observer *MacOSHostInstallationFootprintObserver) observeRequiredService(context context.Context, service hostinstallationmanagerdomain.HostProductRequiredService) hostinstallationmanagerdomain.HostInstallationServiceObservation {
	definitionState, definitionIssue := observeRequiredServiceDefinition(service)
	observation := hostinstallationmanagerdomain.HostInstallationServiceObservation{
		Role:            service.Role,
		Name:            service.Name,
		DefinitionState: definitionState,
		DefinitionIssue: definitionIssue,
	}
	result, err := observer.commandRunner.RunHostInstallationCommand(context, observer.launchctlExecutablePath, "print", "system/"+service.Name)
	if err != nil {
		observation.State = "failed"
		observation.Issue = issue("macos-service-observation-failed", err.Error(), "launchctl")
		return observation
	}
	switch result.ExitCode {
	case 0:
		observation.State = "registered"
	case 3:
		observation.State = "absent"
	default:
		observation.State = "failed"
		observation.Issue = issue("macos-service-observation-failed", fmt.Sprintf("launchctl exited with status %d", result.ExitCode), "launchctl")
	}
	return observation
}

func observeRequiredServiceDefinition(service hostinstallationmanagerdomain.HostProductRequiredService) (string, *hostinstallationmanagerdomain.HostInstallationIssue) {
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

func observeMutableStore(store hostinstallationmanagerdomain.HostProductMutableStoreDeclaration) hostinstallationmanagerdomain.HostInstallationMutableStoreObservation {
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
	return hostinstallationmanagerdomain.HostInstallationMutableStoreObservation{ID: store.ID, State: "present-unknown"}
}

func observeInstallationTransaction(journalPath string) hostinstallationmanagerdomain.HostInstallationTransactionObservation {
	info, statError := os.Lstat(journalPath)
	if errors.Is(statError, os.ErrNotExist) {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "absent", JournalPath: journalPath}
	}
	if statError != nil {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-read-failed", statError.Error(), "filesystem")}
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-is-not-regular-file", journalPath, "filesystem")}
	}
	file, err := os.Open(journalPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-read-failed", err.Error(), "filesystem")}
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, 1024*1024+1))
	decoder.DisallowUnknownFields()
	var journal hostinstallationmanagerdomain.HostInstallationJournal
	if err := decoder.Decode(&journal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-decode-failed", err.Error(), "filesystem")}
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-decode-failed", "journal must contain one JSON document", "filesystem")}
	}
	switch journal.State {
	case hostinstallationmanagerdomain.HostInstallationJournalActivated:
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "completed", JournalPath: journalPath}
	case hostinstallationmanagerdomain.HostInstallationJournalPreflightVerified, hostinstallationmanagerdomain.HostInstallationJournalActivationPending, hostinstallationmanagerdomain.HostInstallationJournalFailed:
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "active", JournalPath: journalPath}
	default:
		return hostinstallationmanagerdomain.HostInstallationTransactionObservation{State: "unreadable", JournalPath: journalPath, Issue: issue("installation-journal-state-invalid", "journal state is not recognized", "filesystem")}
	}
}

func issue(code string, message string, dependency string) *hostinstallationmanagerdomain.HostInstallationIssue {
	return &hostinstallationmanagerdomain.HostInstallationIssue{Code: code, Message: message, Dependency: dependency}
}
