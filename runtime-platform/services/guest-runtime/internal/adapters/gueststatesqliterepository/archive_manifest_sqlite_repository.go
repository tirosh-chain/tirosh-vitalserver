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

func (repository *GuestRuntimeStateSQLiteRepository) ReadArtifactExportOperation(ctx context.Context, id string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperation(ctx, id)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadArtifactExportOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadArtifactManifest(ctx context.Context, id string) (guestruntimedomain.ArtifactManifest, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM archive_manifests WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.ArtifactManifest{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.ArtifactManifest{}, fmt.Errorf("read ArtifactManifest: %w", err)
	}
	var manifest guestruntimedomain.ArtifactManifest
	if err := json.Unmarshal([]byte(encoded), &manifest); err != nil {
		return guestruntimedomain.ArtifactManifest{}, fmt.Errorf("decode owned ArtifactManifest: %w", err)
	}
	return manifest, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadArtifactExportReceipt(ctx context.Context, id string) (guestruntimedomain.ExportReceipt, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM archive_export_receipts WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.ExportReceipt{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.ExportReceipt{}, fmt.Errorf("read ExportReceipt: %w", err)
	}
	var receipt guestruntimedomain.ExportReceipt
	if err := json.Unmarshal([]byte(encoded), &receipt); err != nil {
		return guestruntimedomain.ExportReceipt{}, fmt.Errorf("decode owned ExportReceipt: %w", err)
	}
	return receipt, nil
}

// AdmitArtifactExport atomically persists the finalized source bytes,
// immutable manifest, and running operation before the provider is called.
// The Guest SQLite artifact object prevents an untracked filesystem artifact if
// command admission fails halfway through finalization.
func (repository *GuestRuntimeStateSQLiteRepository) AdmitArtifactExport(ctx context.Context, manifest guestruntimedomain.ArtifactManifest, payload []byte, sourceSessionID string, operation guestruntimedomain.Operation) error {
	if len(payload) == 0 || sourceSessionID == "" {
		return fmt.Errorf("artifact admission requires finalized payload and source session id")
	}
	encodedManifest, err := json.Marshal(manifest)
	if err != nil {
		return fmt.Errorf("encode ArtifactManifest: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode Archive Export operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Archive Export admission transaction: %w", err)
	}
	defer transaction.Rollback()
	if _, err := transaction.ExecContext(ctx, `INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation)); err != nil {
		return mapArchiveConflict("persist Archive Export operation", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO archive_manifests (id, artifact_id, source_resource_id, source_session_id, document_json) VALUES (?, ?, ?, ?, ?)`, manifest.ID, manifest.Artifact.ArtifactID, manifest.Source.ResourceID, sourceSessionID, string(encodedManifest)); err != nil {
		return mapArchiveConflict("persist ArtifactManifest", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO archive_objects (artifact_id, payload) VALUES (?, ?)`, manifest.Artifact.ArtifactID, payload); err != nil {
		return mapArchiveConflict("persist finalized artifact", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Archive Export admission transaction: %w", err)
	}
	return nil
}

// CommitArtifactExportOutcome records the one terminal receipt and atomically
// moves the already durable running operation to its terminal state.
func (repository *GuestRuntimeStateSQLiteRepository) CommitArtifactExportOutcome(ctx context.Context, receipt guestruntimedomain.ExportReceipt, operation guestruntimedomain.Operation) error {
	encodedReceipt, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode ExportReceipt: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal Archive Export operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin Archive Export outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	var currentJSON string
	var digest string
	err = transaction.QueryRowContext(ctx, `SELECT command_digest, document_json FROM runtime_operations WHERE id = ?`, operation.ID).Scan(&digest, &currentJSON)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return fmt.Errorf("read running Archive Export operation: %w", err)
	}
	var current guestruntimedomain.Operation
	if err := json.Unmarshal([]byte(currentJSON), &current); err != nil {
		return fmt.Errorf("decode running Archive Export operation: %w", err)
	}
	if current.State != "running" || current.RequestID != receipt.RequestID || digest != operation.CommandDigest {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal Archive Export operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO archive_export_receipts (id, operation_id, request_id, document_json) VALUES (?, ?, ?, ?)`, receipt.ID, receipt.OperationID, receipt.RequestID, string(encodedReceipt)); err != nil {
		return mapArchiveConflict("persist ExportReceipt", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Archive Export outcome transaction: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListArtifactsRetainedForResource(ctx context.Context, target guestruntimedomain.ResourceReference) ([]guestruntimedomain.ResourceReference, error) {
	var query string
	var value string
	switch target.ResourceType {
	case guestruntimedomain.LabSessionResourceType:
		query = `SELECT id, artifact_id FROM archive_manifests WHERE source_session_id = ? ORDER BY id`
		value = target.ResourceID
	case guestruntimedomain.VirtualRecorderResourceType:
		query = `SELECT id, artifact_id FROM archive_manifests WHERE source_resource_id = ? ORDER BY id`
		value = target.ResourceID
	case guestruntimedomain.LabBedResourceType:
		return []guestruntimedomain.ResourceReference{}, nil
	default:
		return nil, fmt.Errorf("Archive retention has no policy for resource type %q", target.ResourceType)
	}
	rows, err := repository.database.QueryContext(ctx, query, value)
	if err != nil {
		return nil, fmt.Errorf("list retained Archive artifacts: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.ResourceReference{}
	for rows.Next() {
		var manifestID string
		var artifactID string
		if err := rows.Scan(&manifestID, &artifactID); err != nil {
			return nil, fmt.Errorf("scan retained Archive artifact: %w", err)
		}
		result = append(result,
			guestruntimedomain.ResourceReference{ResourceType: "artifact-manifest", ResourceID: manifestID},
			guestruntimedomain.ResourceReference{ResourceType: "guest-archive-object", ResourceID: artifactID},
		)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate retained Archive artifacts: %w", err)
	}
	return result, nil
}

func mapArchiveConflict(subject string, err error) error {
	if strings.Contains(strings.ToLower(err.Error()), "unique") {
		return fmt.Errorf("%w: %s", guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict, subject)
	}
	return fmt.Errorf("%s: %w", subject, err)
}

var _ guestruntimeapplication.GuestRuntimeArchiveStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
