// Package gueststatepostgresqlbackup owns the bounded pg_dump/pg_restore
// effect for the explicit Guest operational-state owner schemas.
package gueststatepostgresqlbackup

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/postgresqlcommandenvironment"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const postgreSQLCommandOutputLimit = 4 * 1024 * 1024

type Configuration struct {
	DatabaseURL             string
	PGDumpExecutablePath    string
	PGRestoreExecutablePath string
	ExpectedAlembicRevision string
}

type Snapshot struct {
	DatabaseID           string
	AlembicRevision      string
	IncludedOwnerSchemas []string
	ByteSize             int64
	SHA256               string
}

// Rejection is explicit evidence that an acceptable snapshot was not
// produced. Other errors leave the effect outcome unknown.
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

type Owner struct {
	configuration      Configuration
	commandEnvironment []string
	database           *sql.DB
}

func Open(ctx context.Context, configuration Configuration) (*Owner, error) {
	if configuration.DatabaseURL == "" ||
		!filepath.IsAbs(configuration.PGDumpExecutablePath) ||
		!filepath.IsAbs(configuration.PGRestoreExecutablePath) ||
		!guestruntimedomain.ValidIdentifier(configuration.ExpectedAlembicRevision) {
		return nil, fmt.Errorf("PostgreSQL logical snapshot configuration is incomplete")
	}
	for _, path := range []string{
		configuration.PGDumpExecutablePath,
		configuration.PGRestoreExecutablePath,
	} {
		info, err := os.Stat(path)
		if err != nil {
			return nil, fmt.Errorf("PostgreSQL backup executable is unreadable: %w", err)
		}
		if info.IsDir() || info.Mode()&0o111 == 0 {
			return nil, fmt.Errorf("PostgreSQL backup executable path is not executable")
		}
	}
	commandEnvironment, err := postgresqlcommandenvironment.FromDatabaseURL(
		os.Environ(),
		configuration.DatabaseURL,
	)
	if err != nil {
		return nil, err
	}
	database, err := sql.Open("pgx", configuration.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("open PostgreSQL logical snapshot owner: %w", err)
	}
	database.SetMaxOpenConns(1)
	owner := &Owner{
		configuration:      configuration,
		commandEnvironment: commandEnvironment,
		database:           database,
	}
	if _, _, err := owner.readSourceIdentity(ctx); err != nil {
		database.Close()
		return nil, err
	}
	return owner, nil
}

func (owner *Owner) Close() error {
	if owner == nil || owner.database == nil {
		return fmt.Errorf("PostgreSQL logical snapshot owner is not open")
	}
	return owner.database.Close()
}

func (owner *Owner) CreateLogicalSnapshot(
	ctx context.Context,
	destinationPath string,
) (Snapshot, error) {
	if owner == nil || owner.database == nil {
		return Snapshot{}, fmt.Errorf("PostgreSQL logical snapshot owner is not open")
	}
	if !filepath.IsAbs(destinationPath) {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-destination-invalid",
			Message: "PostgreSQL logical snapshot destination must be absolute",
		}
	}
	info, err := os.Stat(filepath.Dir(destinationPath))
	if err != nil {
		return Snapshot{}, fmt.Errorf("read PostgreSQL snapshot parent: %w", err)
	}
	if !info.IsDir() {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-destination-invalid",
			Message: "PostgreSQL logical snapshot parent is not a directory",
		}
	}
	databaseID, revision, err := owner.readSourceIdentity(ctx)
	if err != nil {
		return Snapshot{}, err
	}
	if _, err := os.Stat(destinationPath); err == nil {
		return owner.inspectSnapshot(ctx, destinationPath, databaseID, revision)
	} else if !errors.Is(err, os.ErrNotExist) {
		return Snapshot{}, fmt.Errorf("inspect PostgreSQL snapshot destination: %w", err)
	}
	partialPath := destinationPath + ".partial"
	if _, err := os.Stat(partialPath); err == nil {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-partial-exists",
			Message: "PostgreSQL logical snapshot has ambiguous partial output",
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return Snapshot{}, fmt.Errorf("inspect PostgreSQL partial snapshot: %w", err)
	}
	arguments := []string{
		"--format=custom",
		"--no-owner",
		"--no-privileges",
		"--file=" + partialPath,
	}
	for _, schema := range guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas {
		arguments = append(arguments, "--schema="+schema)
	}
	// PostgreSQL combines --schema and --table include filters as an
	// intersection. Select public as a schema only after readSourceIdentity
	// proves that it owns no relation other than Alembic's version table and
	// primary-key index.
	arguments = append(arguments, "--schema=public")
	if _, err := owner.runCommand(
		ctx,
		owner.configuration.PGDumpExecutablePath,
		arguments,
	); err != nil {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-logical-snapshot-failed",
			Message: "pg_dump did not create a PostgreSQL logical snapshot",
			Cause:   err,
		}
	}
	snapshot, err := owner.inspectSnapshot(ctx, partialPath, databaseID, revision)
	if err != nil {
		return Snapshot{}, err
	}
	if err := os.Rename(partialPath, destinationPath); err != nil {
		return Snapshot{}, fmt.Errorf("publish PostgreSQL logical snapshot: %w", err)
	}
	parent, err := os.Open(filepath.Dir(destinationPath))
	if err != nil {
		return Snapshot{}, fmt.Errorf("open PostgreSQL snapshot parent: %w", err)
	}
	defer parent.Close()
	if err := parent.Sync(); err != nil {
		return Snapshot{}, fmt.Errorf("sync PostgreSQL snapshot parent: %w", err)
	}
	return snapshot, nil
}

