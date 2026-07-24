// Package nocloudguestproductbootstrapvolumeadapter implements the one chosen
// C40 delivery artifact: a read-only RAW disk image whose one partition contains
// a NoCloud ISO9660 CIDATA volume. The Host attaches the RAW disk image, while
// cloud-init in the Guest owns the later root-filesystem change.
package nocloudguestproductbootstrapvolumeadapter

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/disk"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/filesystem/iso9660"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

const (
	iso9660LogicalBlockSize                = 2048
	noCloudVolumeFixedOverheadBytes int64  = 16 * 1024 * 1024
	rawDiskLogicalSectorBytes              = 512
	bootstrapPartitionStartSector   uint32 = 2048
	iso9660MBRPartitionType         byte   = 0xcd
	copyBufferBytes                        = 1 << 20
	// A YAML block scalar must be indented farther than the `content` key.
	// `content` is nested below one write_files item (four spaces), so its
	// Guest bootstrap script owns this six-space indentation contract.
	cloudInitWriteFileContentIndentation = "      "
)

// NoCloudGuestProductBootstrapVolumeAdapter is the selected C40 effect
// adapter. Its name says that it creates Guest-visible NoCloud data; the plan
// makes the Host-attachable RAW storage image and Guest-visible ISO9660
// filesystem explicit as separate concepts.
type NoCloudGuestProductBootstrapVolumeAdapter struct{}

// NewNoCloudGuestProductBootstrapVolumeAdapter selects a RAW storage image
// containing one ISO9660/CIDATA partition as the sole release-build delivery
// medium for this composer.
func NewNoCloudGuestProductBootstrapVolumeAdapter() NoCloudGuestProductBootstrapVolumeAdapter {
	return NoCloudGuestProductBootstrapVolumeAdapter{}
}

// ComposeDeclaredGuestProductBootstrapVolume verifies every C40 source,
// renders the Guest-owned cloud-init bootstrap script, and atomically publishes
// one new RAW storage image containing an ISO9660 CIDATA partition. A failure
// publishes no output volume.
func (NoCloudGuestProductBootstrapVolumeAdapter) ComposeDeclaredGuestProductBootstrapVolume(
	plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan,
	sourceRoot string,
	outputVolumePath string,
) error {
	sourcesByID, err := verifyDeclaredBootstrapSources(plan.Sources, sourceRoot)
	if err != nil {
		return err
	}
	if err := verifyDeclaredBootstrapArchive(plan, sourcesByID); err != nil {
		return err
	}
	userData, err := renderNoCloudUserData(plan)
	if err != nil {
		return err
	}
	metaData := []byte("instance-id: " + plan.InstanceID + "\nlocal-hostname: " + plan.LocalHostName + "\n")
	bootstrapManifest, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return fmt.Errorf("C40 bootstrap manifest cannot be encoded: %w", err)
	}
	bootstrapManifest = append(bootstrapManifest, '\n')

	temporaryDirectory, err := os.MkdirTemp(filepath.Dir(outputVolumePath), ".guest-product-bootstrap-volume.")
	if err != nil {
		return fmt.Errorf("C40 output staging directory cannot be created: %w", err)
	}
	defer os.RemoveAll(temporaryDirectory)
	temporaryISO9660FilesystemPath := filepath.Join(temporaryDirectory, "guest-product-bootstrap.iso9660")
	if err := composeNoCloudISO9660Volume(
		temporaryISO9660FilesystemPath,
		plan,
		sourcesByID,
		map[string][]byte{
			"meta-data":                           metaData,
			"user-data":                           userData,
			"vitalserver-bootstrap-manifest.json": bootstrapManifest,
		},
	); err != nil {
		return err
	}
	temporaryRawStorageImagePath := filepath.Join(temporaryDirectory, "guest-product-bootstrap.raw")
	if err := composeRawStorageImageContainingISO9660Partition(temporaryISO9660FilesystemPath, temporaryRawStorageImagePath); err != nil {
		return err
	}
	if err := os.Rename(temporaryRawStorageImagePath, outputVolumePath); err != nil {
		return fmt.Errorf("C40 output volume cannot be published: %w", err)
	}
	return nil
}

