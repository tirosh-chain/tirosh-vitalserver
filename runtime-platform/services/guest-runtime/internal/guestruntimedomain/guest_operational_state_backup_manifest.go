package guestruntimedomain

import "fmt"

var GuestOperationalStatePostgreSQLOwnerSchemas = []string{
	"recorder_catalog",
	"archive_export",
	"recorder_assignment",
	"guest_operational_state",
}

type GuestOperationalStateBackupSnapshotArtifact struct {
	Reference ResourceReference `json:"reference"`
	ByteSize  int64             `json:"byteSize"`
	SHA256    string            `json:"sha256"`
}

type GuestOperationalStateSQLiteSnapshotReceipt struct {
	DatabaseID    string                                      `json:"databaseId"`
	SchemaVersion int                                         `json:"schemaVersion"`
	Snapshot      GuestOperationalStateBackupSnapshotArtifact `json:"snapshot"`
}

type GuestOperationalStatePostgreSQLSnapshotReceipt struct {
	DatabaseID           string                                      `json:"databaseId"`
	AlembicRevision      string                                      `json:"alembicRevision"`
	IncludedOwnerSchemas []string                                    `json:"includedOwnerSchemas"`
	Snapshot             GuestOperationalStateBackupSnapshotArtifact `json:"snapshot"`
}

type GuestOperationalStateArtifactInventoryReceipt struct {
	ArtifactCount int                                         `json:"artifactCount"`
	Inventory     GuestOperationalStateBackupSnapshotArtifact `json:"inventory"`
}

type GuestOperationalStateArtifactInventoryItem struct {
	ArtifactID        string            `json:"artifactId"`
	StorageReference  ResourceReference `json:"storageReference"`
	ByteSize          int64             `json:"byteSize"`
	SHA256            string            `json:"sha256"`
	FinalizationState string            `json:"finalizationState"`
}

type GuestOperationalStateArtifactInventory struct {
	SchemaVersion       string                                       `json:"schemaVersion"`
	OperationID         string                                       `json:"operationId"`
	Artifacts           []GuestOperationalStateArtifactInventoryItem `json:"artifacts"`
	ObjectBytesIncluded bool                                         `json:"objectBytesIncluded"`
	CreatedAt           string                                       `json:"createdAt"`
}

type GuestOperationalStateBackupManifest struct {
	SchemaVersion        string                                         `json:"schemaVersion"`
	ID                   string                                         `json:"id"`
	OperationID          string                                         `json:"operationId"`
	DestinationReference ResourceReference                              `json:"destinationReference"`
	SQLiteSnapshot       GuestOperationalStateSQLiteSnapshotReceipt     `json:"sqliteSnapshot"`
	PostgreSQLSnapshot   GuestOperationalStatePostgreSQLSnapshotReceipt `json:"postgresqlSnapshot"`
	ArtifactInventory    GuestOperationalStateArtifactInventoryReceipt  `json:"artifactInventory"`
	ObjectBytesIncluded  bool                                           `json:"objectBytesIncluded"`
	CreatedAt            string                                         `json:"createdAt"`
}

func ValidateGuestOperationalStateBackupManifest(
	manifest GuestOperationalStateBackupManifest,
) error {
	if manifest.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(manifest.ID) ||
		!ValidIdentifier(manifest.OperationID) ||
		!validResourceReference(manifest.DestinationReference) ||
		!validTimestamp(manifest.CreatedAt) ||
		manifest.ObjectBytesIncluded {
		return fmt.Errorf("Guest operational-state backup manifest identity is invalid")
	}
	if !ValidIdentifier(manifest.SQLiteSnapshot.DatabaseID) ||
		manifest.SQLiteSnapshot.SchemaVersion < 1 ||
		!validGuestOperationalStateBackupSnapshotArtifact(
			manifest.SQLiteSnapshot.Snapshot,
		) {
		return fmt.Errorf("Guest operational-state SQLite snapshot receipt is invalid")
	}
	if !ValidIdentifier(manifest.PostgreSQLSnapshot.DatabaseID) ||
		!ValidIdentifier(manifest.PostgreSQLSnapshot.AlembicRevision) ||
		!exactGuestOperationalStatePostgreSQLOwnerSchemas(
			manifest.PostgreSQLSnapshot.IncludedOwnerSchemas,
		) ||
		!validGuestOperationalStateBackupSnapshotArtifact(
			manifest.PostgreSQLSnapshot.Snapshot,
		) {
		return fmt.Errorf("Guest operational-state PostgreSQL snapshot receipt is invalid")
	}
	if manifest.ArtifactInventory.ArtifactCount < 0 ||
		!validGuestOperationalStateBackupSnapshotArtifact(
			manifest.ArtifactInventory.Inventory,
		) {
		return fmt.Errorf("Guest operational-state artifact inventory receipt is invalid")
	}
	return nil
}

func ValidateGuestOperationalStateArtifactInventory(
	inventory GuestOperationalStateArtifactInventory,
) error {
	if inventory.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(inventory.OperationID) ||
		inventory.Artifacts == nil ||
		inventory.ObjectBytesIncluded ||
		!validTimestamp(inventory.CreatedAt) {
		return fmt.Errorf("Guest operational-state artifact inventory identity is invalid")
	}
	previousArtifactID := ""
	for _, artifact := range inventory.Artifacts {
		if ValidateGuestOperationalStateArtifactInventoryItem(artifact) != nil ||
			(previousArtifactID != "" && artifact.ArtifactID <= previousArtifactID) {
			return fmt.Errorf("Guest operational-state artifact inventory item is invalid or unordered")
		}
		previousArtifactID = artifact.ArtifactID
	}
	return nil
}

func ValidateGuestOperationalStateArtifactInventoryItem(
	artifact GuestOperationalStateArtifactInventoryItem,
) error {
	if !ValidIdentifier(artifact.ArtifactID) ||
		!validResourceReference(artifact.StorageReference) ||
		artifact.ByteSize < 0 ||
		!validSHA256(artifact.SHA256) ||
		artifact.FinalizationState != "finalized" {
		return fmt.Errorf("Guest operational-state artifact inventory item is invalid")
	}
	return nil
}

func validGuestOperationalStateBackupSnapshotArtifact(
	artifact GuestOperationalStateBackupSnapshotArtifact,
) bool {
	return validResourceReference(artifact.Reference) &&
		artifact.ByteSize > 0 &&
		validSHA256(artifact.SHA256)
}

func exactGuestOperationalStatePostgreSQLOwnerSchemas(actual []string) bool {
	if len(actual) != len(GuestOperationalStatePostgreSQLOwnerSchemas) {
		return false
	}
	seen := make(map[string]struct{}, len(actual))
	for _, schema := range actual {
		if _, exists := seen[schema]; exists {
			return false
		}
		seen[schema] = struct{}{}
	}
	for _, expected := range GuestOperationalStatePostgreSQLOwnerSchemas {
		if _, exists := seen[expected]; !exists {
			return false
		}
	}
	return true
}