func (owner *Owner) readSourceIdentity(ctx context.Context) (string, string, error) {
	var databaseID string
	var contractVersion string
	var revision string
	var schemaCount int
	var unexpectedPublicRelationCount int
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
		        (SELECT version_num FROM public.alembic_version),
		        (
		          SELECT count(*)
		            FROM pg_namespace
		           WHERE nspname IN (
		             'recorder_catalog',
		             'archive_export',
		             'recorder_assignment',
		             'guest_operational_state'
		           )
		        ),
		        (
		          SELECT count(*)
		            FROM pg_catalog.pg_class AS relation
		            JOIN pg_catalog.pg_namespace AS namespace
		              ON namespace.oid = relation.relnamespace
		           WHERE namespace.nspname = 'public'
		             AND relation.relname NOT IN (
		               'alembic_version',
		               'alembic_version_pkc'
		             )
		        )`,
	).Scan(
		&databaseID,
		&contractVersion,
		&revision,
		&schemaCount,
		&unexpectedPublicRelationCount,
	); err != nil {
		return "", "", fmt.Errorf("read PostgreSQL backup owner identity: %w", err)
	}
	if contractVersion != guestruntimedomain.SchemaVersion ||
		!guestruntimedomain.ValidIdentifier(databaseID) {
		return "", "", &Rejection{
			Code:    "postgresql-backup-owner-identity-invalid",
			Message: "PostgreSQL backup owner identity is invalid",
		}
	}
	if revision != owner.configuration.ExpectedAlembicRevision {
		return "", "", &Rejection{
			Code: "postgresql-backup-revision-mismatch",
			Message: fmt.Sprintf(
				"expected=%s actual=%s",
				owner.configuration.ExpectedAlembicRevision,
				revision,
			),
		}
	}
	if schemaCount != len(guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas) {
		return "", "", &Rejection{
			Code:    "postgresql-backup-owner-schema-missing",
			Message: "one or more PostgreSQL backup owner schemas are missing",
		}
	}
	if unexpectedPublicRelationCount != 0 {
		return "", "", &Rejection{
			Code:    "postgresql-backup-public-owner-conflict",
			Message: "public schema contains relations not owned by the Alembic revision contract",
		}
	}
	return databaseID, revision, nil
}

func (owner *Owner) inspectSnapshot(
	ctx context.Context,
	path string,
	databaseID string,
	revision string,
) (Snapshot, error) {
	list, err := owner.runCommand(
		ctx,
		owner.configuration.PGRestoreExecutablePath,
		[]string{"--list", path},
	)
	if err != nil {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-proof-failed",
			Message: "pg_restore could not read the logical snapshot",
			Cause:   err,
		}
	}
	for _, schema := range guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas {
		if !strings.Contains(list, schema) {
			return Snapshot{}, &Rejection{
				Code:    "postgresql-snapshot-owner-schema-missing",
				Message: "PostgreSQL snapshot omitted " + schema,
			}
		}
	}
	if !strings.Contains(list, "alembic_version") {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-revision-proof-missing",
			Message: "PostgreSQL snapshot omitted public.alembic_version",
		}
	}
	file, err := os.Open(path)
	if err != nil {
		return Snapshot{}, fmt.Errorf("open PostgreSQL logical snapshot: %w", err)
	}
	defer file.Close()
	digest := sha256.New()
	byteSize, err := io.Copy(digest, file)
	if err != nil {
		return Snapshot{}, fmt.Errorf("digest PostgreSQL logical snapshot: %w", err)
	}
	if byteSize < 1 {
		return Snapshot{}, &Rejection{
			Code:    "postgresql-snapshot-empty",
			Message: "PostgreSQL logical snapshot is empty",
		}
	}
	return Snapshot{
		DatabaseID:           databaseID,
		AlembicRevision:      revision,
		IncludedOwnerSchemas: append([]string{}, guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...),
		ByteSize:             byteSize,
		SHA256:               hex.EncodeToString(digest.Sum(nil)),
	}, nil
}

func (owner *Owner) runCommand(
	ctx context.Context,
	executable string,
	arguments []string,
) (string, error) {
	output := &boundedCommandOutput{maximumBytes: postgreSQLCommandOutputLimit}
	command := exec.CommandContext(ctx, executable, arguments...)
	command.Env = append([]string{}, owner.commandEnvironment...)
	command.Stdout = output
	command.Stderr = output
	if err := command.Run(); err != nil {
		return output.String(), fmt.Errorf(
			"%s failed: %w: %s",
			filepath.Base(executable),
			err,
			output.String(),
		)
	}
	if output.exceeded {
		return output.String(), fmt.Errorf(
			"%s output exceeded %d bytes",
			filepath.Base(executable),
			postgreSQLCommandOutputLimit,
		)
	}
	return output.String(), nil
}

type boundedCommandOutput struct {
	buffer       bytes.Buffer
	maximumBytes int
	exceeded     bool
}

func (output *boundedCommandOutput) Write(contents []byte) (int, error) {
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

func (output *boundedCommandOutput) String() string {
	value := strings.TrimSpace(output.buffer.String())
	if output.exceeded {
		return value + " [output truncated]"
	}
	return value
}