// composeRawStorageImageContainingISO9660Partition creates the Host-facing
// disk-image container around the Guest-facing CIDATA filesystem. Apple
// Virtualization opens RAW disk images, while cloud-init discovers the
// ISO9660 filesystem through the Guest partition device. Neither side has to
// infer the other side's format.
func composeRawStorageImageContainingISO9660Partition(iso9660FilesystemPath string, rawStorageImagePath string) error {
	iso9660Info, err := os.Stat(iso9660FilesystemPath)
	if err != nil {
		return fmt.Errorf("C40 ISO9660 filesystem cannot be stated: %w", err)
	}
	if !iso9660Info.Mode().IsRegular() || iso9660Info.Size() < 1 {
		return fmt.Errorf("C40 ISO9660 filesystem must be a non-empty regular file")
	}
	partitionSectorCount := (iso9660Info.Size() + rawDiskLogicalSectorBytes - 1) / rawDiskLogicalSectorBytes
	if partitionSectorCount > int64(^uint32(0)) {
		return fmt.Errorf("C40 ISO9660 filesystem exceeds the MBR partition size limit")
	}
	diskSectorCount := int64(bootstrapPartitionStartSector) + partitionSectorCount
	if diskSectorCount > int64(^uint32(0)) {
		return fmt.Errorf("C40 RAW storage image exceeds the MBR disk size limit")
	}
	rawStorageImage, err := os.OpenFile(rawStorageImagePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("C40 RAW storage image cannot be created: %w", err)
	}
	closeRawStorageImage := func() error { return rawStorageImage.Close() }
	if err := rawStorageImage.Truncate(diskSectorCount * rawDiskLogicalSectorBytes); err != nil {
		closeRawStorageImage()
		return fmt.Errorf("C40 RAW storage image cannot be sized: %w", err)
	}
	if err := writeMBRPartitionTable(rawStorageImage, uint32(partitionSectorCount)); err != nil {
		closeRawStorageImage()
		return err
	}
	if _, err := rawStorageImage.Seek(int64(bootstrapPartitionStartSector)*rawDiskLogicalSectorBytes, io.SeekStart); err != nil {
		closeRawStorageImage()
		return fmt.Errorf("C40 RAW storage image cannot seek to bootstrap partition: %w", err)
	}
	iso9660Filesystem, err := os.Open(iso9660FilesystemPath)
	if err != nil {
		closeRawStorageImage()
		return fmt.Errorf("C40 ISO9660 filesystem cannot be opened: %w", err)
	}
	_, copyError := io.CopyBuffer(rawStorageImage, iso9660Filesystem, make([]byte, copyBufferBytes))
	iso9660CloseError := iso9660Filesystem.Close()
	if copyError != nil || iso9660CloseError != nil {
		closeRawStorageImage()
		return fmt.Errorf("C40 ISO9660 filesystem cannot be copied into RAW storage image")
	}
	if err := rawStorageImage.Sync(); err != nil {
		closeRawStorageImage()
		return fmt.Errorf("C40 RAW storage image cannot be synchronized: %w", err)
	}
	if err := closeRawStorageImage(); err != nil {
		return fmt.Errorf("C40 RAW storage image cannot be closed: %w", err)
	}
	return nil
}

func writeMBRPartitionTable(rawStorageImage *os.File, partitionSectorCount uint32) error {
	mbr := make([]byte, rawDiskLogicalSectorBytes)
	partitionEntry := mbr[446 : 446+16]
	partitionEntry[0] = 0x00
	partitionEntry[1], partitionEntry[2], partitionEntry[3] = 0xfe, 0xff, 0xff
	partitionEntry[4] = iso9660MBRPartitionType
	partitionEntry[5], partitionEntry[6], partitionEntry[7] = 0xfe, 0xff, 0xff
	binary.LittleEndian.PutUint32(partitionEntry[8:12], bootstrapPartitionStartSector)
	binary.LittleEndian.PutUint32(partitionEntry[12:16], partitionSectorCount)
	mbr[510], mbr[511] = 0x55, 0xaa
	if _, err := rawStorageImage.WriteAt(mbr, 0); err != nil {
		return fmt.Errorf("C40 RAW storage image MBR cannot be written: %w", err)
	}
	return nil
}

