package gueststatesqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabReplaySourceAdmission(
	ctx context.Context,
	requestID string,
) (guestruntimeapplication.StoredLabReplaySourceAdmission, error) {
	var commandDigest string
	var encodedCommand string
	var encodedReceipt string
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT command_digest, command_json, receipt_json
		   FROM lab_replay_source_admissions
		  WHERE request_id = ?`,
		requestID,
	).Scan(&commandDigest, &encodedCommand, &encodedReceipt)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{},
			fmt.Errorf("read Lab replay source admission: %w", err)
	}
	var command guestruntimedomain.LabReplaySourceAdmissionCommand
	if err := json.Unmarshal([]byte(encodedCommand), &command); err != nil {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{},
			fmt.Errorf("decode Lab replay source command: %w", err)
	}
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		guestruntimedomain.MaximumLabReplaySourceByteSize,
	); err != nil {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{}, err
	}
	var receipt guestruntimedomain.LabReplaySourceAdmissionReceipt
	if err := json.Unmarshal([]byte(encodedReceipt), &receipt); err != nil {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{},
			fmt.Errorf("decode Lab replay source receipt: %w", err)
	}
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionReceipt(receipt); err != nil {
		return guestruntimeapplication.StoredLabReplaySourceAdmission{}, err
	}
	return guestruntimeapplication.StoredLabReplaySourceAdmission{
		CommandDigest: commandDigest,
		Command:       command,
		Receipt:       receipt,
	}, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitLabReplaySourceAdmission(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.LabReplaySourceAdmissionCommand,
	receipt guestruntimedomain.LabReplaySourceAdmissionReceipt,
) error {
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		guestruntimedomain.MaximumLabReplaySourceByteSize,
	); err != nil {
		return err
	}
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionReceipt(receipt); err != nil {
		return err
	}
	if command.RequestID != receipt.RequestID ||
		command.SourceID != receipt.SourceReference.ResourceID ||
		command.OriginalFileName != receipt.OriginalFileName ||
		command.MediaType != receipt.MediaType ||
		command.ByteSize != receipt.ByteSize ||
		command.SHA256 != receipt.SHA256 {
		return fmt.Errorf("Lab replay source command and receipt do not match")
	}
	encodedCommand, err := json.Marshal(command)
	if err != nil {
		return fmt.Errorf("encode Lab replay source command: %w", err)
	}
	encodedReceipt, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode Lab replay source receipt: %w", err)
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO lab_replay_source_admissions (
		   request_id, source_id, command_digest, command_json, receipt_json
		 ) VALUES (?, ?, ?, ?, ?)`,
		command.RequestID,
		command.SourceID,
		commandDigest,
		string(encodedCommand),
		string(encodedReceipt),
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
		return fmt.Errorf("commit Lab replay source admission: %w", err)
	}
	return nil
}

var _ guestruntimeapplication.GuestRuntimeLabReplaySourceRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
