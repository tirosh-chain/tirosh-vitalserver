package gueststatebackupstageexecutor

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

var publishedManifestIDPattern = regexp.MustCompile(`^guest-backup-[0-9a-f]{32}$`)

type SQLiteRestoreOwner interface {
	ProveEmpty(context.Context) (guestruntimedomain.GuestOperationalStateSQLiteEmptyTargetProof, error)
	Restore(
		context.Context,
		string,
		guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
	) (guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt, error)
	Verify(
		context.Context,
		guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt,
	) (guestruntimedomain.GuestOperationalStateSQLiteOwnerReadProof, error)
}

type PostgreSQLRestoreOwner interface {
	ProveEmptyTarget(
		context.Context,
	) (guestruntimedomain.GuestOperationalStatePostgreSQLEmptyTargetProof, error)
	RestoreSnapshot(
		context.Context,
		string,
		gueststatepostgresqlrestore.Snapshot,
	) error
	VerifyOwnerReads(
		context.Context,
		gueststatepostgresqlrestore.Snapshot,
	) (guestruntimedomain.GuestOperationalStatePostgreSQLOwnerReadProof, error)
}

type RestoreConfiguration struct {
	RootDirectory   string
	TargetReference guestruntimedomain.ResourceReference
}

type RestoreExecutor struct {
	configuration     RestoreConfiguration
	sqliteOwner       SQLiteRestoreOwner
	postgresqlOwner   PostgreSQLRestoreOwner
	clock             guestruntimeapplication.GuestRuntimeClock
	operationsRoot    string
	manifestsRoot     string
	restoreEventsRoot string
}

func NewRestore(
	configuration RestoreConfiguration,
	sqliteOwner SQLiteRestoreOwner,
	postgresqlOwner PostgreSQLRestoreOwner,
	clock guestruntimeapplication.GuestRuntimeClock,
) (*RestoreExecutor, error) {
	if !filepath.IsAbs(configuration.RootDirectory) ||
		!validReference(configuration.TargetReference) ||
		sqliteOwner == nil ||
		postgresqlOwner == nil ||
		clock == nil {
		return nil, fmt.Errorf("Guest operational-state restore stage executor configuration is incomplete")
	}
	info, err := os.Stat(configuration.RootDirectory)
	if err != nil || !info.IsDir() {
		return nil, fmt.Errorf("Guest operational-state restore root is unavailable")
	}
	executor := &RestoreExecutor{
		configuration:     configuration,
		sqliteOwner:       sqliteOwner,
		postgresqlOwner:   postgresqlOwner,
		clock:             clock,
		operationsRoot:    filepath.Join(configuration.RootDirectory, "operations"),
		manifestsRoot:     filepath.Join(configuration.RootDirectory, "manifests"),
		restoreEventsRoot: filepath.Join(configuration.RootDirectory, "restores"),
	}
	for _, path := range []string{
		executor.operationsRoot,
		executor.manifestsRoot,
		executor.restoreEventsRoot,
	} {
		if err := ensurePrivateDirectory(path); err != nil {
			return nil, err
		}
	}
	return executor, nil
}

func (executor *RestoreExecutor) ExecuteStage(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	if operation.Kind != guestruntimedomain.GuestStateRestoreKind ||
		operation.TargetReference == nil ||
		*operation.TargetReference != executor.configuration.TargetReference {
		return rejected(
			"restore-target-not-configured",
			"restore operation does not name the configured empty target",
		), nil
	}
	if stage != guestruntimedomain.GuestStateRestoreBackupValidationStage {
		recovered, exists, err := executor.recoverRestoreDetail(
			ctx,
			operation,
			stage,
		)
		if err != nil {
			return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
		}
		if exists {
			return recovered, nil
		}
	}
	var result guestruntimeapplication.GuestOperationalStateBackupStageResult
	var err error
	switch stage {
	case guestruntimedomain.GuestStateRestoreBackupValidationStage:
		result, err = executor.validateBackup(operation)
	case guestruntimedomain.GuestStateRestoreEmptyTargetProofStage:
		result, err = executor.proveEmptyTarget(ctx, operation)
	case guestruntimedomain.GuestStateRestoreSQLiteStage:
		result, err = executor.restoreSQLite(ctx, operation)
	case guestruntimedomain.GuestStateRestorePostgreSQLStage:
		result, err = executor.restorePostgreSQL(ctx, operation)
	case guestruntimedomain.GuestStateRestoreOwnerReadVerificationStage:
		result, err = executor.verifyOwnerReads(ctx, operation)
	default:
		return rejected(
			"restore-stage-not-supported",
			"restore stage executor received an unsupported effect",
		), nil
	}
	var known *restoreRejection
	if errors.As(err, &known) {
		return rejected(known.code, known.message), nil
	}
	var sqliteRejection *gueststatesqliterestore.Rejection
	if errors.As(err, &sqliteRejection) {
		if stage == guestruntimedomain.GuestStateRestoreSQLiteStage &&
			(sqliteRejection.Code == "sqlite-restore-target-not-empty" ||
				sqliteRejection.Code == "sqlite-restore-partial-exists" ||
				sqliteRejection.Code == "sqlite-restore-target-raced") {
			return result, err
		}
		return rejected(sqliteRejection.Code, sqliteRejection.Message), nil
	}
	if errors.Is(err, gueststatepostgresqlrestore.ErrTargetNotEmpty) {
		if stage == guestruntimedomain.GuestStateRestorePostgreSQLStage {
			return result, err
		}
		return rejected(
			"postgresql-restore-target-not-empty",
			"PostgreSQL restore target already contains state",
		), nil
	}
	var postgreSQLRejection *gueststatepostgresqlrestore.Rejection
	if errors.As(err, &postgreSQLRejection) {
		return rejected(
			postgreSQLRejection.Code,
			postgreSQLRejection.Message,
		), nil
	}
	return result, err
}

