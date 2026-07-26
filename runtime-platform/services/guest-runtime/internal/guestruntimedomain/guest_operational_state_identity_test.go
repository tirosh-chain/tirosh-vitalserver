package guestruntimedomain

import "testing"

func TestValidateGuestOperationalStateIdentityRequiresBothOwnerIdentities(t *testing.T) {
	valid := GuestOperationalStateIdentity{
		SchemaVersion: GuestOperationalStateIdentitySchemaVersion,
		SQLite: GuestOperationalStateSQLiteIdentity{
			DatabaseID:    "guest-runtime-ledger-1",
			SchemaVersion: 1,
		},
		PostgreSQL: GuestOperationalStatePostgreSQLIdentity{
			DatabaseID:      "guest-postgresql-00000000-0000-0000-0000-000000000001",
			AlembicRevision: "0006_backup_owner",
			OwnerSchemas: append(
				[]string(nil),
				GuestOperationalStatePostgreSQLOwnerSchemas...,
			),
		},
		Bootstrap: GuestOperationalStateBootstrapIdentity{
			MigrationReceipt: GuestOperationalStateMigrationReceipt{
				SchemaVersion: "v1",
				State:         "succeeded",
				Revision:      "0006_backup_owner",
				StartedAt:     "2026-07-24T22:59:00Z",
				FinishedAt:    "2026-07-24T22:59:05Z",
			},
			PrivateMaterialSet: GuestOperationalStatePrivateMaterialSetIdentity{
				MaterialCount: 3,
				SHA256:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			},
		},
		ObservedAt: "2026-07-24T23:00:00Z",
	}
	if err := ValidateGuestOperationalStateIdentity(valid); err != nil {
		t.Fatal(err)
	}
	invalid := valid
	invalid.PostgreSQL.OwnerSchemas = []string{"recorder_catalog"}
	if err := ValidateGuestOperationalStateIdentity(invalid); err == nil {
		t.Fatal("partial PostgreSQL owner schema set must be rejected")
	}
	invalid = valid
	invalid.PostgreSQL.AlembicRevision = "0005_recorder_assignment_owner"
	if err := ValidateGuestOperationalStateIdentity(invalid); err == nil {
		t.Fatal("stale PostgreSQL migration revision must be rejected")
	}
	invalid = valid
	invalid.Bootstrap.MigrationReceipt.Revision =
		"0005_recorder_assignment_owner"
	if err := ValidateGuestOperationalStateIdentity(invalid); err == nil {
		t.Fatal("migration receipt and PostgreSQL revision mismatch must be rejected")
	}
	invalid = valid
	invalid.Bootstrap.PrivateMaterialSet.MaterialCount = 2
	if err := ValidateGuestOperationalStateIdentity(invalid); err == nil {
		t.Fatal("partial private material set must be rejected")
	}
}
