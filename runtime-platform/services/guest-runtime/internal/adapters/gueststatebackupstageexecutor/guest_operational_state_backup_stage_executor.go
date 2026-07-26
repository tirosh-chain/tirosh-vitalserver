// Package gueststatebackupstageexecutor composes explicit C76 backup owner
// effects into the application stage-executor port.
package gueststatebackupstageexecutor

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlbackup"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type SQLiteSnapshotOwner interface {
	CreateOnlineSnapshot(
		context.Context,
		string,
	) (gueststatesqliterepository.GuestRuntimeStateSQLiteSnapshot, error)
}

type PostgreSQLSnapshotOwner interface {
	CreateLogicalSnapshot(
		context.Context,
		string,
	) (gueststatepostgresqlbackup.Snapshot, error)
}

type Configuration struct {
	RootDirectory        string
	DestinationReference guestruntimedomain.ResourceReference
}

type Executor struct {
	configuration      Configuration
	sqliteOwner        SQLiteSnapshotOwner
	postgresqlOwner    PostgreSQLSnapshotOwner
	inventoryOwner     guestruntimeapplication.GuestOperationalStateArtifactInventoryOwner
	clock              guestruntimeapplication.GuestRuntimeClock
	operationsRootPath string
	manifestsRootPath  string
}

func New(
	configuration Configuration,
	sqliteOwner SQLiteSnapshotOwner,
	postgresqlOwner PostgreSQLSnapshotOwner,
	inventoryOwner guestruntimeapplication.GuestOperationalStateArtifactInventoryOwner,
	clock guestruntimeapplication.GuestRuntimeClock,
) (*Executor, error) {
	if !filepath.IsAbs(configuration.RootDirectory) ||
		!validReference(configuration.DestinationReference) ||
		sqliteOwner == nil ||
		postgresqlOwner == nil ||
		inventoryOwner == nil ||
		clock == nil {
		return nil, fmt.Errorf("Guest operational-state backup stage executor configuration is incomplete")
	}
	info, err := os.Stat(configuration.RootDirectory)
	if err != nil {
		return nil, fmt.Errorf("Guest operational-state backup root is unreadable: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("Guest operational-state backup root is not a directory")
	}
	operationsRootPath := filepath.Join(configuration.RootDirectory, "operations")
	manifestsRootPath := filepath.Join(configuration.RootDirectory, "manifests")
	for _, path := range []string{operationsRootPath, manifestsRootPath} {
		if err := ensurePrivateDirectory(path); err != nil {
			return nil, err
		}
	}
	return &Executor{
		configuration:      configuration,
		sqliteOwner:        sqliteOwner,
		postgresqlOwner:    postgresqlOwner,
		inventoryOwner:     inventoryOwner,
		clock:              clock,
		operationsRootPath: operationsRootPath,
		manifestsRootPath:  manifestsRootPath,
	}, nil
}

func (executor *Executor) ExecuteStage(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	if operation.Kind != guestruntimedomain.GuestStateBackupKind ||
		operation.DestinationReference == nil ||
		*operation.DestinationReference != executor.configuration.DestinationReference {
		return rejected(
			"backup-destination-not-configured",
			"backup operation does not name the configured immutable destination",
		), nil
	}
	var result guestruntimeapplication.GuestOperationalStateBackupStageResult
	var err error
	switch stage {
	case guestruntimedomain.GuestStateBackupSQLiteSnapshotStage:
		result, err = executor.snapshotSQLite(ctx, operation)
	case guestruntimedomain.GuestStateBackupPostgreSQLSnapshotStage:
		result, err = executor.snapshotPostgreSQL(ctx, operation)
	case guestruntimedomain.GuestStateBackupArtifactInventoryStage:
		result, err = executor.inventoryArtifacts(ctx, operation)
	case guestruntimedomain.GuestStateBackupManifestPublicationStage:
		result, err = executor.publishManifest(operation)
	default:
		return rejected(
			"backup-stage-not-supported",
			"backup stage executor received an unsupported effect",
		), nil
	}
	var postgreSQLRejection *gueststatepostgresqlbackup.Rejection
	if errors.As(err, &postgreSQLRejection) {
		return rejected(
			postgreSQLRejection.Code,
			postgreSQLRejection.Message,
		), nil
	}
	return result, err
}

func (executor *Executor) snapshotSQLite(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace, err := executor.operationWorkspace(operation.ID)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	snapshotPath := filepath.Join(workspace, "guest-runtime.sqlite")
	snapshot, err := executor.sqliteOwner.CreateOnlineSnapshot(ctx, snapshotPath)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	detail := guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{
		DatabaseID:    snapshot.DatabaseID,
		SchemaVersion: snapshot.SchemaVersion,
		Snapshot: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: backupObjectReference(operation.ID, "sqlite"),
			ByteSize:  snapshot.ByteSize,
			SHA256:    snapshot.SHA256,
		},
	}
	return executor.publishStageDetail(
		operation,
		guestruntimedomain.GuestStateBackupSQLiteSnapshotStage,
		detail,
	)
}

