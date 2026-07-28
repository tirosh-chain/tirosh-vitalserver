// Package hostplatformreleasearchivecomposition owns release-process-only
// construction of a rigid C68 archive. It has no Host runtime state or
// activation responsibility.
package hostplatformreleasearchivecomposition

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	hostPlatformReleaseArchiveMediaType = "application/vnd.tirosh.vitalserver.host-platform-release+tar+gzip"
	maximumCompositionBytes             = 1 << 20
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type ComposeHostPlatformReleaseArchiveRequest struct {
	CompositionPath   string
	OutputArchivePath string
}

type HostPlatformReleaseArchive struct {
	ArchivePath string `json:"archivePath"`
	SHA256      string `json:"sha256"`
	SizeBytes   int64  `json:"sizeBytes"`
	MediaType   string `json:"mediaType"`
}

// HostPlatformReleaseArchiveComposition is an intentionally local release
// selection. None of its source paths crosses the C25/C26/C67 boundary.
type HostPlatformReleaseArchiveComposition struct {
	SchemaVersion                        string                      `json:"schemaVersion"`
	ReleaseSourceDirectory               string                      `json:"releaseSourceDirectory"`
	ServiceDefinitionSources             []HostPlatformServiceSource `json:"serviceDefinitionSources"`
	OperatorInterfaceBootstrapSourcePath string                      `json:"operatorInterfaceBootstrapSourcePath"`
}
type HostPlatformServiceSource struct {
	Role       string `json:"role"`
	SourcePath string `json:"sourcePath"`
}

type installationManifest struct {
	SchemaVersion  string `json:"schemaVersion"`
	InstallationID string `json:"installationId"`
	Platform       string `json:"platform"`
	Release        struct {
		ID             string `json:"id"`
		ProductVersion string `json:"productVersion"`
		RuntimeVersion string `json:"runtimeVersion"`
	} `json:"release"`
	Package struct {
		Identifier     string `json:"identifier"`
		ProductVersion string `json:"productVersion"`
	} `json:"package"`
	ImmutablePayload struct {
		ReleaseCatalogPath string           `json:"releaseCatalogPath"`
		ReleaseRootPath    string           `json:"releaseRootPath"`
		ManifestPath       string           `json:"manifestPath"`
		Entries            []immutableEntry `json:"entries"`
	} `json:"immutablePayload"`
	Activation struct {
		CurrentReleaseLinkPath  string `json:"currentReleaseLinkPath"`
		ReferenceKind           string `json:"referenceKind"`
		ExpectedReleaseRootPath string `json:"expectedReleaseRootPath"`
	} `json:"activation"`
	OperatorInterface struct {
		BootstrapConfigurationPath   string `json:"bootstrapConfigurationPath"`
		BootstrapConfigurationSHA256 string `json:"bootstrapConfigurationSha256"`
	} `json:"operatorInterface"`
	RequiredServices []requiredService `json:"requiredServices"`
	MutableStores    []struct {
		ID        string `json:"id"`
		Path      string `json:"path"`
		Kind      string `json:"kind"`
		Owner     string `json:"owner"`
		Retention string `json:"retention"`
	} `json:"mutableStores"`
}
type immutableEntry struct {
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	Executable   bool   `json:"executable"`
}
type requiredService struct {
	Role             string `json:"role"`
	Manager          string `json:"manager"`
	Name             string `json:"name"`
	DefinitionPath   string `json:"definitionPath"`
	DefinitionSHA256 string `json:"definitionSha256"`
}
type archiveEntry struct {
	Name       string
	SourcePath string
	Mode       int64
}

// ComposeHostPlatformReleaseArchive validates a complete explicit source
// selection, then atomically writes a new deterministic C68 archive. The
// manager validates C48 again at runtime; this tool prevents release
// selection mistakes from becoming a signed payload in the first place.
func ComposeHostPlatformReleaseArchive(request ComposeHostPlatformReleaseArchiveRequest) (HostPlatformReleaseArchive, error) {
	composition, err := readComposition(request.CompositionPath)
	if err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	if err := validateComposition(composition); err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	outputPath, err := requireNewOutputPath(request.OutputArchivePath)
	if err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	manifestPath := filepath.Join(composition.ReleaseSourceDirectory, "installation-manifest.json")
	manifestBytes, err := readRegularFile(manifestPath, maximumCompositionBytes)
	if err != nil {
		return HostPlatformReleaseArchive{}, fmt.Errorf("read candidate C48: %w", err)
	}
	manifest, err := decodeManifest(manifestBytes)
	if err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	entries, err := collectArchiveEntries(composition, manifest, manifestPath)
	if err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	if err := writeArchive(outputPath, entries); err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	return inspectArchive(outputPath)
}

