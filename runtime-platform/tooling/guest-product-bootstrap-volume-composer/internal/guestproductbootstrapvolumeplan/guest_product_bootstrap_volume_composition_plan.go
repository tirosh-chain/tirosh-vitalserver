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
	SchemaVersion              string                             `json:"schemaVersion"`
	BootstrapID                string                             `json:"bootstrapId"`
	VolumeLabel                string                             `json:"volumeLabel"`
	StorageImageFormat         string                             `json:"storageImageFormat"`
	GuestVolumeFileSystem      string                             `json:"guestVolumeFileSystem"`
	InstanceID                 string                             `json:"instanceId"`
	LocalHostName              string                             `json:"localHostName"`
	ServiceUnitName            string                             `json:"serviceUnitName"`
	GuestRuntimeStateDirectory DeclaredGuestDirectory             `json:"guestRuntimeStateDirectory"`
	Sources                    []DeclaredBootstrapSource          `json:"sources"`
	FileInstallations          []DeclaredGuestFileInstallation    `json:"fileInstallations"`
	ArchiveInstallations       []DeclaredGuestArchiveInstallation `json:"archiveInstallations"`
	SymbolicLinks              []DeclaredGuestSymbolicLink        `json:"symbolicLinks"`
}

// DeclaredGuestDirectory is one mutable Guest-owned directory that must exist
// before a stateful service starts. It is desired installation input, not an
// observation that the directory exists or is writable.
type DeclaredGuestDirectory struct {
	DirectoryPath string `json:"directoryPath"`
	DirectoryMode string `json:"directoryMode"`
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
	if !serviceUnitPattern.MatchString(plan.ServiceUnitName) {
		return fmt.Errorf("C40 serviceUnitName is invalid")
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
	if len(plan.Sources) < 2 || len(plan.FileInstallations) < 1 || len(plan.ArchiveInstallations) != 1 || len(plan.SymbolicLinks) != 1 {
		return fmt.Errorf("C40 requires at least two declared payloads, one file installation, one archive installation, and one service enable link")
	}
	if !isSafeAbsoluteGuestPath(plan.GuestRuntimeStateDirectory.DirectoryPath) || plan.GuestRuntimeStateDirectory.DirectoryMode != "0700" {
		return fmt.Errorf("C40 Guest Runtime state directory is invalid")
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
	for _, symbolicLink := range plan.SymbolicLinks {
		if !isSafeAbsoluteGuestPath(symbolicLink.LinkPath) || !isSafeAbsoluteGuestPath(symbolicLink.TargetPath) {
			return fmt.Errorf("C40 symbolic link is invalid")
		}
		if _, exists := installedGuestFiles[symbolicLink.TargetPath]; !exists {
			return fmt.Errorf("C40 service enable link %q does not target an installed Guest file", symbolicLink.LinkPath)
		}
		if path.Base(symbolicLink.LinkPath) != plan.ServiceUnitName || path.Base(symbolicLink.TargetPath) != plan.ServiceUnitName {
			return fmt.Errorf("C40 service enable link must name declared service unit %q", plan.ServiceUnitName)
		}
		if prior, exists := destinations[symbolicLink.LinkPath]; exists {
			return fmt.Errorf("C40 link path %q is declared by both %s and symbolic link", symbolicLink.LinkPath, prior)
		}
		destinations[symbolicLink.LinkPath] = "symbolic link"
	}
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

func splitPath(value string) []string {
	return strings.Split(value, "/")
}
