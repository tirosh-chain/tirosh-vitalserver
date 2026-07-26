// Package gueststatebackupsqliterepository owns the durable C76 workflow
// ledger. It is intentionally separate from the Guest Runtime SQLite database
// that C76 snapshots and restores.
package gueststatebackupsqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type Repository struct {
	database *sql.DB
}

func Open(ctx context.Context, databasePath string) (*Repository, error) {
	if !filepath.IsAbs(databasePath) {
		return nil, fmt.Errorf("Guest operational-state backup ledger path must be absolute")
	}
	parent := filepath.Dir(databasePath)
	info, err := os.Stat(parent)
	if err != nil {
		return nil, fmt.Errorf("Guest operational-state backup ledger parent is unreadable: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("Guest operational-state backup ledger parent is not a directory")
	}
	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return nil, fmt.Errorf("open Guest operational-state backup ledger: %w", err)
	}
	database.SetMaxOpenConns(1)
	repository := &Repository{database: database}
	if err := repository.migrate(ctx); err != nil {
		database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *Repository) Close() error {
	return repository.database.Close()
}

func (repository *Repository) migrate(ctx context.Context) error {
	for _, statement := range []string{
		`PRAGMA foreign_keys = ON`,
		`PRAGMA journal_mode = WAL`,
		`CREATE TABLE IF NOT EXISTS backup_operations (
			id TEXT PRIMARY KEY,
			request_id TEXT NOT NULL UNIQUE,
			command_digest TEXT NOT NULL,
			resource_revision INTEGER NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS backup_effects (
			operation_id TEXT NOT NULL REFERENCES backup_operations(id),
			operation_revision INTEGER NOT NULL,
			effect TEXT NOT NULL,
			state TEXT NOT NULL CHECK (state IN ('pending', 'completed')),
			created_at TEXT NOT NULL,
			completed_at TEXT,
			PRIMARY KEY (operation_id, operation_revision)
		)`,
		`CREATE INDEX IF NOT EXISTS backup_effects_pending
		 ON backup_effects(state, created_at, operation_id)`,
	} {
		if _, err := repository.database.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate Guest operational-state backup ledger: %w", err)
		}
	}
	return nil
}

func (repository *Repository) ReadOperation(
	ctx context.Context,
	operationID string,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	return repository.readOperation(
		ctx,
		`SELECT document_json FROM backup_operations WHERE id = ?`,
		operationID,
	)
}

func (repository *Repository) ReadOperationByRequestID(
	ctx context.Context,
	requestID string,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	return repository.readOperation(
		ctx,
		`SELECT document_json FROM backup_operations WHERE request_id = ?`,
		requestID,
	)
}

func (repository *Repository) readOperation(
	ctx context.Context,
	statement string,
	value string,
) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, statement, value).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.GuestOperationalStateBackupOperation{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{},
			fmt.Errorf("read Guest operational-state backup operation: %w", err)
	}
	return decodeOperation(encoded)
}

