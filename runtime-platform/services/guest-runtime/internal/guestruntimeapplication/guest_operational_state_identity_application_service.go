package guestruntimeapplication

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type GuestOperationalStateIdentityApplicationService struct {
	sqlite     GuestRuntimeSQLiteIdentityReader
	postgresql GuestRuntimePostgreSQLIdentityReader
	bootstrap  GuestRuntimeBootstrapIdentityReader
	clock      GuestRuntimeClock
}

func NewGuestOperationalStateIdentityApplicationService(
	sqlite GuestRuntimeSQLiteIdentityReader,
	postgresql GuestRuntimePostgreSQLIdentityReader,
	bootstrap GuestRuntimeBootstrapIdentityReader,
	clock GuestRuntimeClock,
) (*GuestOperationalStateIdentityApplicationService, error) {
	if sqlite == nil || postgresql == nil || bootstrap == nil || clock == nil {
		return nil, fmt.Errorf(
			"Guest operational-state SQLite, PostgreSQL, bootstrap identity readers, and clock are required",
		)
	}
	return &GuestOperationalStateIdentityApplicationService{
		sqlite: sqlite, postgresql: postgresql, bootstrap: bootstrap, clock: clock,
	}, nil
}

func (service *GuestOperationalStateIdentityApplicationService) Read(
	ctx context.Context,
) guestruntimedomain.ReadResult {
	observedAt := guestruntimedomain.Timestamp(service.clock.Now())
	sqliteIdentity, err := service.sqlite.ReadGuestOperationalStateSQLiteIdentity(ctx)
	if err != nil {
		return failedRead(
			observedAt,
			"guest-operational-state-sqlite-identity-read-failed",
			err.Error(),
			"guest-runtime-state-sqlite",
		)
	}
	postgresqlIdentity, err := service.postgresql.ReadGuestOperationalStatePostgreSQLIdentity(ctx)
	if err != nil {
		return failedRead(
			observedAt,
			"guest-operational-state-postgresql-identity-read-failed",
			err.Error(),
			"guest-operational-state-postgresql",
		)
	}
	bootstrapIdentity, err :=
		service.bootstrap.ReadGuestOperationalStateBootstrapIdentity(ctx)
	if err != nil {
		return failedRead(
			observedAt,
			"guest-operational-state-bootstrap-identity-read-failed",
			err.Error(),
			"guest-product-bootstrap",
		)
	}
	identity := guestruntimedomain.GuestOperationalStateIdentity{
		SchemaVersion: guestruntimedomain.GuestOperationalStateIdentitySchemaVersion,
		SQLite:        sqliteIdentity,
		PostgreSQL:    postgresqlIdentity,
		Bootstrap:     bootstrapIdentity,
		ObservedAt:    observedAt,
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateIdentity(identity); err != nil {
		return failedRead(
			observedAt,
			"guest-operational-state-identity-invariant-failed",
			err.Error(),
			"guest-operational-state",
		)
	}
	return guestruntimedomain.ReadResult{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		State:         "available",
		ObservedAt:    observedAt,
		Value:         identity,
	}
}
