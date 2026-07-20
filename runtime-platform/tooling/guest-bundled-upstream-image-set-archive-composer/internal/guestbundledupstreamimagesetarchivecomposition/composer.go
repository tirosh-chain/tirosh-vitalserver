// Package guestbundledupstreamimagesetarchivecomposition creates the fixed
// archive layout consumed by Guest-owned C64. It is a release-process tool:
// it neither invokes Docker nor reads or changes the active Guest image-set.
package guestbundledupstreamimagesetarchivecomposition

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
	imageSetArchiveMediaType = "application/vnd.tirosh.vitalserver.bundled-upstream-image-set+tar+gzip"
	maximumCompositionBytes  = 1 << 20
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

type ComposeGuestBundledUpstreamImageSetArchiveRequest struct {
	CompositionPath   string
	OutputArchivePath string
}

type GuestBundledUpstreamImageSetArchive struct {
	ArchivePath string `json:"archivePath"`
	SHA256      string `json:"sha256"`
	SizeBytes   int64  `json:"sizeBytes"`
	MediaType   string `json:"mediaType"`
}

// GuestBundledUpstreamImageSetArchiveComposition deliberately maps every
// release-process source to one C64 archive path. Paths are not discovered
// from a Docker daemon, a Compose file, or a build workspace.
type GuestBundledUpstreamImageSetArchiveComposition struct {
	SchemaVersion         string                                   `json:"schemaVersion"`
	ImageSetID            string                                   `json:"imageSetId"`
	ComposeFileSourcePath string                                   `json:"composeFileSourcePath"`
	ImageArchiveSources   []GuestBundledUpstreamImageArchiveSource `json:"imageArchiveSources"`
}

type GuestBundledUpstreamImageArchiveSource struct {
	ArchivePath string `json:"archivePath"`
	SourcePath  string `json:"sourcePath"`
}

type imageSetManifest struct {
	SchemaVersion     string   `json:"schemaVersion"`
	ImageSetID        string   `json:"imageSetId"`
	ComposeFile       string   `json:"composeFile"`
	ImageArchivePaths []string `json:"imageArchivePaths"`
}

type archiveEntry struct {
	Name       string
	SourcePath string
	Contents   []byte
}

func ComposeGuestBundledUpstreamImageSetArchive(request ComposeGuestBundledUpstreamImageSetArchiveRequest) (GuestBundledUpstreamImageSetArchive, error) {
	composition, err := readComposition(request.CompositionPath)
	if err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	if err := validateComposition(composition); err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	outputPath, err := requireNewOutputPath(request.OutputArchivePath)
	if err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	entries, err := collectArchiveEntries(composition)
	if err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	if err := writeArchive(outputPath, entries); err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	return inspectArchive(outputPath)
}

