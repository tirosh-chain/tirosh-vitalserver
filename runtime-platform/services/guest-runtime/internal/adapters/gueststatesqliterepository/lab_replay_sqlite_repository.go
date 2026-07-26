package gueststatesqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabReplayOperation(
	ctx context.Context,
	replayID string,
) (guestruntimedomain.LabReplayOperation, error) {
	return repository.readLabReplayOperation(
		ctx,
		`SELECT document_json FROM lab_replay_operations WHERE id = ?`,
		replayID,
	)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadLabReplayOperationByRequestID(
	ctx context.Context,
	requestID string,
) (guestruntimedomain.LabReplayOperation, error) {
	return repository.readLabReplayOperation(
		ctx,
		`SELECT document_json FROM lab_replay_operations WHERE request_id = ?`,
		requestID,
	)
}

func (repository *GuestRuntimeStateSQLiteRepository) readLabReplayOperation(
	ctx context.Context,
	statement string,
	value string,
) (guestruntimedomain.LabReplayOperation, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, statement, value).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.LabReplayOperation{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("read Lab replay operation: %w", err)
	}
	return decodeLabReplayOperation(encoded)
}

func (repository *GuestRuntimeStateSQLiteRepository) AdmitLabReplayOperation(
	ctx context.Context,
	commandDigest string,
	operation guestruntimedomain.LabReplayOperation,
	effectCommand string,
) error {
	if len(commandDigest) != 64 {
		return fmt.Errorf("Lab replay command digest is invalid")
	}
	if err := guestruntimedomain.ValidateLabReplayOperation(operation); err != nil {
		return err
	}
	expectedCommand, ok := guestruntimedomain.LabReplayCommandForState(operation.State)
	if !ok || effectCommand != expectedCommand || operation.ResourceRevision != 1 {
		return fmt.Errorf("Lab replay admission effect does not match operation state")
	}
	encoded, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode Lab replay operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Lab replay admission: %w", err)
	}
	defer transaction.Rollback()
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO lab_replay_operations(
			id, request_id, command_digest, resource_revision, document_json
		) VALUES (?, ?, ?, ?, ?)`,
		operation.ID,
		operation.RequestID,
		commandDigest,
		operation.ResourceRevision,
		string(encoded),
	); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
		return fmt.Errorf("persist Lab replay operation admission: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO lab_replay_effects(
			operation_id, operation_revision, command, state, created_at
		) VALUES (?, ?, ?, 'pending', ?)`,
		operation.ID,
		operation.ResourceRevision,
		effectCommand,
		operation.UpdatedAt,
	); err != nil {
		return fmt.Errorf("persist Lab replay admission effect: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Lab replay admission: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitLabReplayTransition(
	ctx context.Context,
	current guestruntimedomain.LabReplayOperation,
	next guestruntimedomain.LabReplayOperation,
	completedCommand string,
	nextCommand string,
) error {
	if err := validateLabReplayRepositoryTransition(
		current,
		next,
		completedCommand,
		nextCommand,
	); err != nil {
		return err
	}
	encodedNext, err := json.Marshal(next)
	if err != nil {
		return fmt.Errorf("encode next Lab replay operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Lab replay transition: %w", err)
	}
	defer transaction.Rollback()
	var encodedCurrent string
	var storedRevision int
	err = transaction.QueryRowContext(
		ctx,
		`SELECT resource_revision, document_json
		   FROM lab_replay_operations
		  WHERE id = ?`,
		current.ID,
	).Scan(&storedRevision, &encodedCurrent)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return fmt.Errorf("read current Lab replay transition state: %w", err)
	}
	storedCurrent, err := decodeLabReplayOperation(encodedCurrent)
	if err != nil {
		return err
	}
	if storedRevision != current.ResourceRevision ||
		!reflect.DeepEqual(storedCurrent, current) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	effectResult, err := transaction.ExecContext(
		ctx,
		`UPDATE lab_replay_effects
		    SET state = 'completed', completed_at = ?
		  WHERE operation_id = ?
		    AND operation_revision = ?
		    AND command = ?
		    AND state = 'pending'`,
		next.UpdatedAt,
		current.ID,
		current.ResourceRevision,
		completedCommand,
	)
	if err != nil {
		return fmt.Errorf("complete Lab replay effect: %w", err)
	}
	if affected, err := effectResult.RowsAffected(); err != nil {
		return fmt.Errorf("read Lab replay effect completion result: %w", err)
	} else if affected != 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	updateResult, err := transaction.ExecContext(
		ctx,
		`UPDATE lab_replay_operations
		    SET resource_revision = ?, document_json = ?
		  WHERE id = ? AND resource_revision = ?`,
		next.ResourceRevision,
		string(encodedNext),
		current.ID,
		current.ResourceRevision,
	)
	if err != nil {
		return fmt.Errorf("persist Lab replay transition: %w", err)
	}
	if affected, err := updateResult.RowsAffected(); err != nil {
		return fmt.Errorf("read Lab replay transition result: %w", err)
	} else if affected != 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	if nextCommand != "" {
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO lab_replay_effects(
				operation_id, operation_revision, command, state, created_at
			) VALUES (?, ?, ?, 'pending', ?)`,
			next.ID,
			next.ResourceRevision,
			nextCommand,
			next.UpdatedAt,
		); err != nil {
			return fmt.Errorf("persist next Lab replay effect: %w", err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Lab replay transition: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListPendingLabReplayEffects(
	ctx context.Context,
	limit int,
) ([]guestruntimeapplication.PendingLabReplayEffect, error) {
	if limit < 1 || limit > 100 {
		return nil, fmt.Errorf("Lab replay pending effect limit is invalid")
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT operation.document_json, effect.command, effect.created_at
		   FROM lab_replay_effects AS effect
		   JOIN lab_replay_operations AS operation
		     ON operation.id = effect.operation_id
		  WHERE effect.state = 'pending'
		    AND operation.resource_revision = effect.operation_revision
		  ORDER BY effect.created_at, effect.operation_id
		  LIMIT ?`,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list pending Lab replay effects: %w", err)
	}
	defer rows.Close()
	effects := make([]guestruntimeapplication.PendingLabReplayEffect, 0)
	for rows.Next() {
		var encodedOperation string
		var effect guestruntimeapplication.PendingLabReplayEffect
		if err := rows.Scan(
			&encodedOperation,
			&effect.Command,
			&effect.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan pending Lab replay effect: %w", err)
		}
		effect.Operation, err = decodeLabReplayOperation(encodedOperation)
		if err != nil {
			return nil, err
		}
		expectedCommand, ok := guestruntimedomain.LabReplayCommandForState(
			effect.Operation.State,
		)
		if !ok || expectedCommand != effect.Command {
			return nil, fmt.Errorf("pending Lab replay effect does not match operation state")
		}
		effects = append(effects, effect)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate pending Lab replay effects: %w", err)
	}
	return effects, nil
}