type verifiedBootstrapSource struct {
	declaration guestproductbootstrapvolumeplan.DeclaredBootstrapSource
	path        string
}

func verifyDeclaredBootstrapSources(
	sources []guestproductbootstrapvolumeplan.DeclaredBootstrapSource,
	sourceRoot string,
) (map[string]verifiedBootstrapSource, error) {
	verified := make(map[string]verifiedBootstrapSource, len(sources))
	for _, source := range sources {
		sourcePath, err := resolveDeclaredBootstrapSourcePath(sourceRoot, source.SourceRelativePath)
		if err != nil {
			return nil, fmt.Errorf("C40 source %s: %w", source.ID, err)
		}
		info, err := os.Lstat(sourcePath)
		if err != nil {
			return nil, fmt.Errorf("C40 source %s cannot be stated: %w", source.ID, err)
		}
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("C40 source %s must be a regular non-symlink file", source.ID)
		}
		if info.Size() != source.SizeBytes {
			return nil, fmt.Errorf("C40 source %s has size %d, expected %d", source.ID, info.Size(), source.SizeBytes)
		}
		digest, err := sha256ForRegularFile(sourcePath)
		if err != nil {
			return nil, fmt.Errorf("C40 source %s cannot be hashed: %w", source.ID, err)
		}
		if digest != source.SHA256 {
			return nil, fmt.Errorf("C40 source %s sha256 differs from its declaration", source.ID)
		}
		verified[source.ID] = verifiedBootstrapSource{declaration: source, path: sourcePath}
	}
	return verified, nil
}

func resolveDeclaredBootstrapSourcePath(sourceRoot string, sourceRelativePath string) (string, error) {
	if !guestproductbootstrapvolumeplan.IsSafeSourceRelativePath(sourceRelativePath) {
		return "", fmt.Errorf("unsafe sourceRelativePath")
	}
	resolved := filepath.Join(sourceRoot, filepath.FromSlash(sourceRelativePath))
	relative, err := filepath.Rel(sourceRoot, resolved)
	if err != nil || relative == "." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) || relative == ".." {
		return "", fmt.Errorf("sourceRelativePath escapes source root")
	}
	return resolved, nil
}

func verifyDeclaredBootstrapArchive(
	plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan,
	sources map[string]verifiedBootstrapSource,
) error {
	for _, installation := range plan.ArchiveInstallations {
		source := sources[installation.SourceID]
		file, err := os.Open(source.path)
		if err != nil {
			return fmt.Errorf("C40 archive source %s cannot be opened: %w", installation.SourceID, err)
		}
		gzipReader, gzipError := gzip.NewReader(file)
		if gzipError != nil {
			file.Close()
			return fmt.Errorf("C40 archive source %s is not readable tar-gzip: %w", installation.SourceID, gzipError)
		}
		archiveError := validateDeclaredTarGzipContents(
			tar.NewReader(gzipReader),
			installation.RequiredArchivePaths,
			installation.SymbolicLinkPolicy,
		)
		gzipCloseError := gzipReader.Close()
		fileCloseError := file.Close()
		if archiveError != nil {
			return fmt.Errorf("C40 archive source %s: %w", installation.SourceID, archiveError)
		}
		if gzipCloseError != nil || fileCloseError != nil {
			return fmt.Errorf("C40 archive source %s cannot be closed", installation.SourceID)
		}
	}
	return nil
}

// declaredTarGzipSymbolicLink retains the resolved target after all archive
// entries have been read. The target cannot be validated while streaming,
// because a permitted regular-file target may appear later in the archive.
type declaredTarGzipSymbolicLink struct {
	archivePath string
	targetPath  string
}

