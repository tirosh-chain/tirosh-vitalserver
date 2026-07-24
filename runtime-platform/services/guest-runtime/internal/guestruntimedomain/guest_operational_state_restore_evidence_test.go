package guestruntimedomain

import "testing"

func TestEmptyRestoreTargetProofPreservesAbsentAndEmptyOwnerMeanings(t *testing.T) {
	proof := GuestOperationalStateEmptyTargetProof{
		SchemaVersion: SchemaVersion,
		OperationID:   "restore-operation-1",
		TargetReference: ResourceReference{
			ResourceType: "guest-restore-target",
			ResourceID:   "empty-target-1",
		},
		SQLiteTarget: GuestOperationalStateSQLiteEmptyTargetProof{
			State: GuestOperationalStateSQLiteRestoreTargetAbsent,
		},
		PostgreSQLTarget: GuestOperationalStatePostgreSQLEmptyTargetProof{
			State:                      GuestOperationalStatePostgreSQLRestoreTargetEmpty,
			OwnerSchemaCount:           0,
			AlembicVersionTablePresent: false,
		},
		ProvedAt: "2026-07-24T20:00:00Z",
	}
	if err := ValidateGuestOperationalStateEmptyTargetProof(proof); err != nil {
		t.Fatal(err)
	}
	proof.PostgreSQLTarget.OwnerSchemaCount = 1
	if err := ValidateGuestOperationalStateEmptyTargetProof(proof); err == nil {
		t.Fatal("target with an existing owner schema must not be accepted as empty")
	}
}
