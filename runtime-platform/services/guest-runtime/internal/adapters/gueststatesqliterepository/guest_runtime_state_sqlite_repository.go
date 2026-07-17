// Package gueststatesqliterepository persists Guest Runtime-owned operational
// state through application repository ports using SQLite.
package gueststatesqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type GuestRuntimeStateSQLiteRepository struct {
	database *sql.DB
}

func OpenGuestRuntimeStateSQLiteRepository(ctx context.Context, databasePath string) (*GuestRuntimeStateSQLiteRepository, error) {
	if databasePath == "" {
		return nil, fmt.Errorf("Guest Runtime state database path is required")
	}
	parent := filepath.Dir(databasePath)
	info, err := os.Stat(parent)
	if err != nil {
		return nil, fmt.Errorf("state database parent is unreadable: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("state database parent is not a directory: %s", parent)
	}
	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return nil, fmt.Errorf("open Guest Runtime state database: %w", err)
	}
	database.SetMaxOpenConns(1)
	repository := &GuestRuntimeStateSQLiteRepository{database: database}
	if err := repository.migrate(ctx); err != nil {
		database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) Close() error {
	return repository.database.Close()
}

func (repository *GuestRuntimeStateSQLiteRepository) migrate(ctx context.Context) error {
	statements := []string{
		`PRAGMA foreign_keys = ON`,
		`CREATE TABLE IF NOT EXISTS runtime_topology (
			singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
			id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS runtime_operations (
			id TEXT PRIMARY KEY,
			request_id TEXT NOT NULL UNIQUE,
			command_digest TEXT NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS runtime_capability (
			singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
			id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS lab_sessions (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS lab_beds (
			id TEXT PRIMARY KEY,
			session_id TEXT NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS lab_beds_session_id ON lab_beds(session_id)`,
		`CREATE TABLE IF NOT EXISTS lab_virtual_recorders (
			id TEXT PRIMARY KEY,
			session_id TEXT NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS lab_virtual_recorders_session_id ON lab_virtual_recorders(session_id)`,
		`CREATE TABLE IF NOT EXISTS lab_deletion_receipts (
			id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL UNIQUE,
			request_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS archive_manifests (
			id TEXT PRIMARY KEY,
			artifact_id TEXT NOT NULL UNIQUE,
			source_resource_id TEXT NOT NULL,
			source_session_id TEXT NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS archive_manifests_source_resource_id ON archive_manifests(source_resource_id)`,
		`CREATE INDEX IF NOT EXISTS archive_manifests_source_session_id ON archive_manifests(source_session_id)`,
		`CREATE TABLE IF NOT EXISTS archive_objects (
			artifact_id TEXT PRIMARY KEY,
			payload BLOB NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS archive_export_receipts (
			id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL UNIQUE,
			request_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS external_upstream_integrations (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS external_upstream_capabilities (
			integration_id TEXT PRIMARY KEY,
			capability_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS outbound_relay_targets (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS time_authorities (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS catalog_observations (
			id TEXT PRIMARY KEY,
			source_key TEXT NOT NULL UNIQUE,
			envelope_digest TEXT NOT NULL,
			operation_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS telemetry_pipelines (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS telemetry_emission_receipts (
			id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL UNIQUE,
			request_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS telemetry_attribute_cardinality (
			pipeline_id TEXT NOT NULL,
			attribute_key TEXT NOT NULL,
			value_digest TEXT NOT NULL,
			PRIMARY KEY (pipeline_id, attribute_key, value_digest)
		)`,
		`CREATE INDEX IF NOT EXISTS telemetry_attribute_cardinality_lookup ON telemetry_attribute_cardinality(pipeline_id, attribute_key)`,
	}
	for _, statement := range statements {
		if _, err := repository.database.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate Guest Runtime state database: %w", err)
		}
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadRuntimeTopologyCapabilityDocument(ctx context.Context) (guestruntimedomain.CapabilityDocument, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM runtime_capability WHERE singleton = 1`).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.CapabilityDocument{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.CapabilityDocument{}, fmt.Errorf("read CapabilityDocument: %w", err)
	}
	var capability guestruntimedomain.CapabilityDocument
	if err := json.Unmarshal([]byte(encoded), &capability); err != nil {
		return guestruntimedomain.CapabilityDocument{}, fmt.Errorf("decode owned CapabilityDocument: %w", err)
	}
	return capability, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) VerifyRuntimeTopologyStateStoreAvailability(ctx context.Context) error {
	return repository.database.PingContext(ctx)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadRuntimeTopology(ctx context.Context) (guestruntimedomain.RuntimeTopology, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM runtime_topology WHERE singleton = 1`).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.RuntimeTopology{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.RuntimeTopology{}, fmt.Errorf("read RuntimeTopology: %w", err)
	}
	var topology guestruntimedomain.RuntimeTopology
	if err := json.Unmarshal([]byte(encoded), &topology); err != nil {
		return guestruntimedomain.RuntimeTopology{}, fmt.Errorf("decode owned RuntimeTopology: %w", err)
	}
	return topology, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadRuntimeTopologyOperation(ctx context.Context, operationID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperation(ctx, operationID)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadRuntimeTopologyOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) readGuestRuntimeOperation(ctx context.Context, operationID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByStatement(ctx, `SELECT command_digest, document_json FROM runtime_operations WHERE id = ?`, operationID)
}

func (repository *GuestRuntimeStateSQLiteRepository) readGuestRuntimeOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByStatement(ctx, `SELECT command_digest, document_json FROM runtime_operations WHERE request_id = ?`, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) readGuestRuntimeOperationByStatement(ctx context.Context, query string, value string) (guestruntimedomain.Operation, error) {
	var digest string
	var encoded string
	err := repository.database.QueryRowContext(ctx, query, value).Scan(&digest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.Operation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.Operation{}, fmt.Errorf("read Guest Runtime operation: %w", err)
	}
	var operation guestruntimedomain.Operation
	if err := json.Unmarshal([]byte(encoded), &operation); err != nil {
		return guestruntimedomain.Operation{}, fmt.Errorf("decode owned Guest Runtime operation: %w", err)
	}
	operation.CommandDigest = digest
	return operation, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitRuntimeTopologyApplication(ctx context.Context, topology guestruntimedomain.RuntimeTopology, capability *guestruntimedomain.CapabilityDocument, operation guestruntimedomain.Operation) error {
	encodedTopology, err := json.Marshal(topology)
	if err != nil {
		return fmt.Errorf("encode RuntimeTopology: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode Guest Runtime operation: %w", err)
	}
	var encodedCapability []byte
	if capability != nil {
		encodedCapability, err = json.Marshal(capability)
		if err != nil {
			return fmt.Errorf("encode CapabilityDocument: %w", err)
		}
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin topology apply transaction: %w", err)
	}
	defer transaction.Rollback()
	var existingTopologyJSON string
	err = transaction.QueryRowContext(ctx, `SELECT document_json FROM runtime_topology WHERE singleton = 1`).Scan(&existingTopologyJSON)
	if errors.Is(err, sql.ErrNoRows) {
		if topology.ResourceRevision != 1 {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
		}
	} else if err != nil {
		return fmt.Errorf("read RuntimeTopology revision for apply: %w", err)
	} else {
		var existingTopology guestruntimedomain.RuntimeTopology
		if err := json.Unmarshal([]byte(existingTopologyJSON), &existingTopology); err != nil {
			return fmt.Errorf("decode owned RuntimeTopology revision for apply: %w", err)
		}
		if existingTopology.ID != topology.ID || existingTopology.ResourceRevision != topology.ResourceRevision-1 {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
		}
	}
	if _, err := transaction.ExecContext(ctx,
		`INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`,
		operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation),
	); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return fmt.Errorf("%w: operation request id", guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict)
		}
		return fmt.Errorf("persist Guest Runtime operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx,
		`INSERT INTO runtime_topology (singleton, id, document_json) VALUES (1, ?, ?)
		 ON CONFLICT(singleton) DO UPDATE SET id = excluded.id, document_json = excluded.document_json`,
		topology.ID, string(encodedTopology),
	); err != nil {
		return fmt.Errorf("persist RuntimeTopology: %w", err)
	}
	if capability == nil {
		if _, err := transaction.ExecContext(ctx, `DELETE FROM runtime_capability WHERE singleton = 1`); err != nil {
			return fmt.Errorf("clear obsolete CapabilityDocument: %w", err)
		}
	} else if _, err := transaction.ExecContext(ctx,
		`INSERT INTO runtime_capability (singleton, id, document_json) VALUES (1, ?, ?)
		 ON CONFLICT(singleton) DO UPDATE SET id = excluded.id, document_json = excluded.document_json`,
		capability.ID, string(encodedCapability),
	); err != nil {
		return fmt.Errorf("persist CapabilityDocument: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit topology apply transaction: %w", err)
	}
	return nil
}