func (executor *Executor) snapshotPostgreSQL(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace, err := executor.operationWorkspace(operation.ID)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	snapshotPath := filepath.Join(workspace, "guest-operational-state.dump")
	snapshot, err := executor.postgresqlOwner.CreateLogicalSnapshot(ctx, snapshotPath)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	detail := guestruntimedomain.GuestOperationalStatePostgreSQLSnapshotReceipt{
		DatabaseID:           snapshot.DatabaseID,
		AlembicRevision:      snapshot.AlembicRevision,
		IncludedOwnerSchemas: append([]string{}, snapshot.IncludedOwnerSchemas...),
		Snapshot: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: backupObjectReference(operation.ID, "postgresql"),
			ByteSize:  snapshot.ByteSize,
			SHA256:    snapshot.SHA256,
		},
	}
	return executor.publishStageDetail(
		operation,
		guestruntimedomain.GuestStateBackupPostgreSQLSnapshotStage,
		detail,
	)
}

func (executor *Executor) inventoryArtifacts(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace, err := executor.operationWorkspace(operation.ID)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	inventoryPath := filepath.Join(workspace, "archive-artifact-inventory.json")
	artifactCount, byteSize, digest, err := executor.loadOrCreateInventory(
		ctx,
		operation.ID,
		inventoryPath,
	)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	detail := guestruntimedomain.GuestOperationalStateArtifactInventoryReceipt{
		ArtifactCount: artifactCount,
		Inventory: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: backupObjectReference(operation.ID, "artifact-inventory"),
			ByteSize:  byteSize,
			SHA256:    digest,
		},
	}
	return executor.publishStageDetail(
		operation,
		guestruntimedomain.GuestStateBackupArtifactInventoryStage,
		detail,
	)
}

func (executor *Executor) publishManifest(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace, err := executor.operationWorkspace(operation.ID)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	var sqliteReceipt guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt
	var postgresqlReceipt guestruntimedomain.GuestOperationalStatePostgreSQLSnapshotReceipt
	var inventoryReceipt guestruntimedomain.GuestOperationalStateArtifactInventoryReceipt
	for path, target := range map[string]any{
		filepath.Join(workspace, "sqlite-snapshot-receipt.json"):     &sqliteReceipt,
		filepath.Join(workspace, "postgresql-snapshot-receipt.json"): &postgresqlReceipt,
		filepath.Join(workspace, "artifact-inventory-receipt.json"):  &inventoryReceipt,
	} {
		if err := decodeStrictJSONFile(path, target); err != nil {
			return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
		}
	}
	manifestReference := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-manifest",
		ResourceID:   stableResourceID(operation.ID, "manifest"),
	}
	manifestPath := filepath.Join(
		executor.manifestsRootPath,
		manifestReference.ResourceID+".json",
	)
	_, encoded, err := executor.loadOrCreateManifest(
		operation,
		manifestPath,
		sqliteReceipt,
		postgresqlReceipt,
		inventoryReceipt,
	)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	digest := sha256.Sum256(encoded)
	completedAt := guestruntimedomain.Timestamp(executor.clock.Now())
	receipt := guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage:             guestruntimedomain.GuestStateBackupManifestPublicationStage,
		EvidenceReference: manifestReference,
		EvidenceSHA256:    hex.EncodeToString(digest[:]),
		CompletedAt:       completedAt,
	}
	return guestruntimeapplication.GuestOperationalStateBackupStageResult{
		Outcome:           guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded,
		Receipt:           &receipt,
		ManifestReference: &manifestReference,
		ManifestSHA256:    receipt.EvidenceSHA256,
	}, nil
}