type CompositeExecutor struct {
	backup  *Executor
	restore *RestoreExecutor
}

func NewComposite(
	backup *Executor,
	restore *RestoreExecutor,
) (*CompositeExecutor, error) {
	if backup == nil || restore == nil {
		return nil, fmt.Errorf("Guest operational-state backup and restore executors are required")
	}
	return &CompositeExecutor{backup: backup, restore: restore}, nil
}

func (executor *CompositeExecutor) ExecuteStage(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	if operation.Kind == guestruntimedomain.GuestStateBackupKind {
		return executor.backup.ExecuteStage(ctx, operation, stage)
	}
	if operation.Kind == guestruntimedomain.GuestStateRestoreKind {
		return executor.restore.ExecuteStage(ctx, operation, stage)
	}
	return rejected(
		"guest-operational-state-operation-kind-invalid",
		"operation kind is neither backup nor restore",
	), nil
}

func (executor *RestoreExecutor) validateBackup(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	_, encoded, _, err := executor.loadManifest(operation)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	digest := sha256.Sum256(encoded)
	receipt := guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage:             guestruntimedomain.GuestStateRestoreBackupValidationStage,
		EvidenceReference: *operation.ManifestReference,
		EvidenceSHA256:    hex.EncodeToString(digest[:]),
		CompletedAt:       guestruntimedomain.Timestamp(executor.clock.Now()),
	}
	return succeeded(receipt), nil
}

