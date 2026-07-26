// Package guestlinuxbootartifactextraction executes the C42 release-build
// effect. It owns no source selection, Guest lifecycle state, or boot claim.
package guestlinuxbootartifactextraction

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/disk"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/filesystem/ext4"
	declaration "github.com/tirosh-chain/vitalserver-runtime-platform/guest-linux-boot-artifact-extractor/internal/guestlinuxbootartifactdeclaration"
)

const copyBufferBytes = 1 << 20

// GuestLinuxBootArtifactExtractionExecution contains every caller-owned Host
// effect path. The extractor records its own completion time only after it has
// produced and verified the declared C42 output.
type GuestLinuxBootArtifactExtractionExecution struct {
	GuestLinuxBootArtifactExtractionDeclarationPath string
	OutputDirectory                                 string
}

// GuestLinuxBootArtifactExtractionError preserves the explicit C42 identity
// and effect stage. An error never becomes an empty artifact output.
type GuestLinuxBootArtifactExtractionError struct {
	ExtractionID string
	Stage        string
	Reason       string
}

// c73MaterializationReceipt is deliberately local to the C42 adapter. C42
// consumes only the C73 facts needed to verify the raw input it receives; it
// does not own C73 conversion policy or source acquisition.
type c73MaterializationReceipt struct {
	SchemaVersion                    string `json:"schemaVersion"`
	DocumentKind                     string `json:"documentKind"`
	MaterializationID                string `json:"materializationId"`
	Architecture                     string `json:"architecture"`
	MaterializationDeclarationSHA256 string `json:"materializationDeclarationSha256"`
	SourceImage                      struct {
		ID              string `json:"id"`
		SourceOriginURI string `json:"sourceOriginUri"`
		SourceRelease   string `json:"sourceRelease"`
		SizeBytes       int64  `json:"sizeBytes"`
		SHA256          string `json:"sha256"`
	} `json:"sourceImage"`
	SourceImageFormat string `json:"sourceImageFormat"`
	RawImage          struct {
		ID           string `json:"id"`
		RelativePath string `json:"relativePath"`
		ImageFormat  string `json:"imageFormat"`
		SizeBytes    int64  `json:"sizeBytes"`
		SHA256       string `json:"sha256"`
	} `json:"rawImage"`
	CompletedAt string `json:"completedAt"`
}

func (err GuestLinuxBootArtifactExtractionError) Error() string {
	extractionID := err.ExtractionID
	if extractionID == "" {
		extractionID = "unknown"
	}
	return "Guest Linux boot artifact extraction failed extractionId=" + extractionID + " stage=" + err.Stage + " reason=" + err.Reason
}

// ExecuteGuestLinuxBootArtifactExtraction validates C42 and atomically
// publishes only the declared boot and root-storage files plus the C42 receipt.
func ExecuteGuestLinuxBootArtifactExtraction(execution GuestLinuxBootArtifactExtractionExecution) (declaration.GuestLinuxBootArtifactExtractionReceipt, error) {
	if err := requireAbsoluteRegularNonSymlinkFile(execution.GuestLinuxBootArtifactExtractionDeclarationPath, "C42 declaration"); err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure("", "execution-validate", err)
	}
	declarationBytes, err := os.ReadFile(execution.GuestLinuxBootArtifactExtractionDeclarationPath)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure("", "C42-read", err)
	}
	parsedDeclaration, err := declaration.DecodeGuestLinuxBootArtifactExtractionDeclaration(declarationBytes)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure("", "C42-decode", err)
	}
	if err := requireAbsentAbsoluteOutputDirectory(execution.OutputDirectory); err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "output-validate", err)
	}
	return executeDeclaredGuestLinuxBootArtifactExtraction(parsedDeclaration, declarationBytes, execution)
}

