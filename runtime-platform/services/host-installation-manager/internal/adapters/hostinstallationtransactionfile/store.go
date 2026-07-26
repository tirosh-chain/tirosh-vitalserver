// Package hostinstallationtransactionfile records the terminal C50 state
// produced by a C68 transition. It derives only the explicitly named C48
// transaction store; no active release path or state directory is guessed.
package hostinstallationtransactionfile

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type Store struct{}

// RecordHostInstallationTransaction writes the receipt before the journal.
// The journal is C49's terminal transaction marker; keeping it second means a
// failed receipt write cannot leave C49 claiming a completed C50 transition.
func (Store) RecordHostInstallationTransaction(
	context context.Context,
	manifest hostinstallationmanagerdomain.HostProductInstallationManifest,
	journal hostinstallationmanagerdomain.HostInstallationJournal,
	receipt hostinstallationmanagerdomain.HostInstallationReceipt,
) error {
	journalPath, receiptPath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionPaths(manifest)
	if err != nil {
		return fmt.Errorf("resolve declared C50 transaction paths: %w", err)
	}
	if err := (hostinstallationreceiptfile.HostInstallationReceiptFileStore{}).WriteHostInstallationReceipt(context, receiptPath, receipt); err != nil {
		return fmt.Errorf("write C50 terminal receipt: %w", err)
	}
	if err := (hostinstallationjournalfile.HostInstallationJournalFileStore{}).WriteHostInstallationJournal(context, journalPath, journal); err != nil {
		return fmt.Errorf("write C50 terminal journal: %w", err)
	}
	return nil
}
