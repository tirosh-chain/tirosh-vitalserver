package guestlinuxbootartifactextraction_test

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/disk"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/partition/mbr"
	declaration "github.com/tirosh-chain/vitalserver-runtime-platform/guest-linux-boot-artifact-extractor/internal/guestlinuxbootartifactdeclaration"
	extraction "github.com/tirosh-chain/vitalserver-runtime-platform/guest-linux-boot-artifact-extractor/internal/guestlinuxbootartifactextraction"
)

func TestExecuteGuestLinuxBootArtifactExtractionPublishesDeclaredWholeDiskBootArtifacts(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64.img")
	createWholeDiskExt4GuestLinuxSourceImage(t, sourceImagePath, true, gzipCompressedBytes(t, []byte("uncompressed-linux-arm64-kernel-image")))
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	receipt, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err != nil {
		t.Fatalf("extract C42 boot artifacts: %v", err)
	}
	if receipt.ExtractionID != declared.ExtractionID || receipt.Architecture != "arm64" {
		t.Fatalf("unexpected receipt identity: %#v", receipt)
	}
	if _, err := time.Parse(time.RFC3339, receipt.CompletedAt); err != nil {
		t.Fatalf("C42 extractor must record a concrete UTC completion fact: %v", err)
	}
	if string(mustReadFile(t, filepath.Join(outputDirectory, "boot", "Image"))) != "uncompressed-linux-arm64-kernel-image" {
		t.Fatal("C42 did not decompress the declared Linux kernel into the VZ boot-loader Image")
	}
	if string(mustReadFile(t, filepath.Join(outputDirectory, "boot", "initrd.img"))) != "initrd-bytes" {
		t.Fatal("C42 did not extract the declared initial ramdisk bytes")
	}
	if receipt.RootStorage.SHA256 != declared.SourceImage.SHA256 || receipt.RootStorage.SizeBytes != declared.SourceImage.SizeBytes {
		t.Fatalf("C42 root storage must preserve source image identity: %#v", receipt.RootStorage)
	}
	if sourceIdentity := sha256ForRegularFile(t, sourceImagePath); sourceIdentity != sha256ForRegularFile(t, filepath.Join(outputDirectory, "storage", "guest-root.raw")) {
		t.Fatal("C42 root storage does not byte-match the declared source image")
	}
	receiptBytes := mustReadFile(t, filepath.Join(outputDirectory, "guest-linux-boot-artifact-extraction-receipt.json"))
	if contains(string(receiptBytes), sourceImagePath) || contains(string(receiptBytes), temporaryRoot) {
		t.Fatalf("C42 receipt must not retain a build-machine source path: %s", receiptBytes)
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionPublishesExplicitExt4PartitionAsWholeDiskRootStorage(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64-gpt.img")
	createPartitionedExt4GuestLinuxSourceImage(t, sourceImagePath, gzipCompressedBytes(t, []byte("partitioned-linux-arm64-kernel-image")))
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declared.SourceFilesystem = declaration.DeclaredGuestSourceFilesystem{Layout: "partitioned-disk-ext4", FilesystemType: "ext4", PartitionIndex: 1}
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	receipt, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err != nil {
		t.Fatalf("extract partitioned C42 boot artifacts: %v", err)
	}
	if string(mustReadFile(t, filepath.Join(outputDirectory, "boot", "Image"))) != "partitioned-linux-arm64-kernel-image" {
		t.Fatal("C42 did not extract the declared kernel from the explicit ext4 partition")
	}
	rootStoragePath := filepath.Join(outputDirectory, "storage", "guest-root.raw")
	if receipt.RootStorage.SHA256 != sha256ForRegularFile(t, rootStoragePath) {
		t.Fatal("C42 partitioned root-storage receipt does not identify its published bytes")
	}
	if receipt.RootStorage.SHA256 == declared.SourceImage.SHA256 || receipt.RootStorage.SizeBytes >= declared.SourceImage.SizeBytes {
		t.Fatalf("C42 partitioned source must publish only the explicit ext4 partition: %#v", receipt.RootStorage)
	}
	rootDisk, err := diskfs.Open(rootStoragePath, diskfs.WithOpenMode(diskfs.ReadOnly), diskfs.WithSectorSize(diskfs.SectorSize512))
	if err != nil {
		t.Fatal(err)
	}
	defer rootDisk.Close()
	rootFilesystem, err := rootDisk.GetFilesystem(0)
	if err != nil {
		t.Fatal(err)
	}
	if rootFilesystem.Type() != filesystem.TypeExt4 {
		t.Fatalf("published C42 root storage is not a whole-disk ext4 filesystem: %v", rootFilesystem.Type())
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionPublishesExternalBootArtifactsForPartitionedCloudDisk(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64-cloud-disk.raw")
	createPartitionedExt4GuestLinuxSourceImageWithoutBootResources(t, sourceImagePath)
	kernelPath := filepath.Join(temporaryRoot, "ubuntu-arm64-vmlinuz-generic")
	initrdPath := filepath.Join(temporaryRoot, "ubuntu-arm64-initrd-generic")
	if err := os.WriteFile(kernelPath, gzipCompressedBytes(t, []byte("external-uncompressed-linux-arm64-kernel")), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(initrdPath, []byte("external-cpio-initrd"), 0o600); err != nil {
		t.Fatal(err)
	}
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declared.SourceFilesystem = declaration.DeclaredGuestSourceFilesystem{Layout: "partitioned-disk-ext4", FilesystemType: "ext4", PartitionIndex: 1}
	declared.BootResources = declaration.DeclaredGuestLinuxBootResources{
		Kernel: declaration.DeclaredGuestBootResource{
			ID: "linux-arm64-kernel", Source: declaredExternalBootResource(t, kernelPath), SourceCompression: "gzip", OutputRelativePath: "boot/Image", OutputFormat: "uncompressed-linux-arm64-image",
		},
		InitialRamdisk: declaration.DeclaredGuestBootResource{
			ID: "linux-arm64-initrd", Source: declaredExternalBootResource(t, initrdPath), SourceCompression: "none", OutputRelativePath: "boot/initrd.img", OutputFormat: "cpio",
		},
	}
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err != nil {
		t.Fatalf("extract C42 external boot artifacts: %v", err)
	}
	if string(mustReadFile(t, filepath.Join(outputDirectory, "boot", "Image"))) != "external-uncompressed-linux-arm64-kernel" {
		t.Fatal("C42 did not decompress the explicitly identified external kernel")
	}
	if string(mustReadFile(t, filepath.Join(outputDirectory, "boot", "initrd.img"))) != "external-cpio-initrd" {
		t.Fatal("C42 did not publish the explicitly identified external initial ramdisk")
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionRejectsTamperedExternalBootArtifactBeforePublishing(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64-cloud-disk.raw")
	createPartitionedExt4GuestLinuxSourceImageWithoutBootResources(t, sourceImagePath)
	kernelPath := filepath.Join(temporaryRoot, "ubuntu-arm64-vmlinuz-generic")
	initrdPath := filepath.Join(temporaryRoot, "ubuntu-arm64-initrd-generic")
	if err := os.WriteFile(kernelPath, gzipCompressedBytes(t, []byte("external-uncompressed-linux-arm64-kernel")), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(initrdPath, []byte("external-cpio-initrd"), 0o600); err != nil {
		t.Fatal(err)
	}
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declared.SourceFilesystem = declaration.DeclaredGuestSourceFilesystem{Layout: "partitioned-disk-ext4", FilesystemType: "ext4", PartitionIndex: 1}
	declared.BootResources = declaration.DeclaredGuestLinuxBootResources{
		Kernel:         declaration.DeclaredGuestBootResource{ID: "linux-arm64-kernel", Source: declaredExternalBootResource(t, kernelPath), SourceCompression: "gzip", OutputRelativePath: "boot/Image", OutputFormat: "uncompressed-linux-arm64-image"},
		InitialRamdisk: declaration.DeclaredGuestBootResource{ID: "linux-arm64-initrd", Source: declaredExternalBootResource(t, initrdPath), SourceCompression: "none", OutputRelativePath: "boot/initrd.img", OutputFormat: "cpio"},
	}
	if err := os.WriteFile(kernelPath, []byte("tampered external kernel"), 0o600); err != nil {
		t.Fatal(err)
	}
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err == nil || !contains(err.Error(), "stage=boot-resource-extract") || !contains(err.Error(), "immutable identity") {
		t.Fatalf("expected explicit external boot source identity failure, got %v", err)
	}
	if _, statErr := os.Lstat(outputDirectory); !os.IsNotExist(statErr) {
		t.Fatalf("tampered external C42 boot source must not publish output: %v", statErr)
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionRejectsTamperedSourceBeforeCreatingOutput(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64.img")
	createWholeDiskExt4GuestLinuxSourceImage(t, sourceImagePath, true, gzipCompressedBytes(t, []byte("uncompressed-linux-arm64-kernel-image")))
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	sourceFile, err := os.OpenFile(sourceImagePath, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := sourceFile.Write([]byte("tamper")); err != nil {
		sourceFile.Close()
		t.Fatal(err)
	}
	if err := sourceFile.Close(); err != nil {
		t.Fatal(err)
	}
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err = extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err == nil || !contains(err.Error(), "stage=source-image-identity") {
		t.Fatalf("expected explicit source identity failure, got %v", err)
	}
	if _, statErr := os.Lstat(outputDirectory); !os.IsNotExist(statErr) {
		t.Fatalf("tampered C42 source must not create a published output: %v", statErr)
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionAcceptsCompleteC73ReceiptBoundToRawSource(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64.raw")
	createWholeDiskExt4GuestLinuxSourceImage(t, sourceImagePath, true, gzipCompressedBytes(t, []byte("uncompressed-linux-arm64-kernel-image")))
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	materializationReceiptPath := filepath.Join(temporaryRoot, "guest-linux-source-disk-materialization-receipt.json")
	writeC73MaterializationReceipt(t, materializationReceiptPath, declared.SourceImage)
	declared.SourceImage.SourceMaterialization = &declaration.DeclaredGuestLinuxSourceDiskMaterialization{
		ReceiptAbsolutePath: materializationReceiptPath,
		ReceiptSHA256:       sha256ForRegularFile(t, materializationReceiptPath),
		MaterializationID:   "ubuntu-noble-arm64-qcow2-to-raw",
	}
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err != nil {
		t.Fatalf("extract C42 with complete C73 receipt: %v", err)
	}
	if _, err := os.Stat(filepath.Join(outputDirectory, "guest-linux-boot-artifact-extraction-receipt.json")); err != nil {
		t.Fatalf("C42 did not publish receipt after validating C73 materialization: %v", err)
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionRejectsMissingDeclaredInitialRamdiskBeforePublishing(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64.img")
	createWholeDiskExt4GuestLinuxSourceImage(t, sourceImagePath, false, gzipCompressedBytes(t, []byte("uncompressed-linux-arm64-kernel-image")))
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err == nil || !contains(err.Error(), "stage=boot-resource-extract") || !contains(err.Error(), "/boot/initrd.img") {
		t.Fatalf("expected explicit missing-initrd failure, got %v", err)
	}
	if _, statErr := os.Lstat(outputDirectory); !os.IsNotExist(statErr) {
		t.Fatalf("missing C42 boot resource must not publish output: %v", statErr)
	}
}

func TestExecuteGuestLinuxBootArtifactExtractionRejectsMalformedCompressedKernelBeforePublishing(t *testing.T) {
	temporaryRoot := t.TempDir()
	sourceImagePath := filepath.Join(temporaryRoot, "ubuntu-noble-arm64.img")
	createWholeDiskExt4GuestLinuxSourceImage(t, sourceImagePath, true, []byte("not-a-gzip-linux-kernel"))
	declared := declaredGuestLinuxBootArtifactExtraction(t, sourceImagePath)
	declarationPath := filepath.Join(temporaryRoot, "guest-linux-boot-artifact-extraction-declaration.json")
	writeJSON(t, declarationPath, declared)
	outputDirectory := filepath.Join(temporaryRoot, "extracted-boot-artifacts")

	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: declarationPath,
		OutputDirectory: outputDirectory,
	})
	if err == nil || !contains(err.Error(), "stage=boot-resource-extract") || !contains(err.Error(), "not valid gzip") {
		t.Fatalf("expected explicit compressed-kernel failure, got %v", err)
	}
	if _, statErr := os.Lstat(outputDirectory); !os.IsNotExist(statErr) {
		t.Fatalf("malformed C42 compressed kernel must not publish output: %v", statErr)
	}
}

func createWholeDiskExt4GuestLinuxSourceImage(t *testing.T, imagePath string, withInitialRamdisk bool, compressedKernel []byte) {
	t.Helper()
	image, err := diskfs.Create(imagePath, 32*1024*1024, diskfs.SectorSize512)
	if err != nil {
		t.Fatal(err)
	}
	guestFilesystem, err := image.CreateFilesystem(disk.FilesystemSpec{Partition: 0, FSType: filesystem.TypeExt4})
	if err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := guestFilesystem.Mkdir("boot"); err != nil {
		image.Close()
		t.Fatal(err)
	}
	writeGuestRegularFile(t, guestFilesystem, "boot/vmlinuz", compressedKernel)
	if withInitialRamdisk {
		writeGuestRegularFile(t, guestFilesystem, "boot/initrd.img", []byte("initrd-bytes"))
	}
	if err := guestFilesystem.Close(); err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := image.Close(); err != nil {
		t.Fatal(err)
	}
}

func createPartitionedExt4GuestLinuxSourceImage(t *testing.T, imagePath string, compressedKernel []byte) {
	t.Helper()
	image, err := diskfs.Create(imagePath, 32*1024*1024, diskfs.SectorSize512)
	if err != nil {
		t.Fatal(err)
	}
	partition := &mbr.Partition{Index: 1, Start: 2048, Size: 60000, Type: mbr.Linux}
	if err := image.Partition(&mbr.Table{Partitions: []*mbr.Partition{partition}, LogicalSectorSize: 512}); err != nil {
		image.Close()
		t.Fatal(err)
	}
	guestFilesystem, err := image.CreateFilesystem(disk.FilesystemSpec{Partition: 1, FSType: filesystem.TypeExt4})
	if err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := guestFilesystem.Mkdir("boot"); err != nil {
		image.Close()
		t.Fatal(err)
	}
	writeGuestRegularFile(t, guestFilesystem, "boot/vmlinuz", compressedKernel)
	writeGuestRegularFile(t, guestFilesystem, "boot/initrd.img", []byte("partitioned-initrd-bytes"))
	if err := guestFilesystem.Close(); err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := image.Close(); err != nil {
		t.Fatal(err)
	}
}

func createPartitionedExt4GuestLinuxSourceImageWithoutBootResources(t *testing.T, imagePath string) {
	t.Helper()
	image, err := diskfs.Create(imagePath, 32*1024*1024, diskfs.SectorSize512)
	if err != nil {
		t.Fatal(err)
	}
	partition := &mbr.Partition{Index: 1, Start: 2048, Size: 60000, Type: mbr.Linux}
	if err := image.Partition(&mbr.Table{Partitions: []*mbr.Partition{partition}, LogicalSectorSize: 512}); err != nil {
		image.Close()
		t.Fatal(err)
	}
	guestFilesystem, err := image.CreateFilesystem(disk.FilesystemSpec{Partition: 1, FSType: filesystem.TypeExt4})
	if err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := guestFilesystem.Close(); err != nil {
		image.Close()
		t.Fatal(err)
	}
	if err := image.Close(); err != nil {
		t.Fatal(err)
	}
}

func writeGuestRegularFile(t *testing.T, guestFilesystem filesystem.FileSystem, guestPath string, contents []byte) {
	t.Helper()
	guestFile, err := guestFilesystem.OpenFile(guestPath, os.O_CREATE|os.O_RDWR)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := guestFile.Write(contents); err != nil {
		guestFile.Close()
		t.Fatal(err)
	}
	if err := guestFile.Close(); err != nil {
		t.Fatal(err)
	}
}

func declaredGuestLinuxBootArtifactExtraction(t *testing.T, sourceImagePath string) declaration.GuestLinuxBootArtifactExtractionDeclaration {
	t.Helper()
	info, err := os.Stat(sourceImagePath)
	if err != nil {
		t.Fatal(err)
	}
	return declaration.GuestLinuxBootArtifactExtractionDeclaration{
		SchemaVersion: "v1",
		ExtractionID:  "ubuntu-noble-arm64-boot-artifacts",
		Architecture:  "arm64",
		SourceImage: declaration.DeclaredGuestLinuxSourceImage{
			ID:                 "ubuntu-noble-arm64-cloud-image",
			SourceAbsolutePath: sourceImagePath,
			SourceOriginURI:    "https://cloud-images.example.test/ubuntu-noble-arm64.img",
			SourceRelease:      "ubuntu-24.04-noble-release",
			SizeBytes:          info.Size(),
			SHA256:             sha256ForRegularFile(t, sourceImagePath),
		},
		SourceFilesystem: declaration.DeclaredGuestSourceFilesystem{Layout: "whole-disk-ext4", FilesystemType: "ext4"},
		BootResources: declaration.DeclaredGuestLinuxBootResources{
			Kernel:         declaration.DeclaredGuestBootResource{ID: "linux-arm64-kernel", Source: declaration.DeclaredGuestBootResourceSource{Kind: "source-image-filesystem", GuestAbsolutePath: "/boot/vmlinuz"}, SourceCompression: "gzip", OutputRelativePath: "boot/Image", OutputFormat: "uncompressed-linux-arm64-image"},
			InitialRamdisk: declaration.DeclaredGuestBootResource{ID: "linux-arm64-initrd", Source: declaration.DeclaredGuestBootResourceSource{Kind: "source-image-filesystem", GuestAbsolutePath: "/boot/initrd.img"}, SourceCompression: "none", OutputRelativePath: "boot/initrd.img", OutputFormat: "cpio"},
		},
		RootStorage: declaration.DeclaredGuestLinuxRootStorage{ID: "linux-arm64-root-storage-base", GuestDevicePath: "/dev/vda", OutputRelativePath: "storage/guest-root.raw", FilesystemType: "ext4", StorageLayout: "whole-disk-ext4"},
	}
}

func declaredExternalBootResource(t *testing.T, sourcePath string) declaration.DeclaredGuestBootResourceSource {
	t.Helper()
	info, err := os.Stat(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	return declaration.DeclaredGuestBootResourceSource{
		Kind:               "external-artifact",
		SourceAbsolutePath: sourcePath,
		SourceOriginURI:    "https://cloud-images.example.test/ubuntu-arm64-generic",
		SourceRelease:      "ubuntu-24.04-noble-release",
		SizeBytes:          info.Size(),
		SHA256:             sha256ForRegularFile(t, sourcePath),
	}
}

func writeC73MaterializationReceipt(t *testing.T, destination string, source declaration.DeclaredGuestLinuxSourceImage) {
	t.Helper()
	writeJSON(t, destination, map[string]any{
		"schemaVersion":                    "v1",
		"documentKind":                     "guest-linux-source-disk-materialization-receipt",
		"materializationId":                "ubuntu-noble-arm64-qcow2-to-raw",
		"architecture":                     "arm64",
		"materializationDeclarationSha256": "c5b4ab16f4b6b703cbe3be17a43923b7f0e33eb5f0e97e0b768a1e8a6c1ca9b5",
		"sourceImage": map[string]any{
			"id":              "ubuntu-noble-arm64-qcow2",
			"sourceOriginUri": "https://cloud-images.example.test/ubuntu-noble-arm64.qcow2",
			"sourceRelease":   "ubuntu-24.04-noble-release",
			"sizeBytes":       4096,
			"sha256":          "4fb3c0ec11b7bf82e3f9fbe7ee7aab15a1c8486e5d67da4188919c1d0c3b60e8",
		},
		"sourceImageFormat": "qcow2",
		"rawImage": map[string]any{
			"id":           source.ID,
			"relativePath": "storage/ubuntu-noble-arm64.raw",
			"imageFormat":  "raw",
			"sizeBytes":    source.SizeBytes,
			"sha256":       source.SHA256,
		},
		"completedAt": "2026-07-20T00:00:00Z",
	})
}

func gzipCompressedBytes(t *testing.T, contents []byte) []byte {
	t.Helper()
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(contents); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}

func writeJSON(t *testing.T, path string, document any) {
	t.Helper()
	contents, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
}

func sha256ForRegularFile(t *testing.T, path string) string {
	t.Helper()
	contents := mustReadFile(t, path)
	sum := sha256.Sum256(contents)
	return hex.EncodeToString(sum[:])
}

func mustReadFile(t *testing.T, path string) []byte {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return contents
}

func contains(value, part string) bool {
	for index := 0; index+len(part) <= len(value); index++ {
		if value[index:index+len(part)] == part {
			return true
		}
	}
	return false
}
