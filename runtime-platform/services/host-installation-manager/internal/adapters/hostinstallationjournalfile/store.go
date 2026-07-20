// Package hostinstallationjournalfile owns atomic C50 journal persistence.
package hostinstallationjournalfile

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

const maximumHostInstallationJournalBytes = 1024 * 1024

type HostInstallationJournalFileStore struct{}

func (HostInstallationJournalFileStore) ReadHostInstallationJournal(_ context.Context, path string) (hostinstallationmanagerdomain.HostInstallationJournal, error) {
	if path == "" {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("Host installation journal path is required")
	}
	info, statError := os.Lstat(path)
	if statError != nil {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("inspect Host installation journal: %w", statError)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("Host installation journal must be a regular non-symbolic-link file")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("open Host installation journal: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, maximumHostInstallationJournalBytes+1))
	decoder.DisallowUnknownFields()
	var journal hostinstallationmanagerdomain.HostInstallationJournal
	if err := decoder.Decode(&journal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("decode Host installation journal: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("Host installation journal must contain one JSON document")
		}
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("read Host installation journal trailing content: %w", err)
	}
	if err := hostinstallationmanagerdomain.ValidateHostInstallationJournal(journal); err != nil {
		return hostinstallationmanagerdomain.HostInstallationJournal{}, fmt.Errorf("validate Host installation journal: %w", err)
	}
	return journal, nil
}

func (HostInstallationJournalFileStore) WriteHostInstallationJournal(_ context.Context, path string, journal hostinstallationmanagerdomain.HostInstallationJournal) error {
	if path == "" {
		return fmt.Errorf("Host installation journal path is required")
	}
	if err := hostinstallationmanagerdomain.ValidateHostInstallationJournal(journal); err != nil {
		return fmt.Errorf("validate Host installation journal: %w", err)
	}
	return WriteHostInstallationDocumentJSON(path, journal)
}

// WriteHostInstallationDocumentJSON is shared by C50 journal and receipt
// adapters so both documents are persisted atomically with identical rules.
func WriteHostInstallationDocumentJSON(path string, document any) error {
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return fmt.Errorf("inspect Host installation document path: %w", err)
	}
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0750); err != nil {
		return fmt.Errorf("create Host installation document directory: %w", err)
	}
	if err := hostinstallationfilesystem.RejectSymbolicLinkPathComponents(path); err != nil {
		return fmt.Errorf("verify Host installation document path after directory creation: %w", err)
	}
	temporaryFile, err := os.CreateTemp(directory, ".host-installation-document-")
	if err != nil {
		return fmt.Errorf("create temporary Host installation document: %w", err)
	}
	temporaryPath := temporaryFile.Name()
	defer os.Remove(temporaryPath)
	if err := temporaryFile.Chmod(0600); err != nil {
		temporaryFile.Close()
		return fmt.Errorf("set temporary Host installation document mode: %w", err)
	}
	encoder := json.NewEncoder(temporaryFile)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(document); err != nil {
		temporaryFile.Close()
		return fmt.Errorf("encode Host installation document: %w", err)
	}
	if err := temporaryFile.Sync(); err != nil {
		temporaryFile.Close()
		return fmt.Errorf("sync Host installation document: %w", err)
	}
	if err := temporaryFile.Close(); err != nil {
		return fmt.Errorf("close Host installation document: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("replace Host installation document atomically: %w", err)
	}
	return nil
}