// validateDeclaredTarGzipContents verifies the archive semantics selected by
// C39 and carried by C40. The adapter accepts only relative links whose fully
// resolved target is a regular file declared in this archive. This is narrower
// than accepting generic tar links and prevents an archive from naming Host or
// Guest paths outside its own delivery namespace.
func validateDeclaredTarGzipContents(
	reader *tar.Reader,
	requiredPaths []string,
	symbolicLinkPolicy string,
) error {
	if symbolicLinkPolicy != guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy {
		return fmt.Errorf("tar symbolic link policy %q is not supported", symbolicLinkPolicy)
	}
	required := make(map[string]struct{}, len(requiredPaths))
	for _, requiredPath := range requiredPaths {
		required[requiredPath] = struct{}{}
	}
	declaredArchivePaths := make(map[string]struct{})
	declaredRegularFilePaths := make(map[string]struct{})
	declaredSymbolicLinks := make([]declaredTarGzipSymbolicLink, 0)
	for {
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("tar entries cannot be read: %w", err)
		}
		archivePath, archivePathError := normalizeDeclaredTarGzipEntryPath(header.Name)
		if archivePathError != nil {
			return archivePathError
		}
		if _, alreadyDeclared := declaredArchivePaths[archivePath]; alreadyDeclared {
			return fmt.Errorf("tar contains duplicate entry %q", archivePath)
		}
		declaredArchivePaths[archivePath] = struct{}{}
		switch header.Typeflag {
		case tar.TypeReg, tar.TypeRegA:
			declaredRegularFilePaths[archivePath] = struct{}{}
		case tar.TypeDir:
		case tar.TypeSymlink:
			targetPath, targetPathError := resolveRelativeTarGzipSymbolicLinkTarget(archivePath, header.Linkname)
			if targetPathError != nil {
				return fmt.Errorf("tar symbolic link %q: %w", archivePath, targetPathError)
			}
			declaredSymbolicLinks = append(declaredSymbolicLinks, declaredTarGzipSymbolicLink{
				archivePath: archivePath,
				targetPath:  targetPath,
			})
		default:
			return fmt.Errorf("tar contains unsupported entry type for %q", header.Name)
		}
		delete(required, archivePath)
	}
	for _, symbolicLink := range declaredSymbolicLinks {
		if _, targetIsDeclaredRegularFile := declaredRegularFilePaths[symbolicLink.targetPath]; !targetIsDeclaredRegularFile {
			return fmt.Errorf("tar symbolic link %q target %q does not name a declared regular file", symbolicLink.archivePath, symbolicLink.targetPath)
		}
	}
	if len(required) != 0 {
		missing := make([]string, 0, len(required))
		for requiredPath := range required {
			missing = append(missing, requiredPath)
		}
		sort.Strings(missing)
		return fmt.Errorf("tar lacks required paths %s", strings.Join(missing, ","))
	}
	return nil
}

func normalizeDeclaredTarGzipEntryPath(rawArchivePath string) (string, error) {
	archivePath := strings.TrimSuffix(rawArchivePath, "/")
	if archivePath == "" || path.Clean(archivePath) != archivePath || strings.HasPrefix(archivePath, "/") || strings.HasPrefix(archivePath, "../") {
		return "", fmt.Errorf("tar contains unsafe entry %q", rawArchivePath)
	}
	return archivePath, nil
}

func resolveRelativeTarGzipSymbolicLinkTarget(archivePath string, rawTargetPath string) (string, error) {
	if rawTargetPath == "" {
		return "", fmt.Errorf("target is empty")
	}
	if strings.HasPrefix(rawTargetPath, "/") {
		return "", fmt.Errorf("target %q is absolute", rawTargetPath)
	}
	resolvedTargetPath := path.Clean(path.Join(path.Dir(archivePath), rawTargetPath))
	if resolvedTargetPath == "." || resolvedTargetPath == ".." || strings.HasPrefix(resolvedTargetPath, "../") || strings.HasPrefix(resolvedTargetPath, "/") {
		return "", fmt.Errorf("target %q escapes archive root", rawTargetPath)
	}
	return resolvedTargetPath, nil
}

