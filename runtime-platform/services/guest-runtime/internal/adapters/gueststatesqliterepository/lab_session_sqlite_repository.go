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

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabSession(ctx context.Context, id string) (guestruntimedomain.LabSession, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM lab_sessions WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.LabSession{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.LabSession{}, fmt.Errorf("read Lab session: %w", err)
	}
	var session guestruntimedomain.LabSession
	if err := json.Unmarshal([]byte(encoded), &session); err != nil {
		return guestruntimedomain.LabSession{}, fmt.Errorf("decode owned Lab session: %w", err)
	}
	return session, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListLabSessions(ctx context.Context) ([]guestruntimedomain.LabSession, error) {
	rows, err := repository.database.QueryContext(ctx, `SELECT document_json FROM lab_sessions ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("list Lab sessions: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.LabSession{}
	for rows.Next() {
		var encoded string
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan Lab session: %w", err)
		}
		var session guestruntimedomain.LabSession
		if err := json.Unmarshal([]byte(encoded), &session); err != nil {
			return nil, fmt.Errorf("decode owned Lab session: %w", err)
		}
		result = append(result, session)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Lab sessions: %w", err)
	}
	return result, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabBed(ctx context.Context, id string) (guestruntimedomain.LabBed, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM lab_beds WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.LabBed{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.LabBed{}, fmt.Errorf("read Lab bed: %w", err)
	}
	var bed guestruntimedomain.LabBed
	if err := json.Unmarshal([]byte(encoded), &bed); err != nil {
		return guestruntimedomain.LabBed{}, fmt.Errorf("decode owned Lab bed: %w", err)
	}
	return bed, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListLabBeds(ctx context.Context) ([]guestruntimedomain.LabBed, error) {
	return repository.listLabBeds(ctx, `SELECT document_json FROM lab_beds ORDER BY id`)
}

func (repository *GuestRuntimeStateSQLiteRepository) ListLabBedsBySession(ctx context.Context, sessionID string) ([]guestruntimedomain.LabBed, error) {
	return repository.listLabBeds(ctx, `SELECT document_json FROM lab_beds WHERE session_id = ? ORDER BY id`, sessionID)
}

func (repository *GuestRuntimeStateSQLiteRepository) listLabBeds(ctx context.Context, query string, values ...any) ([]guestruntimedomain.LabBed, error) {
	rows, err := repository.database.QueryContext(ctx, query, values...)
	if err != nil {
		return nil, fmt.Errorf("list Lab beds: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.LabBed{}
	for rows.Next() {
		var encoded string
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan Lab bed: %w", err)
		}
		var bed guestruntimedomain.LabBed
		if err := json.Unmarshal([]byte(encoded), &bed); err != nil {
			return nil, fmt.Errorf("decode owned Lab bed: %w", err)
		}
		result = append(result, bed)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Lab beds: %w", err)
	}
	return result, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabVirtualRecorder(ctx context.Context, id string) (guestruntimedomain.VirtualRecorder, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM lab_virtual_recorders WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.VirtualRecorder{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.VirtualRecorder{}, fmt.Errorf("read virtual recorder: %w", err)
	}
	var recorder guestruntimedomain.VirtualRecorder
	if err := json.Unmarshal([]byte(encoded), &recorder); err != nil {
		return guestruntimedomain.VirtualRecorder{}, fmt.Errorf("decode owned virtual recorder: %w", err)
	}
	return recorder, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListVirtualRecorders(ctx context.Context) ([]guestruntimedomain.VirtualRecorder, error) {
	return repository.listVirtualRecorders(ctx, `SELECT document_json FROM lab_virtual_recorders ORDER BY id`)
}

func (repository *GuestRuntimeStateSQLiteRepository) ListVirtualRecordersBySession(ctx context.Context, sessionID string) ([]guestruntimedomain.VirtualRecorder, error) {
	return repository.listVirtualRecorders(ctx, `SELECT document_json FROM lab_virtual_recorders WHERE session_id = ? ORDER BY id`, sessionID)
}

func (repository *GuestRuntimeStateSQLiteRepository) listVirtualRecorders(ctx context.Context, query string, values ...any) ([]guestruntimedomain.VirtualRecorder, error) {
	rows, err := repository.database.QueryContext(ctx, query, values...)
	if err != nil {
		return nil, fmt.Errorf("list virtual recorders: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.VirtualRecorder{}
	for rows.Next() {
		var encoded string
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan virtual recorder: %w", err)
		}
		var recorder guestruntimedomain.VirtualRecorder
		if err := json.Unmarshal([]byte(encoded), &recorder); err != nil {
			return nil, fmt.Errorf("decode owned virtual recorder: %w", err)
		}
		result = append(result, recorder)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate virtual recorders: %w", err)
	}
	return result, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabOperation(ctx context.Context, id string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperation(ctx, id)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabResourceDeletionReceipt(ctx context.Context, id string) (guestruntimedomain.DeletionReceipt, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM lab_deletion_receipts WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.DeletionReceipt{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.DeletionReceipt{}, fmt.Errorf("read deletion receipt: %w", err)
	}
	var receipt guestruntimedomain.DeletionReceipt
	if err := json.Unmarshal([]byte(encoded), &receipt); err != nil {
		return guestruntimedomain.DeletionReceipt{}, fmt.Errorf("decode owned deletion receipt: %w", err)
	}
	return receipt, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitLabStateTransition(ctx context.Context, commit guestruntimeapplication.LabStateTransitionCommit) error {
	if commit.Operation.ID == "" || commit.Operation.RequestID == "" {
		return fmt.Errorf("Lab commit requires an operation")
	}
	encoded, err := encodeLabCommit(commit)
	if err != nil {
		return err
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Lab transaction: %w", err)
	}
	defer transaction.Rollback()
	if commit.OperationContinuation {
		result, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ? AND request_id = ? AND command_digest = ?`, encoded.operation, commit.Operation.ID, commit.Operation.RequestID, commit.Operation.CommandDigest)
		if err != nil {
			return fmt.Errorf("persist Lab operation continuation: %w", err)
		}
		updated, err := result.RowsAffected()
		if err != nil {
			return fmt.Errorf("read Lab operation continuation result: %w", err)
		}
		if updated != 1 {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
	} else {
		if err := validateLabTargetRevision(ctx, transaction, commit.Operation.Target); err != nil {
			return err
		}
		if _, err := transaction.ExecContext(ctx, `INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, commit.Operation.ID, commit.Operation.RequestID, commit.Operation.CommandDigest, encoded.operation); err != nil {
			return mapLabConflict("persist Lab operation", err)
		}
	}
	if encoded.session != "" {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO lab_sessions (id, document_json) VALUES (?, ?)
 ON CONFLICT(id) DO UPDATE SET document_json = excluded.document_json`, commit.UpsertSession.ID, encoded.session); err != nil {
			return fmt.Errorf("persist Lab session: %w", err)
		}
	}
	for index, bed := range commit.UpsertBeds {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO lab_beds (id, session_id, document_json) VALUES (?, ?, ?)
 ON CONFLICT(id) DO UPDATE SET session_id = excluded.session_id, document_json = excluded.document_json`, bed.ID, bed.SessionReference.ResourceID, encoded.beds[index]); err != nil {
			return fmt.Errorf("persist Lab bed: %w", err)
		}
	}
	for index, recorder := range commit.UpsertRecorders {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO lab_virtual_recorders (id, session_id, document_json) VALUES (?, ?, ?)
 ON CONFLICT(id) DO UPDATE SET session_id = excluded.session_id, document_json = excluded.document_json`, recorder.ID, recorder.SessionReference.ResourceID, encoded.recorders[index]); err != nil {
			return fmt.Errorf("persist virtual recorder: %w", err)
		}
	}
	for _, id := range commit.DeleteRecorderIDs {
		if _, err := transaction.ExecContext(ctx, `DELETE FROM lab_virtual_recorders WHERE id = ?`, id); err != nil {
			return fmt.Errorf("delete virtual recorder: %w", err)
		}
	}
	for _, id := range commit.DeleteBedIDs {
		if _, err := transaction.ExecContext(ctx, `DELETE FROM lab_beds WHERE id = ?`, id); err != nil {
			return fmt.Errorf("delete Lab bed: %w", err)
		}
	}
	if commit.DeleteSessionID != "" {
		if _, err := transaction.ExecContext(ctx, `DELETE FROM lab_sessions WHERE id = ?`, commit.DeleteSessionID); err != nil {
			return fmt.Errorf("delete Lab session: %w", err)
		}
	}
	if commit.DeletionReceipt != nil {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO lab_deletion_receipts (id, operation_id, request_id, document_json) VALUES (?, ?, ?, ?)`, commit.DeletionReceipt.ID, commit.DeletionReceipt.OperationID, commit.DeletionReceipt.RequestID, encoded.deletionReceipt); err != nil {
			return mapLabConflict("persist deletion receipt", err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Lab transaction: %w", err)
	}
	return nil
}

type encodedLabCommit struct {
	operation       string
	session         string
	beds            []string
	recorders       []string
	deletionReceipt string
}

func encodeLabCommit(commit guestruntimeapplication.LabStateTransitionCommit) (encodedLabCommit, error) {
	operation, err := json.Marshal(commit.Operation)
	if err != nil {
		return encodedLabCommit{}, fmt.Errorf("encode Lab operation: %w", err)
	}
	result := encodedLabCommit{operation: string(operation), beds: make([]string, len(commit.UpsertBeds)), recorders: make([]string, len(commit.UpsertRecorders))}
	if commit.UpsertSession != nil {
		encoded, err := json.Marshal(*commit.UpsertSession)
		if err != nil {
			return encodedLabCommit{}, fmt.Errorf("encode Lab session: %w", err)
		}
		result.session = string(encoded)
	}
	for index, bed := range commit.UpsertBeds {
		encoded, err := json.Marshal(bed)
		if err != nil {
			return encodedLabCommit{}, fmt.Errorf("encode Lab bed: %w", err)
		}
		result.beds[index] = string(encoded)
	}
	for index, recorder := range commit.UpsertRecorders {
		encoded, err := json.Marshal(recorder)
		if err != nil {
			return encodedLabCommit{}, fmt.Errorf("encode virtual recorder: %w", err)
		}
		result.recorders[index] = string(encoded)
	}
	if commit.DeletionReceipt != nil {
		encoded, err := json.Marshal(*commit.DeletionReceipt)
		if err != nil {
			return encodedLabCommit{}, fmt.Errorf("encode deletion receipt: %w", err)
		}
		result.deletionReceipt = string(encoded)
	}
	return result, nil
}

func validateLabTargetRevision(ctx context.Context, transaction *sql.Tx, target guestruntimedomain.OperationTarget) error {
	table, err := labResourceTable(target.ResourceType)
	if err != nil {
		return err
	}
	var encoded string
	err = transaction.QueryRowContext(ctx, `SELECT document_json FROM `+table+` WHERE id = ?`, target.ResourceID).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		if target.RequestedResourceRevision == 0 {
			return nil
		}
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	if err != nil {
		return fmt.Errorf("read Lab target revision: %w", err)
	}
	if target.RequestedResourceRevision == 0 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	var revision struct {
		ResourceRevision int `json:"resourceRevision"`
	}
	if err := json.Unmarshal([]byte(encoded), &revision); err != nil {
		return fmt.Errorf("decode Lab target revision: %w", err)
	}
	if revision.ResourceRevision != target.RequestedResourceRevision {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	return nil
}

func labResourceTable(resourceType string) (string, error) {
	switch resourceType {
	case guestruntimedomain.LabSessionResourceType:
		return "lab_sessions", nil
	case guestruntimedomain.LabBedResourceType:
		return "lab_beds", nil
	case guestruntimedomain.VirtualRecorderResourceType:
		return "lab_virtual_recorders", nil
	default:
		return "", fmt.Errorf("unsupported Lab resource type %q", resourceType)
	}
}

func mapLabConflict(subject string, err error) error {
	if strings.Contains(strings.ToLower(err.Error()), "unique") {
		return fmt.Errorf("%w: %s", guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict, subject)
	}
	return fmt.Errorf("%s: %w", subject, err)
}

var _ guestruntimeapplication.GuestRuntimeLabStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
