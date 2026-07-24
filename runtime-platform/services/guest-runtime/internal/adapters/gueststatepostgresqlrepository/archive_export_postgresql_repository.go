package gueststatepostgresqlrepository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type ArchiveExportPostgreSQLRepository struct {
	database *sql.DB
}

func (repository *ArchiveExportPostgreSQLRepository) GuestRuntimeReadinessDependencyID() string {
	return "archive-export-postgresql"
}

func (repository *ArchiveExportPostgreSQLRepository) VerifyGuestRuntimeReadinessDependency(
	ctx context.Context,
) error {
	return repository.verifyReady(ctx)
}

func OpenArchiveExportPostgreSQLRepository(
	ctx context.Context,
	databaseURL string,
) (*ArchiveExportPostgreSQLRepository, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("Archive Export PostgreSQL database URL is required")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open Archive Export PostgreSQL database: %w", err)
	}
	database.SetMaxOpenConns(8)
	database.SetMaxIdleConns(2)
	repository := &ArchiveExportPostgreSQLRepository{database: database}
	if err := repository.verifyReady(ctx); err != nil {
		_ = database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *ArchiveExportPostgreSQLRepository) Close() error {
	if repository == nil || repository.database == nil {
		return fmt.Errorf("Archive Export PostgreSQL repository is not open")
	}
	return repository.database.Close()
}

func (repository *ArchiveExportPostgreSQLRepository) verifyReady(ctx context.Context) error {
	if err := repository.database.PingContext(ctx); err != nil {
		return fmt.Errorf("Archive Export PostgreSQL is unavailable: %w", err)
	}
	var revision string
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT version_num FROM public.alembic_version`,
	).Scan(&revision); err != nil {
		return fmt.Errorf("read Archive Export Alembic revision: %w", err)
	}
	if revision != ExpectedRecorderCatalogRevision {
		return fmt.Errorf(
			"Archive Export Alembic revision mismatch: expected=%s actual=%s",
			ExpectedRecorderCatalogRevision,
			revision,
		)
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT 1
		   FROM archive_export.artifacts
		  LIMIT 0`,
	)
	if err != nil {
		return fmt.Errorf("verify Archive Export owner schema read: %w", err)
	}
	if err := rows.Close(); err != nil {
		return fmt.Errorf("close Archive Export owner schema readiness read: %w", err)
	}
	return nil
}

func (repository *ArchiveExportPostgreSQLRepository) CommitFinalizedArchiveArtifact(
	ctx context.Context,
	artifact guestruntimedomain.ArchiveArtifact,
	attribution guestruntimedomain.RecorderArtifactAttribution,
) error {
	if err := guestruntimedomain.ValidateFinalizedArchiveArtifact(artifact, attribution); err != nil {
		return err
	}
	transaction, err := repository.database.BeginTx(
		ctx,
		&sql.TxOptions{Isolation: sql.LevelSerializable},
	)
	if err != nil {
		return fmt.Errorf("begin Archive artifact transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := insertArchiveArtifactAndAttribution(
		ctx,
		transaction,
		artifact,
		attribution,
	); err != nil {
		return err
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit Archive artifact transaction: %w", err)
	}
	return nil
}

func (repository *ArchiveExportPostgreSQLRepository) ReadArchiveSourceAdmission(
	ctx context.Context,
	requestID string,
) (guestruntimeapplication.ArchiveStoredSourceAdmission, error) {
	var stored guestruntimeapplication.ArchiveStoredSourceAdmission
	var commandJSON []byte
	var receiptJSON []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT command_digest, command_document, admission_document
		   FROM archive_export.source_admission_requests
		  WHERE request_id = $1`,
		requestID,
	).Scan(&stored.CommandDigest, &commandJSON, &receiptJSON)
	if errors.Is(err, sql.ErrNoRows) {
		return stored, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return stored, fmt.Errorf("read Archive source admission: %w", err)
	}
	if err := json.Unmarshal(commandJSON, &stored.Command); err != nil {
		return stored, fmt.Errorf("decode Archive source admission command: %w", err)
	}
	if err := json.Unmarshal(receiptJSON, &stored.Receipt); err != nil {
		return stored, fmt.Errorf("decode Archive source admission receipt: %w", err)
	}
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionCommand(stored.Command); err != nil {
		return stored, fmt.Errorf("validate stored Archive source admission command: %w", err)
	}
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionReceipt(stored.Receipt); err != nil {
		return stored, fmt.Errorf("validate stored Archive source admission receipt: %w", err)
	}
	return stored, nil
}

func (repository *ArchiveExportPostgreSQLRepository) ReadArchiveArtifactDetailBySourceReceipt(
	ctx context.Context,
	sourceKind string,
	sourceReceiptType string,
	sourceReceiptID string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	var artifactID string
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT artifact_id
		   FROM archive_export.artifacts
		  WHERE source_kind = $1
		    AND source_receipt_type = $2
		    AND source_receipt_id = $3`,
		sourceKind,
		sourceReceiptType,
		sourceReceiptID,
	).Scan(&artifactID)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.ArchiveArtifactDetail{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.ArchiveArtifactDetail{},
			fmt.Errorf("read Archive artifact identity by source receipt: %w", err)
	}
	return repository.ReadArchiveArtifactDetail(ctx, artifactID)
}

