// Package gueststatepostgresqlrepository persists Guest-owned accumulated
// product evidence in PostgreSQL without reading or writing the Guest SQLite
// control ledger.
package gueststatepostgresqlrepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgconn"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const ExpectedRecorderCatalogRevision = guestruntimedomain.GuestOperationalStatePostgreSQLAlembicRevision

type RecorderCatalogPostgreSQLRepository struct {
	database *sql.DB
}

func (repository *RecorderCatalogPostgreSQLRepository) GuestRuntimeReadinessDependencyID() string {
	return "recorder-catalog-postgresql"
}

func (repository *RecorderCatalogPostgreSQLRepository) VerifyGuestRuntimeReadinessDependency(
	ctx context.Context,
) error {
	return repository.verifyReady(ctx)
}

func OpenRecorderCatalogPostgreSQLRepository(
	ctx context.Context,
	databaseURL string,
) (*RecorderCatalogPostgreSQLRepository, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("Recorder Catalog PostgreSQL database URL is required")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open Recorder Catalog PostgreSQL database: %w", err)
	}
	database.SetMaxOpenConns(8)
	database.SetMaxIdleConns(2)
	repository := &RecorderCatalogPostgreSQLRepository{database: database}
	if err := repository.verifyReady(ctx); err != nil {
		_ = database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) Close() error {
	if repository == nil || repository.database == nil {
		return fmt.Errorf("Recorder Catalog PostgreSQL repository is not open")
	}
	return repository.database.Close()
}