func (repository *Repository) AdmitOperation(
	ctx context.Context,
	commandDigest string,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	effect string,
) error {
	if len(commandDigest) != 64 {
		return fmt.Errorf("Guest operational-state backup command digest is invalid")
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupOperation(operation); err != nil {
		return err
	}
	expectedEffect, ok := guestruntimedomain.GuestOperationalStateBackupEffectForState(operation)
	if !ok ||
		effect != expectedEffect ||
		effect != guestruntimedomain.GuestStateBackupStartWorkflowEffect ||
		operation.ResourceRevision != 1 {
		return fmt.Errorf("Guest operational-state backup admission effect does not match operation")
	}
	encoded, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode Guest operational-state backup operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Guest operational-state backup admission: %w", err)
	}
	defer transaction.Rollback()
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO backup_operations(
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
		return fmt.Errorf("persist Guest operational-state backup admission: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO backup_effects(
			operation_id, operation_revision, effect, state, created_at
		) VALUES (?, ?, ?, 'pending', ?)`,
		operation.ID,
		operation.ResourceRevision,
		effect,
		operation.UpdatedAt,
	); err != nil {
		return fmt.Errorf("persist Guest operational-state backup admission effect: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Guest operational-state backup admission: %w", err)
	}
	return nil
}

func (repository *Repository) ListPendingEffects(
	ctx context.Context,
	limit int,
) ([]guestruntimeapplication.PendingGuestOperationalStateBackupEffect, error) {
	if limit < 1 || limit > 100 {
		return nil, fmt.Errorf("Guest operational-state backup pending effect limit is invalid")
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT operation.document_json, effect.effect
		   FROM backup_effects AS effect
		   JOIN backup_operations AS operation
		     ON operation.id = effect.operation_id
		  WHERE effect.state = 'pending'
		    AND operation.resource_revision = effect.operation_revision
		  ORDER BY effect.created_at, effect.operation_id
		  LIMIT ?`,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list Guest operational-state backup pending effects: %w", err)
	}
	defer rows.Close()
	effects := make([]guestruntimeapplication.PendingGuestOperationalStateBackupEffect, 0)
	for rows.Next() {
		var encoded string
		var effect string
		if err := rows.Scan(&encoded, &effect); err != nil {
			return nil, fmt.Errorf("scan Guest operational-state backup pending effect: %w", err)
		}
		operation, err := decodeOperation(encoded)
		if err != nil {
			return nil, err
		}
		expected, ok := guestruntimedomain.GuestOperationalStateBackupEffectForState(operation)
		if !ok || expected != effect {
			return nil, fmt.Errorf("Guest operational-state backup pending effect disagrees with operation")
		}
		effects = append(effects, guestruntimeapplication.PendingGuestOperationalStateBackupEffect{
			Operation: operation,
			Effect:    effect,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Guest operational-state backup pending effects: %w", err)
	}
	return effects, nil
}

func (repository *Repository) CommitTransition(
	ctx context.Context,
	current guestruntimedomain.GuestOperationalStateBackupOperation,
	next guestruntimedomain.GuestOperationalStateBackupOperation,
	completedEffect string,
	nextEffect string,
) error {
	if err := validateTransition(current, next, completedEffect, nextEffect); err != nil {
		return err
	}
	encodedNext, err := json.Marshal(next)
	if err != nil {
		return fmt.Errorf("encode next Guest operational-state backup operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Guest operational-state backup transition: %w", err)
	}
	defer transaction.Rollback()
	var storedRevision int
	var encodedCurrent string
	err = transaction.QueryRowContext(
		ctx,
		`SELECT resource_revision, document_json
		   FROM backup_operations
		  WHERE id = ?`,
		current.ID,
	).Scan(&storedRevision, &encodedCurrent)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return fmt.Errorf("read current Guest operational-state backup transition: %w", err)
	}
	storedCurrent, err := decodeOperation(encodedCurrent)
	if err != nil {
		return err
	}
	if storedRevision != current.ResourceRevision ||
		!reflect.DeepEqual(storedCurrent, current) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	effectResult, err := transaction.ExecContext(
		ctx,
		`UPDATE backup_effects
		    SET state = 'completed', completed_at = ?
		  WHERE operation_id = ?
		    AND operation_revision = ?
		    AND effect = ?
		    AND state = 'pending'`,
		next.UpdatedAt,
		current.ID,
		current.ResourceRevision,
		completedEffect,
	)
	if err != nil {
		return fmt.Errorf("complete Guest operational-state backup effect: %w", err)
	}
	affected, err := effectResult.RowsAffected()
	if err != nil {
		return fmt.Errorf("read Guest operational-state backup effect completion: %w", err)
	}
	if affected != 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	updateResult, err := transaction.ExecContext(
		ctx,
		`UPDATE backup_operations
		    SET resource_revision = ?, document_json = ?
		  WHERE id = ? AND resource_revision = ?`,
		next.ResourceRevision,
		string(encodedNext),
		current.ID,
		current.ResourceRevision,
	)
	if err != nil {
		return fmt.Errorf("persist Guest operational-state backup transition: %w", err)
	}
	affected, err = updateResult.RowsAffected()
	if err != nil {
		return fmt.Errorf("read Guest operational-state backup transition result: %w", err)
	}
	if affected != 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	if nextEffect != "" {
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO backup_effects(
				operation_id, operation_revision, effect, state, created_at
			) VALUES (?, ?, ?, 'pending', ?)`,
			next.ID,
			next.ResourceRevision,
			nextEffect,
			next.UpdatedAt,
		); err != nil {
			return fmt.Errorf("persist next Guest operational-state backup effect: %w", err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Guest operational-state backup transition: %w", err)
	}
	return nil
}

func validateTransition(
	current guestruntimedomain.GuestOperationalStateBackupOperation,
	next guestruntimedomain.GuestOperationalStateBackupOperation,
	completedEffect string,
	nextEffect string,
) error {
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupOperation(current); err != nil {
		return err
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupOperation(next); err != nil {
		return err
	}
	expectedCompleted, ok := guestruntimedomain.GuestOperationalStateBackupEffectForState(current)
	if !ok || expectedCompleted != completedEffect {
		return fmt.Errorf("completed Guest operational-state backup effect does not match current state")
	}
	if next.ID != current.ID ||
		next.RequestID != current.RequestID ||
		next.Kind != current.Kind ||
		next.ResourceRevision != current.ResourceRevision+1 {
		return fmt.Errorf("Guest operational-state backup transition identity is invalid")
	}
	expectedNext, hasNext := guestruntimedomain.GuestOperationalStateBackupEffectForState(next)
	if hasNext && nextEffect != expectedNext {
		return fmt.Errorf("next Guest operational-state backup effect does not match next state")
	}
	if !hasNext && nextEffect != "" {
		return fmt.Errorf("terminal Guest operational-state backup transition cannot enqueue effect")
	}
	return nil
}

func decodeOperation(encoded string) (guestruntimedomain.GuestOperationalStateBackupOperation, error) {
	var operation guestruntimedomain.GuestOperationalStateBackupOperation
	decoder := json.NewDecoder(strings.NewReader(encoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&operation); err != nil {
		return operation, fmt.Errorf("decode Guest operational-state backup operation: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return operation, fmt.Errorf("Guest operational-state backup operation contains trailing JSON")
		}
		return operation, fmt.Errorf("decode trailing Guest operational-state backup operation JSON: %w", err)
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupOperation(operation); err != nil {
		return operation, err
	}
	return operation, nil
}