func composeNoCloudISO9660Volume(
	outputPath string,
	plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan,
	sources map[string]verifiedBootstrapSource,
	controlFiles map[string][]byte,
) error {
	volumeSize := noCloudVolumeFixedOverheadBytes
	for _, source := range sources {
		volumeSize += source.declaration.SizeBytes
	}
	for _, contents := range controlFiles {
		volumeSize += int64(len(contents))
	}
	volume, err := diskfs.Create(outputPath, volumeSize, diskfs.SectorSizeDefault)
	if err != nil {
		return fmt.Errorf("C40 ISO9660 output cannot be created: %w", err)
	}
	defer volume.Close()
	volume.LogicalBlocksize = iso9660LogicalBlockSize
	filesystemValue, err := volume.CreateFilesystem(disk.FilesystemSpec{Partition: 0, FSType: filesystem.TypeISO9660})
	if err != nil {
		return fmt.Errorf("C40 ISO9660 filesystem cannot be created: %w", err)
	}
	isoFilesystem, ok := filesystemValue.(*iso9660.FileSystem)
	if !ok {
		return fmt.Errorf("C40 ISO9660 filesystem has unexpected adapter type %T", filesystemValue)
	}
	defer isoFilesystem.Close()
	if err := isoFilesystem.Mkdir("payload"); err != nil {
		return fmt.Errorf("C40 ISO9660 payload directory cannot be created: %w", err)
	}
	for filePath, contents := range controlFiles {
		if err := writeNoCloudVolumeBytes(isoFilesystem, filePath, contents); err != nil {
			return fmt.Errorf("C40 ISO9660 control file %s: %w", filePath, err)
		}
	}
	sourceIDs := make([]string, 0, len(sources))
	for sourceID := range sources {
		sourceIDs = append(sourceIDs, sourceID)
	}
	sort.Strings(sourceIDs)
	for _, sourceID := range sourceIDs {
		if err := writeNoCloudVolumeSource(isoFilesystem, "payload/"+sourceID, sources[sourceID].path); err != nil {
			return fmt.Errorf("C40 ISO9660 payload source %s: %w", sourceID, err)
		}
	}
	if err := isoFilesystem.Finalize(iso9660.FinalizeOptions{RockRidge: true, VolumeIdentifier: plan.VolumeLabel}); err != nil {
		return fmt.Errorf("C40 ISO9660 output cannot be finalized: %w", err)
	}
	return nil
}

func writeNoCloudVolumeBytes(isoFilesystem *iso9660.FileSystem, volumePath string, contents []byte) error {
	file, err := isoFilesystem.OpenFile(volumePath, os.O_CREATE|os.O_RDWR)
	if err != nil {
		return err
	}
	_, writeError := file.Write(contents)
	closeError := file.Close()
	if writeError != nil {
		return writeError
	}
	if closeError != nil {
		return closeError
	}
	return nil
}

func writeNoCloudVolumeSource(isoFilesystem *iso9660.FileSystem, volumePath string, sourcePath string) error {
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()
	destination, err := isoFilesystem.OpenFile(volumePath, os.O_CREATE|os.O_RDWR)
	if err != nil {
		return err
	}
	written, copyError := io.CopyBuffer(destination, source, make([]byte, copyBufferBytes))
	destinationCloseError := destination.Close()
	if copyError != nil {
		return copyError
	}
	if destinationCloseError != nil {
		return destinationCloseError
	}
	if written < 1 {
		return fmt.Errorf("source copied zero bytes")
	}
	return nil
}

func renderNoCloudUserData(plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan) ([]byte, error) {
	script, err := renderGuestOwnedBootstrapScript(plan)
	if err != nil {
		return nil, err
	}
	cloudInitWriteFileContent := indentGuestBootstrapScriptForCloudInitWriteFile(script)
	return []byte("#cloud-config\nwrite_files:\n  - path: /usr/local/lib/vitalserver/bootstrap-product-from-nocloud-volume\n    permissions: '0755'\n    owner: root:root\n    content: |\n" + cloudInitWriteFileContent + "\nruncmd:\n  - [ /usr/local/lib/vitalserver/bootstrap-product-from-nocloud-volume ]\n"), nil
}

// indentGuestBootstrapScriptForCloudInitWriteFile preserves the distinction
// between the Guest-owned shell program and the Host release builder's YAML
// representation. Cloud-init owns parsing this document; the builder must
// publish it as a valid YAML block scalar rather than relying on cloud-init to
// recover a malformed configuration.
func indentGuestBootstrapScriptForCloudInitWriteFile(script string) string {
	trimmedScript := strings.TrimSuffix(script, "\n")
	return cloudInitWriteFileContentIndentation + strings.ReplaceAll(trimmedScript, "\n", "\n"+cloudInitWriteFileContentIndentation)
}

