package hoststatesqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

func (repository *HostAgentStateSQLiteRepository) ReadHostTimeAuthority(ctx context.Context, id string) (hostagentdomain.TimeAuthority, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM host_time_authorities WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.TimeAuthority{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.TimeAuthority{}, fmt.Errorf("read Host TimeAuthority: %w", err)
	}
	var authority hostagentdomain.TimeAuthority
	if err := json.Unmarshal([]byte(encoded), &authority); err != nil {
		return hostagentdomain.TimeAuthority{}, fmt.Errorf("decode owned Host TimeAuthority: %w", err)
	}
	return authority, nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostTimeAuthorityOperationByRequestID(ctx context.Context, requestID string) (hostagentdomain.Operation, error) {
	return repository.ReadHostOperationByRequestID(ctx, requestID)
}
func (repository *HostAgentStateSQLiteRepository) AdmitHostTimeAuthorityOperation(ctx context.Context, id string, expectedRevision int, operation hostagentdomain.Operation) error {
	return repository.admitOperationalOperation(ctx, "host_time_authorities", id, expectedRevision, operation, "Host Time Authority")
}

func (repository *HostAgentStateSQLiteRepository) CommitHostTimeAuthorityOutcome(ctx context.Context, authority hostagentdomain.TimeAuthority, operation hostagentdomain.Operation) error {
	encoded, err := json.Marshal(authority)
	if err != nil {
		return fmt.Errorf("encode Host TimeAuthority: %w", err)
	}
	return repository.commitOperationalResource(ctx, "host_time_authorities", authority.ID, authority.ResourceRevision, string(encoded), operation, "Host Time Authority")
}

func (repository *HostAgentStateSQLiteRepository) ReadHostTelemetryPipeline(ctx context.Context, id string) (hostagentdomain.TelemetryPipeline, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM host_telemetry_pipelines WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.TelemetryPipeline{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.TelemetryPipeline{}, fmt.Errorf("read Host TelemetryPipeline: %w", err)
	}
	var pipeline hostagentdomain.TelemetryPipeline
	if err := json.Unmarshal([]byte(encoded), &pipeline); err != nil {
		return hostagentdomain.TelemetryPipeline{}, fmt.Errorf("decode owned Host TelemetryPipeline: %w", err)
	}
	return pipeline, nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostTelemetryPipelineOperationByRequestID(ctx context.Context, requestID string) (hostagentdomain.Operation, error) {
	return repository.ReadHostOperationByRequestID(ctx, requestID)
}
func (repository *HostAgentStateSQLiteRepository) ReadHostTelemetryEmissionOperationByRequestID(ctx context.Context, requestID string) (hostagentdomain.Operation, error) {
	return repository.ReadHostOperationByRequestID(ctx, requestID)
}

func (repository *HostAgentStateSQLiteRepository) ReadHostTelemetryEmissionReceipt(ctx context.Context, id string) (hostagentdomain.TelemetryEmissionReceipt, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM host_telemetry_emission_receipts WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentdomain.TelemetryEmissionReceipt{}, hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return hostagentdomain.TelemetryEmissionReceipt{}, fmt.Errorf("read Host TelemetryEmissionReceipt: %w", err)
	}
	var receipt hostagentdomain.TelemetryEmissionReceipt
	if err := json.Unmarshal([]byte(encoded), &receipt); err != nil {
		return hostagentdomain.TelemetryEmissionReceipt{}, fmt.Errorf("decode owned Host TelemetryEmissionReceipt: %w", err)
	}
	return receipt, nil
}

func (repository *HostAgentStateSQLiteRepository) ReadHostTelemetryAttributeValueDigests(ctx context.Context, pipelineID string, attributeKey string) ([]string, error) {
	rows, err := repository.database.QueryContext(ctx, `SELECT value_digest FROM host_telemetry_attribute_cardinality WHERE pipeline_id = ? AND attribute_key = ? ORDER BY value_digest`, pipelineID, attributeKey)
	if err != nil {
		return nil, fmt.Errorf("read Host telemetry cardinality digests: %w", err)
	}
	defer rows.Close()
	result := []string{}
	for rows.Next() {
		var digest string
		if err := rows.Scan(&digest); err != nil {
			return nil, fmt.Errorf("scan Host telemetry cardinality digest: %w", err)
		}
		result = append(result, digest)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Host telemetry cardinality digests: %w", err)
	}
	return result, nil
}

func (repository *HostAgentStateSQLiteRepository) AdmitHostTelemetryPipelineOperation(ctx context.Context, id string, expectedRevision int, operation hostagentdomain.Operation) error {
	return repository.admitOperationalOperation(ctx, "host_telemetry_pipelines", id, expectedRevision, operation, "Host Telemetry Pipeline")
}

func (repository *HostAgentStateSQLiteRepository) CommitHostTelemetryPipelineOutcome(ctx context.Context, pipeline hostagentdomain.TelemetryPipeline, operation hostagentdomain.Operation) error {
	encoded, err := json.Marshal(pipeline)
	if err != nil {
		return fmt.Errorf("encode Host TelemetryPipeline: %w", err)
	}
	return repository.commitOperationalResource(ctx, "host_telemetry_pipelines", pipeline.ID, pipeline.ResourceRevision, string(encoded), operation, "Host Telemetry Pipeline")
}

func (repository *HostAgentStateSQLiteRepository) AdmitHostTelemetryEmissionOperation(ctx context.Context, pipelineID string, expectedRevision int, operation hostagentdomain.Operation) error {
	return repository.admitOperationalOperation(ctx, "host_telemetry_pipelines", pipelineID, expectedRevision, operation, "Host telemetry emission")
}

func (repository *HostAgentStateSQLiteRepository) CommitHostTelemetryEmissionOutcome(ctx context.Context, receipt hostagentdomain.TelemetryEmissionReceipt, attributeDigests map[string]string, operation hostagentdomain.Operation) error {
	encodedReceipt, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode Host TelemetryEmissionReceipt: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal Host telemetry operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Host telemetry emission outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateHostRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateHostRevision(ctx, transaction, "host_telemetry_pipelines", receipt.PipelineReference.ResourceID, operation.Target.RequestedResourceRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE host_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal Host telemetry operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO host_telemetry_emission_receipts (id, operation_id, request_id, document_json) VALUES (?, ?, ?, ?)`, receipt.ID, operation.ID, receipt.RequestID, string(encodedReceipt)); err != nil {
		return mapHostOperationalConflict("persist Host TelemetryEmissionReceipt", err)
	}
	keys := make([]string, 0, len(attributeDigests))
	for key := range attributeDigests {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if _, err := transaction.ExecContext(ctx, `INSERT OR IGNORE INTO host_telemetry_attribute_cardinality (pipeline_id, attribute_key, value_digest) VALUES (?, ?, ?)`, receipt.PipelineReference.ResourceID, key, attributeDigests[key]); err != nil {
			return fmt.Errorf("persist Host bounded telemetry cardinality digest: %w", err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Host telemetry emission outcome transaction: %w", err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) admitOperationalOperation(ctx context.Context, table string, id string, expectedRevision int, operation hostagentdomain.Operation, subject string) error {
	encoded, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode %s operation: %w", subject, err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s admission transaction: %w", subject, err)
	}
	defer transaction.Rollback()
	if err := validateHostRevision(ctx, transaction, table, id, expectedRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO host_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encoded)); err != nil {
		return mapHostOperationalConflict("persist "+subject+" operation", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit %s admission transaction: %w", subject, err)
	}
	return nil
}

func (repository *HostAgentStateSQLiteRepository) commitOperationalResource(ctx context.Context, table string, id string, nextRevision int, resourceJSON string, operation hostagentdomain.Operation, subject string) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal %s operation: %w", subject, err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s outcome transaction: %w", subject, err)
	}
	defer transaction.Rollback()
	if err := validateHostRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateHostNextRevision(ctx, transaction, table, id, nextRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE host_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal %s operation: %w", subject, err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO `+table+` (id, document_json) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET document_json = excluded.document_json`, id, resourceJSON); err != nil {
		return fmt.Errorf("persist %s: %w", subject, err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit %s outcome transaction: %w", subject, err)
	}
	return nil
}

func validateHostRevision(ctx context.Context, transaction *sql.Tx, table string, id string, expectedRevision int) error {
	var encoded string
	err := transaction.QueryRowContext(ctx, `SELECT document_json FROM `+table+` WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		if expectedRevision == 0 {
			return nil
		}
		return hostagentapplication.ErrHostAgentOwnedResourceRevisionConflict
	}
	if err != nil {
		return fmt.Errorf("read Host resource revision: %w", err)
	}
	if expectedRevision == 0 {
		return hostagentapplication.ErrHostAgentOwnedResourceRevisionConflict
	}
	var resource struct {
		ResourceRevision int `json:"resourceRevision"`
	}
	if err := json.Unmarshal([]byte(encoded), &resource); err != nil {
		return fmt.Errorf("decode Host resource revision: %w", err)
	}
	if resource.ResourceRevision != expectedRevision {
		return hostagentapplication.ErrHostAgentOwnedResourceRevisionConflict
	}
	return nil
}

func validateHostNextRevision(ctx context.Context, transaction *sql.Tx, table string, id string, nextRevision int) error {
	if nextRevision < 1 {
		return hostagentapplication.ErrHostAgentOwnedResourceRevisionConflict
	}
	return validateHostRevision(ctx, transaction, table, id, nextRevision-1)
}

func validateHostRunningOperation(ctx context.Context, transaction *sql.Tx, terminal hostagentdomain.Operation) error {
	var digest string
	var encoded string
	err := transaction.QueryRowContext(ctx, `SELECT command_digest, document_json FROM host_operations WHERE id = ?`, terminal.ID).Scan(&digest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return hostagentapplication.ErrHostAgentOwnedResourceNotFound
	}
	if err != nil {
		return fmt.Errorf("read running Host operational resource operation: %w", err)
	}
	var running hostagentdomain.Operation
	if err := json.Unmarshal([]byte(encoded), &running); err != nil {
		return fmt.Errorf("decode running Host operational resource operation: %w", err)
	}
	if running.State != "running" || running.RequestID != terminal.RequestID || running.Kind != terminal.Kind || digest != terminal.CommandDigest {
		return hostagentapplication.ErrHostAgentOwnedResourceRevisionConflict
	}
	return nil
}

func mapHostOperationalConflict(subject string, err error) error {
	if strings.Contains(strings.ToLower(err.Error()), "unique") {
		return fmt.Errorf("%w: %s", hostagentapplication.ErrHostAgentOwnedResourceConflict, subject)
	}
	return fmt.Errorf("%s: %w", subject, err)
}

var _ hostagentapplication.HostTimeAuthorityStateRepository = (*HostAgentStateSQLiteRepository)(nil)
var _ hostagentapplication.HostTelemetryPipelineStateRepository = (*HostAgentStateSQLiteRepository)(nil)
