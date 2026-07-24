// Package gueststatesqliterestore restores one explicitly validated Guest
// Runtime SQLite snapshot without merging into or overwriting existing state.
package gueststatesqliterestore

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

	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type Rejection struct {
	Code    string
	Message string
}

func (rejection *Rejection) Error() string {
	return rejection.Message
}

type Owner struct {
	targetPath string
}

func New(targetPath string) (*Owner, error) {
	if !filepath.IsAbs(targetPath) {
		return nil, fmt.Errorf("Guest Runtime SQLite restore target path must be absolute")
	}
	parent, err := os.Stat(filepath.Dir(targetPath))
	if err != nil {
		return nil, fmt.Errorf("Guest Runtime SQLite restore target parent is unreadable: %w", err)
	}
	if !parent.IsDir() {
		return nil, fmt.Errorf("Guest Runtime SQLite restore target parent is not a directory")
	}
	return &Owner{targetPath: targetPath}, nil
}

func (owner *Owner) ProveEmpty(
	_ context.Context,
) (guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof, error) {
	if owner == nil || owner.targetPath == "" {
		return guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof{},
			fmt.Errorf("Guest Runtime SQLite restore owner is not configured")
	}
	if _, err := os.Stat(owner.targetPath); errors.Is(err, os.ErrNotExist) {
		return guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof{
			State: guestruntimedomain.GuestOperationalStateSQLiteRestoreTargetAbsent,
		}, nil
	} else if err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof{},
			fmt.Errorf("probe Guest Runtime SQLite restore target: %w", err)
	}
	return guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof{},
		&Rejection{
			Code:    "sqlite-restore-target-not-empty",
			Message: "Guest Runtime SQLite restore target already exists",
		}
}

func (owner *Owner) Restore(
	ctx context.Context,
	sourcePath string,
	expected guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
) (guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt, error) {
	if !filepath.IsAbs(sourcePath) {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			&Rejection{
				Code:    "sqlite-restore-source-invalid",
				Message: "Guest Runtime SQLite restore source path must be absolute",
			}
	}
	if _, err := owner.ProveEmpty(ctx); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{}, err
	}
	if err := inspectSQLiteSnapshot(ctx, sourcePath, expected); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{}, err
	}
	partialPath := owner.targetPath + ".partial"
	if _, err := os.Stat(partialPath); err == nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			&Rejection{
				Code:    "sqlite-restore-partial-exists",
				Message: "Guest Runtime SQLite restore has ambiguous partial output",
			}
	} else if !errors.Is(err, os.ErrNotExist) {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("probe Guest Runtime SQLite restore partial: %w", err)
	}
	source, err := os.Open(sourcePath)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("open Guest Runtime SQLite restore source: %w", err)
	}
	defer source.Close()
	partial, err := os.OpenFile(
		partialPath,
		os.O_WRONLY|os.O_CREATE|os.O_EXCL,
		0o600,
	)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("create Guest Runtime SQLite restore partial: %w", err)
	}
	_, copyErr := io.Copy(partial, source)
	syncErr := partial.Sync()
	closeErr := partial.Close()
	if copyErr != nil || syncErr != nil || closeErr != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			errors.Join(copyErr, syncErr, closeErr)
	}
	if err := inspectSQLiteSnapshot(ctx, partialPath, expected); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{}, err
	}
	// Link is an atomic create-if-absent publication. Rename would overwrite a
	// target created after the empty-target proof.
	if err := os.Link(partialPath, owner.targetPath); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			&Rejection{
				Code:    "sqlite-restore-target-raced",
				Message: "Guest Runtime SQLite restore target appeared after empty-target proof",
			}
	}
	if err := os.Remove(partialPath); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("remove published Guest Runtime SQLite restore partial: %w", err)
	}
	parent, err := os.Open(filepath.Dir(owner.targetPath))
	if err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("open Guest Runtime SQLite restore target parent: %w", err)
	}
	defer parent.Close()
	if err := parent.Sync(); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{},
			fmt.Errorf("sync Guest Runtime SQLite restore target parent: %w", err)
	}
	return expected, nil
}

func (owner *Owner) Verify(
	ctx context.Context,
	expected guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
) (guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof, error) {
	if owner == nil || owner.targetPath == "" {
		return guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof{},
			fmt.Errorf("Guest Runtime SQLite restore owner is not configured")
	}
	if err := inspectSQLiteSnapshot(ctx, owner.targetPath, expected); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof{}, err
	}
	return guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof{
		LedgerIdentityReadSucceeded: true,
	}, nil
}

func inspectSQLiteSnapshot(
	ctx context.Context,
	path string,
	expected guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open Guest Runtime SQLite restore proof: %w", err)
	}
	digest := sha256.New()
	byteSize, copyErr := io.Copy(digest, file)
	closeErr := file.Close()
	if copyErr != nil || closeErr != nil {
		return errors.Join(copyErr, closeErr)
	}
	if byteSize != expected.Snapshot.ByteSize ||
		hex.EncodeToString(digest.Sum(nil)) != expected.Snapshot.SHA256 {
		return &Rejection{
			Code:    "sqlite-restore-source-digest-mismatch",
			Message: "Guest Runtime SQLite restore source bytes do not match manifest",
		}
	}
	database, err := sql.Open("sqlite", path+"?mode=ro")
	if err != nil {
		return fmt.Errorf("open Guest Runtime SQLite restore database proof: %w", err)
	}
	defer database.Close()
	var integrity string
	if err := database.QueryRowContext(ctx, `PRAGMA quick_check`).Scan(&integrity); err != nil {
		return fmt.Errorf("read Guest Runtime SQLite restore integrity proof: %w", err)
	}
	if integrity != "ok" {
		return &Rejection{
			Code:    "sqlite-restore-integrity-failed",
			Message: "Guest Runtime SQLite restore source failed integrity proof",
		}
	}
	var databaseID string
	var schemaVersion int
	if err := database.QueryRowContext(
		ctx,
		`SELECT database_id, schema_version
		   FROM state_store_metadata
		  WHERE singleton = 1`,
	).Scan(&databaseID, &schemaVersion); err != nil {
		return fmt.Errorf("read Guest Runtime SQLite restore identity proof: %w", err)
	}
	if databaseID != expected.DatabaseID ||
		schemaVersion != expected.SchemaVersion {
		return &Rejection{
			Code:    "sqlite-restore-identity-mismatch",
			Message: "Guest Runtime SQLite restore source identity does not match manifest",
		}
	}
	return nil
}
