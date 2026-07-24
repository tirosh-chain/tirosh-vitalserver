// Package gueststatepostgresqlrestore owns restore into an explicitly empty
// PostgreSQL target.
package gueststatepostgresqlrestore

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/postgresqlcommandenvironment"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const restoreOutputLimit = 4 * 1024 * 1024

var ErrTargetNotEmpty = errors.New(
	"Guest operational-state PostgreSQL restore target is not empty",
)

type Rejection struct {
	Code    string
	Message string
	Cause   error
}

func (rejection *Rejection) Error() string {
	if rejection.Cause == nil {
		return rejection.Message
	}
	return rejection.Message + ": " + rejection.Cause.Error()
}

func (rejection *Rejection) Unwrap() error {
	return rejection.Cause
}

type Snapshot struct {
	DatabaseID           string
	AlembicRevision      string
	IncludedOwnerSchemas []string
	ByteSize             int64
	SHA256               string
}

type Owner struct {
	database           *sql.DB
	databaseName       string
	pgRestorePath      string
	commandEnvironment []string
}

func Open(
	ctx context.Context,
	databaseURL string,
	pgRestorePath string,
) (*Owner, error) {
	databaseName, err := restoreDatabaseName(databaseURL)
	if err != nil || !filepath.IsAbs(pgRestorePath) {
		return nil, fmt.Errorf("PostgreSQL restore configuration is incomplete")
	}
	info, err := os.Stat(pgRestorePath)
	if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
		return nil, fmt.Errorf("PostgreSQL restore executable is unavailable")
	}
	commandEnvironment, err := postgresqlcommandenvironment.FromDatabaseURL(
		os.Environ(),
		databaseURL,
	)
	if err != nil {
		return nil, err
	}
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open PostgreSQL restore target: %w", err)
	}
	database.SetMaxOpenConns(1)
	if err := database.PingContext(ctx); err != nil {
		database.Close()
		return nil, fmt.Errorf("reach PostgreSQL restore target: %w", err)
	}
	return &Owner{
		database:           database,
		databaseName:       databaseName,
		pgRestorePath:      pgRestorePath,
		commandEnvironment: commandEnvironment,
	}, nil
}

func (owner *Owner) Close() error {
	if owner == nil || owner.database == nil {
		return fmt.Errorf("PostgreSQL restore owner is not open")
	}
	return owner.database.Close()
}

func (owner *Owner) ProveEmptyTarget(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof, error) {
	if owner == nil || owner.database == nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof{},
			fmt.Errorf("PostgreSQL restore owner is not open")
	}
	var proof guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof
	var nonSystemSchemaCount int
	var publicRelationCount int
	if err := owner.database.QueryRowContext(
		ctx,
		`SELECT (
		          SELECT count(*)
		            FROM pg_catalog.pg_namespace
		           WHERE nspname IN (
		             'recorder_catalog',
		             'archive_export',
		             'recorder_assignment',
		             'guest_operational_state'
		           )
		        ),
		        to_regclass('public.alembic_version') IS NOT NULL,
		        (
		          SELECT count(*)
		            FROM pg_catalog.pg_namespace
		           WHERE nspname NOT IN (
		             'pg_catalog',
		             'information_schema',
		             'pg_toast',
		             'public'
		           )
		             AND nspname NOT LIKE 'pg_temp_%'
		             AND nspname NOT LIKE 'pg_toast_temp_%'
		        ),
		        (
		          SELECT count(*)
		            FROM pg_catalog.pg_class AS relation
		            JOIN pg_catalog.pg_namespace AS namespace
		              ON namespace.oid = relation.relnamespace
		           WHERE namespace.nspname = 'public'
		             AND relation.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
		        )`,
	).Scan(
		&proof.OwnerSchemaCount,
		&proof.AlembicVersionTablePresent,
		&nonSystemSchemaCount,
		&publicRelationCount,
	); err != nil {
		return proof, fmt.Errorf("prove PostgreSQL restore target emptiness: %w", err)
	}
	if proof.OwnerSchemaCount != 0 ||
		proof.AlembicVersionTablePresent ||
		nonSystemSchemaCount != 0 ||
		publicRelationCount != 0 {
		return proof, &Rejection{
			Code:    "postgresql-restore-target-not-empty",
			Message: "PostgreSQL restore target already contains state",
			Cause:   ErrTargetNotEmpty,
		}
	}
	proof.State = guestruntimedomain.GuestOperationalStatePostgreSQLRestoreTargetEmpty
	return proof, nil
}