func executeDeclaredGuestLinuxBootArtifactExtraction(
	parsedDeclaration declaration.GuestLinuxBootArtifactExtractionDeclaration,
	declarationBytes []byte,
	execution GuestLinuxBootArtifactExtractionExecution,
) (declaration.GuestLinuxBootArtifactExtractionReceipt, error) {
	sourceImageIdentity, err := verifyDeclaredGuestLinuxSourceImage(parsedDeclaration.SourceImage)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "source-image-identity", err)
	}
	temporaryOutputDirectory, err := createSiblingTemporaryOutputDirectory(execution.OutputDirectory)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "output-stage-create", err)
	}
	defer os.RemoveAll(temporaryOutputDirectory)

	rootStoragePath := filepath.Join(temporaryOutputDirectory, filepath.FromSlash(parsedDeclaration.RootStorage.OutputRelativePath))
	rootStorageIdentity, err := extractDeclaredGuestRootStorage(parsedDeclaration, rootStoragePath)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "root-storage-copy", err)
	}
	if parsedDeclaration.SourceFilesystem.Layout == "whole-disk-ext4" && (rootStorageIdentity.SizeBytes != sourceImageIdentity.SizeBytes || rootStorageIdentity.SHA256 != sourceImageIdentity.SHA256) {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "root-storage-identity", fmt.Errorf("copied root storage does not match the declared source image"))
	}
	bootResourceIdentities, err := extractDeclaredGuestBootResources(parsedDeclaration, temporaryOutputDirectory)
	if err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "boot-resource-extract", err)
	}
	completedAt := recordGuestLinuxBootArtifactExtractionCompletionTime()
	receipt := declaration.GuestLinuxBootArtifactExtractionReceipt{
		SchemaVersion:               "v1",
		ExtractionID:                parsedDeclaration.ExtractionID,
		Architecture:                parsedDeclaration.Architecture,
		ExtractionDeclarationSHA256: sha256Hex(declarationBytes),
		SourceImage:                 sourceImageIdentity,
		BootResources:               bootResourceIdentities,
		RootStorage:                 rootStorageIdentity,
		CompletedAt:                 completedAt,
	}
	if err := writeNewJSONDocument(filepath.Join(temporaryOutputDirectory, "guest-linux-boot-artifact-extraction-receipt.json"), receipt); err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "receipt-write", err)
	}
	if err := os.Rename(temporaryOutputDirectory, execution.OutputDirectory); err != nil {
		return declaration.GuestLinuxBootArtifactExtractionReceipt{}, extractionFailure(parsedDeclaration.ExtractionID, "output-publish", err)
	}
	return receipt, nil
}

// recordGuestLinuxBootArtifactExtractionCompletionTime records the C42
// completion fact after the extractor has produced every declared artifact.
// It belongs to this effect, not to a release declaration or its caller.
func recordGuestLinuxBootArtifactExtractionCompletionTime() string {
	return time.Now().UTC().Truncate(time.Second).Format(time.RFC3339)
}

func verifyDeclaredGuestLinuxSourceImage(source declaration.DeclaredGuestLinuxSourceImage) (declaration.SourceImageIdentity, error) {
	if err := requireAbsoluteRegularNonSymlinkFile(source.SourceAbsolutePath, "C42 sourceImage"); err != nil {
		return declaration.SourceImageIdentity{}, err
	}
	identity, err := identifyRegularFile(source.ID, "storage/guest-root.raw", source.SourceAbsolutePath)
	if err != nil {
		return declaration.SourceImageIdentity{}, err
	}
	if identity.SizeBytes != source.SizeBytes || identity.SHA256 != source.SHA256 {
		return declaration.SourceImageIdentity{}, fmt.Errorf("C42 sourceImage immutable identity does not match declaration")
	}
	if source.SourceMaterialization != nil {
		if err := verifyDeclaredC73Materialization(source); err != nil {
			return declaration.SourceImageIdentity{}, err
		}
	}
	return declaration.SourceImageIdentity{ID: identity.ID, SizeBytes: identity.SizeBytes, SHA256: identity.SHA256}, nil
}

