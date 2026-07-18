// Package hostinstallationreceiptfile owns atomic C50 receipt persistence.
package hostinstallationreceiptfile

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostInstallationReceiptFileStore struct{}

func (HostInstallationReceiptFileStore) WriteHostInstallationReceipt(_ context.Context, path string, receipt hostinstallationmanagerdomain.HostInstallationReceipt) error {
	if path == "" {
		return fmt.Errorf("Host installation receipt path is required")
	}
	return hostinstallationjournalfile.WriteHostInstallationDocumentJSON(path, receipt)
}