func (executor *Executor) publishStageDetail(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
	detail any,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace, err := executor.operationWorkspace(operation.ID)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	fileName := map[string]string{
		guestruntimedomain.GuestStateBackupSQLiteSnapshotStage:     "sqlite-snapshot-receipt.json",
		guestruntimedomain.GuestStateBackupPostgreSQLSnapshotStage: "postgresql-snapshot-receipt.json",
		guestruntimedomain.GuestStateBackupArtifactInventoryStage:  "artifact-inventory-receipt.json",
	}[stage]
	if fileName == "" {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			fmt.Errorf("Guest operational-state backup stage evidence file is undefined")
	}
	encoded, err := json.Marshal(detail)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			fmt.Errorf("encode Guest operational-state backup stage detail: %w", err)
	}
	encoded = append(encoded, '\n')
	if err := writeImmutableFile(filepath.Join(workspace, fileName), encoded); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	digest := sha256.Sum256(encoded)
	receipt := guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage: stage,
		EvidenceReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-backup-stage-receipt",
			ResourceID:   stableResourceID(operation.ID, stage+"-receipt"),
		},
		EvidenceSHA256: hex.EncodeToString(digest[:]),
		CompletedAt:    guestruntimedomain.Timestamp(executor.clock.Now()),
	}
	return guestruntimeapplication.GuestOperationalStateBackupStageResult{
		Outcome: guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded,
		Receipt: &receipt,
	}, nil
}

func (executor *Executor) loadOrCreateInventory(
	ctx context.Context,
	operationID string,
	path string,
) (int, int64, string, error) {
	if _, err := os.Stat(path); err == nil {
		return inspectInventory(path, operationID)
	} else if !errors.Is(err, os.ErrNotExist) {
		return 0, 0, "", fmt.Errorf("inspect Archive artifact inventory: %w", err)
	}
	partialPath := path + ".partial"
	file, err := os.OpenFile(partialPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return 0, 0, "", fmt.Errorf("create Archive artifact inventory partial: %w", err)
	}
	createdAt := guestruntimedomain.Timestamp(executor.clock.Now())
	count, writeErr := executor.inventoryOwner.WriteGuestOperationalStateArtifactInventory(
		ctx,
		operationID,
		createdAt,
		file,
	)
	syncErr := file.Sync()
	closeErr := file.Close()
	if writeErr != nil || syncErr != nil || closeErr != nil {
		return 0, 0, "", errors.Join(writeErr, syncErr, closeErr)
	}
	inspectedCount, byteSize, digest, err := inspectInventory(
		partialPath,
		operationID,
	)
	if err != nil {
		return 0, 0, "", err
	}
	if inspectedCount != count {
		return 0, 0, "", fmt.Errorf("Archive artifact inventory count disagrees with owner receipt")
	}
	if err := publishPartialFile(partialPath, path); err != nil {
		return 0, 0, "", err
	}
	return count, byteSize, digest, nil
}