func verifyDeclaredC73Materialization(source declaration.DeclaredGuestLinuxSourceImage) error {
	materialization := source.SourceMaterialization
	if materialization == nil {
		return fmt.Errorf("C42 source materialization is required")
	}
	if err := requireAbsoluteRegularNonSymlinkFile(materialization.ReceiptAbsolutePath, "C73 materialization receipt"); err != nil {
		return err
	}
	receiptBytes, err := os.ReadFile(materialization.ReceiptAbsolutePath)
	if err != nil {
		return fmt.Errorf("C73 materialization receipt cannot be read: %w", err)
	}
	if sha256Hex(receiptBytes) != materialization.ReceiptSHA256 {
		return fmt.Errorf("C73 materialization receipt SHA-256 does not match declaration")
	}
	decoder := json.NewDecoder(bytes.NewReader(receiptBytes))
	decoder.DisallowUnknownFields()
	var receipt c73MaterializationReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return fmt.Errorf("C73 materialization receipt cannot be decoded: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return fmt.Errorf("C73 materialization receipt has more than one JSON value")
		}
		return fmt.Errorf("C73 materialization receipt trailing JSON cannot be decoded: %w", err)
	}
	if receipt.SchemaVersion != "v1" || receipt.DocumentKind != "guest-linux-source-disk-materialization-receipt" || receipt.MaterializationID != materialization.MaterializationID || receipt.Architecture != "arm64" || receipt.MaterializationDeclarationSHA256 == "" || receipt.SourceImage.ID == "" || receipt.SourceImage.SourceOriginURI == "" || receipt.SourceImage.SourceRelease == "" || receipt.SourceImage.SizeBytes <= 0 || receipt.SourceImage.SHA256 == "" || receipt.SourceImageFormat != "qcow2" || receipt.CompletedAt == "" {
		return fmt.Errorf("C73 materialization receipt identity does not match C42 source materialization")
	}
	if receipt.RawImage.ID != source.ID || receipt.RawImage.RelativePath == "" || receipt.RawImage.ImageFormat != "raw" || receipt.RawImage.SizeBytes != source.SizeBytes || receipt.RawImage.SHA256 != source.SHA256 {
		return fmt.Errorf("C73 materialization receipt raw image identity does not match C42 source image")
	}
	return nil
}

func extractDeclaredGuestRootStorage(parsedDeclaration declaration.GuestLinuxBootArtifactExtractionDeclaration, outputPath string) (declaration.ArtifactIdentity, error) {
	if parsedDeclaration.SourceFilesystem.Layout == "whole-disk-ext4" {
		return copyDeclaredRegularFile(parsedDeclaration.RootStorage.ID, parsedDeclaration.RootStorage.OutputRelativePath, parsedDeclaration.SourceImage.SourceAbsolutePath, outputPath)
	}
	disk, err := diskfs.Open(parsedDeclaration.SourceImage.SourceAbsolutePath, diskfs.WithOpenMode(diskfs.ReadOnly), diskfs.WithSectorSize(diskfs.SectorSize512))
	if err != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("C42 partitioned-disk source cannot be opened read-only: %w", err)
	}
	defer disk.Close()
	if _, err := disk.GetPartitionTable(); err != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("C42 partitioned-disk source partition table cannot be read: %w", err)
	}
	return copyDeclaredPartitionContents(disk, parsedDeclaration.SourceFilesystem.PartitionIndex, parsedDeclaration.RootStorage.ID, parsedDeclaration.RootStorage.OutputRelativePath, outputPath)
}

type openedDeclaredGuestSourceFilesystem struct {
	disk       *disk.Disk
	filesystem *ext4.FileSystem
}

func (opened openedDeclaredGuestSourceFilesystem) Close() error {
	filesystemError := opened.filesystem.Close()
	diskError := opened.disk.Close()
	if filesystemError != nil {
		return filesystemError
	}
	return diskError
}

