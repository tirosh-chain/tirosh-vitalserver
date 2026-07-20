package vitalserverindexedlibrary

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const guestRuntimePrivateCredentialMaterialRoot = "/run/vitalserver"

// VitalServerIndexedLibraryCredentialMaterialFileOwner owns the C51 private
// file only. It receives no archive payload, does not persist an operation or
// receipt, and never returns credential values, paths, byte counts, or an OS
// error to an application caller.
//
// The explicitly selected C44 or C46 document is read once at composition
// because it is non-secret desired input. The
// actual C51 contents are read only on the explicit availability read or an
// archive adapter invocation, so a missing credential cannot prevent Guest
// Runtime from starting and accepting a local provision command.
type VitalServerIndexedLibraryCredentialMaterialFileOwner struct {
	credentialMaterialPath     string
	privateCredentialDirectory string
	expectedReference          guestruntimedomain.VitalServerIndexedLibraryCredentialReference
	mutex                      sync.Mutex
}

// NewVitalServerIndexedLibraryCredentialMaterialFileOwner validates the
// selected C37 Archive provider against its selected C44 or C46 document
// before it accepts a secret write.
// It intentionally does not require C51 to exist at startup.
func NewVitalServerIndexedLibraryCredentialMaterialFileOwner(
	vitalServerConfigurationKind string,
	vitalServerConfigurationPath string,
	credentialMaterialPath string,
	expectedArchiveProviderReference guestruntimedomain.ArchiveProviderReference,
) (*VitalServerIndexedLibraryCredentialMaterialFileOwner, error) {
	return newVitalServerIndexedLibraryCredentialMaterialFileOwner(
		vitalServerConfigurationKind,
		vitalServerConfigurationPath,
		credentialMaterialPath,
		expectedArchiveProviderReference,
		filepath.Dir(credentialMaterialPath),
	)
}

func newVitalServerIndexedLibraryCredentialMaterialFileOwner(
	vitalServerConfigurationKind string,
	vitalServerConfigurationPath string,
	credentialMaterialPath string,
	expectedArchiveProviderReference guestruntimedomain.ArchiveProviderReference,
	privateDirectory string,
) (*VitalServerIndexedLibraryCredentialMaterialFileOwner, error) {
	configuration, err := loadVitalServerIndexedLibraryConfiguration(vitalServerConfigurationKind, vitalServerConfigurationPath)
	if err != nil {
		return nil, fmt.Errorf("VitalServer indexed-library configuration is unavailable")
	}
	if !sameProviderReference(configuration.archiveProvider, expectedArchiveProviderReference) {
		return nil, fmt.Errorf("VitalServer indexed-library configuration provider does not match the selected Archive provider")
	}
	if !isPrivateCredentialMaterialPath(credentialMaterialPath, privateDirectory) {
		return nil, fmt.Errorf("VitalServer indexed-library credential material path must be inside the private Guest secret directory")
	}
	return &VitalServerIndexedLibraryCredentialMaterialFileOwner{
		credentialMaterialPath:     credentialMaterialPath,
		privateCredentialDirectory: privateDirectory,
		expectedReference: guestruntimedomain.VitalServerIndexedLibraryCredentialReference{
			Kind: configuration.archiveCredentialReference.Kind,
			ID:   configuration.archiveCredentialReference.ID,
		},
	}, nil
}

// ObserveVitalServerIndexedLibraryCredentialMaterial returns only a
// non-secret availability classification. The caller supplies its own clock,
// so this adapter has no hidden time state.
func (owner *VitalServerIndexedLibraryCredentialMaterialFileOwner) ObserveVitalServerIndexedLibraryCredentialMaterial(context.Context) (string, *guestruntimedomain.Issue) {
	if owner == nil {
		return "failed", credentialMaterialIssue("credential-material-owner-unavailable", "Guest credential-material owner is not configured", true)
	}
	owner.mutex.Lock()
	defer owner.mutex.Unlock()
	return owner.observeLocked()
}

// ProvisionVitalServerIndexedLibraryCredentialMaterial atomically replaces
// C51 after validating the C46 identity. The private file and directory are
// mode 0600/0700. A caller never receives the underlying filesystem failure,
// because it could contain a path or other deployment-private fact.
func (owner *VitalServerIndexedLibraryCredentialMaterialFileOwner) ProvisionVitalServerIndexedLibraryCredentialMaterial(_ context.Context, material guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial) *guestruntimedomain.Issue {
	if owner == nil {
		return credentialMaterialIssue("credential-material-owner-unavailable", "Guest credential-material owner is not configured", true)
	}
	if issue := guestruntimedomain.ValidateVitalServerIndexedLibraryCredentialMaterial(material); issue != nil {
		return issue
	}
	if !guestruntimedomain.SameVitalServerIndexedLibraryCredentialReference(material.CredentialReference, owner.expectedReference) {
		return credentialMaterialIssue("credential-reference-mismatch", "credential material does not match the selected VitalServer indexed-library credential reference", false)
	}
	owner.mutex.Lock()
	defer owner.mutex.Unlock()
	if err := ensurePrivateCredentialMaterialDirectory(owner.privateCredentialDirectory); err != nil {
		return credentialMaterialIssue("credential-material-directory-unavailable", "Guest credential-material directory is unavailable", true)
	}
	if err := writePrivateCredentialMaterialFile(owner.credentialMaterialPath, owner.privateCredentialDirectory, material); err != nil {
		return credentialMaterialIssue("credential-material-write-failed", "Guest credential material could not be provisioned", true)
	}
	state, issue := owner.observeLocked()
	if state != "available" || issue != nil {
		return credentialMaterialIssue("credential-material-write-verification-failed", "Guest credential material could not be verified after provisioning", true)
	}
	return nil
}