func (executor *RestoreExecutor) proveEmptyTarget(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	sqliteProof, err := executor.sqliteOwner.ProveEmpty(ctx)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	postgresqlProof, err := executor.postgresqlOwner.ProveEmptyTarget(ctx)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	proof := guestruntimedomain.GuestOperationalStateEmptyTargetProof{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		OperationID:      operation.ID,
		TargetReference:  executor.configuration.TargetReference,
		SQLiteTarget:     sqliteProof,
		PostgreSQLTarget: postgresqlProof,
		ProvedAt:         guestruntimedomain.Timestamp(executor.clock.Now()),
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateEmptyTargetProof(proof); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	return executor.publishRestoreDetail(
		operation,
		guestruntimedomain.GuestStateRestoreEmptyTargetProofStage,
		proof,
	)
}

func (executor *RestoreExecutor) restoreSQLite(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	manifest, _, workspace, err := executor.loadManifest(operation)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	receipt, err := executor.sqliteOwner.Restore(
		ctx,
		filepath.Join(workspace, "guest-runtime.sqlite"),
		manifest.SQLiteSnapshot,
	)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	return executor.publishRestoreDetail(
		operation,
		guestruntimedomain.GuestStateRestoreSQLiteStage,
		receipt,
	)
}

func (executor *RestoreExecutor) restorePostgreSQL(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	manifest, _, workspace, err := executor.loadManifest(operation)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	expected := postgreSQLRestoreSnapshot(manifest.PostgreSQLSnapshot)
	if err := executor.postgresqlOwner.RestoreSnapshot(
		ctx,
		filepath.Join(workspace, "guest-operational-state.dump"),
		expected,
	); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	return executor.publishRestoreDetail(
		operation,
		guestruntimedomain.GuestStateRestorePostgreSQLStage,
		manifest.PostgreSQLSnapshot,
	)
}

func (executor *RestoreExecutor) verifyOwnerReads(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	manifest, _, _, err := executor.loadManifest(operation)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	sqliteProof, err := executor.sqliteOwner.Verify(ctx, manifest.SQLiteSnapshot)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	postgresqlProof, err := executor.postgresqlOwner.VerifyOwnerReads(
		ctx,
		postgreSQLRestoreSnapshot(manifest.PostgreSQLSnapshot),
	)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	evidence := guestruntimedomain.GuestOperationalStateRestoreOwnerReadProof{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		OperationID:      operation.ID,
		TargetReference:  executor.configuration.TargetReference,
		SQLiteOwner:      sqliteProof,
		PostgreSQLOwners: postgresqlProof,
		VerifiedAt: guestruntimedomain.Timestamp(
			executor.clock.Now(),
		),
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateRestoreOwnerReadProof(
		evidence,
	); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	return executor.publishRestoreDetail(
		operation,
		guestruntimedomain.GuestStateRestoreOwnerReadVerificationStage,
		evidence,
	)
}

func (executor *RestoreExecutor) loadManifest(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) (
	guestruntimedomain.GuestOperationalStateBackupManifest,
	[]byte,
	string,
	error,
) {
	var manifest guestruntimedomain.GuestOperationalStateBackupManifest
	if operation.ManifestReference == nil ||
		operation.ManifestReference.ResourceType != "guest-backup-manifest" ||
		!publishedManifestIDPattern.MatchString(operation.ManifestReference.ResourceID) {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-reference-invalid",
			message: "restore manifest reference is not a published C76 manifest",
		}
	}
	path := filepath.Join(
		executor.manifestsRoot,
		operation.ManifestReference.ResourceID+".json",
	)
	encoded, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-missing",
			message: "restore manifest does not exist in the configured backup store",
		}
	}
	if err != nil {
		return manifest, nil, "", fmt.Errorf("read Guest operational-state backup manifest: %w", err)
	}
	digest := sha256.Sum256(encoded)
	if hex.EncodeToString(digest[:]) != operation.ManifestSHA256 {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-digest-mismatch",
			message: "restore manifest bytes do not match the command digest",
		}
	}
	if err := decodeStrictJSONFile(path, &manifest); err != nil {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-invalid",
			message: err.Error(),
		}
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBackupManifest(manifest); err != nil {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-invalid",
			message: err.Error(),
		}
	}
	if manifest.ID != operation.ManifestReference.ResourceID ||
		manifest.SQLiteSnapshot.Snapshot.Reference != backupObjectReference(manifest.OperationID, "sqlite") ||
		manifest.PostgreSQLSnapshot.Snapshot.Reference != backupObjectReference(manifest.OperationID, "postgresql") ||
		manifest.ArtifactInventory.Inventory.Reference != backupObjectReference(manifest.OperationID, "artifact-inventory") {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-manifest-object-reference-mismatch",
			message: "manifest object references do not match its source operation",
		}
	}
	workspace := filepath.Join(
		executor.operationsRoot,
		stableResourceID(manifest.OperationID, "workspace"),
	)
	count, byteSize, inventoryDigest, err := inspectInventory(
		filepath.Join(workspace, "archive-artifact-inventory.json"),
		manifest.OperationID,
	)
	if err != nil {
		return manifest, nil, "", err
	}
	if count != manifest.ArtifactInventory.ArtifactCount ||
		byteSize != manifest.ArtifactInventory.Inventory.ByteSize ||
		inventoryDigest != manifest.ArtifactInventory.Inventory.SHA256 {
		return manifest, nil, "", &restoreRejection{
			code:    "backup-artifact-inventory-mismatch",
			message: "artifact inventory bytes do not match the manifest",
		}
	}
	return manifest, encoded, workspace, nil
}

func (executor *RestoreExecutor) publishRestoreDetail(
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
	detail any,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	workspace := filepath.Join(
		executor.restoreEventsRoot,
		stableResourceID(operation.ID, "restore-workspace"),
	)
	if err := ensurePrivateDirectory(workspace); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	detailBytes, err := json.Marshal(detail)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			fmt.Errorf("encode Guest operational-state restore evidence: %w", err)
	}
	evidence := restoreStageEvidence{
		Stage:       stage,
		CompletedAt: guestruntimedomain.Timestamp(executor.clock.Now()),
		Detail:      detailBytes,
	}
	encoded, err := json.Marshal(evidence)
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			fmt.Errorf("encode Guest operational-state restore evidence envelope: %w", err)
	}
	encoded = append(encoded, '\n')
	path := filepath.Join(workspace, stage+".json")
	if err := writeImmutableFile(path, encoded); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, err
	}
	digest := sha256.Sum256(encoded)
	receipt := guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage: stage,
		EvidenceReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-restore-stage-receipt",
			ResourceID:   stableResourceID(operation.ID, stage+"-receipt"),
		},
		EvidenceSHA256: hex.EncodeToString(digest[:]),
		CompletedAt:    evidence.CompletedAt,
	}
	return succeeded(receipt), nil
}