func (owner *Owner) RestoreSnapshot(
	ctx context.Context,
	snapshotPath string,
	expected Snapshot,
) error {
	if owner == nil || owner.database == nil {
		return fmt.Errorf("PostgreSQL restore owner is not open")
	}
	if !filepath.IsAbs(snapshotPath) {
		return fmt.Errorf("PostgreSQL restore snapshot path must be absolute")
	}
	if err := validateSnapshot(expected); err != nil {
		return err
	}
	if _, err := owner.ProveEmptyTarget(ctx); err != nil {
		return err
	}
	byteSize, digest, err := digestFile(snapshotPath)
	if err != nil {
		return err
	}
	if byteSize != expected.ByteSize || digest != expected.SHA256 {
		return &Rejection{
			Code:    "postgresql-restore-source-digest-mismatch",
			Message: "PostgreSQL restore snapshot bytes do not match manifest",
		}
	}
	list, err := owner.run(
		ctx,
		[]string{"--list", snapshotPath},
		nil,
	)
	if err != nil {
		return fmt.Errorf("verify PostgreSQL restore snapshot archive: %w", err)
	}
	if err := validateRestoreList(list, expected); err != nil {
		return &Rejection{
			Code:    "postgresql-restore-owner-object-missing",
			Message: "PostgreSQL restore snapshot omitted required owner objects",
			Cause:   err,
		}
	}
	if _, err := owner.run(
		ctx,
		[]string{
			"--single-transaction",
			"--exit-on-error",
			"--clean",
			"--if-exists",
			"--no-owner",
			"--no-privileges",
			"--dbname=" + owner.databaseName,
			snapshotPath,
		},
		owner.commandEnvironment,
	); err != nil {
		return &Rejection{
			Code:    "postgresql-restore-command-failed",
			Message: "pg_restore transaction failed before complete owner state was proven",
			Cause:   err,
		}
	}
	return nil
}

func restoreDatabaseName(databaseURL string) (string, error) {
	parsed, err := url.Parse(databaseURL)
	if err != nil ||
		(parsed.Scheme != "postgresql" && parsed.Scheme != "postgres") ||
		parsed.Hostname() == "" ||
		parsed.User == nil ||
		parsed.User.Username() == "" {
		return "", fmt.Errorf("PostgreSQL restore database URL is incomplete")
	}
	name := strings.TrimPrefix(parsed.Path, "/")
	if name == "" || strings.Contains(name, "/") {
		return "", fmt.Errorf("PostgreSQL restore database name is invalid")
	}
	return name, nil
}

func (owner *Owner) VerifyOwnerReads(
	ctx context.Context,
	expected Snapshot,
) (guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof, error) {
	var proof guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof
	var databaseID string
	var contractVersion string
	var revision string
	if err := owner.database.QueryRowContext(
		ctx,
		`SELECT (
		          SELECT database_id
		            FROM guest_operational_state.metadata
		           WHERE singleton = true
		        ),
		        (
		          SELECT backup_contract_version
		            FROM guest_operational_state.metadata
		           WHERE singleton = true
		        ),
		        (SELECT version_num FROM public.alembic_version)`,
	).Scan(&databaseID, &contractVersion, &revision); err != nil {
		return proof, fmt.Errorf("read restored PostgreSQL owner identity: %w", err)
	}
	if databaseID != expected.DatabaseID ||
		contractVersion != guestruntimedomain.SchemaVersion ||
		revision != expected.AlembicRevision ||
		revision != gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision {
		return proof, &Rejection{
			Code:    "postgresql-restored-identity-mismatch",
			Message: "restored PostgreSQL identity or revision does not match manifest",
		}
	}
	proof.IdentityReadSucceeded = true
	checks := []struct {
		query  string
		target *bool
	}{
		{query: "SELECT 1 FROM recorder_catalog.recorder_current LIMIT 0", target: &proof.RecorderCurrentProjectionReadSucceeded},
		{query: "SELECT 1 FROM recorder_catalog.recorder_expectations LIMIT 0", target: &proof.RecorderExpectationReadSucceeded},
		{query: "SELECT 1 FROM recorder_catalog.observations LIMIT 0", target: &proof.RecorderObservationHistoryReadSucceeded},
		{query: "SELECT 1 FROM archive_export.recorder_attributions LIMIT 0", target: &proof.ArchiveArtifactAttributionReadSucceeded},
		{query: "SELECT 1 FROM archive_export.upload_attempts WHERE false UNION ALL SELECT 1 FROM archive_export.indexing_receipts WHERE false", target: &proof.ArchiveUploadIndexReceiptsReadSucceeded},
		{query: "SELECT 1 FROM recorder_assignment.evidence WHERE false UNION ALL SELECT 1 FROM recorder_assignment.resolutions WHERE false", target: &proof.RecorderAssignmentEvidenceReadSucceeded},
	}
	for _, check := range checks {
		if _, err := owner.database.ExecContext(ctx, check.query); err != nil {
			return proof, fmt.Errorf("verify restored PostgreSQL public owner read: %w", err)
		}
		*check.target = true
	}
	return proof, nil
}

