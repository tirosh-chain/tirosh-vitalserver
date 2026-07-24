package guestruntimeapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type operationalStateSQLiteIdentityReaderStub struct {
	value guestruntimedomain.GuestOperationalStateSQLiteIdentity
	err   error
}

func (stub operationalStateSQLiteIdentityReaderStub) ReadGuestOperationalStateSQLiteIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStateSQLiteIdentity, error) {
	return stub.value, stub.err
}

type operationalStatePostgreSQLIdentityReaderStub struct {
	value guestruntimedomain.GuestOperationalStatePostgreSQLIdentity
	err   error
}

func (stub operationalStatePostgreSQLIdentityReaderStub) ReadGuestOperationalStatePostgreSQLIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLIdentity, error) {
	return stub.value, stub.err
}

type operationalStateBootstrapIdentityReaderStub struct {
	value guestruntimedomain.GuestOperationalStateBootstrapIdentity
	err   error
}

func (stub operationalStateBootstrapIdentityReaderStub) ReadGuestOperationalStateBootstrapIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStateBootstrapIdentity, error) {
	return stub.value, stub.err
}

type operationalStateIdentityClockStub struct{ now time.Time }

func (stub operationalStateIdentityClockStub) Now() time.Time { return stub.now }

func validOperationalStateBootstrapIdentity() guestruntimedomain.GuestOperationalStateBootstrapIdentity {
	return guestruntimedomain.GuestOperationalStateBootstrapIdentity{
		MigrationReceipt: guestruntimedomain.GuestOperationalStateMigrationReceipt{
			SchemaVersion: "v1",
			State:         "succeeded",
			Revision:      "0006_backup_owner",
			StartedAt:     "2026-07-24T22:59:00Z",
			FinishedAt:    "2026-07-24T22:59:05Z",
		},
		PrivateMaterialSet: guestruntimedomain.GuestOperationalStatePrivateMaterialSetIdentity{
			MaterialCount: 3,
			SHA256:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}
}

func TestGuestOperationalStateIdentityReadIsAtomicAndOwnerProvided(t *testing.T) {
	service, err := NewGuestOperationalStateIdentityApplicationService(
		operationalStateSQLiteIdentityReaderStub{
			value: guestruntimedomain.GuestOperationalStateSQLiteIdentity{
				DatabaseID: "guest-runtime-ledger-1", SchemaVersion: 1,
			},
		},
		operationalStatePostgreSQLIdentityReaderStub{
			value: guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{
				DatabaseID:      "guest-postgresql-00000000-0000-0000-0000-000000000001",
				AlembicRevision: "0006_backup_owner",
				OwnerSchemas: append(
					[]string(nil),
					guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
				),
			},
		},
		operationalStateBootstrapIdentityReaderStub{
			value: validOperationalStateBootstrapIdentity(),
		},
		operationalStateIdentityClockStub{
			now: time.Date(2026, 7, 24, 23, 0, 0, 0, time.UTC),
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	result := service.Read(context.Background())
	if result.State != "available" {
		t.Fatalf("result=%+v", result)
	}
	identity, ok := result.Value.(guestruntimedomain.GuestOperationalStateIdentity)
	if !ok || identity.SQLite.DatabaseID != "guest-runtime-ledger-1" ||
		identity.PostgreSQL.AlembicRevision != "0006_backup_owner" {
		t.Fatalf("identity=%+v", result.Value)
	}
}

func TestGuestOperationalStateIdentityReadDoesNotReturnPartialState(t *testing.T) {
	service, err := NewGuestOperationalStateIdentityApplicationService(
		operationalStateSQLiteIdentityReaderStub{
			value: guestruntimedomain.GuestOperationalStateSQLiteIdentity{
				DatabaseID: "guest-runtime-ledger-1", SchemaVersion: 1,
			},
		},
		operationalStatePostgreSQLIdentityReaderStub{
			err: errors.New("PostgreSQL owner unavailable"),
		},
		operationalStateBootstrapIdentityReaderStub{
			value: validOperationalStateBootstrapIdentity(),
		},
		operationalStateIdentityClockStub{now: time.Now()},
	)
	if err != nil {
		t.Fatal(err)
	}
	result := service.Read(context.Background())
	if result.State != "failed" || result.Value != nil ||
		result.Issue == nil ||
		result.Issue.Code != "guest-operational-state-postgresql-identity-read-failed" {
		t.Fatalf("result=%+v", result)
	}
}

func TestGuestOperationalStateIdentityReadDoesNotHideBootstrapEvidenceFailure(t *testing.T) {
	service, err := NewGuestOperationalStateIdentityApplicationService(
		operationalStateSQLiteIdentityReaderStub{
			value: guestruntimedomain.GuestOperationalStateSQLiteIdentity{
				DatabaseID: "guest-runtime-ledger-1", SchemaVersion: 1,
			},
		},
		operationalStatePostgreSQLIdentityReaderStub{
			value: guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{
				DatabaseID:      "guest-postgresql-00000000-0000-0000-0000-000000000001",
				AlembicRevision: "0006_backup_owner",
				OwnerSchemas: append(
					[]string(nil),
					guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
				),
			},
		},
		operationalStateBootstrapIdentityReaderStub{
			err: errors.New("migration receipt unavailable"),
		},
		operationalStateIdentityClockStub{now: time.Now()},
	)
	if err != nil {
		t.Fatal(err)
	}
	result := service.Read(context.Background())
	if result.State != "failed" || result.Value != nil ||
		result.Issue == nil ||
		result.Issue.Code != "guest-operational-state-bootstrap-identity-read-failed" {
		t.Fatalf("result=%+v", result)
	}
}
