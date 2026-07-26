// Package guestbundledupstreamimagesetfilesystem owns C64's Guest filesystem
// state. It never discovers state from Docker or a directory listing.
package guestbundledupstreamimagesetfilesystem

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

type ImageSetOperationFileRepository struct {
	configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration
}
type ActiveImageSetFileRepository struct {
	configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration
}

func NewImageSetOperationFileRepository(configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration) (*ImageSetOperationFileRepository, error) {
	if err := ensureStateRoots(configuration); err != nil {
		return nil, err
	}
	operations := filepath.Join(configuration.StateDirectory, "operations")
	if err := os.MkdirAll(operations, 0o700); err != nil {
		return nil, fmt.Errorf("create C64 operation directory: %w", err)
	}
	if err := requireDirectory(operations); err != nil {
		return nil, fmt.Errorf("validate C64 operation directory: %w", err)
	}
	return &ImageSetOperationFileRepository{configuration: configuration}, nil
}

func NewActiveImageSetFileRepository(configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration) (*ActiveImageSetFileRepository, error) {
	if err := ensureStateRoots(configuration); err != nil {
		return nil, err
	}
	return &ActiveImageSetFileRepository{configuration: configuration}, nil
}

func (repository *ImageSetOperationFileRepository) ReadImageSetOperation(_ context.Context, updateID string) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, bool, error) {
	path, err := repository.operationPath(updateID)
	if err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, false, err
	}
	contents, found, err := readRegularFile(path)
	if err != nil || !found {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, found, err
	}
	var operation guestbundledupstreamimagesetmanagerdomain.ImageSetOperation
	if err := decodeOneStrictJSON(contents, &operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, false, fmt.Errorf("decode C64 operation record: %w", err)
	}
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateImageSetOperation(repository.configuration, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, false, fmt.Errorf("validate C64 operation record: %w", err)
	}
	return operation, true, nil
}

func (repository *ImageSetOperationFileRepository) WriteImageSetOperation(_ context.Context, operation guestbundledupstreamimagesetmanagerdomain.ImageSetOperation) error {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateImageSetOperation(repository.configuration, operation); err != nil {
		return err
	}
	path, err := repository.operationPath(operation.UpdateID)
	if err != nil {
		return err
	}
	contents, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode C64 operation record: %w", err)
	}
	return writeAtomicRegularFile(path, append(contents, '\n'), 0o600)
}

func (repository *ImageSetOperationFileRepository) operationPath(updateID string) (string, error) {
	if updateID == "" || strings.ContainsAny(updateID, `/\\`) || strings.Contains(updateID, "..") {
		return "", fmt.Errorf("C64 operation id is unsafe")
	}
	return filepath.Join(repository.configuration.StateDirectory, "operations", updateID+".json"), nil
}

func (repository *ActiveImageSetFileRepository) ReadActiveImageSet(_ context.Context) (guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection, *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure) {
	contents, found, err := readRegularFile(filepath.Join(repository.configuration.StateDirectory, "active-image-set.json"))
	if err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{}, unavailable("active-image-set-state-unreadable", err, "guest-image-set-state")
	}
	if !found {
		return guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{}, unavailable("active-image-set-state-missing", fmt.Errorf("C64 active image-set selection has not been explicitly provisioned"), "guest-image-set-state")
	}
	var selection guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection
	if err := decodeOneStrictJSON(contents, &selection); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{}, unavailable("active-image-set-state-invalid", err, "guest-image-set-state")
	}
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateActiveImageSetSelection(selection); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{}, unavailable("active-image-set-state-invalid", err, "guest-image-set-state")
	}
	return selection, nil
}

func (repository *ActiveImageSetFileRepository) WriteActiveImageSet(_ context.Context, selection guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateActiveImageSetSelection(selection); err != nil {
		return failed("active-image-set-state-invalid", err, "guest-image-set-state")
	}
	contents, err := json.Marshal(selection)
	if err != nil {
		return failed("active-image-set-state-encode-failed", err, "guest-image-set-state")
	}
	if err := writeAtomicRegularFile(filepath.Join(repository.configuration.StateDirectory, "active-image-set.json"), append(contents, '\n'), 0o600); err != nil {
		return unavailable("active-image-set-state-write-failed", err, "guest-image-set-state")
	}
	return nil
}

// InitializeActiveImageSet is a one-time, explicit bootstrap transition. It
// is deliberately separate from ReadActiveImageSet: absence is not evidence
// that the Guest is safely unprovisioned. C39/bootstrap tooling must invoke
// this action with the declared selection before C64 serves update commands.
func (repository *ActiveImageSetFileRepository) InitializeActiveImageSet(_ context.Context, selection guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateActiveImageSetSelection(selection); err != nil {
		return failed("initial-active-image-set-invalid", err, "guest-image-set-state")
	}
	contents, err := json.Marshal(selection)
	if err != nil {
		return failed("initial-active-image-set-encode-failed", err, "guest-image-set-state")
	}
	path := filepath.Join(repository.configuration.StateDirectory, "active-image-set.json")
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		return failed("initial-active-image-set-already-provisioned", fmt.Errorf("C64 active image-set selection already exists"), "guest-image-set-state")
	}
	if err != nil {
		return unavailable("initial-active-image-set-write-failed", err, "guest-image-set-state")
	}
	if _, err := file.Write(append(contents, '\n')); err != nil {
		_ = file.Close()
		_ = os.Remove(path)
		return unavailable("initial-active-image-set-write-failed", err, "guest-image-set-state")
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return unavailable("initial-active-image-set-write-failed", err, "guest-image-set-state")
	}
	if err := file.Close(); err != nil {
		return unavailable("initial-active-image-set-write-failed", err, "guest-image-set-state")
	}
	return nil
}

func ensureStateRoots(configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration) error {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return err
	}
	if err := os.MkdirAll(configuration.StateDirectory, 0o700); err != nil {
		return fmt.Errorf("create C64 state directory: %w", err)
	}
	if err := requireDirectory(configuration.StateDirectory); err != nil {
		return fmt.Errorf("validate C64 state directory: %w", err)
	}
	return nil
}

func readRegularFile(path string) ([]byte, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, false, fmt.Errorf("path is missing, non-regular, or a symbolic link")
	}
	contents, err := os.ReadFile(path)
	return contents, true, err
}

func decodeOneStrictJSON(contents []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("multiple documents")
	}
	return nil
}

func writeAtomicRegularFile(path string, contents []byte, mode os.FileMode) error {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func requireDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("directory is missing, not a directory, or a symbolic link")
	}
	return nil
}

func failed(code string, err error, dependency string) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	return &guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure{State: guestbundledupstreamimagesetmanagerdomain.OperationStateFailed, Issue: guestbundledupstreamimagesetmanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}}
}
func unavailable(code string, err error, dependency string) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	return &guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure{State: guestbundledupstreamimagesetmanagerdomain.OperationStateUnavailable, Issue: guestbundledupstreamimagesetmanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}}
}

var _ guestbundledupstreamimagesetmanagerapplication.ImageSetOperationRepository = (*ImageSetOperationFileRepository)(nil)
var _ guestbundledupstreamimagesetmanagerapplication.ActiveImageSetRepository = (*ActiveImageSetFileRepository)(nil)
