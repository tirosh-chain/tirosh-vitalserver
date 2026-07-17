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
			Kernel:         declaration.DeclaredGuestBootResource{ID: "linux-arm64-kernel", GuestAbsolutePath: "/boot/vmlinuz", SourceCompression: "gzip", OutputRelativePath: "boot/Image", OutputFormat: "uncompressed-linux-arm64-image"},
			InitialRamdisk: declaration.DeclaredGuestBootResource{ID: "linux-arm64-initrd", GuestAbsolutePath: "/boot/initrd.img", SourceCompression: "none", OutputRelativePath: "boot/initrd.img", OutputFormat: "cpio"},
		},
		RootStorage: declaration.DeclaredGuestLinuxRootStorage{ID: "linux-arm64-root-storage-base", GuestDevicePath: "/dev/vda", OutputRelativePath: "storage/guest-root.raw", FilesystemType: "ext4", StorageLayout: "whole-disk-ext4"},
	}
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
