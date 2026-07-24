package gueststatesqliterepository

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

type GuestRuntimeStateSQLiteSnapshot struct {
	DatabaseID    string
	SchemaVersion int
	ByteSize      int64
	SHA256        string
}

// CreateOnlineSnapshot asks the SQLite owner to create one transactionally
// consistent snapshot. The caller owns destination naming, but cannot infer
// database identity or schema version from a file name or table probe.
func (repository *GuestRuntimeStateSQLiteRepository) CreateOnlineSnapshot(
	ctx context.Context,
	destinationPath string,
) (GuestRuntimeStateSQLiteSnapshot, error) {
	if repository == nil || repository.database == nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime state repository is not open")
	}
	if !filepath.IsAbs(destinationPath) {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot path must be absolute")
	}
	parentInfo, err := os.Stat(filepath.Dir(destinationPath))
	if err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot parent is unreadable: %w", err)
	}
	if !parentInfo.IsDir() {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot parent is not a directory")
	}
	var sourceDatabaseID string
	var sourceSchemaVersion int
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT database_id, schema_version
		   FROM state_store_metadata
		  WHERE singleton = 1`,
	).Scan(&sourceDatabaseID, &sourceSchemaVersion); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("read Guest Runtime SQLite snapshot identity: %w", err)
	}
	if _, err := os.Stat(destinationPath); err == nil {
		return inspectGuestRuntimeStateSQLiteSnapshot(
			ctx,
			destinationPath,
			sourceDatabaseID,
			sourceSchemaVersion,
		)
	} else if !errors.Is(err, os.ErrNotExist) {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("inspect Guest Runtime SQLite snapshot destination: %w", err)
	}
	partialPath := destinationPath + ".partial"
	if _, err := os.Stat(partialPath); err == nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot has ambiguous partial output")
	} else if !errors.Is(err, os.ErrNotExist) {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("inspect Guest Runtime SQLite partial snapshot: %w", err)
	}
	if _, err := repository.database.ExecContext(
		ctx,
		`VACUUM INTO ?`,
		partialPath,
	); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("create Guest Runtime SQLite online snapshot: %w", err)
	}
	snapshot, err := inspectGuestRuntimeStateSQLiteSnapshot(
		ctx,
		partialPath,
		sourceDatabaseID,
		sourceSchemaVersion,
	)
	if err != nil {
		return GuestRuntimeStateSQLiteSnapshot{}, err
	}
	if err := os.Rename(partialPath, destinationPath); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("publish Guest Runtime SQLite snapshot: %w", err)
	}
	parent, err := os.Open(filepath.Dir(destinationPath))
	if err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("open Guest Runtime SQLite snapshot parent: %w", err)
	}
	defer parent.Close()
	if err := parent.Sync(); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("sync Guest Runtime SQLite snapshot parent: %w", err)
	}
	return snapshot, nil
}

func inspectGuestRuntimeStateSQLiteSnapshot(
	ctx context.Context,
	path string,
	expectedDatabaseID string,
	expectedSchemaVersion int,
) (GuestRuntimeStateSQLiteSnapshot, error) {
	snapshotDatabase, err := sql.Open("sqlite", path)
	if err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("open Guest Runtime SQLite snapshot proof: %w", err)
	}
	defer snapshotDatabase.Close()
	var integrity string
	if err := snapshotDatabase.QueryRowContext(
		ctx,
		`PRAGMA quick_check`,
	).Scan(&integrity); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("read Guest Runtime SQLite snapshot integrity proof: %w", err)
	}
	if integrity != "ok" {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot integrity proof failed")
	}
	snapshot := GuestRuntimeStateSQLiteSnapshot{}
	if err := snapshotDatabase.QueryRowContext(
		ctx,
		`SELECT database_id, schema_version
		   FROM state_store_metadata
		  WHERE singleton = 1`,
	).Scan(&snapshot.DatabaseID, &snapshot.SchemaVersion); err != nil {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("read Guest Runtime SQLite snapshot metadata proof: %w", err)
	}
	if snapshot.DatabaseID != expectedDatabaseID ||
		snapshot.SchemaVersion != expectedSchemaVersion {
		return GuestRuntimeStateSQLiteSnapshot{},
			fmt.Errorf("Guest Runtime SQLite snapshot metadata does not match source")
	}
	snapshot.ByteSize, snapshot.SHA256, err = syncAndDigestSnapshot(path)
	if err != nil {
		return GuestRuntimeStateSQLiteSnapshot{}, err
	}
	return snapshot, nil
}

func syncAndDigestSnapshot(path string) (int64, string, error) {
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return 0, "", fmt.Errorf("open Guest Runtime SQLite snapshot: %w", err)
	}
	defer file.Close()
	if err := file.Sync(); err != nil {
		return 0, "", fmt.Errorf("sync Guest Runtime SQLite snapshot: %w", err)
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return 0, "", fmt.Errorf("rewind Guest Runtime SQLite snapshot: %w", err)
	}
	digest := sha256.New()
	byteSize, err := io.Copy(digest, file)
	if err != nil {
		return 0, "", fmt.Errorf("digest Guest Runtime SQLite snapshot: %w", err)
	}
	if byteSize < 1 {
		return 0, "", fmt.Errorf("Guest Runtime SQLite snapshot is empty")
	}
	return byteSize, hex.EncodeToString(digest.Sum(nil)), nil
}
