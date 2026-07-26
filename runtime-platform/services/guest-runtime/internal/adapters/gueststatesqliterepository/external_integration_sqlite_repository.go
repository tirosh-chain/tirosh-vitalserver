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

func (repository *GuestRuntimeStateSQLiteRepository) ReadExternalUpstreamIntegrationState(ctx context.Context, id string) (guestruntimedomain.ExternalUpstreamIntegration, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM external_upstream_integrations WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.ExternalUpstreamIntegration{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.ExternalUpstreamIntegration{}, fmt.Errorf("read ExternalUpstreamIntegration: %w", err)
	}
	var integration guestruntimedomain.ExternalUpstreamIntegration
	if err := json.Unmarshal([]byte(encoded), &integration); err != nil {
		return guestruntimedomain.ExternalUpstreamIntegration{}, fmt.Errorf("decode owned ExternalUpstreamIntegration: %w", err)
	}
	return integration, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListExternalUpstreamIntegrations(ctx context.Context) ([]guestruntimedomain.ExternalUpstreamIntegration, error) {
	rows, err := repository.database.QueryContext(ctx, `SELECT document_json FROM external_upstream_integrations ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("list ExternalUpstreamIntegrations: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.ExternalUpstreamIntegration{}
	for rows.Next() {
		var encoded string
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan ExternalUpstreamIntegration: %w", err)
		}
		var integration guestruntimedomain.ExternalUpstreamIntegration
		if err := json.Unmarshal([]byte(encoded), &integration); err != nil {
			return nil, fmt.Errorf("decode owned ExternalUpstreamIntegration: %w", err)
		}
		result = append(result, integration)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate ExternalUpstreamIntegrations: %w", err)
	}
	return result, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadExternalUpstreamCapabilityDocument(ctx context.Context, integrationID string) (guestruntimedomain.CapabilityDocument, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM external_upstream_capabilities WHERE integration_id = ?`, integrationID).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.CapabilityDocument{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.CapabilityDocument{}, fmt.Errorf("read external upstream CapabilityDocument: %w", err)
	}
	var capability guestruntimedomain.CapabilityDocument
	if err := json.Unmarshal([]byte(encoded), &capability); err != nil {
		return guestruntimedomain.CapabilityDocument{}, fmt.Errorf("decode owned external upstream CapabilityDocument: %w", err)
	}
	return capability, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadExternalUpstreamIntegrationOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

// AdmitExternalUpstreamOperation persists a running operation before an
// adapter call. It rechecks the owner resource revision in the same SQLite
// transaction so a stale command cannot execute the external effect.
func (repository *GuestRuntimeStateSQLiteRepository) AdmitExternalUpstreamOperation(ctx context.Context, integrationID string, expectedRevision int, operation guestruntimedomain.Operation) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode external upstream operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin external upstream admission transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateIntegrationRevision(ctx, transaction, "external_upstream_integrations", integrationID, expectedRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation)); err != nil {
		return mapIntegrationConflict("persist external upstream operation", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit external upstream admission transaction: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitExternalUpstreamOutcome(ctx context.Context, integration guestruntimedomain.ExternalUpstreamIntegration, capability *guestruntimedomain.CapabilityDocument, operation guestruntimedomain.Operation) error {
	encodedIntegration, err := json.Marshal(integration)
	if err != nil {
		return fmt.Errorf("encode ExternalUpstreamIntegration: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal external upstream operation: %w", err)
	}
	var encodedCapability []byte
	if capability != nil {
		encodedCapability, err = json.Marshal(capability)
		if err != nil {
			return fmt.Errorf("encode external upstream CapabilityDocument: %w", err)
		}
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin external upstream outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateNextIntegrationRevision(ctx, transaction, "external_upstream_integrations", integration.ID, integration.ResourceRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal external upstream operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO external_upstream_integrations (id, document_json) VALUES (?, ?)
ON CONFLICT(id) DO UPDATE SET document_json = excluded.document_json`, integration.ID, string(encodedIntegration)); err != nil {
		return fmt.Errorf("persist ExternalUpstreamIntegration: %w", err)
	}
	if capability == nil {
		if _, err := transaction.ExecContext(ctx, `DELETE FROM external_upstream_capabilities WHERE integration_id = ?`, integration.ID); err != nil {
			return fmt.Errorf("clear obsolete external upstream CapabilityDocument: %w", err)
		}
	} else if _, err := transaction.ExecContext(ctx, `INSERT INTO external_upstream_capabilities (integration_id, capability_id, document_json) VALUES (?, ?, ?)
ON CONFLICT(integration_id) DO UPDATE SET capability_id = excluded.capability_id, document_json = excluded.document_json`, integration.ID, capability.ID, string(encodedCapability)); err != nil {
		return mapIntegrationConflict("persist external upstream CapabilityDocument", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit external upstream outcome transaction: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadOutboundRelayTarget(ctx context.Context, id string) (guestruntimedomain.OutboundRelayTarget, error) {
	var encoded string
	err := repository.database.QueryRowContext(ctx, `SELECT document_json FROM outbound_relay_targets WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.OutboundRelayTarget{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.OutboundRelayTarget{}, fmt.Errorf("read OutboundRelayTarget: %w", err)
	}
	var target guestruntimedomain.OutboundRelayTarget
	if err := json.Unmarshal([]byte(encoded), &target); err != nil {
		return guestruntimedomain.OutboundRelayTarget{}, fmt.Errorf("decode owned OutboundRelayTarget: %w", err)
	}
	return target, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ListOutboundRelayTargets(ctx context.Context) ([]guestruntimedomain.OutboundRelayTarget, error) {
	rows, err := repository.database.QueryContext(ctx, `SELECT document_json FROM outbound_relay_targets ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("list OutboundRelayTargets: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.OutboundRelayTarget{}
	for rows.Next() {
		var encoded string
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan OutboundRelayTarget: %w", err)
		}
		var target guestruntimedomain.OutboundRelayTarget
		if err := json.Unmarshal([]byte(encoded), &target); err != nil {
			return nil, fmt.Errorf("decode owned OutboundRelayTarget: %w", err)
		}
		result = append(result, target)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate OutboundRelayTargets: %w", err)
	}
	return result, nil
}

func (repository *GuestRuntimeStateSQLiteRepository) ReadOutboundRelayTargetOperationByRequestID(ctx context.Context, requestID string) (guestruntimedomain.Operation, error) {
	return repository.readGuestRuntimeOperationByRequestID(ctx, requestID)
}

func (repository *GuestRuntimeStateSQLiteRepository) AdmitOutboundRelayOperation(ctx context.Context, targetID string, expectedRevision int, operation guestruntimedomain.Operation) error {
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode outbound relay operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin outbound relay admission transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateIntegrationRevision(ctx, transaction, "outbound_relay_targets", targetID, expectedRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO runtime_operations (id, request_id, command_digest, document_json) VALUES (?, ?, ?, ?)`, operation.ID, operation.RequestID, operation.CommandDigest, string(encodedOperation)); err != nil {
		return mapIntegrationConflict("persist outbound relay operation", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit outbound relay admission transaction: %w", err)
	}
	return nil
}

func (repository *GuestRuntimeStateSQLiteRepository) CommitOutboundRelayOutcome(ctx context.Context, target guestruntimedomain.OutboundRelayTarget, operation guestruntimedomain.Operation) error {
	encodedTarget, err := json.Marshal(target)
	if err != nil {
		return fmt.Errorf("encode OutboundRelayTarget: %w", err)
	}
	encodedOperation, err := json.Marshal(operation)
	if err != nil {
		return fmt.Errorf("encode terminal outbound relay operation: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin outbound relay outcome transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := validateRunningOperation(ctx, transaction, operation); err != nil {
		return err
	}
	if err := validateNextIntegrationRevision(ctx, transaction, "outbound_relay_targets", target.ID, target.ResourceRevision); err != nil {
		return err
	}
	if _, err := transaction.ExecContext(ctx, `UPDATE runtime_operations SET document_json = ? WHERE id = ?`, string(encodedOperation), operation.ID); err != nil {
		return fmt.Errorf("persist terminal outbound relay operation: %w", err)
	}
	if _, err := transaction.ExecContext(ctx, `INSERT INTO outbound_relay_targets (id, document_json) VALUES (?, ?)
ON CONFLICT(id) DO UPDATE SET document_json = excluded.document_json`, target.ID, string(encodedTarget)); err != nil {
		return fmt.Errorf("persist OutboundRelayTarget: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit outbound relay outcome transaction: %w", err)
	}
	return nil
}

func validateIntegrationRevision(ctx context.Context, transaction *sql.Tx, table string, id string, expectedRevision int) error {
	var encoded string
	err := transaction.QueryRowContext(ctx, `SELECT document_json FROM `+table+` WHERE id = ?`, id).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		if expectedRevision == 0 {
			return nil
		}
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	if err != nil {
		return fmt.Errorf("read integration target revision: %w", err)
	}
	if expectedRevision == 0 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	var resource struct {
		ResourceRevision int `json:"resourceRevision"`
	}
	if err := json.Unmarshal([]byte(encoded), &resource); err != nil {
		return fmt.Errorf("decode integration target revision: %w", err)
	}
	if resource.ResourceRevision != expectedRevision {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	return nil
}

func validateNextIntegrationRevision(ctx context.Context, transaction *sql.Tx, table string, id string, nextRevision int) error {
	if nextRevision < 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	return validateIntegrationRevision(ctx, transaction, table, id, nextRevision-1)
}

func validateRunningOperation(ctx context.Context, transaction *sql.Tx, terminal guestruntimedomain.Operation) error {
	var digest string
	var encoded string
	err := transaction.QueryRowContext(ctx, `SELECT command_digest, document_json FROM runtime_operations WHERE id = ?`, terminal.ID).Scan(&digest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return fmt.Errorf("read running integration operation: %w", err)
	}
	var running guestruntimedomain.Operation
	if err := json.Unmarshal([]byte(encoded), &running); err != nil {
		return fmt.Errorf("decode running integration operation: %w", err)
	}
	if running.State != "running" || running.RequestID != terminal.RequestID || running.Kind != terminal.Kind || digest != terminal.CommandDigest {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceRevisionConflict
	}
	return nil
}

func mapIntegrationConflict(subject string, err error) error {
	if strings.Contains(strings.ToLower(err.Error()), "unique") {
		return fmt.Errorf("%w: %s", guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict, subject)
	}
	return fmt.Errorf("%s: %w", subject, err)
}

var _ guestruntimeapplication.GuestRuntimeExternalUpstreamStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
var _ guestruntimeapplication.GuestRuntimeOutboundRelayStateRepository = (*GuestRuntimeStateSQLiteRepository)(nil)