func extractDeclaredGuestBootResources(parsedDeclaration declaration.GuestLinuxBootArtifactExtractionDeclaration, temporaryOutputDirectory string) ([]declaration.ArtifactIdentity, error) {
	var guestFilesystem *ext4.FileSystem
	if bootResourcesUseSourceImageFilesystem(parsedDeclaration.BootResources) {
		openedFilesystem, err := openDeclaredGuestSourceFilesystem(parsedDeclaration)
		if err != nil {
			return nil, err
		}
		defer openedFilesystem.Close()
		guestFilesystem = openedFilesystem.filesystem
	}
	kernelOutputPath := filepath.Join(temporaryOutputDirectory, filepath.FromSlash(parsedDeclaration.BootResources.Kernel.OutputRelativePath))
	kernelIdentity, err := extractDeclaredGzipCompressedGuestLinuxKernel(
		guestFilesystem,
		parsedDeclaration.BootResources.Kernel,
		kernelOutputPath,
	)
	if err != nil {
		return nil, err
	}
	initialRamdiskOutputPath := filepath.Join(temporaryOutputDirectory, filepath.FromSlash(parsedDeclaration.BootResources.InitialRamdisk.OutputRelativePath))
	initialRamdiskIdentity, err := extractDeclaredGuestRegularFile(
		guestFilesystem,
		parsedDeclaration.BootResources.InitialRamdisk,
		initialRamdiskOutputPath,
	)
	if err != nil {
		return nil, err
	}
	return []declaration.ArtifactIdentity{kernelIdentity, initialRamdiskIdentity}, nil
}

func bootResourcesUseSourceImageFilesystem(resources declaration.DeclaredGuestLinuxBootResources) bool {
	return resources.Kernel.Source.Kind == "source-image-filesystem" || resources.InitialRamdisk.Source.Kind == "source-image-filesystem"
}

func openDeclaredGuestSourceFilesystem(parsedDeclaration declaration.GuestLinuxBootArtifactExtractionDeclaration) (openedDeclaredGuestSourceFilesystem, error) {
	disk, err := diskfs.Open(parsedDeclaration.SourceImage.SourceAbsolutePath, diskfs.WithOpenMode(diskfs.ReadOnly), diskfs.WithSectorSize(diskfs.SectorSize512))
	if err != nil {
		return openedDeclaredGuestSourceFilesystem{}, fmt.Errorf("C42 declared source disk cannot be opened read-only: %w", err)
	}
	// diskfs owns the filesystem handle. The caller closes the resulting
	// filesystem after extracting every resource that explicitly selected it.
	if parsedDeclaration.SourceFilesystem.Layout == "partitioned-disk-ext4" {
		if _, err := disk.GetPartitionTable(); err != nil {
			disk.Close()
			return openedDeclaredGuestSourceFilesystem{}, fmt.Errorf("C42 partitioned-disk source partition table cannot be read: %w", err)
		}
	}
	partitionIndex := parsedDeclaration.SourceFilesystem.PartitionIndex
	selectedFilesystem, err := disk.GetFilesystem(partitionIndex)
	if err != nil {
		disk.Close()
		return openedDeclaredGuestSourceFilesystem{}, fmt.Errorf("C42 declared ext4 source filesystem cannot be read: %w", err)
	}
	guestFilesystem, ok := selectedFilesystem.(*ext4.FileSystem)
	if !ok || selectedFilesystem.Type() != filesystem.TypeExt4 {
		selectedFilesystem.Close()
		disk.Close()
		return openedDeclaredGuestSourceFilesystem{}, fmt.Errorf("C42 declared source filesystem is not ext4")
	}
	return openedDeclaredGuestSourceFilesystem{disk: disk, filesystem: guestFilesystem}, nil
}

