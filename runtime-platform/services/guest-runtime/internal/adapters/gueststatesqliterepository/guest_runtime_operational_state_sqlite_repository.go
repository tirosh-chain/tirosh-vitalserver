package gueststatesqliterepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (repository *GuestRuntimeStateSQLiteRepository) ReadTimeAuthority(ctx context.Context, id string) (guestruntimedomain.TimeAuthority, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM time_authorities WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.TimeAuthority{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.TimeAuthority{}, fmt.Errorf("read TimeAuthority: %w", err)
	}
	var authority guestruntimedomain.TimeAuthority
	if err := json.Unmarshal([]byte(encoded), &authority); err != nil {
		return guestruntimedomain.TimeAuthority{}, fmt.Errorf("decode owned TimeAuthority: %w", err)
	}
	return authority, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTimeAuthorityOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) AdmitTimeAuthorityOperation(ctx context.Context, authorityID string, expectedRevision int, operation guestruntimedomain.Operation) error {
	return repository.admitRevisionedOperationalOperation(ctx, "time_authorities", authorityID, expectedRevision, operation, "Time Authority")
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitTimeAuthorityOutcome(ctx context.Context, authority guestruntimedomain.TimeAuthority, operation guestruntimedomain.Operation) error {
	encodedAuthority, err := json.Marshal(authority)
	if err != nil {
		return fmt.Errorf("encode TimeAuthority: %w", err)
	}
	return repository.commitRevisionedOperationalOutcome(ctx, "time_authorities", authority.ID, authority.ResourceRevision, string(encodedAuthority), operation, "Time Authority")
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTelemetryPipeline(ctx context.Context, id string) (guestruntimedomain.TelemetryPipeline, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM telemetry_pipelines WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.TelemetryPipeline{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.TelemetryPipeline{}, fmt.Errorf("read TelemetryPipeline: %w", err)
	}
	var pipeline guestruntimedomain.TelemetryPipeline
	if err := json.Unmarshal([]byte(encoded), &pipeline); err != nil {
		return guestruntimedomain.TelemetryPipeline{}, fmt.Errorf("decode owned TelemetryPipeline: %w", err)
	}
	return pipeline, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTelemetryPipelineOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTelemetrySignalEmissionOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTelemetryEmissionReceipt(ctx context.Context, id string) (guestruntimedomain.TelemetryEmissionReceipt, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM telemetry_emission_receipts WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.TelemetryEmissionReceipt{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.TelemetryEmissionReceipt{}, fmt.Errorf("read TelemetryEmissionReceipt: %w", err)
	}
	var receipt guestruntimedomain.TelemetryEmissionReceipt
	if err := json.Unmarshal([]byte(encoded), &receipt); err != nil {
		return guestruntimedomain.TelemetryEmissionReceipt{}, fmt.Errorf("decode owned TelemetryEmissionReceipt: %w", err)
	}
	return receipt, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadTelemetryAttributeValueDigests(ctx context.Context, pipelineID string, attributeKey string) ([]string, error) {
	rows, err := repository.database.QueryContext(ctx, `SELECT value_digest FROM telemetry_attribute_cardinality WHERE pipeline_id = ? AND attribute_key = ? ORDER BY value_digest`, pipelineID, attributeKey)
	if err != nil {
		return nil, fmt.Errorf("read telemetry cardinality digests: %w", err)
	}
	defer rows.Close()
	digests := []string{}
	for rows.Next() {
		var digest string
		if err := rows.Scan(&digest); err != nil {
			return nil, fmt.Errorf("scan telemetry cardinality digest: %w", err)
		}
		digests = append(digests, digest)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate telemetry cardinality digests: %w", err)
	}
	return digests, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) AdmitTelemetryPipelineOperation(ctx context.Context, pipelineID string, expectedRevision int, operation guestruntimedomain.Operation) error {
	return repository.admitRevisionedOperationalOperation(ctx, "telemetry_pipelines", pipelineID, expectedRevision, operation, "Telemetry Pipeline")
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitTelemetryPipelineOutcome(ctx context.Context, pipeline guestruntimedomain.TelemetryPipeline, operation guestruntimedomain.Operation) error {
	encodedPipeline, err := json.Marshal(pipeline)
	if err != nil {
		return fmt.Errorf("encode TelemetryPipeline: %w", err)
	}
	return repository.commitRevisionedOperationalOutcome(ctx, "telemetry_pipelines", pipeline.ID, pipeline.ResourceRevision, string(encodedPipeline), operation, "Telemetry Pipeline")
}

func (repository *GuestRuntimeStateSQLiteRepository) AdmitTelemetryEmissionOperation(ctx context.Context, pipelineID string, expectedRevision int, operation guestruntimedomain.Operation) error {
	return repository.admitRevisionedOperationalOperation(ctx, "telemetry_pipelines", pipelineID, expectedRevision, operation, "Telemetry emission")
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitTelemetryEmissionOutcome(ctx context.Context, receipt guestruntimedomain.TelemetryEmissionReceipt, attributeDigests map[string]string, operation guestruntimedomain.Operation) error {
	encodedReceipt, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode TelemetryEmissionReceipt: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal telemetry emission operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin telemetry emission outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateIntegrationRevision(ctx, transaction, "telemetry_pipelines", receipt.PipelineReference.ResourceID, operation.Target.RequestedResourceRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal telemetry emission operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO telemetry_emission_receipts (id, operation_id, request_id, document_json) VALUES (?, ?, ?, ?)`, receipt.ID, operation.ID, receipt.RequestID, string(encodedReceipt)); err != nil {
		return mapOperationalConflict("persist TelemetryEmissionReceipt", err)
	}
	keys := make([]string, 0, len(attributeDigests))
	for key := range attributeDigests {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if _, err := transaction.ExecContext(ctx, `INSERT OR IGNORE INTO telemetry_attribute_cardinality (pipeline_id, attribute_key, value_digest) VALUES (?, ?, ?)`, receipt.PipelineReference.ResourceID, key, attributeDigests[key]); err != nil {
			return fmt.Errorf("persist bounded telemetry cardinality digest: %w", err)
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit telemetry emission outcome transaction: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) admitRevisionedOperationalOperation(ctx context.Context, table string, id string, expectedRevision int, operation guestruntimedomain.Operation, subject string) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode %s operation: %w", subject, err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s admission transaction: %w", subject, err)
	}
	defer transaction.Rollback()
	if err := validateIntegrationRevision(ctx, transaction, table, id, expectedRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation)); err != nil {
		return mapOperationalConflict("persist "+subject+" operation", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit %s admission transaction: %w", subject, err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) commitRevisionedOperationalOutcome(ctx context.Context, table string, id string, nextRevision int, resourceJSON string, operation guestruntimedomain.Operation, subject string) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal %s operation: %w", subject, err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s outcome transaction: %w", subject, err)
	}
	defer transaction.Rollback()
	if err := validateRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateNextIntegrationRevision(ctx, transaction, table, id, nextRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal %s operation: %w", subject, err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO `+table+` (id, document_json) VALUES (?, ?)
ON CONFLICT(id) DO UPDATE SET document_json = excluded.document_json`, id, resourceJSON); err != nil {
		return fmt.Errorf("persist %s: %w", subject, err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit %s outcome transaction: %w", subject, err)
	}
	return nil
}

func decodeOperationalOperation(encoded string, digest string) (guestruntimedomain.Operation, error) {
	var operation guestruntimedomain.Operation
	if err := json.Unmarshal([]byte(encoded), &operation); err != nil {
		return guestruntimedomain.Operation{}, fmt.Errorf("decode owned operational operation: %w", err)
	}
	operation.CommandDigest = digest
	return operation, nil
}

func mapOperationalConflict(subject string, err error) error {
	if isUniqueConstraint(err) {
		return fmt.Errorf("%w: %s", guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict, subject)
	}
	return fmt.Errorf("%s: %w", subject, err)
}

func isUniqueConstraint(err error) bool {
	return strings.Contains(strings.ToLower(err.Error()), "unique")
}

var _ guestruntimeapplication.GuestRuntimeTimeAuthorityStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
var _ guestruntimeapplication.GuestRuntimeTelemetryPipelineStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
