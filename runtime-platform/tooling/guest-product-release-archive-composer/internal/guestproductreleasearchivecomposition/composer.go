// Package guestproductreleasearchivecomposition owns release-process-only
// formation of a deterministic C59-compatible Guest Product release archive.
// It does not read Guest state, select a current release, or activate one.
package guestproductreleasearchivecomposition

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const guestProductReleaseArchiveMediaType = "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"

type ComposeGuestProductReleaseArchiveRequest struct {
	ReleaseSourceDirectory string
	OutputArchivePath      string
}

type GuestProductReleaseArchive struct {
	ArchivePath string `json:"archivePath"`
	SHA256      string `json:"sha256"`
	SizeBytes   int64  `json:"sizeBytes"`
	MediaType   string `json:"mediaType"`
}

type sourceEntry struct {
	relativePath string
	absPath      string
	mode         os.FileMode
	linkTarget   string
	kind         byte
	size         int64
}

// ComposeGuestProductReleaseArchive reads one explicit local release tree and
// atomically creates one new gzip tar stream accepted by C59's filesystem
// stager. It preserves only directories, regular files, and safe relative
// symlinks to declared regular files; devices, sockets, absolute links,
// traversal, and output replacement are rejected before publication.
func ComposeGuestProductReleaseArchive(request ComposeGuestProductReleaseArchiveRequest) (GuestProductReleaseArchive, error) {
	releaseSource, err := requireReleaseSourceDirectory(request.ReleaseSourceDirectory)
	if err != nil {
		return GuestProductReleaseArchive{}, err
	}
	outputPath, err := requireNewOutputArchivePath(request.OutputArchivePath)
	if err != nil {
		return GuestProductReleaseArchive{}, err
	}
	entries, err := collectReleaseEntries(releaseSource)
	if err != nil {
		return GuestProductReleaseArchive{}, err
	}
	if err := writeArchive(outputPath, entries); err != nil {
		return GuestProductReleaseArchive{}, err
	}
	artifact, err := inspectArchive(outputPath)
	if err != nil {
		return GuestProductReleaseArchive{}, err
	}
	return artifact, nil
}

func requireReleaseSourceDirectory(pathValue string) (string, error) {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return "", fmt.Errorf("Guest Product release source directory must be absolute")
	}
	abs, err := filepath.Abs(pathValue)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("Guest Product release source directory is missing, not a directory, or a symbolic link")
	}
	return abs, nil
}

func requireNewOutputArchivePath(pathValue string) (string, error) {
	if pathValue == "" || !filepath.IsAbs(pathValue) {
		return "", fmt.Errorf("Guest Product release archive output path must be absolute")
	}
	abs, err := filepath.Abs(pathValue)
	if err != nil {
		return "", err
	}
	if _, err := os.Lstat(abs); err == nil {
		return "", fmt.Errorf("Guest Product release archive output already exists: %s", abs)
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect Guest Product release archive output: %w", err)
	}
	parent := filepath.Dir(abs)
	info, err := os.Lstat(parent)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("Guest Product release archive output parent must be an existing non-symlink directory")
	}
	return abs, nil
}