func (owner *VitalServerIndexedLibraryCredentialMaterialFileOwner) CredentialReference() guestruntimedomain.VitalServerIndexedLibraryCredentialReference {
	if owner == nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialReference{}
	}
	return owner.expectedReference
}

func (owner *VitalServerIndexedLibraryCredentialMaterialFileOwner) observeLocked() (string, *guestruntimedomain.Issue) {
	information, err := os.Lstat(owner.credentialMaterialPath)
	if errors.Is(err, os.ErrNotExist) {
		return "missing", credentialMaterialIssue("credential-material-missing", "Guest credential material has not been provisioned", true)
	}
	if err != nil {
		return "failed", credentialMaterialIssue("credential-material-read-failed", "Guest credential material could not be read", true)
	}
	if !information.Mode().IsRegular() || information.Mode()&os.ModeSymlink != 0 || information.Mode().Perm()&0o077 != 0 {
		return "invalid", credentialMaterialIssue("credential-material-permission-invalid", "Guest credential material is not a private regular file", false)
	}
	material, err := loadVitalServerIndexedLibraryCredentialMaterial(owner.credentialMaterialPath)
	if errors.Is(err, errVitalServerIndexedLibraryCredentialMaterialUnavailable) {
		return "failed", credentialMaterialIssue("credential-material-read-failed", "Guest credential material could not be read", true)
	}
	if err != nil {
		return "invalid", credentialMaterialIssue("credential-material-invalid", "Guest credential material is invalid", false)
	}
	if !guestruntimedomain.SameVitalServerIndexedLibraryCredentialReference(material.CredentialReference, owner.expectedReference) {
		return "invalid", credentialMaterialIssue("credential-reference-mismatch", "Guest credential material does not match the selected credential reference", false)
	}
	return "available", nil
}

func ensurePrivateCredentialMaterialDirectory(privateDirectory string) error {
	if !filepath.IsAbs(privateDirectory) || strings.Contains(privateDirectory, "\\") || filepath.Clean(privateDirectory) != privateDirectory {
		return errors.New("private credential material directory is invalid")
	}
	parent := filepath.Dir(privateDirectory)
	if parentInformation, err := os.Lstat(parent); err != nil || !parentInformation.IsDir() || parentInformation.Mode()&os.ModeSymlink != 0 {
		if !strings.HasPrefix(privateDirectory, guestRuntimePrivateCredentialMaterialRoot+"/") {
			return errors.New("private credential material parent directory is unavailable")
		}
		if err := ensurePrivateCredentialDirectory(guestRuntimePrivateCredentialMaterialRoot); err != nil {
			return err
		}
		parentInformation, err := os.Lstat(parent)
		if err != nil || !parentInformation.IsDir() || parentInformation.Mode()&os.ModeSymlink != 0 {
			return errors.New("private credential material parent directory is unavailable")
		}
	}
	return ensurePrivateCredentialDirectory(privateDirectory)
}

func ensurePrivateCredentialDirectory(directory string) error {
	information, err := os.Lstat(directory)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.Mkdir(directory, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
			return err
		}
		information, err = os.Lstat(directory)
	}
	if err != nil || !information.IsDir() || information.Mode()&os.ModeSymlink != 0 || information.Mode().Perm()&0o077 != 0 {
		return errors.New("private credential material directory is unavailable")
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return err
	}
	return nil
}

func writePrivateCredentialMaterialFile(path string, privateDirectory string, material guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial) error {
	if !isPrivateCredentialMaterialPath(path, privateDirectory) {
		return errors.New("credential material path is outside the private directory")
	}
	if information, err := os.Lstat(path); err == nil {
		if !information.Mode().IsRegular() || information.Mode()&os.ModeSymlink != 0 {
			return errors.New("credential material destination is unsafe")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	encoded, err := json.Marshal(material)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(privateDirectory, ".credential-material.*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if err := temporary.Chmod(0o600); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(append(encoded, '\n')); err != nil {
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
	if err := os.Rename(temporaryPath, path); err != nil {
		return err
	}
	return syncPrivateCredentialMaterialDirectory(privateDirectory)
}

// syncPrivateCredentialMaterialDirectory makes the completed rename durable
// as a directory entry, not merely as file contents. The C51 owner returns a
// failed outcome if this proof cannot be completed; it never claims a secret
// provision succeeded solely because the temporary file was synced.
func syncPrivateCredentialMaterialDirectory(privateDirectory string) error {
	directory, err := os.Open(privateDirectory)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func isPrivateCredentialMaterialPath(path string, privateDirectory string) bool {
	if !filepath.IsAbs(path) || strings.Contains(path, "\\") || filepath.Dir(path) != privateDirectory {
		return false
	}
	return filepath.Base(path) != "." && filepath.Base(path) != "/" && filepath.Base(path) == path[len(privateDirectory)+1:]
}

func credentialMaterialIssue(code string, message string, retryable bool) *guestruntimedomain.Issue {
	return &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: "guest-secret-material"}
}