func (repository *RecorderCatalogPostgreSQLRepository) verifyReady(ctx context.Context) error {
	if err := repository.database.PingContext(ctx); err != nil {
		return fmt.Errorf("Recorder Catalog PostgreSQL is unavailable: %w", err)
	}
	var revision string
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT version_num FROM public.alembic_version`,
	).Scan(&revision); err != nil {
		return fmt.Errorf("read Recorder Catalog Alembic revision: %w", err)
	}
	if revision != ExpectedRecorderCatalogRevision {
		return fmt.Errorf(
			"Recorder Catalog Alembic revision mismatch: expected=%s actual=%s",
			ExpectedRecorderCatalogRevision,
			revision,
		)
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT 1
		   FROM recorder_catalog.admission_requests
		  LIMIT 0`,
	)
	if err != nil {
		return fmt.Errorf("verify Recorder Catalog owner schema read: %w", err)
	}
	if err := rows.Close(); err != nil {
		return fmt.Errorf("close Recorder Catalog owner schema readiness read: %w", err)
	}
	return nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadCatalogObservation(
	ctx context.Context,
	id string,
) (guestruntimedomain.CatalogObservation, error) {
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT document FROM recorder_catalog.observations WHERE observation_id = $1`,
		id,
	).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.CatalogObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.CatalogObservation{}, fmt.Errorf("read CatalogObservation from PostgreSQL: %w", err)
	}
	return decodeCatalogObservation(encoded)
}

func (repository *RecorderCatalogPostgreSQLRepository) ListRecorderCatalogObservations(
	ctx context.Context,
	recorderID string,
	limit int,
	position *guestruntimeapplication.CatalogObservationPagePosition,
	reportedIssuesOnly bool,
) ([]guestruntimedomain.CatalogObservation, error) {
	query := `SELECT document
	            FROM recorder_catalog.observations
	           WHERE recorder_id = $1`
	arguments := []any{recorderID}
	if reportedIssuesOnly {
		query += ` AND (
		  (document #> '{envelope,time,issue}') IS NOT NULL
		  OR (document #> '{envelope,runtime,issue}') IS NOT NULL
		)`
	}
	if position != nil {
		query += ` AND (persisted_at, observation_id) < ($2::timestamptz, $3)`
		arguments = append(arguments, position.PersistedAt, position.ObservationID, limit)
		query += ` ORDER BY persisted_at DESC, observation_id DESC LIMIT $4`
	} else {
		arguments = append(arguments, limit)
		query += ` ORDER BY persisted_at DESC, observation_id DESC LIMIT $2`
	}
	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list bounded Recorder Catalog observations from PostgreSQL: %w", err)
	}
	defer rows.Close()
	observations := make([]guestruntimedomain.CatalogObservation, 0, limit)
	for rows.Next() {
		var encoded []byte
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan bounded Recorder Catalog observation: %w", err)
		}
		observation, err := decodeCatalogObservation(encoded)
		if err != nil {
			return nil, err
		}
		observations = append(observations, observation)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bounded Recorder Catalog observations: %w", err)
	}
	return observations, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadCatalogObservationBySourceKey(
	ctx context.Context,
	sourceKey string,
) (guestruntimeapplication.CatalogStoredObservation, error) {
	var envelopeDigest string
	var observationJSON []byte
	var admissionJSON []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT request.envelope_digest,
		        observation.document,
		        request.admission_document
		   FROM recorder_catalog.admission_requests AS request
		   JOIN recorder_catalog.observations AS observation
		     ON observation.request_id = request.request_id
		  WHERE request.source_key = $1`,
		sourceKey,
	).Scan(&envelopeDigest, &observationJSON, &admissionJSON)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.CatalogStoredObservation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimeapplication.CatalogStoredObservation{}, fmt.Errorf("read Catalog source identity from PostgreSQL: %w", err)
	}
	observation, err := decodeCatalogObservation(observationJSON)
	if err != nil {
		return guestruntimeapplication.CatalogStoredObservation{}, err
	}
	admission, err := decodeCatalogAdmission(admissionJSON)
	if err != nil {
		return guestruntimeapplication.CatalogStoredObservation{}, err
	}
	return guestruntimeapplication.CatalogStoredObservation{
		Observation:    observation,
		EnvelopeDigest: envelopeDigest,
		Admission:      admission,
	}, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadCatalogObservationAdmissionByRequestID(
	ctx context.Context,
	requestID string,
) (guestruntimeapplication.CatalogStoredAdmission, error) {
	var commandDigest string
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT command_digest, admission_document
		   FROM recorder_catalog.admission_requests
		  WHERE request_id = $1`,
		requestID,
	).Scan(&commandDigest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.CatalogStoredAdmission{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimeapplication.CatalogStoredAdmission{}, fmt.Errorf("read Catalog admission from PostgreSQL: %w", err)
	}
	admission, err := decodeCatalogAdmission(encoded)
	if err != nil {
		return guestruntimeapplication.CatalogStoredAdmission{}, err
	}
	return guestruntimeapplication.CatalogStoredAdmission{Admission: admission, CommandDigest: commandDigest}, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadRecorderObservabilitySummary(
	ctx context.Context,
	recorderID string,
) (guestruntimedomain.RecorderObservabilitySummary, error) {
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT document
		   FROM recorder_catalog.recorder_current
		  WHERE recorder_id = $1`,
		recorderID,
	).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.RecorderObservabilitySummary{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.RecorderObservabilitySummary{}, fmt.Errorf("read Recorder current projection from PostgreSQL: %w", err)
	}
	var summary guestruntimedomain.RecorderObservabilitySummary
	if err := json.Unmarshal(encoded, &summary); err != nil {
		return guestruntimedomain.RecorderObservabilitySummary{}, fmt.Errorf("decode owned Recorder current projection from PostgreSQL: %w", err)
	}
	return summary, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ListRecorderObservabilitySummaries(
	ctx context.Context,
	limit int,
	position *guestruntimeapplication.RecorderSummaryPagePosition,
) ([]guestruntimedomain.RecorderObservabilitySummary, error) {
	query := `SELECT document
	            FROM recorder_catalog.recorder_current`
	arguments := make([]any, 0, 2)
	if position != nil {
		query += ` WHERE recorder_id > $1`
		arguments = append(arguments, position.RecorderID, limit)
		query += ` ORDER BY recorder_id ASC LIMIT $2`
	} else {
		arguments = append(arguments, limit)
		query += ` ORDER BY recorder_id ASC LIMIT $1`
	}
	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list bounded Recorder current projections from PostgreSQL: %w", err)
	}
	defer rows.Close()
	summaries := make([]guestruntimedomain.RecorderObservabilitySummary, 0, limit)
	for rows.Next() {
		var encoded []byte
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan bounded Recorder current projection: %w", err)
		}
		var summary guestruntimedomain.RecorderObservabilitySummary
		if err := json.Unmarshal(encoded, &summary); err != nil {
			return nil, fmt.Errorf("decode owned Recorder current projection from PostgreSQL: %w", err)
		}
		summaries = append(summaries, summary)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bounded Recorder current projections: %w", err)
	}
	return summaries, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadRecorderExpectation(
	ctx context.Context,
	recorderID string,
) (guestruntimedomain.RecorderExpectation, error) {
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT expectation_document
		   FROM recorder_catalog.recorder_expectations
		  WHERE recorder_id = $1`,
		recorderID,
	).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.RecorderExpectation{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.RecorderExpectation{}, fmt.Errorf("read Recorder expectation from PostgreSQL: %w", err)
	}
	var expectation guestruntimedomain.RecorderExpectation
	if err := json.Unmarshal(encoded, &expectation); err != nil {
		return guestruntimedomain.RecorderExpectation{}, fmt.Errorf("decode owned Recorder expectation from PostgreSQL: %w", err)
	}
	return expectation, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) ReadRecorderExpectationEventByRequestID(
	ctx context.Context,
	requestID string,
) (guestruntimeapplication.CatalogStoredExpectationEvent, error) {
	var commandDigest string
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT command_digest, event_document
		   FROM recorder_catalog.expectation_events
		  WHERE request_id = $1`,
		requestID,
	).Scan(&commandDigest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.CatalogStoredExpectationEvent{}, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimeapplication.CatalogStoredExpectationEvent{}, fmt.Errorf("read Recorder expectation event from PostgreSQL: %w", err)
	}
	var event guestruntimedomain.RecorderExpectationEvent
	if err := json.Unmarshal(encoded, &event); err != nil {
		return guestruntimeapplication.CatalogStoredExpectationEvent{}, fmt.Errorf("decode owned Recorder expectation event from PostgreSQL: %w", err)
	}
	return guestruntimeapplication.CatalogStoredExpectationEvent{Event: event, CommandDigest: commandDigest}, nil
}