type restoreStageEvidence struct {
	Stage       string          `json:"stage"`
	CompletedAt string          `json:"completedAt"`
	Detail      json.RawMessage `json:"detail"`
}

func (executor *RestoreExecutor) recoverRestoreDetail(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, bool, error) {
	path := executor.restoreDetailPath(operation.ID, stage)
	encoded, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, false, nil
	}
	if err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			false,
			fmt.Errorf("read Guest operational-state restore recovery evidence: %w", err)
	}
	var evidence restoreStageEvidence
	if err := decodeStrictJSONBytes(encoded, &evidence); err != nil ||
		evidence.Stage != stage ||
		len(evidence.Detail) == 0 {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			false,
			fmt.Errorf("Guest operational-state restore recovery evidence is invalid")
	}
	if _, err := time.Parse(time.RFC3339Nano, evidence.CompletedAt); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			false,
			fmt.Errorf("Guest operational-state restore recovery time is invalid")
	}
	if err := executor.verifyRecoveredRestoreStage(
		ctx,
		operation,
		stage,
	); err != nil {
		return guestruntimeapplication.GuestOperationalStateBackupStageResult{},
			false,
			fmt.Errorf("verify recovered Guest operational-state restore stage: %w", err)
	}
	digest := sha256.Sum256(encoded)
	return succeeded(guestruntimedomain.GuestOperationalStateBackupStageReceipt{
		Stage: stage,
		EvidenceReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-restore-stage-receipt",
			ResourceID:   stableResourceID(operation.ID, stage+"-receipt"),
		},
		EvidenceSHA256: hex.EncodeToString(digest[:]),
		CompletedAt:    evidence.CompletedAt,
	}), true, nil
}

func (executor *RestoreExecutor) verifyRecoveredRestoreStage(
	ctx context.Context,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	stage string,
) error {
	manifest, _, _, err := executor.loadManifest(operation)
	if err != nil {
		return err
	}
	switch stage {
	case guestruntimedomain.GuestStateRestoreEmptyTargetProofStage:
		if _, err := executor.sqliteOwner.ProveEmpty(ctx); err != nil {
			return err
		}
		_, err = executor.postgresqlOwner.ProveEmptyTarget(ctx)
		return err
	case guestruntimedomain.GuestStateRestoreSQLiteStage:
		_, err := executor.sqliteOwner.Verify(ctx, manifest.SQLiteSnapshot)
		return err
	case guestruntimedomain.GuestStateRestorePostgreSQLStage:
		_, err := executor.postgresqlOwner.VerifyOwnerReads(
			ctx,
			postgreSQLRestoreSnapshot(manifest.PostgreSQLSnapshot),
		)
		return err
	case guestruntimedomain.GuestStateRestoreOwnerReadVerificationStage:
		if _, err := executor.sqliteOwner.Verify(
			ctx,
			manifest.SQLiteSnapshot,
		); err != nil {
			return err
		}
		_, err := executor.postgresqlOwner.VerifyOwnerReads(
			ctx,
			postgreSQLRestoreSnapshot(manifest.PostgreSQLSnapshot),
		)
		return err
	default:
		return fmt.Errorf("restore recovery stage is unsupported")
	}
}

func (executor *RestoreExecutor) restoreDetailPath(
	operationID string,
	stage string,
) string {
	return filepath.Join(
		executor.restoreEventsRoot,
		stableResourceID(operationID, "restore-workspace"),
		stage+".json",
	)
}

func decodeStrictJSONBytes(encoded []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("restore evidence contains trailing JSON")
	}
	return nil
}

func postgreSQLRestoreSnapshot(
	receipt guestruntimedomain.GuestOperationalStatePostgreSQLSnapshotReceipt,
) gueststatepostgresqlrestore.Snapshot {
	return gueststatepostgresqlrestore.Snapshot{
		DatabaseID:           receipt.DatabaseID,
		AlembicRevision:      receipt.AlembicRevision,
		IncludedOwnerSchemas: append([]string{}, receipt.IncludedOwnerSchemas...),
		ByteSize:             receipt.Snapshot.ByteSize,
		SHA256:               receipt.Snapshot.SHA256,
	}
}

func succeeded(
	receipt guestruntimedomain.GuestOperationalStateBackupStageReceipt,
) guestruntimeapplication.GuestOperationalStateBackupStageResult {
	return guestruntimeapplication.GuestOperationalStateBackupStageResult{
		Outcome: guestruntimeapplication.GuestStateBackupStageOutcomeSucceeded,
		Receipt: &receipt,
	}
}

type restoreRejection struct {
	code    string
	message string
}

func (rejection *restoreRejection) Error() string {
	return rejection.message
}

var _ guestruntimeapplication.GuestOperationalStateBackupStageExecutor = (*CompositeExecutor)(nil)