func (repository *ArchiveExportPostgreSQLRepository) CommitAcceptedArchiveSourceAdmission(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
	artifact guestruntimedomain.ArchiveArtifact,
	attribution guestruntimedomain.RecorderArtifactAttribution,
) error {
	if receipt.Outcome != "accepted" {
		return fmt.Errorf("accepted Archive source admission must have accepted outcome")
	}
	if err := validateArchiveSourceAdmissionCommit(
		commandDigest,
		command,
		receipt,
		&artifact,
	); err != nil {
		return err
	}
	if err := guestruntimedomain.ValidateFinalizedArchiveArtifact(artifact, attribution); err != nil {
		return err
	}
	transaction, err := repository.database.BeginTx(
		ctx,
		&sql.TxOptions{Isolation: sql.LevelSerializable},
	)
	if err != nil {
		return fmt.Errorf("begin accepted Archive source admission transaction: %w", err)
	}
	defer transaction.Rollback()
	if err := insertArchiveArtifactAndAttribution(
		ctx,
		transaction,
		artifact,
		attribution,
	); err != nil {
		return err
	}
	if err := insertArchiveSourceAdmission(
		ctx,
		transaction,
		commandDigest,
		command,
		receipt,
	); err != nil {
		return err
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit accepted Archive source admission transaction: %w", err)
	}
	return nil
}

func (repository *ArchiveExportPostgreSQLRepository) CommitTerminalArchiveSourceAdmission(
	ctx context.Context,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
) error {
	if receipt.Outcome != "duplicate" && receipt.Outcome != "quarantined" {
		return fmt.Errorf("terminal Archive source admission must be duplicate or quarantined")
	}
	if err := validateArchiveSourceAdmissionCommit(
		commandDigest,
		command,
		receipt,
		nil,
	); err != nil {
		return err
	}
	return insertArchiveSourceAdmission(
		ctx,
		repository.database,
		commandDigest,
		command,
		receipt,
	)
}