func (repository *RecorderCatalogPostgreSQLRepository) CommitAcceptedCatalogObservation(
	ctx context.Context,
	observation guestruntimedomain.CatalogObservation,
	commandDigest string,
	envelopeDigest string,
	admission guestruntimedomain.CatalogObservationAdmission,
	summary guestruntimedomain.RecorderObservabilitySummary,
	expectedPreviousRevision int,
	evidence guestruntimeapplication.CatalogObservationAdmissionEvidence,
) error {
	observationJSON, err := json.Marshal(observation)
	if err != nil {
		return fmt.Errorf("encode CatalogObservation for PostgreSQL: %w", err)
	}
	admissionJSON, err := json.Marshal(admission)
	if err != nil {
		return fmt.Errorf("encode Catalog admission for PostgreSQL: %w", err)
	}
	summaryJSON, err := json.Marshal(summary)
	if err != nil {
		return fmt.Errorf("encode Recorder current projection for PostgreSQL: %w", err)
	}
	sourceDocumentJSON, err := json.Marshal(observation.Envelope)
	if err != nil {
		return fmt.Errorf("encode Catalog source document for PostgreSQL: %w", err)
	}
	transaction, err := repository.database.BeginTx(
		ctx,
		&sql.TxOptions{Isolation: sql.LevelSerializable},
	)
	if err != nil {
		return fmt.Errorf("begin Recorder Catalog PostgreSQL transaction: %w", err)
	}
	defer transaction.Rollback()
	sourceKey := guestruntimedomain.CatalogSourceKey(observation.Envelope)
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO recorder_catalog.admission_requests (
		   request_id, command_digest, source_key, envelope_digest,
		   source_identity, media_type, received_bytes, outcome, issue,
		   admission_document, source_document, received_at, persisted_at
		 ) VALUES (
		   $1, $2, $3, $4,
		   $5, $6, $7, 'accepted', NULL,
		   $8, $9, $10, $11
		 )`,
		admission.RequestID,
		commandDigest,
		sourceKey,
		envelopeDigest,
		evidence.SourceIdentity,
		evidence.MediaType,
		evidence.ReceivedBytes,
		admissionJSON,
		sourceDocumentJSON,
		admission.ReceivedAt,
		admission.PersistedAt,
	); err != nil {
		return mapCatalogWriteError("persist Catalog admission", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO recorder_catalog.observations (
		   observation_id, request_id, recorder_id, boot_id, sequence,
		   protocol_version, occurred_at, received_at, persisted_at,
		   envelope_sha256, document
		 ) VALUES (
		   $1, $2, $3, $4, $5,
		   $6, $7, $8, $9,
		   $10, $11
		 )`,
		observation.ID,
		admission.RequestID,
		observation.Envelope.RecorderID,
		observation.Envelope.BootID,
		observation.Envelope.Sequence,
		observation.Envelope.ProtocolVersion,
		observation.Envelope.OccurredAt,
		observation.ReceivedAt,
		observation.PersistedAt,
		envelopeDigest,
		observationJSON,
	); err != nil {
		return mapCatalogWriteError("persist Catalog observation", err)
	}
	if expectedPreviousRevision == 0 {
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO recorder_catalog.recorder_current (
			   recorder_id, resource_revision, support_state, expectation_state,
			   report_state, latest_observation_id, latest_boot_id, latest_sequence,
			   latest_occurred_at, latest_received_at, latest_persisted_at,
			   document, updated_at
			 ) VALUES (
			   $1, $2, $3, $4,
			   $5, $6, $7, $8,
			   $9, $10, $11,
			   $12, $13
			 )`,
			summary.RecorderID,
			summary.ResourceRevision,
			summary.SupportState,
			summary.ExpectationState,
			summary.ReportState,
			summary.LatestObservationReference.ResourceID,
			*summary.LatestBootID,
			*summary.LatestSequence,
			*summary.LatestOccurredAt,
			*summary.LatestReceivedAt,
			*summary.LatestPersistedAt,
			summaryJSON,
			summary.UpdatedAt,
		); err != nil {
			return mapCatalogWriteError("persist initial Recorder current projection", err)
		}
	} else {
		result, err := transaction.ExecContext(
			ctx,
			`UPDATE recorder_catalog.recorder_current
			    SET resource_revision = $2,
			        support_state = $3,
			        expectation_state = $4,
			        report_state = $5,
			        latest_observation_id = $6,
			        latest_boot_id = $7,
			        latest_sequence = $8,
			        latest_occurred_at = $9,
			        latest_received_at = $10,
			        latest_persisted_at = $11,
			        document = $12,
			        updated_at = $13
			  WHERE recorder_id = $1
			    AND resource_revision = $14`,
			summary.RecorderID,
			summary.ResourceRevision,
			summary.SupportState,
			summary.ExpectationState,
			summary.ReportState,
			summary.LatestObservationReference.ResourceID,
			*summary.LatestBootID,
			*summary.LatestSequence,
			*summary.LatestOccurredAt,
			*summary.LatestReceivedAt,
			*summary.LatestPersistedAt,
			summaryJSON,
			summary.UpdatedAt,
			expectedPreviousRevision,
		)
		if err != nil {
			return mapCatalogWriteError("persist revised Recorder current projection", err)
		}
		affected, err := result.RowsAffected()
		if err != nil {
			return fmt.Errorf("read revised Recorder current projection write count: %w", err)
		}
		if affected != 1 {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Recorder Catalog PostgreSQL transaction: %w", err)
	}
	return nil
}

func (repository *RecorderCatalogPostgreSQLRepository) CommitDuplicateCatalogObservationAdmission(
	ctx context.Context,
	commandDigest string,
	sourceKey string,
	envelopeDigest string,
	admission guestruntimedomain.CatalogObservationAdmission,
	evidence guestruntimeapplication.CatalogObservationAdmissionEvidence,
) error {
	admissionJSON, err := json.Marshal(admission)
	if err != nil {
		return fmt.Errorf("encode duplicate Catalog admission for PostgreSQL: %w", err)
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO recorder_catalog.admission_requests (
		   request_id, command_digest, source_key, envelope_digest,
		   source_identity, media_type, received_bytes, outcome, issue,
		   admission_document, source_document, received_at, persisted_at
		 ) VALUES (
		   $1, $2, $3, $4,
		   $5, $6, $7, 'duplicate', NULL,
		   $8,
		   (SELECT source_document
		      FROM recorder_catalog.admission_requests
		     WHERE source_key = $3 AND outcome = 'accepted'
		     ORDER BY persisted_at, request_id
		     LIMIT 1),
		   $9, $10
		 )`,
		admission.RequestID,
		commandDigest,
		sourceKey,
		envelopeDigest,
		evidence.SourceIdentity,
		evidence.MediaType,
		evidence.ReceivedBytes,
		admissionJSON,
		admission.ReceivedAt,
		admission.PersistedAt,
	)
	if err != nil {
		return mapCatalogWriteError("persist duplicate Catalog admission", err)
	}
	return nil
}

