// Package guestlinuxbootartifactdeclaration owns pure C42 declaration and
// receipt language. It performs no filesystem, image, or network effect.
package guestlinuxbootartifactdeclaration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"path"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	identifierPattern        = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
	sha256Pattern            = regexp.MustCompile(`^[a-f0-9]{64}$`)
	guestAbsolutePathPattern = regexp.MustCompile(`^/[A-Za-z0-9._/-]+$`)
	bootOutputPathPattern    = regexp.MustCompile(`^boot/(?:[A-Za-z0-9][A-Za-z0-9._-]*/)*[A-Za-z0-9][A-Za-z0-9._-]*$`)
	storageOutputPathPattern = regexp.MustCompile(`^storage/(?:[A-Za-z0-9][A-Za-z0-9._-]*/)*[A-Za-z0-9][A-Za-z0-9._-]*$`)
)

// GuestLinuxBootArtifactExtractionDeclaration is C42. The source path exists
// only while the release build reads the Host build-machine input; it must not
// appear in C42 output evidence or any following C35 artifact.
type GuestLinuxBootArtifactExtractionDeclaration struct {
	SchemaVersion    string                          `json:"schemaVersion"`
	ExtractionID     string                          `json:"extractionId"`
	Architecture     string                          `json:"architecture"`
	SourceImage      DeclaredGuestLinuxSourceImage   `json:"sourceImage"`
	SourceFilesystem DeclaredGuestSourceFilesystem   `json:"sourceFilesystem"`
	BootResources    DeclaredGuestLinuxBootResources `json:"bootResources"`
	RootStorage      DeclaredGuestLinuxRootStorage   `json:"rootStorage"`
}

// DeclaredGuestLinuxSourceImage names one release-owned, whole-disk source.
type DeclaredGuestLinuxSourceImage struct {
	ID                 string `json:"id"`
	SourceAbsolutePath string `json:"sourceAbsolutePath"`
	SourceOriginURI    string `json:"sourceOriginUri"`
	SourceRelease      string `json:"sourceRelease"`
	SizeBytes          int64  `json:"sizeBytes"`
	SHA256             string `json:"sha256"`
}

// DeclaredGuestSourceFilesystem declares the image layout; it is not inferred
// from a filename or a source provider default.
type DeclaredGuestSourceFilesystem struct {
	Layout         string `json:"layout"`
	FilesystemType string `json:"filesystemType"`
}

// DeclaredGuestLinuxBootResources names the format expected by the macOS
// Virtualization Linux boot loader as well as the source encoding in the
// immutable Guest image. The Guest's vmlinuz download is not itself a boot
// loader input: C42 must publish the declared uncompressed ARM64 Image.
// A release must not silently boot with a missing initramfs.
type DeclaredGuestLinuxBootResources struct {
	Kernel         DeclaredGuestBootResource `json:"kernel"`
	InitialRamdisk DeclaredGuestBootResource `json:"initialRamdisk"`
}

// DeclaredGuestBootResource maps one explicit path inside the immutable source
// image to one identity-only C42 output path. sourceCompression and
// outputFormat are explicit because copied source bytes and the target boot
// loader artifact can be different representations of the same kernel.
type DeclaredGuestBootResource struct {
	ID                 string `json:"id"`
	GuestAbsolutePath  string `json:"guestAbsolutePath"`
	SourceCompression  string `json:"sourceCompression"`
	OutputRelativePath string `json:"outputRelativePath"`
	OutputFormat       string `json:"outputFormat"`
}

// DeclaredGuestLinuxRootStorage publishes the unchanged source image as a
// whole-disk ext4 device. A partition must not be invented for this layout.
type DeclaredGuestLinuxRootStorage struct {
	ID                 string `json:"id"`
	GuestDevicePath    string `json:"guestDevicePath"`
	OutputRelativePath string `json:"outputRelativePath"`
	FilesystemType     string `json:"filesystemType"`
	StorageLayout      string `json:"storageLayout"`
}

// ArtifactIdentity is a C42 output identity. It contains no source absolute
// path, URL credential, cache path, or runtime observation.
type ArtifactIdentity struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SizeBytes    int64  `json:"sizeBytes"`
	SHA256       string `json:"sha256"`
}

// SourceImageIdentity identifies the caller-provided image without inventing a
// published artifact path. The same bytes may be published as RootStorage at a
// different declared output path.
type SourceImageIdentity struct {
	ID        string `json:"id"`
	SizeBytes int64  `json:"sizeBytes"`
	SHA256    string `json:"sha256"`
}

// GuestLinuxBootArtifactExtractionReceipt is C42 immutable build evidence.
type GuestLinuxBootArtifactExtractionReceipt struct {
	SchemaVersion               string              `json:"schemaVersion"`
	ExtractionID                string              `json:"extractionId"`
	Architecture                string              `json:"architecture"`
	ExtractionDeclarationSHA256 string              `json:"extractionDeclarationSHA256"`
	SourceImage                 SourceImageIdentity `json:"sourceImage"`
	BootResources               []ArtifactIdentity  `json:"bootResources"`
	RootStorage                 ArtifactIdentity    `json:"rootStorage"`
	CompletedAt                 string              `json:"completedAt"`
}

