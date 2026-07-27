// Package hoststatesqliterepository persists Host Agent-owned operational state
// through application repository ports using SQLite.
package hoststatesqliterepository

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

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type HostAgentStateSQLiteRepository struct {
	database *sql.DB
}

func OpenHostStateSQLiteRepository(ctx context.Context, databasePath string) (*HostAgentStateSQLiteRepository, error) {
	if databasePath == "" {
		return nil, fmt.Errorf("Host Agent state database path is required")
	}
	parent := filepath.Dir(databasePath)
	info, err := os.Stat(parent)
	if err != nil {
		return nil, fmt.Errorf("Host state database parent is unreadable: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("Host state database parent is not a directory: %s", parent)
	}
	database, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return nil, fmt.Errorf("open Host state database: %w", err)
	}
	database.SetMaxOpenConns(1)
	repository := &HostAgentStateSQLiteRepository{database: database}
	if err := repository.migrate(ctx); err != nil {
		database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *HostAgentStateSQLiteRepository) Close() error { return repository.database.Close() }

func (repository *HostAgentStateSQLiteRepository) migrate(ctx context.Context) error {
	statements := []string{
		`PRAGMA foreign_keys = ON`,
		`CREATE TABLE IF NOT EXISTS platform_installations (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS guest_endpoints (
			singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
			id TEXT NOT NULL UNIQUE,
			resource_revision INTEGER NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS host_operations (
			id TEXT PRIMARY KEY,
			request_id TEXT NOT NULL UNIQUE,
			command_digest TEXT NOT NULL,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS host_update_journals (
			id TEXT PRIMARY KEY,
			request_id TEXT NOT NULL UNIQUE,
			operation_id TEXT NOT NULL UNIQUE,
			journal_revision INTEGER NOT NULL,
			command_digest TEXT NOT NULL,
			execution_digest TEXT,
			document_json TEXT NOT NULL
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS host_update_journals_one_active_owner
			ON host_update_journals ((1))
			WHERE json_extract(document_json, '$.state') IN ('requested', 'bootstrap-staged', 'handoff-pending', 'applying')`,
		`CREATE TABLE IF NOT EXISTS host_time_authorities (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS host_telemetry_pipelines (
			id TEXT PRIMARY KEY,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS host_telemetry_emission_receipts (
			id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL UNIQUE,
			request_id TEXT NOT NULL UNIQUE,
			document_json TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS host_telemetry_attribute_cardinality (
			pipeline_id TEXT NOT NULL,
			attribute_key TEXT NOT NULL,
			value_digest TEXT NOT NULL,
			PRIMARY KEY (pipeline_id, attribute_key, value_digest)
		)`,
		`CREATE INDEX IF NOT EXISTS host_telemetry_attribute_cardinality_lookup ON host_telemetry_attribute_cardinality(pipeline_id, attribute_key)`,
	}
	for _, statement := range statements {
		if _, err := repository.database.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate Host state database: %w", err)
		}
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) InitializeHostAgentControlState(ctx context.Context, installation hostagentdomain.PlatformInstallation, endpoint hostagentdomain.GuestRuntimeControlEndpoint) error {
	encodedInstallation, err := json.Marshal(installation)
	if err != nil {
		return fmt.Errorf("encode platform installation: %w", err)
	}
	encodedEndpoint, err := json.Marshal(endpoint)
	if err != nil {
		return fmt.Errorf("encode Guest endpoint: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Host configuration transaction: %w", err)
	}
	defer transaction.Rollback()

	var existingInstallationJSON string
	err = transaction.QueryRowContext(ctx, `SELECT document_json FROM platform_installations LIMIT 1`).Scan(&existingInstallationJSON)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO platform_installations (id, document_json) VALUES (?, ?)`, installation.ID, string(encodedInstallation)); err != nil {
			return fmt.Errorf("persist platform installation configuration: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("read platform installation configuration: %w", err)
	} else {
		var existing hostagentdomain.PlatformInstallation
		if err := json.Unmarshal([]byte(existingInstallationJSON), &existing); err != nil {
			return fmt.Errorf("decode owned platform installation: %w", err)
		}
		if !hostagentdomain.SameInstallationConfiguration(existing, installation) {
			return fmt.Errorf("configured platform installation differs from persisted Host-owned installation; use an explicit update workflow")
		}
	}

	var existingEndpointJSON string
	err = transaction.QueryRowContext(ctx, `SELECT document_json FROM guest_endpoints WHERE singleton = 1`).Scan(&existingEndpointJSON)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := transaction.ExecContext(ctx, `INSERT INTO guest_endpoints (singleton, id, resource_revision, document_json) VALUES (1, ?, ?, ?)`, endpoint.ID, endpoint.ResourceRevision, string(encodedEndpoint)); err != nil {
			return fmt.Errorf("persist Guest endpoint configuration: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("read Guest endpoint configuration: %w", err)
	} else {
		var existing hostagentdomain.GuestRuntimeControlEndpoint
		if err := json.Unmarshal([]byte(existingEndpointJSON), &existing); err != nil {
			return fmt.Errorf("decode owned Guest endpoint: %w", err)
		}
		if !hostagentdomain.SameGuestRuntimeControlEndpointConfiguration(existing, endpoint) {
			return fmt.Errorf("configured Guest endpoint differs from persisted Host-owned endpoint; use an explicit reconfiguration workflow")
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Host configuration transaction: %w", err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostPlatformInstallation(ctx context.Context) (hostagentdomain.PlatformInstallation, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM platform_installations LIMIT 1`).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.PlatformInstallation{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.PlatformInstallation{}, fmt.Errorf("read platform installation: %w", err)
	}
	var installation hostagentdomain.PlatformInstallation
	if err := json.Unmarshal([]byte(encoded), &installation); err != nil {
		return hostagentdomain.PlatformInstallation{}, fmt.Errorf("decode owned platform installation: %w", err)
	}
	return installation, nil
}

