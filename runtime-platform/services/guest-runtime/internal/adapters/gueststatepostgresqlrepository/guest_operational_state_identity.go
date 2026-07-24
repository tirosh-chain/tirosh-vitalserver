package gueststatepostgresqlrepository

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func (repository *RecorderCatalogPostgreSQLRepository) ReadGuestOperationalStatePostgreSQLIdentity(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLIdentity, error) {
	if repository == nil || repository.database == nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf("Recorder Catalog PostgreSQL repository is not open")
	}
	var identity guestruntimedomain.GuestOperationalStatePostgreSQLIdentity
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT metadata.database_id, version.version_num
		   FROM guest_operational_state.metadata AS metadata
		  CROSS JOIN public.alembic_version AS version
		  WHERE metadata.singleton = true`,
	).Scan(&identity.DatabaseID, &identity.AlembicRevision); err != nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf("read Guest operational-state PostgreSQL identity: %w", err)
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT schema_name
		   FROM information_schema.schemata
		  WHERE schema_name IN (
		        'recorder_catalog',
		        'archive_export',
		        'recorder_assignment',
		        'guest_operational_state'
		  )
		  ORDER BY schema_name`,
	)
	if err != nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf("read Guest operational-state PostgreSQL owner schemas: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var schema string
		if err := rows.Scan(&schema); err != nil {
			return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
				fmt.Errorf("scan Guest operational-state PostgreSQL owner schema: %w", err)
		}
		identity.OwnerSchemas = append(identity.OwnerSchemas, schema)
	}
	if err := rows.Err(); err != nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf("iterate Guest operational-state PostgreSQL owner schemas: %w", err)
	}
	if identity.AlembicRevision != ExpectedRecorderCatalogRevision {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf(
				"Guest operational-state PostgreSQL Alembic revision mismatch: expected=%s actual=%s",
				ExpectedRecorderCatalogRevision,
				identity.AlembicRevision,
			)
	}
	if err := guestruntimedomain.ValidateGuestOperationalStatePostgreSQLIdentity(
		identity,
	); err != nil {
		return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{},
			fmt.Errorf("validate Guest operational-state PostgreSQL identity: %w", err)
	}
	return identity, nil
}
