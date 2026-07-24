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

type RecorderAssignmentPostgreSQLRepository struct {
	database *sql.DB
}

func OpenRecorderAssignmentPostgreSQLRepository(
	ctx context.Context,
	databaseURL string,
) (*RecorderAssignmentPostgreSQLRepository, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("Recorder Assignment PostgreSQL database URL is required")
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open Recorder Assignment PostgreSQL database: %w", err)
	}
	database.SetMaxOpenConns(4)
	database.SetMaxIdleConns(1)
	repository := &RecorderAssignmentPostgreSQLRepository{database: database}
	if err := repository.verifyReady(ctx); err != nil {
		_ = database.Close()
		return nil, err
	}
	return repository, nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) Close() error {
	if repository == nil || repository.database == nil {
		return fmt.Errorf("Recorder Assignment PostgreSQL repository is not open")
	}
	return repository.database.Close()
}

func (repository *RecorderAssignmentPostgreSQLRepository) GuestRuntimeReadinessDependencyID() string {
	return "recorder-assignment-postgresql"
}

func (repository *RecorderAssignmentPostgreSQLRepository) VerifyGuestRuntimeReadinessDependency(
	ctx context.Context,
) error {
	return repository.verifyReady(ctx)
}

func (repository *RecorderAssignmentPostgreSQLRepository) verifyReady(
	ctx context.Context,
) error {
	if err := repository.database.PingContext(ctx); err != nil {
		return fmt.Errorf("Recorder Assignment PostgreSQL is unavailable: %w", err)
	}
	var revision string
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT version_num FROM public.alembic_version`,
	).Scan(&revision); err != nil {
		return fmt.Errorf("read Recorder Assignment Alembic revision: %w", err)
	}
	if revision != ExpectedRecorderCatalogRevision {
		return fmt.Errorf(
			"Recorder Assignment Alembic revision mismatch: expected=%s actual=%s",
			ExpectedRecorderCatalogRevision,
			revision,
		)
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT 1 FROM recorder_assignment.evidence LIMIT 0`,
	)
	if err != nil {
		return fmt.Errorf("verify Recorder Assignment owner schema read: %w", err)
	}
	if err := rows.Close(); err != nil {
		return fmt.Errorf("close Recorder Assignment owner schema readiness read: %w", err)
	}
	return nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) ReadRecorderAssignmentEvidenceByRequestID(
	ctx context.Context,
	requestID string,
) (guestruntimeapplication.StoredRecorderAssignmentEvidence, error) {
	var commandDigest string
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT command_digest, evidence_document
		   FROM recorder_assignment.evidence
		  WHERE request_id = $1`,
		requestID,
	).Scan(&commandDigest, &encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimeapplication.StoredRecorderAssignmentEvidence{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimeapplication.StoredRecorderAssignmentEvidence{},
			fmt.Errorf("read Recorder assignment evidence request: %w", err)
	}
	evidence, err := decodeRecorderAssignmentEvidence(encoded)
	if err != nil {
		return guestruntimeapplication.StoredRecorderAssignmentEvidence{}, err
	}
	return guestruntimeapplication.StoredRecorderAssignmentEvidence{
		Evidence:      evidence,
		CommandDigest: commandDigest,
	}, nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) CommitRecorderAssignmentEvidence(
	ctx context.Context,
	requestID string,
	commandDigest string,
	evidence guestruntimedomain.RecorderAssignmentEvidence,
) error {
	if err := guestruntimedomain.ValidateRecorderAssignmentEvidence(evidence); err != nil {
		return err
	}
	sourceReference, err := json.Marshal(evidence.SourceReference)
	if err != nil {
		return fmt.Errorf("encode Recorder assignment source reference: %w", err)
	}
	document, err := json.Marshal(evidence)
	if err != nil {
		return fmt.Errorf("encode Recorder assignment evidence: %w", err)
	}
	var effectiveUntil any
	if evidence.EffectiveUntil != nil {
		effectiveUntil = *evidence.EffectiveUntil
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO recorder_assignment.evidence (
		   evidence_id, request_id, command_digest, recorder_id, bed_name,
		   effective_from, effective_until, observed_at, persisted_at,
		   source_kind, source_reference, evidence_document
		 ) VALUES (
		   $1, $2, $3, $4, $5, $6::timestamptz, $7::timestamptz,
		   $8::timestamptz, $9::timestamptz, $10, $11::jsonb, $12::jsonb
		 )`,
		evidence.EvidenceID,
		requestID,
		commandDigest,
		evidence.RecorderID,
		evidence.BedName,
		evidence.EffectiveFrom,
		effectiveUntil,
		evidence.ObservedAt,
		evidence.PersistedAt,
		evidence.SourceKind,
		sourceReference,
		document,
	)
	if err != nil {
		var postgresError *pgconn.PgError
		if errors.As(err, &postgresError) && postgresError.Code == "23505" {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
		return fmt.Errorf("commit Recorder assignment evidence: %w", err)
	}
	return nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) ListEffectiveRecorderAssignmentEvidence(
	ctx context.Context,
	bedName string,
	effectiveAt string,
	limit int,
) ([]guestruntimedomain.RecorderAssignmentEvidence, error) {
	if limit < 1 || limit > guestruntimedomain.MaximumRecorderAssignmentCandidates+1 {
		return nil, fmt.Errorf("Recorder assignment evidence limit is invalid")
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT evidence_document
		   FROM recorder_assignment.evidence
		  WHERE bed_name = $1
		    AND effective_from <= $2::timestamptz
		    AND (effective_until IS NULL OR $2::timestamptz < effective_until)
		  ORDER BY recorder_id, evidence_id
		  LIMIT $3`,
		bedName,
		effectiveAt,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list effective Recorder assignment evidence: %w", err)
	}
	defer rows.Close()
	values := make([]guestruntimedomain.RecorderAssignmentEvidence, 0)
	for rows.Next() {
		var encoded []byte
		if err := rows.Scan(&encoded); err != nil {
			return nil, fmt.Errorf("scan Recorder assignment evidence: %w", err)
		}
		evidence, err := decodeRecorderAssignmentEvidence(encoded)
		if err != nil {
			return nil, err
		}
		values = append(values, evidence)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate Recorder assignment evidence: %w", err)
	}
	return values, nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) ReadRecorderAssignmentResolution(
	ctx context.Context,
	resolutionID string,
) (guestruntimedomain.RecorderAssignmentResolution, error) {
	var encoded []byte
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT resolution_document
		   FROM recorder_assignment.resolutions
		  WHERE resolution_id = $1`,
		resolutionID,
	).Scan(&encoded)
	if errors.Is(err, sql.ErrNoRows) {
		return guestruntimedomain.RecorderAssignmentResolution{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	}
	if err != nil {
		return guestruntimedomain.RecorderAssignmentResolution{},
			fmt.Errorf("read Recorder assignment resolution: %w", err)
	}
	var resolution guestruntimedomain.RecorderAssignmentResolution
	if err := json.Unmarshal(encoded, &resolution); err != nil {
		return guestruntimedomain.RecorderAssignmentResolution{},
			fmt.Errorf("decode Recorder assignment resolution: %w", err)
	}
	if err := guestruntimedomain.ValidateRecorderAssignmentResolution(resolution); err != nil {
		return guestruntimedomain.RecorderAssignmentResolution{}, err
	}
	return resolution, nil
}

func (repository *RecorderAssignmentPostgreSQLRepository) CommitRecorderAssignmentResolution(
	ctx context.Context,
	resolution guestruntimedomain.RecorderAssignmentResolution,
) error {
	if err := guestruntimedomain.ValidateRecorderAssignmentResolution(resolution); err != nil {
		return err
	}
	evidenceReferences, err := json.Marshal(resolution.EvidenceReferences)
	if err != nil {
		return fmt.Errorf("encode Recorder assignment resolution evidence: %w", err)
	}
	candidates, err := json.Marshal(resolution.CandidateRecorderIDs)
	if err != nil {
		return fmt.Errorf("encode Recorder assignment resolution candidates: %w", err)
	}
	document, err := json.Marshal(resolution)
	if err != nil {
		return fmt.Errorf("encode Recorder assignment resolution: %w", err)
	}
	_, err = repository.database.ExecContext(
		ctx,
		`INSERT INTO recorder_assignment.resolutions (
		   resolution_id, bed_name, effective_at, evidence_references,
		   candidate_recorder_ids, policy_version, resolved_at,
		   resolution_document
		 ) VALUES (
		   $1, $2, $3::timestamptz, $4::jsonb, $5::jsonb, $6,
		   $7::timestamptz, $8::jsonb
		 )`,
		resolution.ResolutionID,
		resolution.BedName,
		resolution.EffectiveAt,
		evidenceReferences,
		candidates,
		resolution.PolicyVersion,
		resolution.ResolvedAt,
		document,
	)
	if err != nil {
		var postgresError *pgconn.PgError
		if errors.As(err, &postgresError) && postgresError.Code == "23505" {
			return guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict
		}
		return fmt.Errorf("commit Recorder assignment resolution: %w", err)
	}
	return nil
}

func decodeRecorderAssignmentEvidence(
	encoded []byte,
) (guestruntimedomain.RecorderAssignmentEvidence, error) {
	var evidence guestruntimedomain.RecorderAssignmentEvidence
	if err := json.Unmarshal(encoded, &evidence); err != nil {
		return guestruntimedomain.RecorderAssignmentEvidence{},
			fmt.Errorf("decode Recorder assignment evidence: %w", err)
	}
	if err := guestruntimedomain.ValidateRecorderAssignmentEvidence(evidence); err != nil {
		return guestruntimedomain.RecorderAssignmentEvidence{}, err
	}
	return evidence, nil
}

var _ guestruntimeapplication.GuestRuntimeRecorderAssignmentRepository = (*RecorderAssignmentPostgreSQLRepository)(nil)
var _ guestruntimeapplication.GuestRuntimeReadinessDependency = (*RecorderAssignmentPostgreSQLRepository)(nil)