func (repository *HostAgentStateSQLiteRepository) ReadGuestRuntimeControlEndpoint(ctx context.Context) (hostagentdomain.GuestRuntimeControlEndpoint, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM guest_endpoints WHERE singleton = 1`).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, fmt.Errorf("read Guest Runtime Control endpoint: %w", err)
	}
	var endpoint hostagentdomain.GuestRuntimeControlEndpoint
	if err := json.Unmarshal([]byte(encoded), &endpoint); err != nil {
		return hostagentdomain.GuestRuntimeControlEndpoint{}, fmt.Errorf("decode owned Guest Runtime Control endpoint: %w", err)
	}
	return endpoint, nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostOperation(ctx context.Context, operationID string) (hostagentdomain.Operation, error) {
	return repository.operationBy(ctx, `SELECT command_digest, document_json FROM host_operations WHERE id = ?`, operationID)
}

func (repository *HostAgentStateSQLiteRepository) ReadHostOperationByRequestID(ctx context.Context, requestID string) (hostagentdomain.Operation, error) {
	return repository.operationBy(ctx, `SELECT command_digest, document_json FROM host_operations WHERE request_id = ?`, requestID)
}

func (repository *HostAgentStateSQLiteRepository) operationBy(ctx context.Context, query string, value string) (hostagentdomain.Operation, error) {
	var digest string
	var encoded string
	err := repository.database.QueryRowContext(ctx, query, value).Scan(&digest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.Operation{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.Operation{}, fmt.Errorf("read Host operation: %w", err)
	}
	var operation hostagentdomain.Operation
	if err := json.Unmarshal([]byte(encoded), &operation); err != nil {
		return hostagentdomain.Operation{}, fmt.Errorf("decode owned Host operation: %w", err)
	}
	operation.CommandDigest = digest
	return operation, nil
}

func (repository *HostAgentStateSQLiteRepository) PersistNewHostOperation(ctx context.Context, operation hostagentdomain.Operation) error {
	encoded, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode requested Host operation: %w", err)
	}
	_, err = repository.database.ExecContext(ctx, `INSERT INTO host_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encoded))
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return fmt.Errorf("%w: Host operation request id", hostagentapplication.ErrHostAgentOwnedResourceConflict)
		}
		return fmt.Errorf("persist requested Host operation: %w", err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) CommitGuestLifecycleOutcome(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint, operation hostagentdomain.Operation) error {
	encodedEndpoint, err := json.Marshal(endpoint)
	if err != nil {
		return fmt.Errorf("encode lifecycle Guest endpoint: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode lifecycle Host operation: %w", err)
	}
	if endpoint.ResourceRevision < 2 {
		return fmt.Errorf("lifecycle endpoint revision must advance")
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin lifecycle outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	result, err := transaction.ExecContext(ctx, `UPDATE guest_endpoints SET resource_revision = ?, document_json = ? WHERE singleton = 1 AND resource_revision = ?`, endpoint.ResourceRevision, string(encodedEndpoint), endpoint.ResourceRevision-1)
	if err != nil {
		return fmt.Errorf("update lifecycle Guest endpoint: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect lifecycle Guest endpoint update: %w", err)
	}
	if count != 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceConflict
	}
	result, err = transaction.ExecContext(ctx, `UPDATE host_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID)
	if err != nil {
		return fmt.Errorf("update lifecycle Host operation: %w", err)
	}
	count, err = result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect lifecycle Host operation update: %w", err)
	}
	if count != 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit lifecycle outcome transaction: %w", err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) PersistGuestRuntimeControlEndpointObservation(ctx context.Context, endpoint hostagentdomain.GuestRuntimeControlEndpoint) error {
	encoded, err := json.Marshal(endpoint)
	if err != nil {
		return fmt.Errorf("encode Guest endpoint: %w", err)
	}
	if endpoint.ResourceRevision < 2 {
		return fmt.Errorf("Guest endpoint revision must advance")
	}
	result, err := repository.database.ExecContext(ctx, `UPDATE guest_endpoints SET resource_revision = ?, document_json = ? WHERE singleton = 1 AND resource_revision = ?`, endpoint.ResourceRevision, string(encoded), endpoint.ResourceRevision-1)
	if err != nil {
		return fmt.Errorf("update Guest endpoint: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect Guest endpoint update: %w", err)
	}
	if count != 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceConflict
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostUpdateJournal(ctx context.Context, updateID string) (hostagentdomain.HostUpdateJournal, error) {
	return repository.readHostUpdateJournalBy(ctx, `SELECT command_digest, COALESCE(execution_digest, ''), document_json FROM host_update_journals WHERE id = ?`, updateID)
}

func (repository *HostAgentStateSQLiteRepository) ReadHostUpdateJournalByRequestID(ctx context.Context, requestID string) (hostagentdomain.HostUpdateJournal, error) {
	return repository.readHostUpdateJournalBy(ctx, `SELECT command_digest, COALESCE(execution_digest, ''), document_json FROM host_update_journals WHERE request_id = ?`, requestID)
}

// ReadActiveHostUpdateJournals returns every non-terminal update ownership
// record. The unique partial index enforces at most one such row atomically;
// returning a slice keeps an invalid pre-existing database observable rather
// than selecting one owner and hiding the others.
func (repository *HostAgentStateSQLiteRepository) ReadActiveHostUpdateJournals(ctx context.Context) ([]hostagentdomain.HostUpdateJournal, error) {
	return repository.readHostUpdateJournalsByState(
		ctx,
		`SELECT command_digest, COALESCE(execution_digest, ''), document_json
		 FROM host_update_journals
		 WHERE json_extract(document_json, '$.state') IN ('requested', 'bootstrap-staged', 'handoff-pending', 'applying')
		 ORDER BY id`,
		"active",
	)
}

// ReadRecoverableHostUpdateJournals returns only the explicitly recoverable part
// of the Host-owned update state machine.  "applying" is deliberately absent:
// a Host restart cannot infer whether the next updater is still executing.
func (repository *HostAgentStateSQLiteRepository) ReadRecoverableHostUpdateJournals(ctx context.Context) ([]hostagentdomain.HostUpdateJournal, error) {
	return repository.readHostUpdateJournalsByState(
		ctx,
		`SELECT command_digest, COALESCE(execution_digest, ''), document_json
		 FROM host_update_journals
		 WHERE json_extract(document_json, '$.state') IN ('bootstrap-staged', 'handoff-pending')
		 ORDER BY id`,
		"recoverable",
	)
}

func (repository *HostAgentStateSQLiteRepository) readHostUpdateJournalsByState(ctx context.Context, query string, description string) ([]hostagentdomain.HostUpdateJournal, error) {
	rows, err := repository.database.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("list %s Host update journals: %w", description, err)
	}
	defer rows.Close()
	journals := []hostagentdomain.HostUpdateJournal{}
	for rows.Next() {
		var commandDigest string
		var executionDigest string
		var encoded string
		if err := rows.Scan(&commandDigest, &executionDigest, &encoded); err != nil {
			return nil, fmt.Errorf("scan %s Host update journal: %w", description, err)
		}
		var journal hostagentdomain.HostUpdateJournal
		if err := json.Unmarshal([]byte(encoded), &journal); err != nil {
			return nil, fmt.Errorf("decode %s Host update journal: %w", description, err)
		}
		journal.CommandDigest = commandDigest
		journal.ExecutionDigest = executionDigest
		journals = append(journals, journal)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate %s Host update journals: %w", description, err)
	}
	return journals, nil
}

func (repository *HostAgentStateSQLiteRepository) readHostUpdateJournalBy(ctx context.Context, query string, value string) (hostagentdomain.HostUpdateJournal, error) {
	var commandDigest string
	var executionDigest string
	var encoded string
	err := repository.database.QueryRowContext(ctx, query, value).Scan(&commandDigest, &executionDigest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.HostUpdateJournal{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.HostUpdateJournal{}, fmt.Errorf("read Host update journal: %w", err)
	}
	var journal hostagentdomain.HostUpdateJournal
	if err := json.Unmarshal([]byte(encoded), &journal); err != nil {
		return hostagentdomain.HostUpdateJournal{}, fmt.Errorf("decode Host update journal: %w", err)
	}
	journal.CommandDigest = commandDigest
	journal.ExecutionDigest = executionDigest
	return journal, nil
}

func (repository *HostAgentStateSQLiteRepository) PersistNewHostUpdate(ctx context.Context, operation hostagentdomain.Operation, journal hostagentdomain.HostUpdateJournal) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode requested Host update operation: %w", err)
	}
	encodedJournal, err := json.Marshal(journal)
	if err != nil {
		return fmt.Errorf("encode requested Host update journal: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Host update admission transaction: %w", err)
	}
	defer transaction.Rollback()
	if _, err := transaction.ExecContext(ctx, `INSERT INTO host_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation)); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return fmt.Errorf("%w: Host update operation request id", hostagentapplication.ErrHostAgentOwnedResourceConflict)
		}
		return fmt.Errorf("persist requested Host update operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO host_update_journals (id, request_id, operation_id, journal_revision, command_digest, execution_digest, document_json) VALUES (?, ?, ?, ?, ?, NULL, ?)`, journal.ID, journal.RequestID, journal.OperationID, journal.JournalRevision, journal.CommandDigest, string(encodedJournal)); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return fmt.Errorf("%w: Host update journal request id", hostagentapplication.ErrHostAgentOwnedResourceConflict)
		}
		return fmt.Errorf("persist requested Host update journal: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Host update admission transaction: %w", err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) PersistHostUpdateProgress(ctx context.Context, operation hostagentdomain.Operation, journal hostagentdomain.HostUpdateJournal) error {
	return repository.commitHostUpdate(ctx, operation, journal, nil)
}