// extractDeclaredGzipCompressedGuestLinuxKernel makes the declared source
// encoding visible. It must not copy compressed vmlinuz bytes into C35 under
// a boot-loader-looking path and leave Apple Virtualization to fail later.
func extractDeclaredGzipCompressedGuestLinuxKernel(guestFilesystem *ext4.FileSystem, resource declaration.DeclaredGuestBootResource, outputPath string) (declaration.ArtifactIdentity, error) {
	source, sourceDescription, err := openDeclaredBootResourceSource(guestFilesystem, resource)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	defer source.Close()
	decompressedKernel, err := gzip.NewReader(source)
	if err != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("C42 declared compressed Guest Linux kernel source %s is not valid gzip: %w", sourceDescription, err)
	}
	defer decompressedKernel.Close()
	identity, err := writeNewReaderOutput(resource.ID, resource.OutputRelativePath, outputPath, decompressedKernel)
	if err != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("C42 declared compressed Guest Linux kernel source %s cannot be decompressed: %w", sourceDescription, err)
	}
	return identity, nil
}

func extractDeclaredGuestRegularFile(guestFilesystem *ext4.FileSystem, resource declaration.DeclaredGuestBootResource, outputPath string) (declaration.ArtifactIdentity, error) {
	source, sourceDescription, err := openDeclaredBootResourceSource(guestFilesystem, resource)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	defer source.Close()
	identity, err := writeNewReaderOutput(resource.ID, resource.OutputRelativePath, outputPath, source)
	if err != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("C42 declared Guest boot source %s cannot be copied: %w", sourceDescription, err)
	}
	return identity, nil
}

func openDeclaredBootResourceSource(guestFilesystem *ext4.FileSystem, resource declaration.DeclaredGuestBootResource) (io.ReadCloser, string, error) {
	switch resource.Source.Kind {
	case "source-image-filesystem":
		if guestFilesystem == nil {
			return nil, "", fmt.Errorf("C42 declared source-image-filesystem boot source has no selected ext4 filesystem")
		}
		guestPath := strings.TrimPrefix(resource.Source.GuestAbsolutePath, "/")
		guestFile, err := guestFilesystem.OpenFile(guestPath, os.O_RDONLY)
		if err != nil {
			return nil, "", fmt.Errorf("C42 declared Guest boot path %s cannot be opened: %w", resource.Source.GuestAbsolutePath, err)
		}
		return guestFile, resource.Source.GuestAbsolutePath, nil
	case "external-artifact":
		if err := verifyDeclaredExternalBootResource(resource); err != nil {
			return nil, "", err
		}
		externalFile, err := os.Open(resource.Source.SourceAbsolutePath)
		if err != nil {
			return nil, "", fmt.Errorf("C42 declared external boot source cannot be opened: %w", err)
		}
		return externalFile, resource.Source.SourceAbsolutePath, nil
	default:
		return nil, "", fmt.Errorf("C42 declared boot source kind is invalid")
	}
}

func verifyDeclaredExternalBootResource(resource declaration.DeclaredGuestBootResource) error {
	source := resource.Source
	if err := requireAbsoluteRegularNonSymlinkFile(source.SourceAbsolutePath, "C42 external boot source"); err != nil {
		return err
	}
	identity, err := identifyRegularFile(resource.ID, resource.OutputRelativePath, source.SourceAbsolutePath)
	if err != nil {
		return fmt.Errorf("C42 external boot source cannot be identified: %w", err)
	}
	if identity.SizeBytes != source.SizeBytes || identity.SHA256 != source.SHA256 {
		return fmt.Errorf("C42 external boot source immutable identity does not match declaration")
	}
	return nil
}

func copyDeclaredRegularFile(id, relativePath, sourcePath, destinationPath string) (declaration.ArtifactIdentity, error) {
	sourceFile, err := os.Open(sourcePath)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	defer sourceFile.Close()
	return writeNewReaderOutput(id, relativePath, destinationPath, sourceFile)
}

func copyDeclaredPartitionContents(sourceDisk *disk.Disk, partitionIndex int, id, relativePath, destinationPath string) (declaration.ArtifactIdentity, error) {
	if err := os.MkdirAll(filepath.Dir(destinationPath), 0o700); err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	destination, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	hasher := sha256.New()
	written, copyErr := sourceDisk.ReadPartitionContents(partitionIndex, io.MultiWriter(destination, hasher))
	syncErr := destination.Sync()
	closeErr := destination.Close()
	if copyErr != nil {
		return declaration.ArtifactIdentity{}, copyErr
	}
	if syncErr != nil || closeErr != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("partition output cannot be synced and closed")
	}
	if written <= 0 {
		return declaration.ArtifactIdentity{}, fmt.Errorf("declared source partition is empty")
	}
	return declaration.ArtifactIdentity{ID: id, RelativePath: relativePath, SizeBytes: written, SHA256: hex.EncodeToString(hasher.Sum(nil))}, nil
}