func (executor *Executor) loadOrCreateManifest(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	path string,
	sqliteReceipt guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
	postgresqlReceipt guestruntimedomain.GuestOperationalStatePostgreSQLSnapshotReceipt,
	inventoryReceipt guestruntimedomain.GuestOperationalStateArtifactInventoryReceipt,
) (guestruntimedomain.GuestOperationalStateBackupManifest, []byte, error) {
	expected := guestruntimedomain.GuestOperationalStateBackupManifest{
		SchemaVersion:        guestruntimedomain.SchemaVersion,
		ID:                   stableResourceID(operation.ID, "manifest"),
		OperationID:          operation.ID,
		DestinationReference: executor.configuration.DestinationReference,
		SQLiteSnapshot:       sqliteReceipt,
		PostgreSQLSnapshot:   postgresqlReceipt,
		ArtifactInventory:    inventoryReceipt,
		ObjectBytesIncluded:  false,
		CreatedAt:            guestruntimedomain.Timestamp(executor.clock.Now()),
	}
	if _, err := os.Stat(path); err == nil {
		var stored guestruntimedomain.GuestOperationalStateBackupManifest
		if err := decodeStrictJSONFile(path, &stored); err != nil {
			return stored, nil, err
		}
		expected.CreatedAt = stored.CreatedAt
		if !reflect.DeepEqual(stored, expected) {
			return stored, nil, fmt.Errorf("published Guest operational-state backup manifest conflicts with operation evidence")
		}
		encoded, err := os.ReadFile(path)
		return stored, encoded, err
	} else if !errors.Is(err, os.ErrNotExist) {
		return expected, nil, fmt.Errorf("inspect Guest operational-state backup manifest: %w", err)
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupManifest(expected); err != nil {
		return expected, nil, err
	}
	encoded, err := json.Marshal(expected)
	if err != nil {
		return expected, nil, fmt.Errorf("encode Guest operational-state backup manifest: %w", err)
	}
	encoded = append(encoded, '\n')
	if err := writeImmutableFile(path, encoded); err != nil {
		return expected, nil, err
	}
	return expected, encoded, nil
}

func (executor *Executor) operationWorkspace(operationID string) (string, error) {
	path := filepath.Join(
		executor.operationsRootPath,
		stableResourceID(operationID, "workspace"),
	)
	if err := ensurePrivateDirectory(path); err != nil {
		return "", err
	}
	return path, nil
}

func inspectInventory(path string, expectedOperationID string) (int, int64, string, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, 0, "", fmt.Errorf("open Archive artifact inventory: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return 0, 0, "", fmt.Errorf("decode Archive artifact inventory object: %w", err)
	}
	var schemaVersion string
	var operationID string
	var objectBytesIncluded bool
	var createdAt string
	seen := map[string]bool{}
	count := 0
	previousArtifactID := ""
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return 0, 0, "", fmt.Errorf("decode Archive artifact inventory key: %w", err)
		}
		key, ok := keyToken.(string)
		if !ok || seen[key] {
			return 0, 0, "", fmt.Errorf("Archive artifact inventory contains an invalid or duplicate key")
		}
		seen[key] = true
		switch key {
		case "schemaVersion":
			err = decoder.Decode(&schemaVersion)
		case "operationId":
			err = decoder.Decode(&operationID)
		case "objectBytesIncluded":
			err = decoder.Decode(&objectBytesIncluded)
		case "createdAt":
			err = decoder.Decode(&createdAt)
		case "artifacts":
			var startArtifacts json.Token
			startArtifacts, err = decoder.Token()
			if err == nil && startArtifacts != json.Delim('[') {
				err = fmt.Errorf("artifacts is not an array")
			}
			for err == nil && decoder.More() {
				var item guestruntimedomain.GuestOperationalStateArtifactInventoryItem
				err = decoder.Decode(&item)
				if err != nil {
					break
				}
				if err = guestruntimedomain.ValidateGuestOperationalStateArtifactInventoryItem(item); err != nil {
					break
				}
				if previousArtifactID != "" && item.ArtifactID <= previousArtifactID {
					err = fmt.Errorf("Archive artifact inventory is unordered")
					break
				}
				previousArtifactID = item.ArtifactID
				count++
			}
			if err == nil {
				var endArtifacts json.Token
				endArtifacts, err = decoder.Token()
				if err == nil && endArtifacts != json.Delim(']') {
					err = fmt.Errorf("artifacts array is not closed")
				}
			}
		default:
			err = fmt.Errorf("Archive artifact inventory contains unknown field %s", key)
		}
		if err != nil {
			return 0, 0, "", fmt.Errorf("decode Archive artifact inventory: %w", err)
		}
	}
	end, err := decoder.Token()
	if err != nil || end != json.Delim('}') {
		return 0, 0, "", fmt.Errorf("decode Archive artifact inventory closing object: %w", err)
	}
	if len(seen) != 5 ||
		!seen["schemaVersion"] ||
		!seen["operationId"] ||
		!seen["artifacts"] ||
		!seen["objectBytesIncluded"] ||
		!seen["createdAt"] {
		return 0, 0, "", fmt.Errorf("Archive artifact inventory is incomplete")
	}
	if operationID != expectedOperationID {
		return 0, 0, "", fmt.Errorf("Archive artifact inventory operation identity mismatch")
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateArtifactInventory(
		guestruntimedomain.GuestOperationalStateArtifactInventory{
			SchemaVersion:       schemaVersion,
			OperationID:         operationID,
			Artifacts:           []guestruntimedomain.GuestOperationalStateArtifactInventoryItem{},
			ObjectBytesIncluded: objectBytesIncluded,
			CreatedAt:           createdAt,
		},
	); err != nil {
		return 0, 0, "", err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return 0, 0, "", fmt.Errorf("Archive artifact inventory contains trailing JSON")
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return 0, 0, "", fmt.Errorf("rewind Archive artifact inventory: %w", err)
	}
	digest := sha256.New()
	byteSize, err := io.Copy(digest, file)
	if err != nil {
		return 0, 0, "", fmt.Errorf("digest Archive artifact inventory: %w", err)
	}
	return count, byteSize, hex.EncodeToString(digest.Sum(nil)), nil
}

