package guestruntimedomain

import "fmt"

const GuestOperationalStateIdentitySchemaVersion = "v1"
const GuestOperationalStatePostgreSQLAlembicRevision = "0006_backup_owner"

// GuestOperationalStateSQLiteIdentity is the SQLite control-ledger identity
// read by its owner. Consumers must not derive either field from a path,
// filename, or table probe.
type GuestOperationalStateSQLiteIdentity struct {
	DatabaseID    string `json:"databaseId"`
	SchemaVersion int    `json:"schemaVersion"`
}

// GuestOperationalStatePostgreSQLIdentity is the accumulated-state identity
// read by its PostgreSQL owner. OwnerSchemas is the complete migration-owned
// set, not a best-effort discovery result.
type GuestOperationalStatePostgreSQLIdentity struct {
	DatabaseID      string   `json:"databaseId"`
	AlembicRevision string   `json:"alembicRevision"`
	OwnerSchemas    []string `json:"ownerSchemas"`
}

// GuestOperationalStateMigrationReceipt is the persisted first-boot
// migration result emitted by the migration owner. It is evidence of that
// explicit effect, not a revision inferred from the current database.
type GuestOperationalStateMigrationReceipt struct {
	SchemaVersion string `json:"schemaVersion"`
	State         string `json:"state"`
	Revision      string `json:"revision"`
	StartedAt     string `json:"startedAt"`
	FinishedAt    string `json:"finishedAt"`
}

// GuestOperationalStatePrivateMaterialSetIdentity is one non-secret digest
// over the complete ordered private-material set. Individual material values
// and individual digests are deliberately not exposed.
type GuestOperationalStatePrivateMaterialSetIdentity struct {
	MaterialCount int    `json:"materialCount"`
	SHA256        string `json:"sha256"`
}

// GuestOperationalStateBootstrapIdentity is read by the Guest bootstrap
// evidence owner from the explicit C37 material and receipt paths.
type GuestOperationalStateBootstrapIdentity struct {
	MigrationReceipt   GuestOperationalStateMigrationReceipt           `json:"migrationReceipt"`
	PrivateMaterialSet GuestOperationalStatePrivateMaterialSetIdentity `json:"privateMaterialSet"`
}

// GuestOperationalStateIdentity is one atomic public observation used by
// installation and reboot acceptance. Partial identity is never available.
type GuestOperationalStateIdentity struct {
	SchemaVersion string                                  `json:"schemaVersion"`
	SQLite        GuestOperationalStateSQLiteIdentity     `json:"sqlite"`
	PostgreSQL    GuestOperationalStatePostgreSQLIdentity `json:"postgresql"`
	Bootstrap     GuestOperationalStateBootstrapIdentity  `json:"bootstrap"`
	ObservedAt    string                                  `json:"observedAt"`
}

func ValidateGuestOperationalStateIdentity(identity GuestOperationalStateIdentity) error {
	if identity.SchemaVersion != GuestOperationalStateIdentitySchemaVersion {
		return fmt.Errorf("Guest operational-state identity schemaVersion must be v1")
	}
	if !ValidIdentifier(identity.SQLite.DatabaseID) ||
		identity.SQLite.SchemaVersion < 1 {
		return fmt.Errorf("Guest operational-state SQLite identity is invalid")
	}
	if err := ValidateGuestOperationalStatePostgreSQLIdentity(
		identity.PostgreSQL,
	); err != nil {
		return err
	}
	if err := ValidateGuestOperationalStateBootstrapIdentity(
		identity.Bootstrap,
		identity.PostgreSQL.AlembicRevision,
	); err != nil {
		return err
	}
	if !validTimestamp(identity.ObservedAt) {
		return fmt.Errorf("Guest operational-state identity observedAt is required")
	}
	return nil
}

func ValidateGuestOperationalStatePostgreSQLIdentity(
	identity GuestOperationalStatePostgreSQLIdentity,
) error {
	if !ValidIdentifier(identity.DatabaseID) ||
		identity.AlembicRevision !=
			GuestOperationalStatePostgreSQLAlembicRevision ||
		!exactGuestOperationalStatePostgreSQLOwnerSchemas(identity.OwnerSchemas) {
		return fmt.Errorf("Guest operational-state PostgreSQL identity is invalid")
	}
	return nil
}

func ValidateGuestOperationalStateBootstrapIdentity(
	identity GuestOperationalStateBootstrapIdentity,
	postgresqlRevision string,
) error {
	receipt := identity.MigrationReceipt
	if receipt.SchemaVersion != GuestOperationalStateIdentitySchemaVersion ||
		receipt.State != "succeeded" ||
		receipt.Revision == "" ||
		receipt.Revision != postgresqlRevision ||
		!validTimestamp(receipt.StartedAt) ||
		!validTimestamp(receipt.FinishedAt) {
		return fmt.Errorf("Guest operational-state migration receipt is invalid")
	}
	if identity.PrivateMaterialSet.MaterialCount != 3 ||
		!validSHA256(identity.PrivateMaterialSet.SHA256) {
		return fmt.Errorf("Guest operational-state private material set identity is invalid")
	}
	return nil
}
