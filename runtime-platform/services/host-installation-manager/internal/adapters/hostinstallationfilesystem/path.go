// Package hostinstallationfilesystem owns safe Host filesystem path checks
// shared by C49 observers and C50 document persistence. It never resolves an
// unexpected symbolic link while deciding where installation state lives.
package hostinstallationfilesystem

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// RejectSymbolicLinkPathComponents proves that each existing component of an
// absolute path is not a symbolic link. A missing component is permitted: the
// caller may be observing an absent resource or creating a declared path.
//
// The check intentionally includes the final component. Callers that model an
// explicit activation link inspect its parent with this function and inspect
// the activation link itself under that contract.
func RejectSymbolicLinkPathComponents(path string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("Host installation path must be absolute")
	}
	cleanPath := filepath.Clean(path)
	if cleanPath == string(filepath.Separator) {
		return nil
	}
	currentPath := string(filepath.Separator)
	for _, component := range strings.Split(strings.TrimPrefix(cleanPath, string(filepath.Separator)), string(filepath.Separator)) {
		if component == "" {
			continue
		}
		currentPath = filepath.Join(currentPath, component)
		info, err := os.Lstat(currentPath)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("inspect Host installation path component %s: %w", currentPath, err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("Host installation path component is a symbolic link: %s", currentPath)
		}
	}
	return nil
}
