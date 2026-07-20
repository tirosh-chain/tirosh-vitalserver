// Package hostplatformstagedreleaseoperationfile owns atomic C68 Host
// Installation Manager operation persistence below its declared mutable store.
package hostplatformstagedreleaseoperationfile

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

const maximumOperationBytes int64 = 1024 * 1024

type Store struct{}

func (Store) ReadHostPlatformStagedReleaseUpdateOperation(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operationID string) (hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation, error) {
	path, err := operationPath(manifest, operationID)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maximumOperationBytes {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("C68 operation is non-regular, symbolic, or too large")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	defer file.Close()
	content, err := io.ReadAll(io.LimitReader(file, maximumOperationBytes+1))
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(content)))
	decoder.DisallowUnknownFields()
	var operation hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation
	if err := decoder.Decode(&operation); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, fmt.Errorf("C68 operation contains multiple documents")
	}
	if err := hostplatformstagedreleaseupdatedomain.ValidateOperation(operation); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation{}, err
	}
	return operation, nil
}
func (Store) WriteHostPlatformStagedReleaseUpdateOperation(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operation hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateOperation) error {
	if err := hostplatformstagedreleaseupdatedomain.ValidateOperation(operation); err != nil {
		return err
	}
	path, err := operationPath(manifest, operation.OperationID)
	if err != nil {
		return err
	}
	if err := ensureNoSymbolicExistingAncestor(filepath.Dir(path)); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	content, err := json.Marshal(operation)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".c68-operation-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(append(content, '\n')); err != nil {
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
func (Store) ReadHostPlatformStagedReleaseRecoveryReceipt(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operationID, recoveryID string) (hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt, error) {
	path, err := recoveryPath(manifest, operationID, recoveryID)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maximumOperationBytes {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("C68 recovery receipt is non-regular, symbolic, or too large")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	defer file.Close()
	content, err := io.ReadAll(io.LimitReader(file, maximumOperationBytes+1))
	if err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(content)))
	decoder.DisallowUnknownFields()
	var receipt hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, fmt.Errorf("C68 recovery receipt contains multiple documents")
	}
	if err := hostplatformstagedreleaseupdatedomain.ValidateRecoveryReceipt(receipt); err != nil {
		return hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt{}, err
	}
	return receipt, nil
}
func (Store) WriteHostPlatformStagedReleaseRecoveryReceipt(_ context.Context, manifest hostinstallationmanagerdomain.HostProductInstallationManifest, receipt hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryReceipt) error {
	if err := hostplatformstagedreleaseupdatedomain.ValidateRecoveryReceipt(receipt); err != nil {
		return err
	}
	path, err := recoveryPath(manifest, receipt.OperationID, receipt.RecoveryID)
	if err != nil {
		return err
	}
	if err := ensureNoSymbolicExistingAncestor(filepath.Dir(path)); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	content, err := json.Marshal(receipt)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".c68-recovery-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(append(content, '\n')); err != nil {
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
func operationPath(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operationID string) (string, error) {
	if !safeIdentifier(operationID) {
		return "", fmt.Errorf("C68 operation id is required")
	}
	storePath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionStorePath(manifest)
	if err != nil {
		return "", fmt.Errorf("resolve C48 C68 operation store: %w", err)
	}
	return filepath.Join(storePath, "host-platform-release-updates", "operations", operationID+".json"), nil
}
func recoveryPath(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, operationID, recoveryID string) (string, error) {
	if !safeIdentifier(operationID) || !safeIdentifier(recoveryID) {
		return "", fmt.Errorf("C68 recovery operation and recovery ids are required")
	}
	storePath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionStorePath(manifest)
	if err != nil {
		return "", fmt.Errorf("resolve C48 C68 recovery store: %w", err)
	}
	return filepath.Join(storePath, "host-platform-release-updates", "recoveries", operationID, recoveryID+".json"), nil
}
func safeIdentifier(value string) bool {
	return value != "" && !strings.ContainsAny(value, `/\\`) && !strings.Contains(value, "..")
}
func ensureNoSymbolicExistingAncestor(value string) error {
	current := filepath.Clean(value)
	for {
		info, err := os.Lstat(current)
		if err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C68 operation path has symbolic ancestor %s", current)
		}
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		current = parent
	}
}
