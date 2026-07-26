// Package updateexecutionreportfile persists the C28 evidence created by the
// staged next updater. The Host owns the destination directory; this adapter
// does not derive a result from a process exit code or replace a pre-existing
// report with different facts.
package updateexecutionreportfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

// WriteStagedProductUpdateExecutionReport writes exactly one C28 document to
// a declared, Host-owned absolute location. A retry may reuse an identical
// document, but a different document at that path is a conflict rather than
// an implicit replacement of update evidence.
func WriteStagedProductUpdateExecutionReport(path string, report hostupdaterdomain.StagedProductUpdateExecutionReport) error {
	if path == "" || !filepath.IsAbs(path) {
		return fmt.Errorf("C28 report output path must be absolute")
	}
	if isWindowsNetworkPath(path) {
		return fmt.Errorf("C28 report output path must be on a Host-local volume")
	}
	canonicalPath, err := canonicalHostOwnedOutputPath(path)
	if err != nil {
		return fmt.Errorf("resolve C28 report output path: %w", err)
	}
	path = canonicalPath
	if err := rejectSymbolicLinkPathComponents(path); err != nil {
		return fmt.Errorf("inspect C28 report output path: %w", err)
	}
	directory := filepath.Dir(path)
	directoryInfo, err := os.Lstat(directory)
	if err != nil || !directoryInfo.IsDir() || directoryInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C28 report output directory is missing, not a directory, or a symbolic link")
	}
	contents, err := json.Marshal(report)
	if err != nil {
		return fmt.Errorf("encode C28 report: %w", err)
	}
	contents = append(contents, '\n')
	temporary, err := os.CreateTemp(directory, ".staged-product-update-report-")
	if err != nil {
		return fmt.Errorf("create temporary C28 report: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("set temporary C28 report mode: %w", err)
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return fmt.Errorf("write temporary C28 report: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync temporary C28 report: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close temporary C28 report: %w", err)
	}
	if err := os.Link(temporaryPath, path); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("publish C28 report without replacing existing evidence: %w", err)
	}
	existing, err := (StagedProductUpdateExecutionReportFileReader{}).Read(path)
	if err != nil {
		return fmt.Errorf("read existing C28 report after idempotency conflict: %w", err)
	}
	if !reflect.DeepEqual(existing, report) {
		return fmt.Errorf("C28 report output path already contains different evidence")
	}
	return nil
}

func isWindowsNetworkPath(path string) bool {
	return strings.HasPrefix(filepath.VolumeName(filepath.Clean(path)), `\\`)
}

// canonicalHostOwnedOutputPath accepts the OS-owned /tmp and /var aliases on
// macOS while preserving the no-arbitrary-symlink rule for product-owned
// paths. A Host staging/report directory often originates in a standard
// temporary directory during installation or recovery; those aliases are part
// of the platform, not a caller-selected redirect.
func canonicalHostOwnedOutputPath(path string) (string, error) {
	directory := filepath.Dir(path)
	canonicalDirectory, err := filepath.EvalSymlinks(directory)
	if err != nil {
		return "", fmt.Errorf("resolve output directory: %w", err)
	}
	if filepath.Clean(directory) != filepath.Clean(canonicalDirectory) && !isSupportedSystemTemporaryAlias(directory) {
		return "", fmt.Errorf("output directory contains an unsupported symbolic link")
	}
	return filepath.Join(canonicalDirectory, filepath.Base(path)), nil
}

func isSupportedSystemTemporaryAlias(path string) bool {
	clean := filepath.Clean(path)
	for _, root := range []string{"/tmp", "/var"} {
		if clean == root || strings.HasPrefix(clean, root+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

func rejectSymbolicLinkPathComponents(path string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("path must be absolute")
	}
	clean := filepath.Clean(path)
	volume := filepath.VolumeName(clean)
	current := volume + string(filepath.Separator)
	relative := strings.TrimPrefix(clean, volume)
	relative = strings.TrimPrefix(relative, string(filepath.Separator))
	for _, component := range strings.Split(relative, string(filepath.Separator)) {
		if component == "" {
			continue
		}
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("inspect path component %s: %w", current, err)
		}
		if info.Mode()&(os.ModeSymlink|os.ModeIrregular) != 0 {
			return fmt.Errorf("path component is a symbolic link or redirecting reparse point: %s", current)
		}
	}
	return nil
}
