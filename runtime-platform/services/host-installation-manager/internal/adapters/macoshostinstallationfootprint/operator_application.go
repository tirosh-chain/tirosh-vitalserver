package macoshostinstallationfootprint

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

// observeMacOSOperatorApplication observes the exact C48-declared application
// bundle without following a bundle link. Its tree identity deliberately
// matches the package composer's `sha256_macos_application_bundle_tree`
// algorithm, so C54 can delete only a bundle whose bytes it has proved.
func observeMacOSOperatorApplication(declared hostinstallationmanagerdomain.HostProductOperatorInterface) hostinstallationmanagerdomain.HostInstallationOperatorApplicationObservation {
	applicationPath := declared.ApplicationBundlePath
	observation := hostinstallationmanagerdomain.HostInstallationOperatorApplicationObservation{ApplicationBundlePath: applicationPath}
	if pathError := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(applicationPath); pathError != nil {
		observation.State = "unreadable"
		observation.Issue = issue("operator-application-path-unreadable", pathError.Error(), "filesystem")
		return observation
	}
	info, statError := os.Lstat(applicationPath)
	if errors.Is(statError, os.ErrNotExist) {
		observation.State = "absent"
		return observation
	}
	if statError != nil {
		observation.State = "unreadable"
		observation.Issue = issue("operator-application-read-failed", statError.Error(), "filesystem")
		return observation
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		observation.State = "diverged"
		observation.Issue = issue("operator-application-root-is-not-directory", "declared macOS operator application bundle is not a directory", "filesystem")
		return observation
	}

	for _, requirement := range []struct {
		relativePath string
		executable   bool
	}{
		{relativePath: "Contents/Info.plist"},
		{relativePath: declared.ApplicationBundleEntrypointRelativePath, executable: true},
	} {
		candidate := filepath.Join(applicationPath, filepath.FromSlash(requirement.relativePath))
		candidateInfo, candidateError := os.Lstat(candidate)
		if errors.Is(candidateError, os.ErrNotExist) {
			observation.State = "diverged"
			observation.Issue = issue("operator-application-required-file-missing", requirement.relativePath, "filesystem")
			return observation
		}
		if candidateError != nil {
			observation.State = "unreadable"
			observation.Issue = issue("operator-application-required-file-read-failed", candidateError.Error(), "filesystem")
			return observation
		}
		if candidateInfo.Mode()&os.ModeSymlink != 0 || !candidateInfo.Mode().IsRegular() {
			observation.State = "diverged"
			observation.Issue = issue("operator-application-required-file-not-regular", requirement.relativePath, "filesystem")
			return observation
		}
		if requirement.executable && candidateInfo.Mode().Perm()&0111 == 0 {
			observation.State = "diverged"
			observation.Issue = issue("operator-application-entrypoint-not-executable", requirement.relativePath, "filesystem")
			return observation
		}
	}

	treeDigest, treeIssue := macOSOperatorApplicationTreeSHA256(applicationPath)
	if treeIssue != nil {
		observation.State = treeIssue.State
		observation.Issue = treeIssue.Issue
		return observation
	}
	if treeDigest != declared.ApplicationBundleTreeSHA256 {
		observation.State = "diverged"
		observation.Issue = issue("operator-application-tree-digest-mismatch", "declared macOS operator application bundle bytes do not match C48", "filesystem")
		return observation
	}
	observation.State = "matching"
	return observation
}

type operatorApplicationTreeIssue struct {
	State string
	Issue *hostinstallationmanagerdomain.HostInstallationIssue
}

func macOSOperatorApplicationTreeSHA256(applicationPath string) (string, *operatorApplicationTreeIssue) {
	resolvedRoot, rootError := filepath.EvalSymlinks(applicationPath)
	if rootError != nil {
		return "", &operatorApplicationTreeIssue{State: "unreadable", Issue: issue("operator-application-root-resolve-failed", rootError.Error(), "filesystem")}
	}
	digest := sha256.New()
	walkError := filepath.WalkDir(applicationPath, func(candidate string, entry os.DirEntry, entryError error) error {
		if entryError != nil {
			return entryError
		}
		if candidate == applicationPath {
			return nil
		}
		relativePath, relativeError := filepath.Rel(applicationPath, candidate)
		if relativeError != nil {
			return relativeError
		}
		relativePath = filepath.ToSlash(relativePath)
		if entry.Type()&os.ModeSymlink != 0 {
			resolvedCandidate, resolveError := filepath.EvalSymlinks(candidate)
			if resolveError != nil {
				return operatorApplicationDivergence{code: "operator-application-symbolic-link-unresolvable", message: relativePath}
			}
			if !pathIsWithin(resolvedRoot, resolvedCandidate) {
				return operatorApplicationDivergence{code: "operator-application-symbolic-link-escapes-bundle", message: relativePath}
			}
			target, readlinkError := os.Readlink(candidate)
			if readlinkError != nil {
				return readlinkError
			}
			digest.Write([]byte("symbolic-link\x00"))
			digest.Write([]byte(relativePath))
			digest.Write([]byte("\x00"))
			digest.Write([]byte(target))
			digest.Write([]byte("\x00"))
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		info, infoError := entry.Info()
		if infoError != nil {
			return infoError
		}
		if !info.Mode().IsRegular() {
			return operatorApplicationDivergence{code: "operator-application-unsupported-filesystem-entry", message: relativePath}
		}
		fileDigest, fileDigestError := sha256RegularFile(candidate)
		if fileDigestError != nil {
			return fileDigestError
		}
		digest.Write([]byte("regular-file\x00"))
		digest.Write([]byte(relativePath))
		digest.Write([]byte("\x00"))
		digest.Write([]byte(fileDigest))
		digest.Write([]byte("\x00"))
		return nil
	})
	if walkError != nil {
		var divergence operatorApplicationDivergence
		if errors.As(walkError, &divergence) {
			return "", &operatorApplicationTreeIssue{State: "diverged", Issue: issue(divergence.code, divergence.message, "filesystem")}
		}
		return "", &operatorApplicationTreeIssue{State: "unreadable", Issue: issue("operator-application-tree-read-failed", walkError.Error(), "filesystem")}
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

type operatorApplicationDivergence struct {
	code    string
	message string
}

func (divergence operatorApplicationDivergence) Error() string {
	return divergence.code + ": " + divergence.message
}

func pathIsWithin(root string, candidate string) bool {
	relativePath, err := filepath.Rel(root, candidate)
	return err == nil && relativePath != ".." && !strings.HasPrefix(relativePath, ".."+string(filepath.Separator)) && !filepath.IsAbs(relativePath)
}

func sha256RegularFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", fmt.Errorf("digest regular file: %w", err)
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}
