// Package hostproductremovaljournalfile owns strict, atomic C54 removal
// journal persistence. It deliberately reuses only the low-level atomic JSON
// writer; C50 and C54 remain different domain documents and validators.
package hostproductremovaljournalfile

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

const maximumHostProductRemovalJournalBytes = 1024 * 1024

type HostProductRemovalJournalFileStore struct{}

func (HostProductRemovalJournalFileStore) ReadHostProductRemovalJournal(_ context.Context, path string) (hostinstallationmanagerdomain.HostProductRemovalJournal, error) {
	if path == "" {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("Host product removal journal path is required")
	}
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("inspect Host product removal journal path: %w", err)
	}
	info, err := os.Lstat(path)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("inspect Host product removal journal: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("Host product removal journal must be a regular non-symbolic-link file")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("open Host product removal journal: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, maximumHostProductRemovalJournalBytes+1))
	decoder.DisallowUnknownFields()
	var journal hostinstallationmanagerdomain.HostProductRemovalJournal
	if err := decoder.Decode(&journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("decode Host product removal journal: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("Host product removal journal must contain one JSON document")
		}
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("read Host product removal journal trailing content: %w", err)
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductRemovalJournal(journal); err != nil {
		return hostinstallationmanagerdomain.HostProductRemovalJournal{}, fmt.Errorf("validate Host product removal journal: %w", err)
	}
	return journal, nil
}

func (HostProductRemovalJournalFileStore) WriteHostProductRemovalJournal(_ context.Context, path string, journal hostinstallationmanagerdomain.HostProductRemovalJournal) error {
	if path == "" {
		return fmt.Errorf("Host product removal journal path is required")
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductRemovalJournal(journal); err != nil {
		return fmt.Errorf("validate Host product removal journal: %w", err)
	}
	return hostinstallationjournalfile.WriteHostInstallationDocumentJSON(path, journal)
}