func validateSnapshot(snapshot Snapshot) error {
	if !guestruntimedomain.ValidIdentifier(snapshot.DatabaseID) ||
		snapshot.AlembicRevision != gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision ||
		snapshot.ByteSize < 1 ||
		len(snapshot.SHA256) != 64 ||
		len(snapshot.IncludedOwnerSchemas) !=
			len(guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas) {
		return fmt.Errorf("PostgreSQL restore snapshot receipt is invalid")
	}
	seen := map[string]bool{}
	for _, schema := range snapshot.IncludedOwnerSchemas {
		seen[schema] = true
	}
	for _, schema := range guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas {
		if !seen[schema] {
			return fmt.Errorf("PostgreSQL restore snapshot omitted owner schema %s", schema)
		}
	}
	return nil
}

func validateRestoreList(list string, snapshot Snapshot) error {
	for _, required := range append(
		append([]string{}, snapshot.IncludedOwnerSchemas...),
		"alembic_version",
	) {
		if !strings.Contains(list, required) {
			return fmt.Errorf("PostgreSQL restore list omitted required owner object %s", required)
		}
	}
	return nil
}

func (owner *Owner) run(
	ctx context.Context,
	arguments []string,
	environment []string,
) (string, error) {
	output := &boundedOutput{maximumBytes: restoreOutputLimit}
	command := exec.CommandContext(ctx, owner.pgRestorePath, arguments...)
	if environment == nil {
		command.Env = os.Environ()
	} else {
		command.Env = append([]string{}, environment...)
	}
	command.Stdout = output
	command.Stderr = output
	if err := command.Run(); err != nil {
		return output.String(), fmt.Errorf("pg_restore failed: %w: %s", err, output.String())
	}
	if output.exceeded {
		return output.String(), fmt.Errorf("pg_restore output exceeded limit")
	}
	return output.String(), nil
}

func digestFile(path string) (int64, string, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, "", fmt.Errorf("open PostgreSQL restore snapshot: %w", err)
	}
	defer file.Close()
	digest := sha256.New()
	byteSize, err := io.Copy(digest, file)
	if err != nil {
		return 0, "", fmt.Errorf("digest PostgreSQL restore snapshot: %w", err)
	}
	return byteSize, hex.EncodeToString(digest.Sum(nil)), nil
}

type boundedOutput struct {
	buffer       bytes.Buffer
	maximumBytes int
	exceeded     bool
}

func (output *boundedOutput) Write(contents []byte) (int, error) {
	originalLength := len(contents)
	remaining := output.maximumBytes - output.buffer.Len()
	if remaining > 0 {
		if len(contents) > remaining {
			contents = contents[:remaining]
			output.exceeded = true
		}
		_, _ = output.buffer.Write(contents)
	} else {
		output.exceeded = true
	}
	return originalLength, nil
}

func (output *boundedOutput) String() string {
	value := strings.TrimSpace(output.buffer.String())
	if output.exceeded {
		return value + " [output truncated]"
	}
	return value
}
