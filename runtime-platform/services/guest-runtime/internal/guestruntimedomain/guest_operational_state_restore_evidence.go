package guestruntimedomain

import "fmt"

const (
	GuestOperationalStateSQLiteRestoreTargetAbsent    = "absent"
	GuestOperationalStatePostgreSQLRestoreTargetEmpty = "empty"
)

type GuestOperationalStateSQLiteEmptyTargetProof struct {
	State string `json:"state"`
}

type GuestOperationalStatePostgreSQLEmptyTargetProof struct {
	State                      string `json:"state"`
	OwnerSchemaCount           int    `json:"ownerSchemaCount"`
	AlembicVersionTablePresent bool   `json:"alembicVersionTablePresent"`
}

type GuestOperationalStateEmptyTargetProof struct {
	SchemaVersion    string                                          `json:"schemaVersion"`
	OperationID      string                                          `json:"operationId"`
	TargetReference  ResourceReference                               `json:"targetReference"`
	SQLiteTarget     GuestOperationalStateSQLiteEmptyTargetProof     `json:"sqliteTarget"`
	PostgreSQLTarget GuestOperationalStatePostgreSQLEmptyTargetProof `json:"postgresqlTarget"`
	ProvedAt         string                                          `json:"provedAt"`
}

type GuestOperationalStateSQLiteOwnerReadProof struct {
	LedgerIdentityReadSucceeded bool `json:"ledgerIdentityReadSucceeded"`
}

type GuestOperationalStatePostgreSQLOwnerReadProof struct {
	IdentityReadSucceeded                   bool `json:"identityReadSucceeded"`
	RecorderCurrentProjectionReadSucceeded  bool `json:"recorderCurrentProjectionReadSucceeded"`
	RecorderExpectationReadSucceeded        bool `json:"recorderExpectationReadSucceeded"`
	RecorderObservationHistoryReadSucceeded bool `json:"recorderObservationHistoryReadSucceeded"`
	ArchiveArtifactAttributionReadSucceeded bool `json:"archiveArtifactAttributionReadSucceeded"`
	ArchiveUploadIndexReceiptsReadSucceeded bool `json:"archiveUploadIndexReceiptsReadSucceeded"`
	RecorderAssignmentEvidenceReadSucceeded bool `json:"recorderAssignmentEvidenceReadSucceeded"`
}

type GuestOperationalStateRestoreOwnerReadProof struct {
	SchemaVersion    string                                        `json:"schemaVersion"`
	OperationID      string                                        `json:"operationId"`
	TargetReference  ResourceReference                             `json:"targetReference"`
	SQLiteOwner      GuestOperationalStateSQLiteOwnerReadProof     `json:"sqliteOwner"`
	PostgreSQLOwners GuestOperationalStatePostgreSQLOwnerReadProof `json:"postgresqlOwners"`
	VerifiedAt       string                                        `json:"verifiedAt"`
}

func ValidateGuestOperationalStateEmptyTargetProof(
	proof GuestOperationalStateEmptyTargetProof,
) error {
	if proof.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(proof.OperationID) ||
		!validResourceReference(proof.TargetReference) ||
		proof.SQLiteTarget.State != GuestOperationalStateSQLiteRestoreTargetAbsent ||
		proof.PostgreSQLTarget.State != GuestOperationalStatePostgreSQLRestoreTargetEmpty ||
		proof.PostgreSQLTarget.OwnerSchemaCount != 0 ||
		proof.PostgreSQLTarget.AlembicVersionTablePresent ||
		!validTimestamp(proof.ProvedAt) {
		return fmt.Errorf("Guest operational-state empty restore target proof is invalid")
	}
	return nil
}

func ValidateGuestOperationalStateRestoreOwnerReadProof(
	proof GuestOperationalStateRestoreOwnerReadProof,
) error {
	if proof.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(proof.OperationID) ||
		!validResourceReference(proof.TargetReference) ||
		!proof.SQLiteOwner.LedgerIdentityReadSucceeded ||
		!proof.PostgreSQLOwners.IdentityReadSucceeded ||
		!proof.PostgreSQLOwners.RecorderCurrentProjectionReadSucceeded ||
		!proof.PostgreSQLOwners.RecorderExpectationReadSucceeded ||
		!proof.PostgreSQLOwners.RecorderObservationHistoryReadSucceeded ||
		!proof.PostgreSQLOwners.ArchiveArtifactAttributionReadSucceeded ||
		!proof.PostgreSQLOwners.ArchiveUploadIndexReceiptsReadSucceeded ||
		!proof.PostgreSQLOwners.RecorderAssignmentEvidenceReadSucceeded ||
		!validTimestamp(proof.VerifiedAt) {
		return fmt.Errorf("Guest operational-state restored owner read proof is incomplete")
	}
	return nil
}
