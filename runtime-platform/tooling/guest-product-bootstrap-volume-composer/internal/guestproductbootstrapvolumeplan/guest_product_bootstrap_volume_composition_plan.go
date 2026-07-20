// Package guestproductbootstrapvolumeplan defines the explicit Guest-owned
// bootstrap request that a release-build composer may turn into one NoCloud
// volume. It is pure: it neither opens a Host file nor mutates a Guest root.
package guestproductbootstrapvolumeplan

import (
	"fmt"
	"path"
	"regexp"
	"sort"
	"strings"
)

const (
	ExpectedSchemaVersion                          = "v1"
	RequiredNoCloudVolumeLabel                     = "CIDATA"
	RequiredBootstrapStorageImageFormat            = "raw"
	RequiredBootstrapVolumeFileSystem              = "iso9660"
	DeclaredTarGzipArchiveFormat                   = "tar-gzip"
	PreserveArchiveEntryModePolicy                 = "preserve-archive-mode"
	AllowRelativeLinksToDeclaredRegularFilesPolicy = "allow-relative-links-to-declared-regular-files"
	GuestProductBootstrapPlanMaximumBytes          = 1 << 20
)

var (
	identifierPattern  = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
	serviceUnitPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,123}\.service$`)
	sha256Pattern      = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

// GuestProductBootstrapVolumeCompositionPlan declares the whole desired
// first-boot installation. The producer selects all sources and final Guest
// destinations explicitly; the composer cannot infer either from a release
// directory, the Host, or the base image.
type GuestProductBootstrapVolumeCompositionPlan struct {
	SchemaVersion                       string                                       `json:"schemaVersion"`
	BootstrapID                         string                                       `json:"bootstrapId"`
	VolumeLabel                         string                                       `json:"volumeLabel"`
	StorageImageFormat                  string                                       `json:"storageImageFormat"`
	GuestVolumeFileSystem               string                                       `json:"guestVolumeFileSystem"`
	InstanceID                          string                                       `json:"instanceId"`
	LocalHostName                       string                                       `json:"localHostName"`
	ServiceUnitName                     string                                       `json:"serviceUnitName"`
	ReleaseManagerServiceUnitName       string                                       `json:"releaseManagerServiceUnitName"`
	GuestProductRelease                 DeclaredGuestProductRelease                  `json:"guestProductRelease"`
	GuestRuntimeStateDirectory          DeclaredGuestDirectory                       `json:"guestRuntimeStateDirectory"`
	GuestTelemetryStateDirectory        *DeclaredGuestDirectory                      `json:"guestTelemetryStateDirectory,omitempty"`
	GuestBundledUpstreamImageSetManager *DeclaredGuestBundledUpstreamImageSetManager `json:"guestBundledUpstreamImageSetManager,omitempty"`
	GuestTimeSynchronization            *DeclaredGuestTimeSynchronization            `json:"guestTimeSynchronization,omitempty"`
	Sources                             []DeclaredBootstrapSource                    `json:"sources"`
	FileInstallations                   []DeclaredGuestFileInstallation              `json:"fileInstallations"`
	ArchiveInstallations                []DeclaredGuestArchiveInstallation           `json:"archiveInstallations"`
	SymbolicLinks                       []DeclaredGuestSymbolicLink                  `json:"symbolicLinks"`
}

// DeclaredGuestProductRelease is the first-boot activation declaration for
// one immutable Guest Product release. The initial current-release link is an
// explicit release-manager action, not a convenient alias inferred from a
// directory name.
type DeclaredGuestProductRelease struct {
	ReleaseID                 string `json:"releaseId"`
	ReleaseDirectory          string `json:"releaseDirectory"`
	CurrentReleaseLinkPath    string `json:"currentReleaseLinkPath"`
	ReleaseStateDirectory     string `json:"releaseStateDirectory"`
	ReleaseStateDirectoryMode string `json:"releaseStateDirectoryMode"`
}

// DeclaredGuestDirectory is one mutable Guest-owned directory that must exist
// before a stateful service starts. It is desired installation input, not an
// observation that the directory exists or is writable.
type DeclaredGuestDirectory struct {
	DirectoryPath string `json:"directoryPath"`
	DirectoryMode string `json:"directoryMode"`
}

// DeclaredGuestBundledUpstreamImageSetManager is the C40 execution contract
// for one C64 service. C40 creates the owned state root and explicitly writes
// its initial selection exactly once; it neither assumes an image set nor
// invokes Docker. C64 later owns image-set transitions through C55/C66.
type DeclaredGuestBundledUpstreamImageSetManager struct {
	ManagerID                  string                                `json:"managerId"`
	ExecutablePath             string                                `json:"executablePath"`
	ConfigurationPath          string                                `json:"configurationPath"`
	StateDirectory             DeclaredGuestDirectory                `json:"stateDirectory"`
	ContainerEngineBootstrap   DeclaredGuestContainerEngineBootstrap `json:"containerEngineBootstrap"`
	ServiceUnitName            string                                `json:"serviceUnitName"`
	InitialActiveImageSetState string                                `json:"initialActiveImageSetState"`
}

// DeclaredGuestContainerEngineBootstrap is the one package/service action
// required before C64 runs. It has no observed engine-health state.
type DeclaredGuestContainerEngineBootstrap struct {
	PackageManager string `json:"packageManager"`
	PackageName    string `json:"packageName"`
	ServiceName    string `json:"serviceName"`
}

// DeclaredGuestTimeSynchronization is the narrow Guest bootstrap effect for
// the selected clock service. It is not a clock-quality observation: the
// Guest Runtime reads Chrony separately after this first-boot action has
// completed.
type DeclaredGuestTimeSynchronization struct {
	PackageManager string `json:"packageManager"`
	PackageName    string `json:"packageName"`
	ServiceName    string `json:"serviceName"`
}

// DeclaredBootstrapSource is one byte-identified Guest bootstrap payload
// supplied below the caller-selected source root. Every payload must have one
// declared Guest installation consumer; staging a byte with no Guest action is
// not a C40 delivery plan. The source path is deliberately relative so the
// plan never leaks an incidental build-machine location into the Guest.
type DeclaredBootstrapSource struct {
	ID                 string `json:"id"`
	SourceRelativePath string `json:"sourceRelativePath"`
	SizeBytes          int64  `json:"sizeBytes"`
	SHA256             string `json:"sha256"`
}

// DeclaredGuestFileInstallation copies one named payload to one Guest path.
type DeclaredGuestFileInstallation struct {
	SourceID        string `json:"sourceId"`
	DestinationPath string `json:"destinationPath"`
	FileMode        string `json:"fileMode"`
}

// DeclaredGuestArchiveInstallation extracts an integrity-pinned tar-gzip
// payload below exactly one Guest path. EntryModePolicy preserves declared
// archive file modes; SymbolicLinkPolicy separately says which archive link
// relationship the C40 adapter may accept before the Guest extracts it.
type DeclaredGuestArchiveInstallation struct {
	SourceID             string   `json:"sourceId"`
	ArchiveFormat        string   `json:"archiveFormat"`
	EntryModePolicy      string   `json:"entryModePolicy"`
	SymbolicLinkPolicy   string   `json:"symbolicLinkPolicy"`
	DestinationDirectory string   `json:"destinationDirectory"`
	RequiredArchivePaths []string `json:"requiredArchivePaths"`
}

// DeclaredGuestSymbolicLink enables one declared service-unit link after all
// payload bytes have been verified and installed by cloud-init.
type DeclaredGuestSymbolicLink struct {
	LinkPath   string `json:"linkPath"`
	TargetPath string `json:"targetPath"`
}

// ValidateGuestProductBootstrapVolumeCompositionPlan preserves the semantic
// distinctions that JSON Schema cannot express: unique source identities,
// complete operation references, and non-overlapping Guest destinations.
func ValidateGuestProductBootstrapVolumeCompositionPlan(plan GuestProductBootstrapVolumeCompositionPlan) error {
	if plan.SchemaVersion != ExpectedSchemaVersion {
		return fmt.Errorf("C40 schemaVersion must be %q", ExpectedSchemaVersion)
	}
	if !identifierPattern.MatchString(plan.BootstrapID) || !identifierPattern.MatchString(plan.InstanceID) || !identifierPattern.MatchString(plan.LocalHostName) {
		return fmt.Errorf("C40 bootstrap identity is invalid")
	}
	if !serviceUnitPattern.MatchString(plan.ServiceUnitName) || plan.ReleaseManagerServiceUnitName != "vitalserver-guest-product-release-manager.service" || plan.ReleaseManagerServiceUnitName == plan.ServiceUnitName {
		return fmt.Errorf("C40 product and release-manager service unit names are invalid")
	}
	if !identifierPattern.MatchString(plan.GuestProductRelease.ReleaseID) ||
		!isSafeAbsoluteGuestPath(plan.GuestProductRelease.ReleaseDirectory) ||
		!isSafeAbsoluteGuestPath(plan.GuestProductRelease.CurrentReleaseLinkPath) ||
		!isSafeAbsoluteGuestPath(plan.GuestProductRelease.ReleaseStateDirectory) ||
		plan.GuestProductRelease.ReleaseStateDirectoryMode != "0700" ||
		path.Base(plan.GuestProductRelease.ReleaseDirectory) != plan.GuestProductRelease.ReleaseID ||
		path.Dir(plan.GuestProductRelease.CurrentReleaseLinkPath) != path.Dir(path.Dir(plan.GuestProductRelease.ReleaseDirectory)) ||
		plan.GuestProductRelease.ReleaseDirectory == plan.GuestProductRelease.CurrentReleaseLinkPath ||
		plan.GuestProductRelease.ReleaseDirectory == plan.GuestProductRelease.ReleaseStateDirectory ||
		plan.GuestProductRelease.CurrentReleaseLinkPath == plan.GuestProductRelease.ReleaseStateDirectory {
		return fmt.Errorf("C40 Guest Product release declaration is invalid")
	}
	if plan.VolumeLabel != RequiredNoCloudVolumeLabel {
		return fmt.Errorf("C40 volumeLabel must be %q", RequiredNoCloudVolumeLabel)
	}
	if plan.StorageImageFormat != RequiredBootstrapStorageImageFormat {
		return fmt.Errorf("C40 storageImageFormat must be %q", RequiredBootstrapStorageImageFormat)
	}
	if plan.GuestVolumeFileSystem != RequiredBootstrapVolumeFileSystem {
		return fmt.Errorf("C40 guestVolumeFileSystem must be %q", RequiredBootstrapVolumeFileSystem)
	}
	if len(plan.Sources) < 2 || len(plan.FileInstallations) < 1 || len(plan.ArchiveInstallations) != 1 {
		return fmt.Errorf("C40 requires at least two declared payloads, one file installation, and one archive installation")
	}
	if !isSafeAbsoluteGuestPath(plan.GuestRuntimeStateDirectory.DirectoryPath) || plan.GuestRuntimeStateDirectory.DirectoryMode != "0700" {
		return fmt.Errorf("C40 Guest Runtime state directory is invalid")
	}
	if plan.GuestTelemetryStateDirectory != nil && (!isSafeAbsoluteGuestPath(plan.GuestTelemetryStateDirectory.DirectoryPath) || plan.GuestTelemetryStateDirectory.DirectoryMode != "0700" || plan.GuestTelemetryStateDirectory.DirectoryPath == plan.GuestRuntimeStateDirectory.DirectoryPath) {
		return fmt.Errorf("C40 Guest telemetry state directory is invalid or overlaps the Guest Runtime state directory")
	}
	if plan.GuestTimeSynchronization != nil && (plan.GuestTimeSynchronization.PackageManager != "apt" || plan.GuestTimeSynchronization.PackageName != "chrony" || plan.GuestTimeSynchronization.ServiceName != "chrony.service") {
		return fmt.Errorf("C40 Guest time synchronization declaration is invalid")
	}

	sourcesByID := make(map[string]DeclaredBootstrapSource, len(plan.Sources))
	sourcePaths := make(map[string]struct{}, len(plan.Sources))
	for _, source := range plan.Sources {
		if !identifierPattern.MatchString(source.ID) || !isSafeSourceRelativePath(source.SourceRelativePath) || source.SizeBytes < 1 || !sha256Pattern.MatchString(source.SHA256) {
			return fmt.Errorf("C40 source declaration is invalid")
		}
		if _, exists := sourcesByID[source.ID]; exists {
			return fmt.Errorf("C40 source id %q is declared more than once", source.ID)
		}
		if _, exists := sourcePaths[source.SourceRelativePath]; exists {
			return fmt.Errorf("C40 sourceRelativePath %q is declared more than once", source.SourceRelativePath)
		}
		sourcesByID[source.ID] = source
		sourcePaths[source.SourceRelativePath] = struct{}{}
	}

	destinations := make(map[string]string)
	payloadConsumers := make(map[string]string, len(plan.Sources))
	installedGuestFiles := make(map[string]struct{}, len(plan.FileInstallations))
	destinations[plan.GuestRuntimeStateDirectory.DirectoryPath] = "Guest Runtime state directory"
	destinations[plan.GuestProductRelease.ReleaseStateDirectory] = "Guest Product release state directory"
	if plan.GuestTelemetryStateDirectory != nil {
		destinations[plan.GuestTelemetryStateDirectory.DirectoryPath] = "Guest telemetry state directory"
	}
	if manager := plan.GuestBundledUpstreamImageSetManager; manager != nil {
		if !identifierPattern.MatchString(manager.ManagerID) || !isSafeAbsoluteGuestPath(manager.ExecutablePath) || !isSafeAbsoluteGuestPath(manager.ConfigurationPath) || !isSafeAbsoluteGuestPath(manager.StateDirectory.DirectoryPath) || manager.StateDirectory.DirectoryMode != "0700" || manager.ContainerEngineBootstrap.PackageManager != "apt" || manager.ContainerEngineBootstrap.PackageName != "docker.io" || manager.ContainerEngineBootstrap.ServiceName != "docker.service" || !serviceUnitPattern.MatchString(manager.ServiceUnitName) || manager.ServiceUnitName != "vitalserver-guest-bundled-upstream-image-set-manager.service" || manager.InitialActiveImageSetState != "unprovisioned" || manager.ExecutablePath == manager.ConfigurationPath || manager.StateDirectory.DirectoryPath == plan.GuestRuntimeStateDirectory.DirectoryPath || manager.StateDirectory.DirectoryPath == plan.GuestProductRelease.ReleaseStateDirectory {
			return fmt.Errorf("C40 Guest Bundled Upstream Image-set Manager declaration is invalid")
		}
		destinations[manager.StateDirectory.DirectoryPath] = "Guest Bundled Upstream Image-set Manager state directory"
	}
	for _, installation := range plan.FileInstallations {
		if _, exists := sourcesByID[installation.SourceID]; !exists || !isSafeAbsoluteGuestPath(installation.DestinationPath) || (installation.FileMode != "0644" && installation.FileMode != "0755") {
			return fmt.Errorf("C40 file installation is invalid")
		}
		if priorConsumer, exists := payloadConsumers[installation.SourceID]; exists {
			return fmt.Errorf("C40 payload %q is declared for both %s and file installation", installation.SourceID, priorConsumer)
		}
		if prior, exists := destinations[installation.DestinationPath]; exists {
			return fmt.Errorf("C40 destination %q is declared by both %s and file installation", installation.DestinationPath, prior)
		}
		if !isPathBelow(plan.GuestProductRelease.ReleaseDirectory, installation.DestinationPath) && installation.DestinationPath != "/etc/systemd/system/"+plan.ServiceUnitName && installation.DestinationPath != "/etc/systemd/system/"+plan.ReleaseManagerServiceUnitName && (plan.GuestBundledUpstreamImageSetManager == nil || installation.DestinationPath != "/etc/systemd/system/"+plan.GuestBundledUpstreamImageSetManager.ServiceUnitName) && installation.DestinationPath != "/etc/chrony/chrony.conf" {
			return fmt.Errorf("C40 file installation must stay below the Guest Product release directory unless it is a selected Guest OS service resource")
		}
		payloadConsumers[installation.SourceID] = "file installation"
		destinations[installation.DestinationPath] = "file installation"
		installedGuestFiles[installation.DestinationPath] = struct{}{}
	}
	for _, installation := range plan.ArchiveInstallations {
		if _, exists := sourcesByID[installation.SourceID]; !exists || installation.ArchiveFormat != DeclaredTarGzipArchiveFormat || installation.EntryModePolicy != PreserveArchiveEntryModePolicy || installation.SymbolicLinkPolicy != AllowRelativeLinksToDeclaredRegularFilesPolicy || !isSafeAbsoluteGuestPath(installation.DestinationDirectory) || len(installation.RequiredArchivePaths) < 2 {
			return fmt.Errorf("C40 archive installation is invalid")
		}
		if priorConsumer, exists := payloadConsumers[installation.SourceID]; exists {
			return fmt.Errorf("C40 payload %q is declared for both %s and archive installation", installation.SourceID, priorConsumer)
		}
		if !isPathAtOrBelow(plan.GuestProductRelease.ReleaseDirectory, installation.DestinationDirectory) {
			return fmt.Errorf("C40 archive installation must stay below the Guest Product release directory")
		}
		archivePaths := make(map[string]struct{}, len(installation.RequiredArchivePaths))
		for _, requiredPath := range installation.RequiredArchivePaths {
			if !isSafeRelativePayloadPath(requiredPath) {
				return fmt.Errorf("C40 archive required path %q is invalid", requiredPath)
			}
			if _, exists := archivePaths[requiredPath]; exists {
				return fmt.Errorf("C40 archive required path %q is declared more than once", requiredPath)
			}
			archivePaths[requiredPath] = struct{}{}
		}
		payloadConsumers[installation.SourceID] = "archive installation"
	}
	for _, sourceID := range sortedSourceIDs(sourcesByID) {
		if _, exists := payloadConsumers[sourceID]; !exists {
			return fmt.Errorf("C40 payload %q does not declare an installation", sourceID)
		}
	}
	declaredServiceLinks := make(map[string]struct{}, len(plan.SymbolicLinks))
	for _, symbolicLink := range plan.SymbolicLinks {
		if !isSafeAbsoluteGuestPath(symbolicLink.LinkPath) || !isSafeAbsoluteGuestPath(symbolicLink.TargetPath) {
			return fmt.Errorf("C40 symbolic link is invalid")
		}
		if _, exists := installedGuestFiles[symbolicLink.TargetPath]; !exists {
			return fmt.Errorf("C40 service enable link %q does not target an installed Guest file", symbolicLink.LinkPath)
		}
		unitName := path.Base(symbolicLink.LinkPath)
		if unitName != path.Base(symbolicLink.TargetPath) || (unitName != plan.ServiceUnitName && unitName != plan.ReleaseManagerServiceUnitName && (plan.GuestBundledUpstreamImageSetManager == nil || unitName != plan.GuestBundledUpstreamImageSetManager.ServiceUnitName)) {
			return fmt.Errorf("C40 service enable link must name a declared product, release-manager, or bundled-upstream manager service unit")
		}
		if _, exists := declaredServiceLinks[unitName]; exists {
			return fmt.Errorf("C40 service enable link declares %q more than once", unitName)
		}
		declaredServiceLinks[unitName] = struct{}{}
		if prior, exists := destinations[symbolicLink.LinkPath]; exists {
			return fmt.Errorf("C40 link path %q is declared by both %s and symbolic link", symbolicLink.LinkPath, prior)
		}
		destinations[symbolicLink.LinkPath] = "symbolic link"
	}
	expectedServiceLinks := 2
	if plan.GuestBundledUpstreamImageSetManager != nil {
		expectedServiceLinks++
	}
	if len(declaredServiceLinks) != expectedServiceLinks {
		return fmt.Errorf("C40 must enable every declared service unit")
	}
	if prior, exists := destinations[plan.GuestProductRelease.CurrentReleaseLinkPath]; exists {
		return fmt.Errorf("C40 current Guest Product release link path %q is declared by both %s and release activation", plan.GuestProductRelease.CurrentReleaseLinkPath, prior)
	}
	destinations[plan.GuestProductRelease.CurrentReleaseLinkPath] = "Guest Product release activation"
	return nil
}

func sortedSourceIDs(sourcesByID map[string]DeclaredBootstrapSource) []string {
	identifiers := make([]string, 0, len(sourcesByID))
	for sourceID := range sourcesByID {
		identifiers = append(identifiers, sourceID)
	}
	sort.Strings(identifiers)
	return identifiers
}

func IsSafeSourceRelativePath(value string) bool {
	return isSafeSourceRelativePath(value)
}

// IsSafeAbsoluteGuestPath exposes the C40 lexical Guest-path guard to the
// pure C39-to-C40 composer without granting it filesystem access.
func IsSafeAbsoluteGuestPath(value string) bool {
	return isSafeAbsoluteGuestPath(value)
}

func isSafeSourceRelativePath(value string) bool {
	return isSafeRelativePath(value) && (len(value) > len("sources/") && value[:len("sources/")] == "sources/" || len(value) > len("generated/") && value[:len("generated/")] == "generated/")
}

func isSafeRelativePayloadPath(value string) bool {
	return isSafeRelativePath(value)
}

func isSafeRelativePath(value string) bool {
	if value == "" || value[0] == '/' || path.Clean(value) != value {
		return false
	}
	for _, component := range splitPath(value) {
		if component == "" || component == "." || component == ".." {
			return false
		}
	}
	return true
}

func isSafeAbsoluteGuestPath(value string) bool {
	if value == "/" || len(value) < 2 || value[0] != '/' || path.Clean(value) != value {
		return false
	}
	for _, component := range splitPath(value[1:]) {
		if component == "" || component == "." || component == ".." {
			return false
		}
	}
	return true
}

func isPathBelow(parent string, child string) bool {
	return child != parent && strings.HasPrefix(child, parent+"/")
}

func isPathAtOrBelow(parent string, child string) bool {
	return child == parent || isPathBelow(parent, child)
}

func splitPath(value string) []string {
	return strings.Split(value, "/")
}