// DecodeGuestLinuxBootArtifactExtractionDeclaration decodes one closed C42
// declaration. Unknown fields are a contract failure, not an ignored preset.
func DecodeGuestLinuxBootArtifactExtractionDeclaration(contents []byte) (GuestLinuxBootArtifactExtractionDeclaration, error) {
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	var declaration GuestLinuxBootArtifactExtractionDeclaration
	if err := decoder.Decode(&declaration); err != nil {
		return GuestLinuxBootArtifactExtractionDeclaration{}, fmt.Errorf("C42 declaration JSON cannot be decoded: %w", err)
	}
	if err := requireNoTrailingJSONValue(decoder); err != nil {
		return GuestLinuxBootArtifactExtractionDeclaration{}, err
	}
	if err := ValidateGuestLinuxBootArtifactExtractionDeclaration(declaration); err != nil {
		return GuestLinuxBootArtifactExtractionDeclaration{}, err
	}
	return declaration, nil
}

// ValidateGuestLinuxBootArtifactExtractionDeclaration is pure C42 policy.
func ValidateGuestLinuxBootArtifactExtractionDeclaration(declaration GuestLinuxBootArtifactExtractionDeclaration) error {
	if declaration.SchemaVersion != "v1" {
		return fmt.Errorf("C42 schemaVersion must be v1")
	}
	if !identifierPattern.MatchString(declaration.ExtractionID) {
		return fmt.Errorf("C42 extractionId is invalid")
	}
	if declaration.Architecture != "arm64" {
		return fmt.Errorf("C42 architecture must be arm64")
	}
	if err := validateDeclaredGuestLinuxSourceImage(declaration.SourceImage); err != nil {
		return err
	}
	if declaration.SourceFilesystem.Layout != "whole-disk-ext4" || declaration.SourceFilesystem.FilesystemType != "ext4" {
		return fmt.Errorf("C42 sourceFilesystem must declare whole-disk-ext4")
	}
	if err := validateDeclaredGuestBootResource(declaration.BootResources.Kernel, "kernel", "gzip", "boot/Image", "uncompressed-linux-arm64-image"); err != nil {
		return err
	}
	if err := validateDeclaredGuestBootResource(declaration.BootResources.InitialRamdisk, "initialRamdisk", "none", "boot/initrd.img", "cpio"); err != nil {
		return err
	}
	if declaration.BootResources.Kernel.ID == declaration.BootResources.InitialRamdisk.ID || declaration.BootResources.Kernel.OutputRelativePath == declaration.BootResources.InitialRamdisk.OutputRelativePath {
		return fmt.Errorf("C42 kernel and initialRamdisk identities must differ")
	}
	if err := validateDeclaredGuestLinuxRootStorage(declaration.RootStorage); err != nil {
		return err
	}
	return nil
}

func validateDeclaredGuestLinuxSourceImage(source DeclaredGuestLinuxSourceImage) error {
	if !identifierPattern.MatchString(source.ID) {
		return fmt.Errorf("C42 sourceImage id is invalid")
	}
	if !filepath.IsAbs(source.SourceAbsolutePath) {
		return fmt.Errorf("C42 sourceImage sourceAbsolutePath must be absolute")
	}
	parsedURI, err := url.ParseRequestURI(source.SourceOriginURI)
	if err != nil || parsedURI.Scheme != "https" || parsedURI.Host == "" {
		return fmt.Errorf("C42 sourceImage sourceOriginUri must be an absolute HTTPS URI")
	}
	if strings.TrimSpace(source.SourceRelease) == "" {
		return fmt.Errorf("C42 sourceImage sourceRelease is required")
	}
	if source.SizeBytes <= 0 || !sha256Pattern.MatchString(source.SHA256) {
		return fmt.Errorf("C42 sourceImage immutable identity is invalid")
	}
	return nil
}

func validateDeclaredGuestBootResource(resource DeclaredGuestBootResource, name string, sourceCompression string, outputRelativePath string, outputFormat string) error {
	if !identifierPattern.MatchString(resource.ID) {
		return fmt.Errorf("C42 bootResources %s id is invalid", name)
	}
	if !isSafeAbsoluteGuestPath(resource.GuestAbsolutePath) {
		return fmt.Errorf("C42 bootResources %s guestAbsolutePath is invalid", name)
	}
	if resource.SourceCompression != sourceCompression || resource.OutputRelativePath != outputRelativePath || resource.OutputFormat != outputFormat || !bootOutputPathPattern.MatchString(resource.OutputRelativePath) {
		return fmt.Errorf("C42 bootResources %s sourceCompression, outputRelativePath, or outputFormat is invalid", name)
	}
	return nil
}

func validateDeclaredGuestLinuxRootStorage(storage DeclaredGuestLinuxRootStorage) error {
	if !identifierPattern.MatchString(storage.ID) || storage.GuestDevicePath != "/dev/vda" || !storageOutputPathPattern.MatchString(storage.OutputRelativePath) || storage.FilesystemType != "ext4" || storage.StorageLayout != "whole-disk-ext4" {
		return fmt.Errorf("C42 rootStorage must declare one whole-disk ext4 /dev/vda artifact")
	}
	return nil
}

func isSafeAbsoluteGuestPath(value string) bool {
	if !guestAbsolutePathPattern.MatchString(value) {
		return false
	}
	for _, component := range strings.Split(value, "/") {
		if component == ".." {
			return false
		}
	}
	return path.Clean(value) == value
}

func requireNoTrailingJSONValue(decoder *json.Decoder) error {
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return fmt.Errorf("C42 declaration has more than one JSON value")
		}
		return fmt.Errorf("C42 declaration trailing JSON cannot be decoded: %w", err)
	}
	return nil
}