func writeNewReaderOutput(id, relativePath, destinationPath string, source io.Reader) (declaration.ArtifactIdentity, error) {
	if err := os.MkdirAll(filepath.Dir(destinationPath), 0o700); err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	destination, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	hasher := sha256.New()
	written, copyErr := io.CopyBuffer(io.MultiWriter(destination, hasher), source, make([]byte, copyBufferBytes))
	syncErr := destination.Sync()
	closeErr := destination.Close()
	if copyErr != nil {
		return declaration.ArtifactIdentity{}, copyErr
	}
	if syncErr != nil || closeErr != nil {
		return declaration.ArtifactIdentity{}, fmt.Errorf("output cannot be synced and closed")
	}
	if written <= 0 {
		return declaration.ArtifactIdentity{}, fmt.Errorf("output is empty")
	}
	return declaration.ArtifactIdentity{ID: id, RelativePath: relativePath, SizeBytes: written, SHA256: hex.EncodeToString(hasher.Sum(nil))}, nil
}

func identifyRegularFile(id, relativePath, value string) (declaration.ArtifactIdentity, error) {
	file, err := os.Open(value)
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	defer file.Close()
	hasher := sha256.New()
	written, err := io.CopyBuffer(hasher, file, make([]byte, copyBufferBytes))
	if err != nil {
		return declaration.ArtifactIdentity{}, err
	}
	if written <= 0 {
		return declaration.ArtifactIdentity{}, fmt.Errorf("regular file is empty")
	}
	return declaration.ArtifactIdentity{ID: id, RelativePath: relativePath, SizeBytes: written, SHA256: hex.EncodeToString(hasher.Sum(nil))}, nil
}

func requireAbsoluteRegularNonSymlinkFile(value string, name string) error {
	if !filepath.IsAbs(value) {
		return fmt.Errorf("%s path must be absolute", name)
	}
	info, err := os.Lstat(value)
	if err != nil {
		return fmt.Errorf("cannot state %s: %w", name, err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return fmt.Errorf("%s must be a regular non-symlink file", name)
	}
	return nil
}

func requireAbsentAbsoluteOutputDirectory(value string) error {
	if !filepath.IsAbs(value) {
		return fmt.Errorf("C42 output directory path must be absolute")
	}
	parentDirectory := filepath.Dir(value)
	parentInfo, err := os.Lstat(parentDirectory)
	if err != nil {
		return fmt.Errorf("C42 output parent directory cannot be stated: %w", err)
	}
	if parentInfo.Mode()&os.ModeSymlink != 0 || !parentInfo.IsDir() {
		return fmt.Errorf("C42 output parent directory must be a directory non-symlink")
	}
	if _, err := os.Lstat(value); err == nil {
		return fmt.Errorf("C42 output directory already exists")
	} else if !os.IsNotExist(err) {
		return err
	}
	return nil
}

func createSiblingTemporaryOutputDirectory(outputDirectory string) (string, error) {
	return os.MkdirTemp(filepath.Dir(outputDirectory), "."+filepath.Base(outputDirectory)+".C42.")
}

func writeNewJSONDocument(destination string, document any) error {
	contents, err := json.Marshal(document)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(contents, '\n')); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func sha256Hex(contents []byte) string {
	sum := sha256.Sum256(contents)
	return hex.EncodeToString(sum[:])
}

func extractionFailure(extractionID, stage string, err error) GuestLinuxBootArtifactExtractionError {
	return GuestLinuxBootArtifactExtractionError{ExtractionID: extractionID, Stage: stage, Reason: err.Error()}
}
