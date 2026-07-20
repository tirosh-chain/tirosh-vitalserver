// Package hostinstallationreceiptfile owns atomic C50 receipt persistence.
package hostinstallationreceiptfile

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

const maximumHostInstallationReceiptBytes = 1024 * 1024

type HostInstallationReceiptFileStore struct{}

// ReadHostInstallationReceipt decodes one strict C50 receipt. The caller may
// distinguish a missing path before calling this method, but a present unreadable,
// symbolic-link, malformed, or invalid receipt always remains an error.
func (HostInstallationReceiptFileStore) ReadHostInstallationReceipt(_ context.Context, path string) (hostinstallationmanagerdomain.HostInstallationReceipt, error) {
	if path == "" {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("Host installation receipt path is required")
	}
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("inspect Host installation receipt path: %w", err)
	}
	info, statError := os.Lstat(path)
	if statError != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("inspect Host installation receipt: %w", statError)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("Host installation receipt must be a regular non-symbolic-link file")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("open Host installation receipt: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, maximumHostInstallationReceiptBytes+1))
	decoder.DisallowUnknownFields()
	var receipt hostinstallationmanagerdomain.HostInstallationReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("decode Host installation receipt: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("Host installation receipt must contain one JSON document")
		}
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("read Host installation receipt trailing content: %w", err)
	}
	if err := hostinstallationmanagerdomain.ValidateHostInstallationReceipt(receipt); err != nil {
		return hostinstallationmanagerdomain.HostInstallationReceipt{}, fmt.Errorf("validate Host installation receipt: %w", err)
	}
	return receipt, nil
}

func (HostInstallationReceiptFileStore) WriteHostInstallationReceipt(_ context.Context, path string, receipt hostinstallationmanagerdomain.HostInstallationReceipt) error {
	if path == "" {
		return fmt.Errorf("Host installation receipt path is required")
	}
	if err := hostinstallationmanagerdomain.ValidateHostInstallationReceipt(receipt); err != nil {
		return fmt.Errorf("validate Host installation receipt: %w", err)
	}
	return hostinstallationjournalfile.WriteHostInstallationDocumentJSON(path, receipt)
}