func (repository *ArchiveExportPostgreSQLRepository) CommitArchiveUploadAttempt(
	ctx context.Context,
	attempt guestruntimedomain.ArchiveUploadAttempt,
) error {
	if err := guestruntimedomain.ValidateArchiveUploadAttempt(attempt); err != nil {
		return err
	}
	providerJSON, err := json.Marshal(attempt.Provider)
	if err != nil {
		return fmt.Errorf("encode Archive upload provider: %w", err)
	}
	issueJSON, err := encodeOptionalIssue(attempt.Issue)
	if err != nil {
		return err
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO archive_export.upload_attempts (
		   attempt_id, request_id, artifact_id, provider_reference,
		   state, issue, started_at, finished_at
		 ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		attempt.AttemptID,
		attempt.RequestID,
		attempt.ArtifactID,
		providerJSON,
		attempt.State,
		nullableJSON(issueJSON),
		attempt.StartedAt,
		attempt.FinishedAt,
	)
	if err != nil {
		return mapArchiveLineageWriteError("persist Archive upload attempt", err)
	}
	return nil
}

func (repository *ArchiveExportPostgreSQLRepository) CommitArchiveIndexingReceipt(
	ctx context.Context,
	receipt guestruntimedomain.ArchiveIndexingReceipt,
) error {
	if err := guestruntimedomain.ValidateArchiveIndexingReceipt(receipt); err != nil {
		return err
	}
	issueJSON, err := encodeOptionalIssue(receipt.Issue)
	if err != nil {
		return err
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO archive_export.indexing_receipts (
		   receipt_id, artifact_id, upload_attempt_id, provider_receipt_id,
		   outcome, issue, observed_at, persisted_at
		 ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		receipt.ReceiptID,
		receipt.ArtifactID,
		receipt.UploadAttemptID,
		receipt.ProviderReceiptID,
		receipt.Outcome,
		nullableJSON(issueJSON),
		receipt.ObservedAt,
		receipt.PersistedAt,
	)
	if err != nil {
		return mapArchiveLineageWriteError("persist Archive indexing receipt", err)
	}
	return nil
}

func (repository *ArchiveExportPostgreSQLRepository) ReadArchiveArtifactDetail(
	ctx context.Context,
	artifactID string,
) (guestruntimedomain.ArchiveArtifactDetail, error) {
	artifact, attribution, err := repository.readArchiveArtifactAndAttribution(
		ctx,
		artifactID,
	)
	if err != nil {
		return guestruntimedomain.ArchiveArtifactDetail{}, err
	}
	attempts, err := repository.listArchiveUploadAttempts(ctx, artifactID)
	if err != nil {
		return guestruntimedomain.ArchiveArtifactDetail{}, err
	}
	receipts, err := repository.listArchiveIndexingReceipts(ctx, artifactID)
	if err != nil {
		return guestruntimedomain.ArchiveArtifactDetail{}, err
	}
	return guestruntimedomain.ArchiveArtifactDetail{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		Artifact:         artifact,
		Attribution:      attribution,
		UploadAttempts:   attempts,
		IndexingReceipts: receipts,
	}, nil
}

func (repository *ArchiveExportPostgreSQLRepository) ListMatchedRecorderArchiveArtifacts(
	ctx context.Context,
	recorderID string,
	limit int,
	position *guestruntimeapplication.ArchiveArtifactPagePosition,
) ([]guestruntimedomain.ArchiveArtifactDetail, error) {
	if !guestruntimedomain.ValidIdentifier(recorderID) ||
		limit < 1 ||
		limit > guestruntimeapplication.MaximumRecorderArtifactRepositoryFetchSize {
		return nil, fmt.Errorf("bounded Recorder artifact query is invalid")
	}
	query := `SELECT attribution.artifact_id
	            FROM archive_export.recorder_attributions AS attribution
	           WHERE attribution.outcome = 'matched'
	             AND attribution.matched_recorder_id = $1`
	arguments := []any{recorderID}
	if position == nil {
		query += ` ORDER BY attribution.resolved_at DESC, attribution.artifact_id DESC LIMIT $2`
		arguments = append(arguments, limit)
	} else {
		query += ` AND (attribution.resolved_at, attribution.artifact_id) < ($2::timestamptz, $3)
		           ORDER BY attribution.resolved_at DESC, attribution.artifact_id DESC LIMIT $4`
		arguments = append(arguments, position.ResolvedAt, position.ArtifactID, limit)
	}
	rows, err := repository.database.QueryContext(ctx, query, arguments...)
	if err != nil {
		return nil, fmt.Errorf("list matched Recorder Archive artifacts: %w", err)
	}
	defer rows.Close()
	artifactIDs := make([]string, 0, limit)
	for rows.Next() {
		var artifactID string
		if err := rows.Scan(&artifactID); err != nil {
			return nil, fmt.Errorf("scan matched Recorder Archive artifact: %w", err)
		}
		artifactIDs = append(artifactIDs, artifactID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate matched Recorder Archive artifacts: %w", err)
	}
	details := make([]guestruntimedomain.ArchiveArtifactDetail, 0, len(artifactIDs))
	for _, artifactID := range artifactIDs {
		detail, err := repository.ReadArchiveArtifactDetail(ctx, artifactID)
		if err != nil {
			return nil, err
		}
		details = append(details, detail)
	}
	return details, nil
}

func (repository *ArchiveExportPostgreSQLRepository) readArchiveArtifactAndAttribution(
	ctx context.Context,
	artifactID string,
) (
	guestruntimedomain.ArchiveArtifact,
	guestruntimedomain.RecorderArtifactAttribution,
	error,
) {
	var artifact guestruntimedomain.ArchiveArtifact
	var attribution guestruntimedomain.RecorderArtifactAttribution
	var manifestJSON []byte
	var assignmentEvidenceJSON []byte
	var candidateRecorderIDsJSON []byte
	var createdAt time.Time
	var finalizedAt sql.NullTime
	var evidenceObservedAt time.Time
	var resolvedAt time.Time
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT artifact.artifact_id, artifact.source_kind,
		        artifact.source_receipt_type, artifact.source_receipt_id,
		        artifact.original_file_name, artifact.media_type,
		        artifact.byte_size, artifact.sha256,
		        artifact.finalization_state, artifact.manifest_document,
		        artifact.created_at, artifact.finalized_at,
		        attribution.reported_bed_name,
		        attribution.evidence_observed_at,
		        attribution.assignment_evidence_reference,
		        attribution.candidate_recorder_ids,
		        attribution.outcome, attribution.matched_recorder_id,
		        attribution.policy_version, attribution.resolved_at
		   FROM archive_export.artifacts AS artifact
		   JOIN archive_export.recorder_attributions AS attribution
		     ON attribution.artifact_id = artifact.artifact_id
		  WHERE artifact.artifact_id = $1`,
		artifactID,
	).Scan(
		&artifact.ArtifactID,
		&artifact.SourceKind,
		&artifact.SourceReceiptType,
		&artifact.SourceReceiptID,
		&artifact.OriginalFileName,
		&artifact.MediaType,
		&artifact.ByteSize,
		&artifact.SHA256,
		&artifact.FinalizationState,
		&manifestJSON,
		&createdAt,
		&finalizedAt,
		&attribution.ReportedBedName,
		&evidenceObservedAt,
		&assignmentEvidenceJSON,
		&candidateRecorderIDsJSON,
		&attribution.Outcome,
		&attribution.MatchedRecorderID,
		&attribution.PolicyVersion,
		&resolvedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return artifact, attribution, guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return artifact, attribution, fmt.Errorf("read Archive artifact detail: %w", err)
	}
	artifact.SchemaVersion = guestruntimedomain.SchemaVersion
	artifact.CreatedAt = guestruntimedomain.Timestamp(createdAt)
	if finalizedAt.Valid {
		value := guestruntimedomain.Timestamp(finalizedAt.Time)
		artifact.FinalizedAt = &value
	}
	if err := json.Unmarshal(manifestJSON, &artifact.Manifest); err != nil {
		return artifact, attribution, fmt.Errorf("decode Archive artifact manifest: %w", err)
	}
	attribution.SchemaVersion = guestruntimedomain.SchemaVersion
	attribution.ArtifactID = artifact.ArtifactID
	attribution.EvidenceObservedAt = guestruntimedomain.Timestamp(evidenceObservedAt)
	attribution.ResolvedAt = guestruntimedomain.Timestamp(resolvedAt)
	if len(assignmentEvidenceJSON) > 0 {
		var evidence guestruntimedomain.EvidenceReference
		if err := json.Unmarshal(assignmentEvidenceJSON, &evidence); err != nil {
			return artifact, attribution, fmt.Errorf("decode Archive assignment evidence: %w", err)
		}
		attribution.AssignmentEvidenceReference = &evidence
	}
	if err := json.Unmarshal(candidateRecorderIDsJSON, &attribution.CandidateRecorderIDs); err != nil {
		return artifact, attribution, fmt.Errorf("decode Archive Recorder candidates: %w", err)
	}
	return artifact, attribution, nil
}

func (repository *ArchiveExportPostgreSQLRepository) listArchiveUploadAttempts(
	ctx context.Context,
	artifactID string,
) ([]guestruntimedomain.ArchiveUploadAttempt, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT attempt_id, request_id, provider_reference, state, issue,
		        started_at, finished_at
		   FROM archive_export.upload_attempts
		  WHERE artifact_id = $1
		  ORDER BY started_at DESC, attempt_id DESC`,
		artifactID,
	)
	if err != nil {
		return nil, fmt.Errorf("list Archive upload attempts: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.ArchiveUploadAttempt{}
	for rows.Next() {
		attempt := guestruntimedomain.ArchiveUploadAttempt{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			ArtifactID:    artifactID,
		}
		var providerJSON []byte
		var issueJSON []byte
		var startedAt time.Time
		var finishedAt sql.NullTime
		if err := rows.Scan(
			&attempt.AttemptID,
			&attempt.RequestID,
			&providerJSON,
			&attempt.State,
			&issueJSON,
			&startedAt,
			&finishedAt,
		); err != nil {
			return nil, fmt.Errorf("scan Archive upload attempt: %w", err)
		}
		if err := json.Unmarshal(providerJSON, &attempt.Provider); err != nil {
			return nil, fmt.Errorf("decode Archive upload provider: %w", err)
		}
		if err := decodeOptionalIssue(issueJSON, &attempt.Issue); err != nil {
			return nil, err
		}
		attempt.StartedAt = guestruntimedomain.Timestamp(startedAt)
		if finishedAt.Valid {
			value := guestruntimedomain.Timestamp(finishedAt.Time)
			attempt.FinishedAt = &value
		}
		result = append(result, attempt)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Archive upload attempts: %w", err)
	}
	return result, nil
}

func (repository *ArchiveExportPostgreSQLRepository) listArchiveIndexingReceipts(
	ctx context.Context,
	artifactID string,
) ([]guestruntimedomain.ArchiveIndexingReceipt, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT receipt_id, upload_attempt_id, provider_receipt_id,
		        outcome, issue, observed_at, persisted_at
		   FROM archive_export.indexing_receipts
		  WHERE artifact_id = $1
		  ORDER BY persisted_at DESC, receipt_id DESC`,
		artifactID,
	)
	if err != nil {
		return nil, fmt.Errorf("list Archive indexing receipts: %w", err)
	}
	defer rows.Close()
	result := []guestruntimedomain.ArchiveIndexingReceipt{}
	for rows.Next() {
		receipt := guestruntimedomain.ArchiveIndexingReceipt{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			ArtifactID:    artifactID,
		}
		var issueJSON []byte
		var observedAt time.Time
		var persistedAt time.Time
		if err := rows.Scan(
			&receipt.ReceiptID,
			&receipt.UploadAttemptID,
			&receipt.ProviderReceiptID,
			&receipt.Outcome,
			&issueJSON,
			&observedAt,
			&persistedAt,
		); err != nil {
			return nil, fmt.Errorf("scan Archive indexing receipt: %w", err)
		}
		if err := decodeOptionalIssue(issueJSON, &receipt.Issue); err != nil {
			return nil, err
		}
		receipt.ObservedAt = guestruntimedomain.Timestamp(observedAt)
		receipt.PersistedAt = guestruntimedomain.Timestamp(persistedAt)
		result = append(result, receipt)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Archive indexing receipts: %w", err)
	}
	return result, nil
}

func encodeOptionalIssue(issue *guestruntimedomain.Issue) ([]byte, error) {
	if issue == nil {
		return nil, nil
	}
	encoded, err := json.Marshal(issue)
	if err != nil {
		return nil, fmt.Errorf("encode Archive issue: %w", err)
	}
	return encoded, nil
}

func decodeOptionalIssue(encoded []byte, target **guestruntimedomain.Issue) error {
	if len(encoded) == 0 {
		return nil
	}
	var issue guestruntimedomain.Issue
	if err := json.Unmarshal(encoded, &issue); err != nil {
		return fmt.Errorf("decode Archive issue: %w", err)
	}
	*target = &issue
	return nil
}

type archiveSQLExecutor interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

func insertArchiveArtifactAndAttribution(
	ctx context.Context,
	executor archiveSQLExecutor,
	artifact guestruntimedomain.ArchiveArtifact,
	attribution guestruntimedomain.RecorderArtifactAttribution,
) error {
	manifestJSON, err := json.Marshal(artifact.Manifest)
	if err != nil {
		return fmt.Errorf("encode Archive artifact manifest: %w", err)
	}
	candidateRecorderIDs := attribution.CandidateRecorderIDs
	if len(candidateRecorderIDs) == 0 {
		candidateRecorderIDs = []string{}
	}
	candidateRecorderIDsJSON, err := json.Marshal(candidateRecorderIDs)
	if err != nil {
		return fmt.Errorf("encode Archive attribution candidates: %w", err)
	}
	var assignmentEvidenceJSON []byte
	if attribution.AssignmentEvidenceReference != nil {
		assignmentEvidenceJSON, err = json.Marshal(attribution.AssignmentEvidenceReference)
		if err != nil {
			return fmt.Errorf("encode Archive assignment evidence: %w", err)
		}
	}
	if _, err := executor.ExecContext(
		ctx,
		`INSERT INTO archive_export.artifacts (
		   artifact_id, source_kind, source_receipt_type, source_receipt_id,
		   manifest_id, original_file_name, media_type, byte_size, sha256,
		   finalization_state, manifest_document, created_at, finalized_at
		 ) VALUES (
		   $1, $2, $3, $4,
		   $5, $6, $7, $8, $9,
		   $10, $11, $12, $13
		 )`,
		artifact.ArtifactID,
		artifact.SourceKind,
		artifact.SourceReceiptType,
		artifact.SourceReceiptID,
		artifact.Manifest.ID,
		artifact.OriginalFileName,
		artifact.MediaType,
		artifact.ByteSize,
		artifact.SHA256,
		artifact.FinalizationState,
		manifestJSON,
		artifact.CreatedAt,
		artifact.FinalizedAt,
	); err != nil {
		return mapArchiveLineageWriteError("persist Archive artifact", err)
	}
	if _, err := executor.ExecContext(
		ctx,
		`INSERT INTO archive_export.recorder_attributions (
		   artifact_id, reported_bed_name, evidence_observed_at,
		   assignment_evidence_reference, candidate_recorder_ids,
		   outcome, matched_recorder_id, policy_version, resolved_at
		 ) VALUES (
		   $1, $2, $3,
		   $4, $5,
		   $6, $7, $8, $9
		 )`,
		attribution.ArtifactID,
		attribution.ReportedBedName,
		attribution.EvidenceObservedAt,
		nullableJSON(assignmentEvidenceJSON),
		candidateRecorderIDsJSON,
		attribution.Outcome,
		attribution.MatchedRecorderID,
		attribution.PolicyVersion,
		attribution.ResolvedAt,
	); err != nil {
		return mapArchiveLineageWriteError("persist Archive Recorder attribution", err)
	}
	return nil
}

func insertArchiveSourceAdmission(
	ctx context.Context,
	executor archiveSQLExecutor,
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
) error {
	commandJSON, err := json.Marshal(command)
	if err != nil {
		return fmt.Errorf("encode Archive source admission command: %w", err)
	}
	receiptJSON, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode Archive source admission receipt: %w", err)
	}
	issueJSON, err := encodeOptionalIssue(receipt.Issue)
	if err != nil {
		return err
	}
	var artifactID *string
	if receipt.ArtifactReference != nil {
		artifactID = &receipt.ArtifactReference.ResourceID
	}
	if _, err := executor.ExecContext(
		ctx,
		`INSERT INTO archive_export.source_admission_requests (
		   request_id, command_digest,
		   source_kind, source_receipt_type, source_receipt_id,
		   outcome, artifact_id, issue,
		   admission_document, command_document,
		   received_at, persisted_at
		 ) VALUES (
		   $1, $2,
		   $3, $4, $5,
		   $6, $7, $8,
		   $9, $10,
		   $11, $12
		 )`,
		command.RequestID,
		commandDigest,
		command.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		command.Source.ID,
		receipt.Outcome,
		artifactID,
		nullableJSON(issueJSON),
		receiptJSON,
		commandJSON,
		receipt.ReceivedAt,
		receipt.PersistedAt,
	); err != nil {
		return mapArchiveLineageWriteError("persist Archive source admission", err)
	}
	return nil
}

func validateArchiveSourceAdmissionCommit(
	commandDigest string,
	command guestruntimedomain.ArchiveSourceAdmissionCommand,
	receipt guestruntimedomain.ArchiveSourceAdmissionReceipt,
	artifact *guestruntimedomain.ArchiveArtifact,
) error {
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionCommand(command); err != nil {
		return err
	}
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionReceipt(receipt); err != nil {
		return err
	}
	expectedDigest, err := guestruntimedomain.CommandDigest(command)
	if err != nil {
		return err
	}
	if commandDigest != expectedDigest {
		return fmt.Errorf("Archive source admission command digest does not match command")
	}
	if receipt.RequestID != command.RequestID ||
		receipt.ReceivedAt != command.Source.ReceivedAt {
		return fmt.Errorf("Archive source admission receipt does not match command")
	}
	if artifact == nil {
		return nil
	}
	if receipt.ArtifactReference == nil ||
		receipt.ArtifactReference.ResourceID != artifact.ArtifactID ||
		artifact.SourceKind != command.Source.SourceKind ||
		artifact.SourceReceiptType != guestruntimedomain.RecorderVitalUploadSourceReceiptType ||
		artifact.SourceReceiptID != command.Source.ID ||
		artifact.OriginalFileName != command.Source.OriginalFileName ||
		artifact.MediaType != command.Source.MediaType ||
		artifact.ByteSize != command.Source.ByteSize ||
		artifact.SHA256 != command.Source.SHA256 {
		return fmt.Errorf("accepted Archive artifact does not match source command")
	}
	return nil
}

func nullableJSON(encoded []byte) any {
	if len(encoded) == 0 {
		return nil
	}
	return encoded
}

func mapArchiveLineageWriteError(action string, err error) error {
	var postgresError *pgconn.PgError
	if errors.As(err, &postgresError) && postgresError.Code == "23505" {
		return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
	}
	return fmt.Errorf("%s: %w", action, err)
}

var _ guestruntimeapplication.GuestRuntimeArchiveLineageRepository = (*ArchiveExportPostgreSQLRepository)(nil)
var _ guestruntimeapplication.GuestRuntimeArchiveSourceAdmissionRepository = (*ArchiveExportPostgreSQLRepository)(nil)
