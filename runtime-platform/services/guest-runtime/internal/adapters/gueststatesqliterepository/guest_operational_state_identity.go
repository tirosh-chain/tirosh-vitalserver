package gueststatesqliterepository

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (repository *GuestRuntimeStateSQLiteRepository) ReadGuestOperationalStateSQLiteIdentity(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStateSQLiteIdentity, error) {
	if repository == nil || repository.database == nil {
		return guestruntimedomain.GuestOperationalStateSQLiteIdentity{},
			fmt.Errorf("Guest Runtime state repository is not open")
	}
	var identity guestruntimedomain.GuestOperationalStateSQLiteIdentity
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT database_id, schema_version
		   FROM state_store_metadata
		  WHERE singleton = 1`,
	).Scan(&identity.DatabaseID, &identity.SchemaVersion); err != nil {
		return guestruntimedomain.GuestOperationalStateSQLiteIdentity{},
			fmt.Errorf("read Guest Runtime SQLite identity: %w", err)
	}
	if !guestruntimedomain.ValidIdentifier(identity.DatabaseID) ||
		identity.SchemaVersion != guestRuntimeStateSQLiteSchemaVersion {
		return guestruntimedomain.GuestOperationalStateSQLiteIdentity{},
			fmt.Errorf("Guest Runtime SQLite identity is invalid")
	}
	return identity, nil
}
