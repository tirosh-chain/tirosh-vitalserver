// Package guestproductreleasefilesystem owns C59 filesystem effects. It
// rejects missing, symlinked, malformed, or non-atomic state instead of
// translating those conditions to an empty release operation.
package guestproductreleasefilesystem

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

type ReleaseOperationFileRepository struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
}

func NewReleaseOperationFileRepository(configuration guestproductreleasemanagerdomain.ManagerConfiguration) (*ReleaseOperationFileRepository, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(configuration.StateDirectory, 0o700); err != nil {
		return nil, fmt.Errorf("create C59 state directory: %w", err)
	}
	if err := requireDirectory(configuration.StateDirectory); err != nil {
		return nil, fmt.Errorf("validate C59 state directory: %w", err)
	}
	operationsDirectory := filepath.Join(configuration.StateDirectory, "operations")
	if err := os.MkdirAll(operationsDirectory, 0o700); err != nil {
		return nil, fmt.Errorf("create C59 operation directory: %w", err)
	}
	if err := requireDirectory(operationsDirectory); err != nil {
		return nil, fmt.Errorf("validate C59 operation directory: %w", err)
	}
	return &ReleaseOperationFileRepository{configuration: configuration}, nil
}

func (repository *ReleaseOperationFileRepository) ReadReleaseOperation(_ context.Context, updateID string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error) {
	path, err := repository.operationPath(updateID)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, err
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, fmt.Errorf("C59 operation record is missing, non-regular, or a symbolic link")
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, fmt.Errorf("read C59 operation record: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var operation guestproductreleasemanagerdomain.GuestProductReleaseOperation
	if err := decoder.Decode(&operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, fmt.Errorf("decode C59 operation record: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, fmt.Errorf("C59 operation record contains multiple documents")
	}
	if err := guestproductreleasemanagerdomain.ValidateReleaseOperation(repository.configuration, operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, false, fmt.Errorf("validate C59 operation record: %w", err)
	}
	return operation, true, nil
}

func (repository *ReleaseOperationFileRepository) WriteReleaseOperation(_ context.Context, operation guestproductreleasemanagerdomain.GuestProductReleaseOperation) error {
	if err := guestproductreleasemanagerdomain.ValidateReleaseOperation(repository.configuration, operation); err != nil {
		return err
	}
	path, err := repository.operationPath(operation.UpdateID)
	if err != nil {
		return err
	}
	contents, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode C59 operation record: %w", err)
	}
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, "."+operation.UpdateID+".*.tmp")
	if err != nil {
		return fmt.Errorf("create C59 operation temporary record: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return fmt.Errorf("write C59 operation temporary record: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync C59 operation temporary record: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close C59 operation temporary record: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("publish C59 operation record: %w", err)
	}
	return nil
}

func (repository *ReleaseOperationFileRepository) operationPath(updateID string) (string, error) {
	if updateID == "" || strings.ContainsAny(updateID, `/\\`) || strings.Contains(updateID, "..") {
		return "", fmt.Errorf("C59 operation id is unsafe")
	}
	return filepath.Join(repository.configuration.StateDirectory, "operations", updateID+".json"), nil
}

func requireDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("directory is missing, not a directory, or a symbolic link")
	}
	return nil
}

var _ guestproductreleasemanagerapplication.ReleaseOperationRepository = (*ReleaseOperationFileRepository)(nil)