func readComposition(pathValue string) (HostPlatformReleaseArchiveComposition, error) {
	contents, err := readRegularFile(pathValue, maximumCompositionBytes)
	if err != nil {
		return HostPlatformReleaseArchiveComposition{}, fmt.Errorf("read Host Platform archive composition: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var composition HostPlatformReleaseArchiveComposition
	if err := decoder.Decode(&composition); err != nil {
		return HostPlatformReleaseArchiveComposition{}, fmt.Errorf("decode Host Platform archive composition: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return HostPlatformReleaseArchiveComposition{}, fmt.Errorf("Host Platform archive composition must contain exactly one JSON object")
	}
	return composition, nil
}

func validateComposition(value HostPlatformReleaseArchiveComposition) error {
	if value.SchemaVersion != "v1" || !absoluteNonSymlinkDirectory(value.ReleaseSourceDirectory) || !absoluteRegularFile(value.OperatorInterfaceBootstrapSourcePath) || len(value.ServiceDefinitionSources) != 3 {
		return fmt.Errorf("Host Platform archive composition is incomplete or invalid")
	}
	seen := map[string]bool{}
	for _, source := range value.ServiceDefinitionSources {
		if !validIdentifier(source.Role) || seen[source.Role] || !absoluteRegularFile(source.SourcePath) {
			return fmt.Errorf("Host Platform service-definition source is invalid")
		}
		seen[source.Role] = true
	}
	return nil
}

func decodeManifest(contents []byte) (installationManifest, error) {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var manifest installationManifest
	if err := decoder.Decode(&manifest); err != nil {
		return installationManifest{}, fmt.Errorf("decode candidate C48: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return installationManifest{}, fmt.Errorf("candidate C48 has multiple documents")
	}
	if manifest.SchemaVersion != "v1" || !validHostPlatform(manifest.Platform) || !validIdentifier(manifest.Release.ID) || !sha256Pattern.MatchString(manifest.OperatorInterface.BootstrapConfigurationSHA256) || len(manifest.ImmutablePayload.Entries) == 0 || len(manifest.RequiredServices) != 3 {
		return installationManifest{}, fmt.Errorf("candidate C48 archive-relevant declaration is invalid")
	}
	seenEntries := map[string]bool{}
	for _, entry := range manifest.ImmutablePayload.Entries {
		if !safeRelativePath(entry.RelativePath) || !sha256Pattern.MatchString(entry.SHA256) || seenEntries[entry.RelativePath] {
			return installationManifest{}, fmt.Errorf("candidate C48 immutable entry is invalid")
		}
		seenEntries[entry.RelativePath] = true
	}
	seenRoles := map[string]bool{}
	for _, service := range manifest.RequiredServices {
		if !validIdentifier(service.Role) || seenRoles[service.Role] || !sha256Pattern.MatchString(service.DefinitionSHA256) {
			return installationManifest{}, fmt.Errorf("candidate C48 service definition is invalid")
		}
		seenRoles[service.Role] = true
	}
	return manifest, nil
}

func collectArchiveEntries(composition HostPlatformReleaseArchiveComposition, manifest installationManifest, manifestPath string) ([]archiveEntry, error) {
	entries := []archiveEntry{{Name: "release/installation-manifest.json", SourcePath: manifestPath, Mode: 0o644}}
	expectedReleaseFiles := map[string]bool{"installation-manifest.json": true}
	for _, item := range manifest.ImmutablePayload.Entries {
		sourcePath := filepath.Join(composition.ReleaseSourceDirectory, filepath.FromSlash(item.RelativePath))
		if err := verifyRegularFileSHA256(sourcePath, item.SHA256); err != nil {
			return nil, fmt.Errorf("verify C48 immutable source %s: %w", item.RelativePath, err)
		}
		mode := int64(0o644)
		if item.Executable {
			mode = 0o755
		}
		entries = append(entries, archiveEntry{Name: path.Join("release", item.RelativePath), SourcePath: sourcePath, Mode: mode})
		expectedReleaseFiles[item.RelativePath] = true
	}
	if err := verifyNoUndeclaredReleaseFiles(composition.ReleaseSourceDirectory, expectedReleaseFiles); err != nil {
		return nil, err
	}
	sources := map[string]string{}
	for _, source := range composition.ServiceDefinitionSources {
		sources[source.Role] = source.SourcePath
	}
	for _, service := range manifest.RequiredServices {
		sourcePath, found := sources[service.Role]
		if !found {
			return nil, fmt.Errorf("C48 service definition source is missing for role %s", service.Role)
		}
		if err := verifyRegularFileSHA256(sourcePath, service.DefinitionSHA256); err != nil {
			return nil, fmt.Errorf("verify C48 service definition source %s: %w", service.Role, err)
		}
		archiveName, err := serviceDefinitionArchiveName(manifest.Platform, service.Role)
		if err != nil {
			return nil, err
		}
		entries = append(entries, archiveEntry{Name: path.Join("service-definitions", archiveName), SourcePath: sourcePath, Mode: 0o644})
	}
	if err := verifyRegularFileSHA256(composition.OperatorInterfaceBootstrapSourcePath, manifest.OperatorInterface.BootstrapConfigurationSHA256); err != nil {
		return nil, fmt.Errorf("verify C48 operator bootstrap source: %w", err)
	}
	entries = append(entries, archiveEntry{Name: "operator-interface/runtime-console-bootstrap.json", SourcePath: composition.OperatorInterfaceBootstrapSourcePath, Mode: 0o644})
	sort.Slice(entries, func(left, right int) bool { return entries[left].Name < entries[right].Name })
	return entries, nil
}

func verifyNoUndeclaredReleaseFiles(root string, expected map[string]bool) error {
	return filepath.WalkDir(root, func(current string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if current == root {
			return nil
		}
		relative, err := filepath.Rel(root, current)
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 || !entry.Type().IsRegular() {
			return fmt.Errorf("candidate release contains non-regular file %s", relative)
		}
		if !expected[filepath.ToSlash(relative)] {
			return fmt.Errorf("candidate release contains undeclared C48 file %s", relative)
		}
		return nil
	})
}

func writeArchive(outputPath string, entries []archiveEntry) error {
	temporary, err := os.CreateTemp(filepath.Dir(outputPath), "."+filepath.Base(outputPath)+".compose-")
	if err != nil {
		return fmt.Errorf("create C68 archive output: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	gzipWriter := gzip.NewWriter(temporary)
	gzipWriter.Name, gzipWriter.Comment, gzipWriter.ModTime = "", "", time.Unix(0, 0).UTC()
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		file, openErr := os.Open(entry.SourcePath)
		if openErr != nil {
			return closeArchiveWriters(temporary, gzipWriter, tarWriter, fmt.Errorf("open C68 source %s: %w", entry.Name, openErr))
		}
		info, statErr := file.Stat()
		if statErr != nil || !info.Mode().IsRegular() || info.Size() < 0 {
			_ = file.Close()
			return closeArchiveWriters(temporary, gzipWriter, tarWriter, fmt.Errorf("inspect C68 source %s", entry.Name))
		}
		header := &tar.Header{Name: entry.Name, Typeflag: tar.TypeReg, Mode: entry.Mode, Size: info.Size(), ModTime: time.Unix(0, 0).UTC(), AccessTime: time.Time{}, ChangeTime: time.Time{}, Uid: 0, Gid: 0}
		if err := tarWriter.WriteHeader(header); err != nil {
			_ = file.Close()
			return closeArchiveWriters(temporary, gzipWriter, tarWriter, err)
		}
		copied, copyErr := io.Copy(tarWriter, file)
		closeErr := file.Close()
		if copyErr != nil || closeErr != nil || copied != info.Size() {
			return closeArchiveWriters(temporary, gzipWriter, tarWriter, fmt.Errorf("copy C68 source %s", entry.Name))
		}
	}
	if err := tarWriter.Close(); err != nil {
		_ = gzipWriter.Close()
		_ = temporary.Close()
		return err
	}
	if err := gzipWriter.Close(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Chmod(temporaryPath, 0o600); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		return fmt.Errorf("publish C68 archive: %w", err)
	}
	return syncDirectory(filepath.Dir(outputPath))
}

func closeArchiveWriters(output *os.File, gzipWriter *gzip.Writer, tarWriter *tar.Writer, cause error) error {
	_ = tarWriter.Close()
	_ = gzipWriter.Close()
	_ = output.Close()
	return cause
}

func inspectArchive(pathValue string) (HostPlatformReleaseArchive, error) {
	file, err := os.Open(pathValue)
	if err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 {
		return HostPlatformReleaseArchive{}, fmt.Errorf("C68 archive output is missing, non-regular, or empty")
	}
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return HostPlatformReleaseArchive{}, err
	}
	return HostPlatformReleaseArchive{ArchivePath: pathValue, SHA256: hex.EncodeToString(digest.Sum(nil)), SizeBytes: info.Size(), MediaType: hostPlatformReleaseArchiveMediaType}, nil
}

func verifyRegularFileSHA256(pathValue, expected string) error {
	if !sha256Pattern.MatchString(expected) {
		return fmt.Errorf("declared SHA-256 is invalid")
	}
	contents, err := readRegularFile(pathValue, -1)
	if err != nil {
		return err
	}
	digest := sha256.Sum256(contents)
	if actual := hex.EncodeToString(digest[:]); actual != expected {
		return fmt.Errorf("SHA-256 differs")
	}
	return nil
}
func readRegularFile(pathValue string, limit int64) ([]byte, error) {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return nil, fmt.Errorf("path must be absolute")
	}
	info, err := os.Lstat(pathValue)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || (limit >= 0 && info.Size() > limit) {
		return nil, fmt.Errorf("path is missing, non-regular, symbolic, or too large")
	}
	file, err := os.Open(pathValue)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := io.Reader(file)
	if limit >= 0 {
		reader = io.LimitReader(file, limit+1)
	}
	contents, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}
	if limit >= 0 && int64(len(contents)) > limit {
		return nil, fmt.Errorf("file exceeds byte limit")
	}
	return contents, nil
}
func requireNewOutputPath(pathValue string) (string, error) {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return "", fmt.Errorf("C68 output archive path must be absolute")
	}
	abs, err := filepath.Abs(pathValue)
	if err != nil {
		return "", err
	}
	if _, err := os.Lstat(abs); err == nil {
		return "", fmt.Errorf("C68 output archive already exists")
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	if !absoluteNonSymlinkDirectory(filepath.Dir(abs)) {
		return "", fmt.Errorf("C68 output archive parent must be an existing non-symbolic directory")
	}
	return abs, nil
}
func absoluteNonSymlinkDirectory(pathValue string) bool {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return false
	}
	info, err := os.Lstat(pathValue)
	return err == nil && info.IsDir() && info.Mode()&os.ModeSymlink == 0
}
func absoluteRegularFile(pathValue string) bool {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return false
	}
	info, err := os.Lstat(pathValue)
	return err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0
}
func safeRelativePath(value string) bool {
	return value != "" && !strings.Contains(value, "\\") && !strings.HasPrefix(value, "/") && path.Clean(value) == value && value != "." && value != ".." && !strings.HasPrefix(value, "../")
}
func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

// serviceDefinitionArchiveName is derived from the explicit C48 platform
// declaration. A C68 archive is portable as bytes, but a launchd plist,
// systemd unit, and SCM JSON declaration are different Host contracts.
func serviceDefinitionArchiveName(platform, role string) (string, error) {
	if !validIdentifier(role) {
		return "", fmt.Errorf("C48 service role is invalid")
	}
	switch platform {
	case "macos":
		return role + ".plist", nil
	case "linux":
		return role + ".service", nil
	case "windows":
		return role + ".json", nil
	default:
		return "", fmt.Errorf("C48 platform %q is not supported by C68 archive composition", platform)
	}
}

func validHostPlatform(value string) bool {
	return value == "macos" || value == "linux" || value == "windows"
}
func syncDirectory(pathValue string) error {
	directory, err := os.Open(pathValue)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
