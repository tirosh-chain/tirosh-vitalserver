// Package gueststatepostgresqlmigration owns the external Alembic effect used
// to advance the Guest-owned Recorder Catalog PostgreSQL schema.
package gueststatepostgresqlmigration

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/migrations"
)

const migrationOutputMaximumBytes = 64 * 1024

type RecorderCatalogMigrationReceipt struct {
	SchemaVersion string `json:"schemaVersion"`
	State         string `json:"state"`
	Revision      string `json:"revision"`
	StartedAt     string `json:"startedAt"`
	FinishedAt    string `json:"finishedAt"`
}

type RecorderCatalogMigrationConfiguration struct {
	PythonExecutablePath string
	DatabaseURL          string
}

// ApplyRecorderCatalogMigrations materializes the embedded canonical Alembic
// tree, runs exactly `upgrade head`, and reads the resulting owner revision.
// Process success without the expected revision is a migration failure.
func ApplyRecorderCatalogMigrations(
	ctx context.Context,
	configuration RecorderCatalogMigrationConfiguration,
) (RecorderCatalogMigrationReceipt, error) {
	if ctx == nil ||
		configuration.PythonExecutablePath == "" ||
		!filepath.IsAbs(configuration.PythonExecutablePath) ||
		configuration.DatabaseURL == "" ||
		strings.TrimSpace(configuration.DatabaseURL) != configuration.DatabaseURL {
		return RecorderCatalogMigrationReceipt{},
			fmt.Errorf("Recorder Catalog migration configuration is incomplete")
	}
	startedAt := time.Now().UTC()
	migrationDirectory, err := os.MkdirTemp("", "vitalserver-recorder-catalog-migrations-")
	if err != nil {
		return RecorderCatalogMigrationReceipt{},
			fmt.Errorf("create private Recorder Catalog migration workspace: %w", err)
	}
	defer os.RemoveAll(migrationDirectory)
	if err := os.Chmod(migrationDirectory, 0o700); err != nil {
		return RecorderCatalogMigrationReceipt{},
			fmt.Errorf("secure Recorder Catalog migration workspace: %w", err)
	}
	if err := migrations.Materialize(migrationDirectory); err != nil {
		return RecorderCatalogMigrationReceipt{}, err
	}
	output := &boundedCommandOutput{maximumBytes: migrationOutputMaximumBytes}
	command := exec.CommandContext(
		ctx,
		configuration.PythonExecutablePath,
		"-m",
		"alembic",
		"-c",
		filepath.Join(migrationDirectory, "alembic.ini"),
		"upgrade",
		"head",
	)
	command.Dir = migrationDirectory
	command.Env = append(
		os.Environ(),
		"VITALSERVER_RECORDER_CATALOG_DATABASE_URL="+configuration.DatabaseURL,
	)
	command.Stdout = output
	command.Stderr = output
	if err := command.Run(); err != nil {
		return RecorderCatalogMigrationReceipt{},
			fmt.Errorf("Recorder Catalog Alembic upgrade failed: %w: %s", err, output.String())
	}
	revision, err := readRecorderCatalogRevision(ctx, configuration.DatabaseURL)
	if err != nil {
		return RecorderCatalogMigrationReceipt{}, err
	}
	if revision != gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision {
		return RecorderCatalogMigrationReceipt{}, fmt.Errorf(
			"Recorder Catalog migration revision mismatch: expected=%s actual=%s",
			gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision,
			revision,
		)
	}
	return RecorderCatalogMigrationReceipt{
		SchemaVersion: "v1",
		State:         "succeeded",
		Revision:      revision,
		StartedAt:     startedAt.Format(time.RFC3339Nano),
		FinishedAt:    time.Now().UTC().Format(time.RFC3339Nano),
	}, nil
}

func readRecorderCatalogRevision(ctx context.Context, databaseURL string) (string, error) {
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return "", fmt.Errorf("open migrated Recorder Catalog PostgreSQL database: %w", err)
	}
	defer database.Close()
	var revision string
	if err := database.QueryRowContext(
		ctx,
		`SELECT version_num FROM public.alembic_version`,
	).Scan(&revision); err != nil {
		return "", fmt.Errorf("read migrated Recorder Catalog revision: %w", err)
	}
	return revision, nil
}

type boundedCommandOutput struct {
	buffer       bytes.Buffer
	maximumBytes int
	truncated    bool
}

func (output *boundedCommandOutput) Write(contents []byte) (int, error) {
	originalLength := len(contents)
	remaining := output.maximumBytes - output.buffer.Len()
	if remaining > 0 {
		if len(contents) > remaining {
			contents = contents[:remaining]
			output.truncated = true
		}
		_, _ = output.buffer.Write(contents)
	} else {
		output.truncated = true
	}
	return originalLength, nil
}

func (output *boundedCommandOutput) String() string {
	contents := strings.TrimSpace(output.buffer.String())
	if output.truncated {
		return contents + " [output truncated]"
	}
	return contents
}