func readComposition(pathValue string) (GuestBundledUpstreamImageSetArchiveComposition, error) {
	contents, err := readRegularFile(pathValue, maximumCompositionBytes)
	if err != nil {
		return GuestBundledUpstreamImageSetArchiveComposition{}, fmt.Errorf("read C64 image-set archive composition: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var composition GuestBundledUpstreamImageSetArchiveComposition
	if err := decoder.Decode(&composition); err != nil {
		return GuestBundledUpstreamImageSetArchiveComposition{}, fmt.Errorf("decode C64 image-set archive composition: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return GuestBundledUpstreamImageSetArchiveComposition{}, fmt.Errorf("C64 image-set archive composition must contain exactly one JSON object")
	}
	return composition, nil
}

func validateComposition(composition GuestBundledUpstreamImageSetArchiveComposition) error {
	if composition.SchemaVersion != "v1" || !validIdentifier(composition.ImageSetID) || !absoluteRegularFile(composition.ComposeFileSourcePath) || len(composition.ImageArchiveSources) == 0 {
		return fmt.Errorf("C64 image-set archive composition is incomplete or invalid")
	}
	seen := map[string]bool{}
	for _, source := range composition.ImageArchiveSources {
		if !safeImageArchivePath(source.ArchivePath) || seen[source.ArchivePath] || !absoluteRegularFile(source.SourcePath) {
			return fmt.Errorf("C64 image-set archive source is invalid")
		}
		seen[source.ArchivePath] = true
	}
	return nil
}

func collectArchiveEntries(composition GuestBundledUpstreamImageSetArchiveComposition) ([]archiveEntry, error) {
	imagePaths := make([]string, 0, len(composition.ImageArchiveSources))
	entries := make([]archiveEntry, 0, len(composition.ImageArchiveSources)+2)
	for _, source := range composition.ImageArchiveSources {
		imagePaths = append(imagePaths, source.ArchivePath)
		entries = append(entries, archiveEntry{Name: source.ArchivePath, SourcePath: source.SourcePath})
	}
	sort.Strings(imagePaths)
	manifestBytes, err := json.Marshal(imageSetManifest{SchemaVersion: "v1", ImageSetID: composition.ImageSetID, ComposeFile: "compose.yaml", ImageArchivePaths: imagePaths})
	if err != nil {
		return nil, fmt.Errorf("encode C64 image-set manifest: %w", err)
	}
	entries = append(entries,
		archiveEntry{Name: "image-set.json", Contents: append(manifestBytes, '\n')},
		archiveEntry{Name: "compose.yaml", SourcePath: composition.ComposeFileSourcePath},
	)
	sort.Slice(entries, func(left, right int) bool { return entries[left].Name < entries[right].Name })
	return entries, nil
}

func writeArchive(outputPath string, entries []archiveEntry) error {
	temporary, err := os.CreateTemp(filepath.Dir(outputPath), "."+filepath.Base(outputPath)+".compose-")
	if err != nil {
		return fmt.Errorf("create C64 image-set archive output: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	gzipWriter := gzip.NewWriter(temporary)
	gzipWriter.Name, gzipWriter.Comment, gzipWriter.ModTime = "", "", time.Unix(0, 0).UTC()
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		contents, err := readEntryContents(entry)
		if err != nil {
			return closeWriters(temporary, gzipWriter, tarWriter, err)
		}
		header := &tar.Header{Name: entry.Name, Typeflag: tar.TypeReg, Mode: 0o644, Size: int64(len(contents)), ModTime: time.Unix(0, 0).UTC(), AccessTime: time.Time{}, ChangeTime: time.Time{}, Uid: 0, Gid: 0}
		if err := tarWriter.WriteHeader(header); err != nil {
			return closeWriters(temporary, gzipWriter, tarWriter, fmt.Errorf("write C64 image-set archive header %q: %w", entry.Name, err))
		}
		if _, err := tarWriter.Write(contents); err != nil {
			return closeWriters(temporary, gzipWriter, tarWriter, fmt.Errorf("write C64 image-set archive contents %q: %w", entry.Name, err))
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
		return fmt.Errorf("publish C64 image-set archive: %w", err)
	}
	return syncDirectory(filepath.Dir(outputPath))
}

func readEntryContents(entry archiveEntry) ([]byte, error) {
	if entry.Contents != nil {
		return entry.Contents, nil
	}
	contents, err := readRegularFile(entry.SourcePath, -1)
	if err != nil {
		return nil, fmt.Errorf("read C64 image-set source %q: %w", entry.Name, err)
	}
	return contents, nil
}

func closeWriters(output *os.File, gzipWriter *gzip.Writer, tarWriter *tar.Writer, cause error) error {
	_ = tarWriter.Close()
	_ = gzipWriter.Close()
	_ = output.Close()
	return cause
}

func inspectArchive(pathValue string) (GuestBundledUpstreamImageSetArchive, error) {
	file, err := os.Open(pathValue)
	if err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 {
		return GuestBundledUpstreamImageSetArchive{}, fmt.Errorf("C64 image-set archive output is missing, non-regular, or empty")
	}
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return GuestBundledUpstreamImageSetArchive{}, err
	}
	return GuestBundledUpstreamImageSetArchive{ArchivePath: pathValue, SHA256: hex.EncodeToString(digest.Sum(nil)), SizeBytes: info.Size(), MediaType: imageSetArchiveMediaType}, nil
}

func requireNewOutputPath(pathValue string) (string, error) {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return "", fmt.Errorf("C64 image-set archive output path must be absolute")
	}
	abs, err := filepath.Abs(pathValue)
	if err != nil {
		return "", err
	}
	if _, err := os.Lstat(abs); err == nil {
		return "", fmt.Errorf("C64 image-set archive output already exists")
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	if !absoluteNonSymlinkDirectory(filepath.Dir(abs)) {
		return "", fmt.Errorf("C64 image-set archive output parent must be an existing non-symbolic directory")
	}
	return abs, nil
}

func readRegularFile(pathValue string, limit int64) ([]byte, error) {
	if !absoluteRegularFile(pathValue) {
		return nil, fmt.Errorf("path is missing, non-regular, or symbolic")
	}
	info, err := os.Lstat(pathValue)
	if err != nil {
		return nil, err
	}
	if limit >= 0 && info.Size() > limit {
		return nil, fmt.Errorf("file exceeds byte limit")
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

func absoluteRegularFile(pathValue string) bool {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return false
	}
	info, err := os.Lstat(pathValue)
	return err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0
}

func absoluteNonSymlinkDirectory(pathValue string) bool {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return false
	}
	info, err := os.Lstat(pathValue)
	return err == nil && info.IsDir() && info.Mode()&os.ModeSymlink == 0
}

func safeImageArchivePath(value string) bool {
	return strings.HasPrefix(value, "images/") && strings.HasSuffix(value, ".tar") && safeArchivePath(value)
}

func safeArchivePath(value string) bool {
	return value != "" && !strings.HasPrefix(value, "/") && !strings.Contains(value, "\\") && path.Clean(value) == value && !strings.Contains(value, "..")
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

func syncDirectory(pathValue string) error {
	directory, err := os.Open(pathValue)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
