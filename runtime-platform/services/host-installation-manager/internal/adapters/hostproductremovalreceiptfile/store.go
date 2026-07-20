// Package hostproductremovalreceiptfile owns strict C54 receipt persistence
// for a data-preserving removal. A purge intentionally returns its receipt on
// stdout only because no in-product file is allowed to survive that command.
package hostproductremovalreceiptfile

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type HostProductRemovalReceiptFileStore struct{}

func (HostProductRemovalReceiptFileStore) WriteHostProductRemovalReceipt(_ context.Context, path string, receipt hostinstallationmanagerdomain.HostProductRemovalReceipt) error {
	if path == "" {
		return fmt.Errorf("Host product removal receipt path is required")
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductRemovalReceipt(receipt); err != nil {
		return fmt.Errorf("validate Host product removal receipt: %w", err)
	}
	return hostinstallationjournalfile.WriteHostInstallationDocumentJSON(path, receipt)
}