func decodeStrictJSONFile(path string, target any) error {
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open Guest operational-state backup evidence: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("decode Guest operational-state backup evidence: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("Guest operational-state backup evidence contains trailing JSON")
	}
	return nil
}

func writeImmutableFile(path string, contents []byte) error {
	if existing, err := os.ReadFile(path); err == nil {
		if !reflect.DeepEqual(existing, contents) {
			return fmt.Errorf("immutable Guest operational-state backup evidence conflicts with existing bytes")
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect immutable Guest operational-state backup evidence: %w", err)
	}
	partialPath := path + ".partial"
	file, err := os.OpenFile(partialPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create immutable Guest operational-state backup evidence partial: %w", err)
	}
	_, writeErr := file.Write(contents)
	syncErr := file.Sync()
	closeErr := file.Close()
	if writeErr != nil || syncErr != nil || closeErr != nil {
		return errors.Join(writeErr, syncErr, closeErr)
	}
	return publishPartialFile(partialPath, path)
}

func publishPartialFile(partialPath string, path string) error {
	if err := os.Rename(partialPath, path); err != nil {
		return fmt.Errorf("publish immutable Guest operational-state backup evidence: %w", err)
	}
	directory, err := os.Open(filepath.Dir(path))
	if err != nil {
		return fmt.Errorf("open immutable Guest operational-state backup evidence parent: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("sync immutable Guest operational-state backup evidence parent: %w", err)
	}
	return nil
}

func ensurePrivateDirectory(path string) error {
	if err := os.Mkdir(path, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("create Guest operational-state backup directory: %w", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("inspect Guest operational-state backup directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("Guest operational-state backup path is not a directory")
	}
	return nil
}

func stableResourceID(operationID string, purpose string) string {
	digest := sha256.Sum256([]byte(operationID + ":" + purpose))
	return "guest-backup-" + hex.EncodeToString(digest[:16])
}

func backupObjectReference(operationID string, purpose string) guestruntimedomain.ResourceReference {
	return guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-object",
		ResourceID:   stableResourceID(operationID, purpose),
	}
}

func validReference(reference guestruntimedomain.ResourceReference) bool {
	return guestruntimedomain.ValidIdentifier(reference.ResourceType) &&
		guestruntimedomain.ValidIdentifier(reference.ResourceID)
}

func rejected(
	code string,
	message string,
) guestruntimeapplication.GuestOperationalStateBackupStageResult {
	return guestruntimeapplication.GuestOperationalStateBackupStageResult{
		Outcome:        guestruntimeapplication.GuestStateBackupStageOutcomeRejected,
		FailureCode:    code,
		FailureMessage: message,
	}
}

var _ guestruntimeapplication.GuestOperationalStateBackupStageExecutor = (*Executor)(nil)