func collectReleaseEntries(root string) ([]sourceEntry, error) {
	entries := make([]sourceEntry, 0)
	regularPaths := map[string]bool{}
	err := filepath.WalkDir(root, func(current string, directoryEntry os.DirEntry, walkErr error) error {
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
		archivePath, err := safeArchivePath(relative)
		if err != nil {
			return err
		}
		info, err := os.Lstat(current)
		if err != nil {
			return err
		}
		entry := sourceEntry{relativePath: archivePath, absPath: current, mode: info.Mode().Perm()}
		switch {
		case info.IsDir():
			entry.kind = tar.TypeDir
		case info.Mode().IsRegular():
			entry.kind = tar.TypeReg
			entry.size = info.Size()
			regularPaths[archivePath] = true
		case info.Mode()&os.ModeSymlink != 0:
			link, readErr := os.Readlink(current)
			if readErr != nil {
				return readErr
			}
			if !safeRelativeLinkTarget(archivePath, link) {
				return fmt.Errorf("Guest Product release symbolic link %q target is invalid", archivePath)
			}
			entry.kind = tar.TypeSymlink
			entry.linkTarget = link
		default:
			return fmt.Errorf("Guest Product release source %q has unsupported filesystem type", archivePath)
		}
		entries = append(entries, entry)
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("read Guest Product release source tree: %w", err)
	}
	if len(regularPaths) == 0 {
		return nil, fmt.Errorf("Guest Product release source tree must contain at least one regular file")
	}
	for _, entry := range entries {
		if entry.kind != tar.TypeSymlink {
			continue
		}
		target := path.Clean(path.Join(path.Dir(entry.relativePath), entry.linkTarget))
		if !regularPaths[target] {
			return nil, fmt.Errorf("Guest Product release symbolic link %q must target a declared regular file", entry.relativePath)
		}
	}
	sort.Slice(entries, func(left int, right int) bool { return entries[left].relativePath < entries[right].relativePath })
	return entries, nil
}

func safeArchivePath(relative string) (string, error) {
	if relative == "" || filepath.IsAbs(relative) || strings.Contains(relative, "\\") {
		return "", fmt.Errorf("release archive path is invalid")
	}
	archivePath := filepath.ToSlash(filepath.Clean(relative))
	if archivePath == "." || archivePath == ".." || strings.HasPrefix(archivePath, "../") || strings.Contains(archivePath, "/../") {
		return "", fmt.Errorf("release archive path escapes source root")
	}
	return archivePath, nil
}

func safeRelativeLinkTarget(entryPath string, target string) bool {
	if target == "" || path.IsAbs(target) || strings.Contains(target, "\\") {
		return false
	}
	resolved := path.Clean(path.Join(path.Dir(entryPath), target))
	return resolved != "." && resolved != ".." && !strings.HasPrefix(resolved, "../")
}

func writeArchive(outputPath string, entries []sourceEntry) error {
	temporary, err := os.CreateTemp(filepath.Dir(outputPath), "."+filepath.Base(outputPath)+".compose-")
	if err != nil {
		return fmt.Errorf("create Guest Product release archive output: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	gzipWriter := gzip.NewWriter(temporary)
	gzipWriter.Name = ""
	gzipWriter.Comment = ""
	gzipWriter.ModTime = time.Unix(0, 0).UTC()
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		name := entry.relativePath
		if entry.kind == tar.TypeDir {
			name += "/"
		}
		header := &tar.Header{Name: name, Typeflag: entry.kind, Mode: int64(entry.mode), Size: entry.size, Linkname: entry.linkTarget, ModTime: time.Unix(0, 0).UTC(), AccessTime: time.Time{}, ChangeTime: time.Time{}, Uid: 0, Gid: 0}
		if err := tarWriter.WriteHeader(header); err != nil {
			tarWriter.Close()
			gzipWriter.Close()
			temporary.Close()
			return fmt.Errorf("write Guest Product release archive header %q: %w", entry.relativePath, err)
		}
		if entry.kind != tar.TypeReg {
			continue
		}
		file, openErr := os.Open(entry.absPath)
		if openErr != nil {
			tarWriter.Close()
			gzipWriter.Close()
			temporary.Close()
			return fmt.Errorf("open Guest Product release source %q: %w", entry.relativePath, openErr)
		}
		info, statErr := file.Stat()
		if statErr != nil || !info.Mode().IsRegular() || info.Size() != entry.size {
			file.Close()
			tarWriter.Close()
			gzipWriter.Close()
			temporary.Close()
			return fmt.Errorf("Guest Product release source %q changed while composing archive", entry.relativePath)
		}
		_, copyErr := io.Copy(tarWriter, file)
		closeErr := file.Close()
		if copyErr != nil || closeErr != nil {
			tarWriter.Close()
			gzipWriter.Close()
			temporary.Close()
			return fmt.Errorf("copy Guest Product release source %q", entry.relativePath)
		}
	}
	if err := tarWriter.Close(); err != nil {
		gzipWriter.Close()
		temporary.Close()
		return fmt.Errorf("close Guest Product release tar stream: %w", err)
	}
	if err := gzipWriter.Close(); err != nil {
		temporary.Close()
		return fmt.Errorf("close Guest Product release gzip stream: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync Guest Product release archive: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close Guest Product release archive: %w", err)
	}
	if err := os.Chmod(temporaryPath, 0o600); err != nil {
		return fmt.Errorf("set Guest Product release archive mode: %w", err)
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		return fmt.Errorf("publish Guest Product release archive: %w", err)
	}
	if err := syncDirectory(filepath.Dir(outputPath)); err != nil {
		return err
	}
	return nil
}

func inspectArchive(pathValue string) (GuestProductReleaseArchive, error) {
	file, err := os.Open(pathValue)
	if err != nil {
		return GuestProductReleaseArchive{}, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 {
		return GuestProductReleaseArchive{}, fmt.Errorf("Guest Product release archive is missing, not regular, or empty")
	}
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return GuestProductReleaseArchive{}, err
	}
	return GuestProductReleaseArchive{ArchivePath: pathValue, SHA256: hex.EncodeToString(digest.Sum(nil)), SizeBytes: info.Size(), MediaType: guestProductReleaseArchiveMediaType}, nil
}

func syncDirectory(pathValue string) error {
	directory, err := os.Open(pathValue)
	if err != nil {
		return fmt.Errorf("open output directory for sync: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("sync output directory: %w", err)
	}
	return nil
}
