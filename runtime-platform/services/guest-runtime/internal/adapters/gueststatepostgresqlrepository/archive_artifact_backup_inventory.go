package gueststatepostgresqlrepository

import (
	"context"
	"encoding/json"
	"fmt"
	"io"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// WriteGuestOperationalStateArtifactInventory streams Archive-owner metadata
// in stable artifact-id order. It deliberately does not read or copy raw
// artifact objects.
func (repository *ArchiveExportPostgreSQLRepository) WriteGuestOperationalStateArtifactInventory(
	ctx context.Context,
	operationID string,
	createdAt string,
	destination io.Writer,
) (int, error) {
	if repository == nil || repository.database == nil || destination == nil {
		return 0, fmt.Errorf("Archive artifact inventory owner is not open")
	}
	identity := guestruntimedomain.GuestOperationalStateArtifactInventory{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		OperationID:         operationID,
		Artifacts:           []guestruntimedomain.GuestOperationalStateArtifactInventoryItem{},
		ObjectBytesIncluded: false,
		CreatedAt:           createdAt,
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateArtifactInventory(identity); err != nil {
		return 0, err
	}
	encodedOperationID, _ := json.Marshal(operationID)
	if err := writeInventoryJSON(
		destination,
		`{"schemaVersion":"v1","operationId":`,
		string(encodedOperationID),
		`,"artifacts":[`,
	); err != nil {
		return 0, err
	}
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT artifact_id, byte_size, sha256,
		        finalization_state, manifest_document
		   FROM archive_export.artifacts
		  ORDER BY artifact_id`,
	)
	if err != nil {
		return 0, fmt.Errorf("read Archive artifact backup inventory: %w", err)
	}
	defer rows.Close()
	count := 0
	previousArtifactID := ""
	for rows.Next() {
		var item guestruntimedomain.GuestOperationalStateArtifactInventoryItem
		var manifestJSON []byte
		if err := rows.Scan(
			&item.ArtifactID,
			&item.ByteSize,
			&item.SHA256,
			&item.FinalizationState,
			&manifestJSON,
		); err != nil {
			return count, fmt.Errorf("scan Archive artifact backup inventory: %w", err)
		}
		var manifest guestruntimedomain.ArchiveLineageManifest
		if err := json.Unmarshal(manifestJSON, &manifest); err != nil {
			return count, fmt.Errorf(
				"decode Archive artifact %s backup inventory manifest: %w",
				item.ArtifactID,
				err,
			)
		}
		if manifest.Artifact.ArtifactID != item.ArtifactID ||
			manifest.Artifact.ByteSize != item.ByteSize ||
			manifest.Artifact.SHA256 != item.SHA256 {
			return count, fmt.Errorf(
				"Archive artifact %s inventory metadata disagrees with its manifest",
				item.ArtifactID,
			)
		}
		item.StorageReference = manifest.Artifact.StorageReference
		if err := guestruntimedomain.ValidateGuestOperationalStateArtifactInventoryItem(
			item,
		); err != nil {
			return count, fmt.Errorf(
				"validate Archive artifact %s backup inventory: %w",
				item.ArtifactID,
				err,
			)
		}
		if previousArtifactID != "" && item.ArtifactID <= previousArtifactID {
			return count, fmt.Errorf("Archive artifact backup inventory is unordered")
		}
		encoded, err := json.Marshal(item)
		if err != nil {
			return count, fmt.Errorf("encode Archive artifact backup inventory item: %w", err)
		}
		if count > 0 {
			if err := writeInventoryJSON(destination, ","); err != nil {
				return count, err
			}
		}
		if err := writeInventoryJSON(destination, string(encoded)); err != nil {
			return count, err
		}
		previousArtifactID = item.ArtifactID
		count++
	}
	if err := rows.Err(); err != nil {
		return count, fmt.Errorf("iterate Archive artifact backup inventory: %w", err)
	}
	encodedCreatedAt, _ := json.Marshal(createdAt)
	if err := writeInventoryJSON(
		destination,
		`],"objectBytesIncluded":false,"createdAt":`,
		string(encodedCreatedAt),
		"}",
	); err != nil {
		return count, err
	}
	return count, nil
}

func writeInventoryJSON(destination io.Writer, fragments ...string) error {
	for _, fragment := range fragments {
		if _, err := io.WriteString(destination, fragment); err != nil {
			return fmt.Errorf("write Archive artifact backup inventory: %w", err)
		}
	}
	return nil
}

var _ guestruntimeapplication.GuestOperationalStateArtifactInventoryOwner = (*ArchiveExportPostgreSQLRepository)(nil)