func (repository *RecorderCatalogPostgreSQLRepository) CommitQuarantinedCatalogObservationAdmission(
	ctx context.Context,
	commandDigest string,
	admission guestruntimedomain.CatalogObservationAdmission,
	sourceDocument map[string]any,
	evidence guestruntimeapplication.CatalogObservationAdmissionEvidence,
) error {
	admissionJSON, err := json.Marshal(admission)
	if err != nil {
		return fmt.Errorf("encode quarantined Catalog admission: %w", err)
	}
	sourceJSON, err := json.Marshal(sourceDocument)
	if err != nil {
		return fmt.Errorf("encode quarantined Catalog source document: %w", err)
	}
	issueJSON, err := json.Marshal(admission.Issue)
	if err != nil {
		return fmt.Errorf("encode quarantined Catalog issue: %w", err)
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO recorder_catalog.admission_requests (
		   request_id, command_digest, source_key, envelope_digest,
		   source_identity, media_type, received_bytes, outcome, issue,
		   admission_document, source_document, received_at, persisted_at
		 ) VALUES (
		   $1, $2, NULL, NULL,
		   $3, $4, $5, 'quarantined', $6,
		   $7, $8, $9, $10
		 )`,
		admission.RequestID, commandDigest,
		evidence.SourceIdentity, evidence.MediaType, evidence.ReceivedBytes, issueJSON,
		admissionJSON, sourceJSON, admission.ReceivedAt, admission.PersistedAt,
	)
	if err != nil {
		return mapCatalogWriteError("persist quarantined Catalog admission", err)
	}
	return nil
}

func (repository *RecorderCatalogPostgreSQLRepository) CommitRecorderExpectation(
	ctx context.Context,
	event guestruntimedomain.RecorderExpectationEvent,
	commandDigest string,
	expectation guestruntimedomain.RecorderExpectation,
	summary guestruntimedomain.RecorderObservabilitySummary,
	expectedSummaryRevision int,
) error {
	eventJSON, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode Recorder expectation event: %w", err)
	}
	evidenceJSON, err := json.Marshal(event.Evidence)
	if err != nil {
		return fmt.Errorf("encode Recorder expectation evidence: %w", err)
	}
	expectationJSON, err := json.Marshal(expectation)
	if err != nil {
		return fmt.Errorf("encode Recorder expectation projection: %w", err)
	}
	summaryJSON, err := json.Marshal(summary)
	if err != nil {
		return fmt.Errorf("encode Recorder summary projection: %w", err)
	}
	transaction, err := repository.database.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return fmt.Errorf("begin Recorder expectation transaction: %w", err)
	}
	defer transaction.Rollback()
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO recorder_catalog.expectation_events (
		   event_id, request_id, command_digest, recorder_id,
		   previous_revision, revision, action, expectation_state, support_state,
		   source, reason, evidence_document, event_document,
		   decided_at, received_at, persisted_at
		 ) VALUES (
		   $1, $2, $3, $4,
		   $5, $6, $7, $8, $9,
		   $10, $11, $12, $13,
		   $14, $15, $16
		 )`,
		event.ID, event.RequestID, commandDigest, event.RecorderID,
		event.PreviousRevision, event.Revision, event.Action, event.ExpectationState, event.SupportState,
		event.Source, event.Reason, evidenceJSON, eventJSON,
		event.DecidedAt, event.ReceivedAt, event.PersistedAt,
	); err != nil {
		return mapCatalogWriteError("persist Recorder expectation event", err)
	}
	if event.PreviousRevision == 0 {
		if _, err := transaction.ExecContext(
			ctx,
			`INSERT INTO recorder_catalog.recorder_expectations (
			   recorder_id, revision, lifecycle_state, expectation_state,
			   support_state, source, reason, evidence_document,
			   expectation_document, source_event_id, updated_at
			 ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
			expectation.RecorderID, expectation.ResourceRevision, expectation.LifecycleState, expectation.ExpectationState,
			expectation.SupportState, expectation.Source, expectation.Reason, evidenceJSON,
			expectationJSON, expectation.SourceEvent.ResourceID, expectation.UpdatedAt,
		); err != nil {
			return mapCatalogWriteError("persist initial Recorder expectation", err)
		}
	} else {
		result, err := transaction.ExecContext(
			ctx,
			`UPDATE recorder_catalog.recorder_expectations
			    SET revision = $2, lifecycle_state = $3, expectation_state = $4,
			        support_state = $5, source = $6, reason = $7,
			        evidence_document = $8, expectation_document = $9,
			        source_event_id = $10, updated_at = $11
			  WHERE recorder_id = $1 AND revision = $12`,
			expectation.RecorderID, expectation.ResourceRevision, expectation.LifecycleState, expectation.ExpectationState,
			expectation.SupportState, expectation.Source, expectation.Reason, evidenceJSON,
			expectationJSON, expectation.SourceEvent.ResourceID, expectation.UpdatedAt, event.PreviousRevision,
		)
		if err != nil {
			return mapCatalogWriteError("persist revised Recorder expectation", err)
		}
		affected, err := result.RowsAffected()
		if err != nil || affected != 1 {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
	}
	if err := persistRecorderSummaryProjection(ctx, transaction, summary, summaryJSON, expectedSummaryRevision); err != nil {
		return err
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Recorder expectation transaction: %w", err)
	}
	return nil
}

func persistRecorderSummaryProjection(ctx context.Context, transaction *sql.Tx, summary guestruntimedomain.RecorderObservabilitySummary, summaryJSON []byte, expectedRevision int) error {
	if expectedRevision == 0 {
		_, err := transaction.ExecContext(
			ctx,
			`INSERT INTO recorder_catalog.recorder_current (
			   recorder_id, resource_revision, support_state, expectation_state,
			   report_state, latest_observation_id, latest_boot_id, latest_sequence,
			   latest_occurred_at, latest_received_at, latest_persisted_at,
			   document, updated_at
			 ) VALUES ($1, $2, $3, $4, $5, NULL, NULL, NULL, NULL, NULL, NULL, $6, $7)`,
			summary.RecorderID, summary.ResourceRevision, summary.SupportState,
			summary.ExpectationState, summary.ReportState, summaryJSON, summary.UpdatedAt,
		)
		if err != nil {
			return mapCatalogWriteError("persist initial Recorder summary from expectation", err)
		}
		return nil
	}
	result, err := transaction.ExecContext(
		ctx,
		`UPDATE recorder_catalog.recorder_current
		    SET resource_revision = $2, support_state = $3, expectation_state = $4,
		        report_state = $5, latest_observation_id = $6, latest_boot_id = $7,
		        latest_sequence = $8, latest_occurred_at = $9, latest_received_at = $10,
		        latest_persisted_at = $11, document = $12, updated_at = $13
		  WHERE recorder_id = $1 AND resource_revision = $14`,
		summary.RecorderID, summary.ResourceRevision, summary.SupportState, summary.ExpectationState,
		summary.ReportState, recorderSummaryObservationID(summary), summary.LatestBootID,
		summary.LatestSequence, summary.LatestOccurredAt, summary.LatestReceivedAt,
		summary.LatestPersistedAt, summaryJSON, summary.UpdatedAt, expectedRevision,
	)
	if err != nil {
		return mapCatalogWriteError("persist revised Recorder summary from expectation", err)
	}
	affected, err := result.RowsAffected()
	if err != nil || affected != 1 {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	return nil
}

func recorderSummaryObservationID(summary guestruntimedomain.RecorderObservabilitySummary) any {
	if summary.LatestObservationReference == nil {
		return nil
	}
	return summary.LatestObservationReference.ResourceID
}

func decodeCatalogObservation(encoded []byte) (guestruntimedomain.CatalogObservation, error) {
	var observation guestruntimedomain.CatalogObservation
	if err := json.Unmarshal(encoded, &observation); err != nil {
		return guestruntimedomain.CatalogObservation{}, fmt.Errorf("decode owned CatalogObservation from PostgreSQL: %w", err)
	}
	return observation, nil
}

func decodeCatalogAdmission(encoded []byte) (guestruntimedomain.CatalogObservationAdmission, error) {
	var admission guestruntimedomain.CatalogObservationAdmission
	if err := json.Unmarshal(encoded, &admission); err != nil {
		return guestruntimedomain.CatalogObservationAdmission{}, fmt.Errorf("decode owned Catalog admission from PostgreSQL: %w", err)
	}
	return admission, nil
}

func mapCatalogWriteError(action string, err error) error {
	var postgresError *pgconn.PgError
	if errors.As(err, &postgresError) && postgresError.Code == "23505" {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	return fmt.Errorf("%s: %w", action, err)
}