func validateLabReplayRepositoryTransition(
	current guestruntimedomain.LabReplayOperation,
	next guestruntimedomain.LabReplayOperation,
	completedCommand string,
	nextCommand string,
) error {
	if err := guestruntimedomain.ValidateLabReplayOperation(current); err != nil {
		return err
	}
	if err := guestruntimedomain.ValidateLabReplayOperation(next); err != nil {
		return err
	}
	expectedCompletedCommand, ok := guestruntimedomain.LabReplayCommandForState(
		current.State,
	)
	if !ok || completedCommand != expectedCompletedCommand ||
		next.ID != current.ID ||
		next.RequestID != current.RequestID ||
		next.ResourceRevision != current.ResourceRevision+1 ||
		next.SourceReference != current.SourceReference ||
		next.SourceSHA256 != current.SourceSHA256 ||
		next.RecorderGatewayRecorderCode != current.RecorderGatewayRecorderCode ||
		next.CreatedAt != current.CreatedAt {
		return fmt.Errorf("Lab replay repository transition is inconsistent")
	}
	expectedNextCommand, hasNextCommand := guestruntimedomain.LabReplayCommandForState(
		next.State,
	)
	if (hasNextCommand && nextCommand != expectedNextCommand) ||
		(!hasNextCommand && nextCommand != "") {
		return fmt.Errorf("Lab replay next effect does not match next state")
	}
	return nil
}

func decodeLabReplayOperation(
	encoded string,
) (guestruntimedomain.LabReplayOperation, error) {
	var operation guestruntimedomain.LabReplayOperation
	if err := json.Unmarshal([]byte(encoded), &operation); err != nil {
		return guestruntimedomain.LabReplayOperation{},
			fmt.Errorf("decode Lab replay operation: %w", err)
	}
	if err := guestruntimedomain.ValidateLabReplayOperation(operation); err != nil {
		return guestruntimedomain.LabReplayOperation{}, err
	}
	return operation, nil
}

var _ guestruntimeapplication.GuestRuntimeLabReplayRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