func renderGuestOwnedBootstrapScript(plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan) (string, error) {
	var script strings.Builder
	script.WriteString("#!/usr/bin/env bash\nset -euo pipefail\n")
	script.WriteString("bootstrap_volume=/dev/disk/by-label/" + plan.VolumeLabel + "\n")
	script.WriteString("[ -b \"$bootstrap_volume\" ]\n")
	script.WriteString("mount_root=/run/vitalserver-bootstrap-volume\nmkdir -p \"$mount_root\"\nmount -o ro \"$bootstrap_volume\" \"$mount_root\"\ncleanup() { umount \"$mount_root\"; rmdir \"$mount_root\"; }\ntrap cleanup EXIT\n")
	// Source declaration order is not semantic. The generated first-boot
	// program must therefore have one canonical order for repeatable output.
	sources := append([]guestproductbootstrapvolumeplan.DeclaredBootstrapSource(nil), plan.Sources...)
	sort.Slice(sources, func(left, right int) bool { return sources[left].ID < sources[right].ID })
	for _, source := range sources {
		payloadPath := "payload/" + source.ID
		script.WriteString("[ \"$(wc -c < \"$mount_root/" + payloadPath + "\")\" -eq " + fmt.Sprintf("%d", source.SizeBytes) + " ]\n")
		script.WriteString("printf '%s  %s\\n' '" + source.SHA256 + "' \"$mount_root/" + payloadPath + "\" | sha256sum -c -\n")
	}
	recorderCatalog := plan.GuestRecorderCatalogPostgreSQL
	script.WriteString(
		"export DEBIAN_FRONTEND=noninteractive\napt-get update\napt-get install --yes --no-install-recommends " +
			strings.Join(recorderCatalog.PackageNames, " ") +
			"\nsystemctl enable " + recorderCatalog.ServiceName +
			"\nsystemctl start " + recorderCatalog.ServiceName + "\n",
	)
	if plan.GuestTimeSynchronization != nil {
		// The plan validator accepts exactly the selected apt/chrony/systemd
		// tuple. This Guest-owned effect still fails closed if package retrieval
		// or installation fails; it never falls back to an image-provided clock
		// daemon whose owner or source was not declared.
		script.WriteString("export DEBIAN_FRONTEND=noninteractive\napt-get update\napt-get install --yes --no-install-recommends chrony\n")
	}
	for _, installation := range plan.FileInstallations {
		script.WriteString("install -D -m " + installation.FileMode + " \"$mount_root/payload/" + installation.SourceID + "\" \"" + installation.DestinationPath + "\"\n")
	}
	for _, installation := range plan.ArchiveInstallations {
		script.WriteString("mkdir -p \"" + installation.DestinationDirectory + "\"\ntar -xzf \"$mount_root/payload/" + installation.SourceID + "\" --no-same-owner --no-same-permissions -C \"" + installation.DestinationDirectory + "\"\n")
	}
	// Initial release activation is deliberately narrower than a future update:
	// bootstrap may create the current link when absent, or prove an idempotent
	// retry already points to this exact release. It never retargets a link that
	// names another release; that transition belongs to the Guest Product Release
	// Manager and requires its own durable update journal.
	release := plan.GuestProductRelease
	script.WriteString("install -d -m " + release.ReleaseStateDirectoryMode + " \"" + release.ReleaseStateDirectory + "\"\n")
	script.WriteString("[ -d \"" + release.ReleaseDirectory + "\" ]\n")
	script.WriteString("if [ -e \"" + release.CurrentReleaseLinkPath + "\" ] || [ -L \"" + release.CurrentReleaseLinkPath + "\" ]; then\n  [ -L \"" + release.CurrentReleaseLinkPath + "\" ]\n  [ \"$(readlink -f \"" + release.CurrentReleaseLinkPath + "\")\" = \"" + release.ReleaseDirectory + "\" ]\nelse\n  mkdir -p \"$(dirname \"" + release.CurrentReleaseLinkPath + "\")\"\n  ln -s \"" + release.ReleaseDirectory + "\" \"" + release.CurrentReleaseLinkPath + "\"\nfi\n")
	for _, symbolicLink := range plan.SymbolicLinks {
		script.WriteString("mkdir -p \"$(dirname \"" + symbolicLink.LinkPath + "\")\"\nln -sfn \"" + symbolicLink.TargetPath + "\" \"" + symbolicLink.LinkPath + "\"\n")
	}
	// C39 declares this state root; creating it is a Guest bootstrap effect.
	// The Guest Runtime remains the state owner and will separately report any
	// database initialization failure rather than treating this declaration as
	// readiness evidence.
	script.WriteString("install -d -m " + plan.GuestRuntimeStateDirectory.DirectoryMode + " \"" + plan.GuestRuntimeStateDirectory.DirectoryPath + "\"\n")
	script.WriteString("install -d -m " + plan.GuestPrivateStateDirectory.DirectoryMode + " \"" + plan.GuestPrivateStateDirectory.DirectoryPath + "\"\n")
	script.WriteString("install -d -m " + plan.GuestArchiveArtifactObjectDirectory.DirectoryMode + " \"" + plan.GuestArchiveArtifactObjectDirectory.DirectoryPath + "\"\n")
	script.WriteString("umask 077\n")
	script.WriteString("database_password=\"$(od -An -N " + fmt.Sprintf("%d", recorderCatalog.GeneratedSecretByteCount) + " -tx1 /dev/urandom | tr -d ' \\n')\"\n")
	script.WriteString("[ \"${#database_password}\" -eq " + fmt.Sprintf("%d", recorderCatalog.GeneratedSecretByteCount*2) + " ]\n")
	script.WriteString("runuser -u postgres -- psql --dbname postgres --set ON_ERROR_STOP=1 --command \"DO \\$\\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '" + recorderCatalog.DatabaseRoleName + "') THEN CREATE ROLE " + recorderCatalog.DatabaseRoleName + " LOGIN; END IF; END \\$\\$;\"\n")
	script.WriteString("runuser -u postgres -- psql --dbname postgres --set ON_ERROR_STOP=1 --command \"ALTER ROLE " + recorderCatalog.DatabaseRoleName + " WITH LOGIN PASSWORD '$database_password';\"\n")
	script.WriteString("if ! runuser -u postgres -- psql --dbname postgres --tuples-only --no-align --command \"SELECT 1 FROM pg_database WHERE datname = '" + recorderCatalog.DatabaseName + "'\" | grep -qx 1; then\n")
	script.WriteString("  runuser -u postgres -- createdb --owner " + recorderCatalog.DatabaseRoleName + " " + recorderCatalog.DatabaseName + "\nfi\n")
	script.WriteString("database_url_temporary=\"$(mktemp \"" + plan.GuestPrivateStateDirectory.DirectoryPath + "/.recorder-catalog-database-url.XXXXXX\")\"\n")
	script.WriteString("printf '%s' \"postgresql://" + recorderCatalog.DatabaseRoleName + ":${database_password}@" + recorderCatalog.DatabaseHost + ":" + fmt.Sprintf("%d", recorderCatalog.DatabasePort) + "/" + recorderCatalog.DatabaseName + "?sslmode=disable\" > \"$database_url_temporary\"\n")
	script.WriteString("chmod 0600 \"$database_url_temporary\"\nmv -f \"$database_url_temporary\" \"" + recorderCatalog.DatabaseURLMaterialPath + "\"\n")
	for _, tokenPath := range []string{
		recorderCatalog.CatalogAdmissionBearerTokenMaterialPath,
		recorderCatalog.ArchiveSourceAdmissionBearerTokenMaterialPath,
	} {
		script.WriteString("token_temporary=\"$(mktemp \"" + plan.GuestPrivateStateDirectory.DirectoryPath + "/.internal-bearer-token.XXXXXX\")\"\n")
		script.WriteString("od -An -N " + fmt.Sprintf("%d", recorderCatalog.GeneratedSecretByteCount) + " -tx1 /dev/urandom | tr -d ' \\n' > \"$token_temporary\"\n")
		script.WriteString("[ \"$(wc -c < \"$token_temporary\")\" -eq " + fmt.Sprintf("%d", recorderCatalog.GeneratedSecretByteCount*2) + " ]\n")
		script.WriteString("chmod 0600 \"$token_temporary\"\nmv -f \"$token_temporary\" \"" + tokenPath + "\"\n")
	}
	script.WriteString("migration_receipt_temporary=\"$(mktemp \"" + plan.GuestPrivateStateDirectory.DirectoryPath + "/.recorder-catalog-migration-receipt.XXXXXX\")\"\n")
	script.WriteString("\"" + recorderCatalog.MigrationExecutablePath + "\" --process-role=recorder-catalog-migrator --migration-python-executable=\"" + recorderCatalog.MigrationPythonExecutablePath + "\" --recorder-catalog-database-url-material-path=\"" + recorderCatalog.DatabaseURLMaterialPath + "\" > \"$migration_receipt_temporary\"\n")
	script.WriteString("grep -Fq '\"state\":\"succeeded\"' \"$migration_receipt_temporary\"\ngrep -Fq '\"revision\":\"" + recorderCatalog.ExpectedRevision + "\"' \"$migration_receipt_temporary\"\n")
	script.WriteString("chmod 0600 \"$migration_receipt_temporary\"\nmv -f \"$migration_receipt_temporary\" \"" + recorderCatalog.MigrationReceiptPath + "\"\n")
	if plan.GuestTelemetryStateDirectory != nil {
		// The Collector owns this store. Cloud-init prepares only the declared
		// directory; it does not treat creation as Collector readiness.
		script.WriteString("install -d -m " + plan.GuestTelemetryStateDirectory.DirectoryMode + " \"" + plan.GuestTelemetryStateDirectory.DirectoryPath + "\"\n")
	}
	if manager := plan.GuestBundledUpstreamImageSetManager; manager != nil {
		// C64 owns image-set state. The bootstrap only prepares its declared
		// state root and invokes the manager's one-shot, exclusive initializer.
		// It does not call Docker, inspect container state, or infer a selected
		// image set from a missing state document.
		script.WriteString("export DEBIAN_FRONTEND=noninteractive\napt-get update\napt-get install --yes --no-install-recommends " + manager.ContainerEngineBootstrap.PackageName + "\nsystemctl enable " + manager.ContainerEngineBootstrap.ServiceName + "\nsystemctl start " + manager.ContainerEngineBootstrap.ServiceName + "\n")
		script.WriteString("install -d -m " + manager.StateDirectory.DirectoryMode + " \"" + manager.StateDirectory.DirectoryPath + "\"\n")
		script.WriteString("\"" + manager.ExecutablePath + "\" --configuration \"" + manager.ConfigurationPath + "\" --mode initialize-active-image-set\n")
	}
	if plan.GuestTimeSynchronization != nil {
		script.WriteString("systemctl enable chrony.service\nsystemctl restart chrony.service\n")
	}
	script.WriteString("systemctl daemon-reload\n")
	if manager := plan.GuestBundledUpstreamImageSetManager; manager != nil {
		script.WriteString("systemctl enable " + manager.ServiceUnitName + "\nsystemctl start " + manager.ServiceUnitName + "\n")
	}
	script.WriteString("systemctl enable " + plan.ServiceUnitName + "\nsystemctl start " + plan.ServiceUnitName + "\n")
	script.WriteString("install -D -m 0644 /dev/null /var/lib/vitalserver/bootstrap-completed\nprintf '%s\\n' '" + plan.BootstrapID + "' > /var/lib/vitalserver/bootstrap-completed\n")
	return script.String(), nil
}

func sha256ForRegularFile(sourcePath string) (string, error) {
	file, err := os.Open(sourcePath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.CopyBuffer(digest, file, make([]byte, copyBufferBytes)); err != nil {
		return "", err
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

var _ guestproductbootstrapvolumeapplication.GuestProductBootstrapVolumeCompositionEffect = NoCloudGuestProductBootstrapVolumeAdapter{}