func (repository *HostAgentStateSQLiteRepository) CommitHostUpdateOutcome(ctx context.Context, operation hostagentdomain.Operation, journal hostagentdomain.HostUpdateJournal, installation *hostagentdomain.PlatformInstallation) error {
	return repository.commitHostUpdate(ctx, operation, journal, installation)
}

func (repository *HostAgentStateSQLiteRepository) commitHostUpdate(ctx context.Context, operation hostagentdomain.Operation, journal hostagentdomain.HostUpdateJournal, installation *hostagentdomain.PlatformInstallation) error {
	if journal.JournalRevision < 2 {
		return fmt.Errorf("Host update journal revision must advance")
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode Host update operation: %w", err)
	}
	encodedJournal, err := json.Marshal(journal)
	if err != nil {
		return fmt.Errorf("encode Host update journal: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Host update commit transaction: %w", err)
	}
	defer transaction.Rollback()
	result, err := transaction.ExecContext(ctx, `UPDATE host_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID)
	if err != nil {
		return fmt.Errorf("update Host update operation: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect Host update operation write: %w", err)
	}
	if count != 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	result, err = transaction.ExecContext(ctx, `UPDATE host_update_journals SET journal_revision = ?, execution_digest = NULLIF(?, ''), document_json = ? WHERE id = ? AND journal_revision = ?`, journal.JournalRevision, journal.ExecutionDigest, string(encodedJournal), journal.ID, journal.JournalRevision-1)
	if err != nil {
		return fmt.Errorf("update Host update journal: %w", err)
	}
	count, err = result.RowsAffected()
	if err != nil {
		return fmt.Errorf("inspect Host update journal write: %w", err)
	}
	if count != 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceConflict
	}
	if installation != nil {
		if installation.ResourceRevision < 2 {
			return fmt.Errorf("updated Host installation revision must advance")
		}
		var encodedCurrentInstallation string
		err := transaction.QueryRowContext(ctx, `SELECT document_json FROM platform_installations WHERE id = ?`, installation.ID).Scan(&encodedCurrentInstallation)
		if errors.Is(err, sql.ErrNoRows) {
			return hostagentapplication.ErrHostAgentOwnedResourceNotFound
		}
		if err != nil {
			return fmt.Errorf("read current Host installation release: %w", err)
		}
		var currentInstallation hostagentdomain.PlatformInstallation
		if err := json.Unmarshal([]byte(encodedCurrentInstallation), &currentInstallation); err != nil {
			return fmt.Errorf("decode current Host installation release: %w", err)
		}
		if currentInstallation.ResourceRevision != installation.ResourceRevision-1 {
			return hostagentapplication.ErrHostAgentOwnedResourceConflict
		}
		encodedInstallation, err := json.Marshal(*installation)
		if err != nil {
			return fmt.Errorf("encode updated Host installation: %w", err)
		}
		result, err = transaction.ExecContext(ctx, `UPDATE platform_installations SET document_json = ? WHERE id = ?`, string(encodedInstallation), installation.ID)
		if err != nil {
			return fmt.Errorf("update Host installation release: %w", err)
		}
		count, err = result.RowsAffected()
		if err != nil {
			return fmt.Errorf("inspect Host installation release write: %w", err)
		}
		if count != 1 {
			return hostagentapplication.ErrHostAgentOwnedResourceNotFound
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Host update transaction: %w", err)
	}
	return nil
}
