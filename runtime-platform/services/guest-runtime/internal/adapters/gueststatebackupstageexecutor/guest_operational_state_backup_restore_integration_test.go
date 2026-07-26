package gueststatebackupstageexecutor

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	_ "modernc.org/sqlite"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupsqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlbackup"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestGuestOperationalStateBackupRestoresBothOwnedDatabasesToEmptyTargets(
	t *testing.T,
) {
	sourceDatabaseURL := os.Getenv(
		"VITALSERVER_GUEST_STATE_BACKUP_TEST_SOURCE_DATABASE_URL",
	)
	targetDatabaseURL := os.Getenv(
		"VITALSERVER_GUEST_STATE_BACKUP_TEST_EMPTY_TARGET_DATABASE_URL",
	)
	pgDumpPath := os.Getenv(
		"VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_DUMP_PATH",
	)
	pgRestorePath := os.Getenv(
		"VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_RESTORE_PATH",
	)
	if sourceDatabaseURL == "" ||
		targetDatabaseURL == "" ||
		pgDumpPath == "" ||
		pgRestorePath == "" {
		t.Skip(
			"explicit seeded source URL, empty target URL, pg_dump, and pg_restore are required",
		)
	}

	ctx := context.Background()
	sourceDatabase := openAcceptanceDatabase(t, sourceDatabaseURL)
	defer sourceDatabase.Close()
	targetDatabase := openAcceptanceDatabase(t, targetDatabaseURL)
	defer targetDatabase.Close()
	requireSeededGuestOwnerEvidence(t, ctx, sourceDatabase)

	root := t.TempDir()
	sourceSQLitePath := filepath.Join(root, "source", "guest-runtime.sqlite")
	if err := os.MkdirAll(filepath.Dir(sourceSQLitePath), 0o700); err != nil {
		t.Fatal(err)
	}
	sourceSQLite, err := gueststatesqliterepository.
		OpenGuestRuntimeStateSQLiteRepository(ctx, sourceSQLitePath)
	if err != nil {
		t.Fatal(err)
	}
	defer sourceSQLite.Close()
	seedGuestRuntimeSQLiteAcceptanceOperation(t, ctx, sourceSQLitePath)

	archiveOwner, err := gueststatepostgresqlrepository.
		OpenArchiveExportPostgreSQLRepository(ctx, sourceDatabaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer archiveOwner.Close()
	postgresqlBackupOwner, err := gueststatepostgresqlbackup.Open(
		ctx,
		gueststatepostgresqlbackup.Configuration{
			DatabaseURL:             sourceDatabaseURL,
			PGDumpExecutablePath:    pgDumpPath,
			PGRestoreExecutablePath: pgRestorePath,
			ExpectedAlembicRevision: gueststatepostgresqlrepository.
				ExpectedRecorderCatalogRevision,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	defer postgresqlBackupOwner.Close()

	backupRoot := filepath.Join(root, "backup")
	if err := os.MkdirAll(backupRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	destination := guestruntimedomain.ResourceReference{
		ResourceType: "guest-backup-destination",
		ResourceID:   "combined-restore-acceptance-destination",
	}
	targetReference := guestruntimedomain.ResourceReference{
		ResourceType: "guest-restore-target",
		ResourceID:   "combined-restore-acceptance-target",
	}
	clock := guestruntimeapplication.SystemGuestRuntimeClock{}
	backupExecutor, err := New(
		Configuration{
			RootDirectory:        backupRoot,
			DestinationReference: destination,
		},
		sourceSQLite,
		postgresqlBackupOwner,
		archiveOwner,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}

	restoreSQLitePath := filepath.Join(root, "restore", "guest-runtime.sqlite")
	if err := os.MkdirAll(filepath.Dir(restoreSQLitePath), 0o700); err != nil {
		t.Fatal(err)
	}
	sqliteRestoreOwner, err := gueststatesqliterestore.New(restoreSQLitePath)
	if err != nil {
		t.Fatal(err)
	}
	postgresqlRestoreOwner, err := gueststatepostgresqlrestore.Open(
		ctx,
		targetDatabaseURL,
		pgRestorePath,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer postgresqlRestoreOwner.Close()
	restoreExecutor, err := NewRestore(
		RestoreConfiguration{
			RootDirectory:   backupRoot,
			TargetReference: targetReference,
		},
		sqliteRestoreOwner,
		postgresqlRestoreOwner,
		clock,
	)
	if err != nil {
		t.Fatal(err)
	}
	composite, err := NewComposite(backupExecutor, restoreExecutor)
	if err != nil {
		t.Fatal(err)
	}
	ledger, err := gueststatebackupsqliterepository.Open(
		ctx,
		filepath.Join(root, "operation-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer ledger.Close()
	service, err := guestruntimeapplication.
		NewGuestOperationalStateBackupApplicationService(ledger, composite, clock)
	if err != nil {
		t.Fatal(err)
	}
	controlHandler := guestruntimecontrolhttpapi.
		NewGuestRuntimeControlHTTPServerWithModules(
			guestruntimecontrolhttpapi.GuestRuntimeControlModules{
				GuestOperationalStateBackup:                  service,
				GuestOperationalStateRestoreAdmissionEnabled: true,
			},
		)

	requestedAt := guestruntimedomain.Timestamp(time.Now().UTC())
	backupOperation := admitGuestOperationalStateCommand(
		t,
		controlHandler,
		"/v1/runtime/operational-state/backups",
		guestruntimedomain.GuestOperationalStateBackupCommand{
			SchemaVersion:        guestruntimedomain.SchemaVersion,
			RequestID:            "combined-backup-request",
			OperationID:          "combined-backup-operation",
			DestinationReference: destination,
			RequestedAt:          requestedAt,
		},
	)
	backupOperation = runGuestStateOperationToTerminal(
		t,
		ctx,
		service,
		backupOperation,
	)
	if backupOperation.State != guestruntimedomain.GuestStateBackupSucceededState ||
		backupOperation.ManifestReference == nil ||
		len(backupOperation.StageReceipts) != 4 {
		t.Fatalf(
			"backup operation=%+v failure=%+v",
			backupOperation,
			backupOperation.Failure,
		)
	}
	requireGuestOperationalStateOperationRead(
		t,
		controlHandler,
		backupOperation,
	)

	restoreOperation := admitGuestOperationalStateCommand(
		t,
		controlHandler,
		"/v1/runtime/operational-state/restores",
		guestruntimedomain.GuestOperationalStateRestoreCommand{
			SchemaVersion:     guestruntimedomain.SchemaVersion,
			RequestID:         "combined-restore-request",
			OperationID:       "combined-restore-operation",
			ManifestReference: *backupOperation.ManifestReference,
			ManifestSHA256:    backupOperation.ManifestSHA256,
			TargetReference:   targetReference,
			RequestedAt:       requestedAt,
		},
	)
	restoreOperation = runGuestStateOperationToTerminal(
		t,
		ctx,
		service,
		restoreOperation,
	)
	if restoreOperation.State !=
		guestruntimedomain.GuestStateBackupSucceededState ||
		len(restoreOperation.StageReceipts) != 5 {
		t.Fatalf(
			"restore operation=%+v failure=%+v",
			restoreOperation,
			restoreOperation.Failure,
		)
	}
	requireGuestOperationalStateOperationRead(
		t,
		controlHandler,
		restoreOperation,
	)
	requireRestoredSQLiteAcceptanceOperation(t, ctx, restoreSQLitePath)
	requireMatchingGuestOwnerEvidence(
		t,
		ctx,
		sourceDatabase,
		targetDatabase,
	)
	requireMatchingPublicGuestOwnerReads(
		t,
		ctx,
		sourceDatabaseURL,
		targetDatabaseURL,
		sourceSQLitePath,
		restoreSQLitePath,
		sourceDatabase,
	)

	secondRestore := admitGuestOperationalStateCommand(
		t,
		controlHandler,
		"/v1/runtime/operational-state/restores",
		guestruntimedomain.GuestOperationalStateRestoreCommand{
			SchemaVersion:     guestruntimedomain.SchemaVersion,
			RequestID:         "combined-second-restore-request",
			OperationID:       "combined-second-restore-operation",
			ManifestReference: *backupOperation.ManifestReference,
			ManifestSHA256:    backupOperation.ManifestSHA256,
			TargetReference:   targetReference,
			RequestedAt:       requestedAt,
		},
	)
	secondRestore = runGuestStateOperationToTerminal(
		t,
		ctx,
		service,
		secondRestore,
	)
	if secondRestore.State != guestruntimedomain.GuestStateBackupFailedState ||
		secondRestore.Failure == nil ||
		secondRestore.Failure.Stage !=
			guestruntimedomain.GuestStateRestoreEmptyTargetProofStage ||
		secondRestore.Failure.Code != "sqlite-restore-target-not-empty" {
		t.Fatalf("second restore operation=%+v", secondRestore)
	}
}

func admitGuestOperationalStateCommand(
	t *testing.T,
	handler http.Handler,
	path string,
	command any,
) guestruntimedomain.GuestOperationalStateBackupOperation {
	t.Helper()
	body, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(body))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted {
		t.Fatalf(
			"Guest operational-state admission path=%s status=%d body=%s",
			path,
			response.Code,
			response.Body.String(),
		)
	}
	var operation guestruntimedomain.GuestOperationalStateBackupOperation
	if err := json.Unmarshal(response.Body.Bytes(), &operation); err != nil {
		t.Fatal(err)
	}
	return operation
}

func requireGuestOperationalStateOperationRead(
	t *testing.T,
	handler http.Handler,
	expected guestruntimedomain.GuestOperationalStateBackupOperation,
) {
	t.Helper()
	request := httptest.NewRequest(
		http.MethodGet,
		"/v1/runtime/operational-state/operations/"+expected.ID,
		nil,
	)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf(
			"Guest operational-state read status=%d body=%s",
			response.Code,
			response.Body.String(),
		)
	}
	var read struct {
		State string                                                  `json:"state"`
		Value guestruntimedomain.GuestOperationalStateBackupOperation `json:"value"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &read); err != nil {
		t.Fatal(err)
	}
	if read.State != "available" ||
		read.Value.ID != expected.ID ||
		read.Value.State != expected.State ||
		read.Value.ResourceRevision != expected.ResourceRevision {
		t.Fatalf(
			"Guest operational-state public read=%+v expected=%+v",
			read,
			expected,
		)
	}
}

func requireMatchingPublicGuestOwnerReads(
	t *testing.T,
	ctx context.Context,
	sourceDatabaseURL string,
	targetDatabaseURL string,
	sourceSQLitePath string,
	targetSQLitePath string,
	sourceDatabase *sql.DB,
) {
	t.Helper()
	observedAt := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	sourceHandler, closeSource := openCombinedAcceptanceOwnerReadHandler(
		t,
		sourceDatabaseURL,
		sourceSQLitePath,
		observedAt,
	)
	defer closeSource()
	targetHandler, closeTarget := openCombinedAcceptanceOwnerReadHandler(
		t,
		targetDatabaseURL,
		targetSQLitePath,
		observedAt,
	)
	defer closeTarget()

	compareCombinedAcceptanceOwnerRead(
		t,
		sourceHandler,
		targetHandler,
		"/v1/runtime/operational-state/identity",
	)
	recorderPage := compareCombinedAcceptanceOwnerRead(
		t,
		sourceHandler,
		targetHandler,
		"/v1/runtime/recorders?limit=100",
	)
	var recorders struct {
		State string `json:"state"`
		Value struct {
			Items []struct {
				RecorderID string `json:"recorderId"`
			} `json:"items"`
		} `json:"value"`
	}
	if err := json.Unmarshal(recorderPage, &recorders); err != nil {
		t.Fatal(err)
	}
	if recorders.State != "available" || len(recorders.Value.Items) == 0 {
		t.Fatalf("restored Recorder owner page has no evidence: %s", recorderPage)
	}
	for _, recorder := range recorders.Value.Items {
		for _, suffix := range []string{
			"/observability",
			"/observability/timeline?limit=100",
			"/observability/incidents?limit=100",
		} {
			compareCombinedAcceptanceOwnerRead(
				t,
				sourceHandler,
				targetHandler,
				"/v1/runtime/recorders/"+recorder.RecorderID+suffix,
			)
		}
	}

	rows, err := sourceDatabase.QueryContext(
		ctx,
		`SELECT DISTINCT matched_recorder_id
		   FROM archive_export.recorder_attributions
		  WHERE matched_recorder_id IS NOT NULL
		  ORDER BY matched_recorder_id`,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	artifactRecorderCount := 0
	for rows.Next() {
		var recorderID string
		if err := rows.Scan(&recorderID); err != nil {
			t.Fatal(err)
		}
		artifactRecorderCount++
		artifactPage := compareCombinedAcceptanceOwnerRead(
			t,
			sourceHandler,
			targetHandler,
			"/v1/runtime/recorders/"+recorderID+"/artifacts?limit=100",
		)
		var artifacts struct {
			State string `json:"state"`
			Value struct {
				Items []struct {
					Artifact struct {
						ArtifactID string `json:"artifactId"`
					} `json:"artifact"`
				} `json:"items"`
			} `json:"value"`
		}
		if err := json.Unmarshal(artifactPage, &artifacts); err != nil {
			t.Fatal(err)
		}
		if artifacts.State != "available" || len(artifacts.Value.Items) == 0 {
			t.Fatalf("restored artifact owner page has no evidence: %s", artifactPage)
		}
		for _, item := range artifacts.Value.Items {
			compareCombinedAcceptanceOwnerRead(
				t,
				sourceHandler,
				targetHandler,
				"/v1/runtime/artifacts/"+item.Artifact.ArtifactID,
			)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	if artifactRecorderCount == 0 {
		t.Fatal("source has no matched Recorder artifact evidence")
	}
}

func openCombinedAcceptanceOwnerReadHandler(
	t *testing.T,
	databaseURL string,
	sqlitePath string,
	observedAt time.Time,
) (http.Handler, func()) {
	t.Helper()
	ctx := context.Background()
	catalogRepository, err := gueststatepostgresqlrepository.
		OpenRecorderCatalogPostgreSQLRepository(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	sqliteRepository, err := gueststatesqliterepository.
		OpenGuestRuntimeStateSQLiteRepository(ctx, sqlitePath)
	if err != nil {
		_ = catalogRepository.Close()
		t.Fatal(err)
	}
	archiveRepository, err := gueststatepostgresqlrepository.
		OpenArchiveExportPostgreSQLRepository(ctx, databaseURL)
	if err != nil {
		_ = sqliteRepository.Close()
		_ = catalogRepository.Close()
		t.Fatal(err)
	}
	clock := combinedAcceptanceClock{now: observedAt}
	identityService, err := guestruntimeapplication.
		NewGuestOperationalStateIdentityApplicationService(
			sqliteRepository,
			catalogRepository,
			combinedAcceptanceBootstrapIdentityReader{},
			clock,
		)
	if err != nil {
		_ = archiveRepository.Close()
		_ = sqliteRepository.Close()
		_ = catalogRepository.Close()
		t.Fatal(err)
	}
	catalogService, err := guestruntimeapplication.
		NewGuestRuntimeObservationCatalogApplicationService(
			catalogRepository,
			clock,
			combinedAcceptanceIdentifierGenerator{},
			guestruntimedomain.RecorderObservationFreshnessPolicy{
				MaxReportAgeSeconds: 300,
			},
		)
	if err != nil {
		_ = archiveRepository.Close()
		_ = sqliteRepository.Close()
		_ = catalogRepository.Close()
		t.Fatal(err)
	}
	archiveService, err := guestruntimeapplication.
		NewGuestRuntimeArchiveLineageApplicationService(
			archiveRepository,
			clock,
		)
	if err != nil {
		_ = archiveRepository.Close()
		_ = sqliteRepository.Close()
		_ = catalogRepository.Close()
		t.Fatal(err)
	}
	handler := guestruntimecontrolhttpapi.
		NewGuestRuntimeControlHTTPServerWithModules(
			guestruntimecontrolhttpapi.GuestRuntimeControlModules{
				RecorderObservationCatalog:    catalogService,
				ArchiveLineage:                archiveService,
				GuestOperationalStateIdentity: identityService,
			},
		)
	return handler, func() {
		if err := errors.Join(
			archiveRepository.Close(),
			sqliteRepository.Close(),
			catalogRepository.Close(),
		); err != nil {
			t.Errorf("close public owner read repositories: %v", err)
		}
	}
}

func compareCombinedAcceptanceOwnerRead(
	t *testing.T,
	source http.Handler,
	target http.Handler,
	path string,
) []byte {
	t.Helper()
	read := func(handler http.Handler) []byte {
		request := httptest.NewRequest(http.MethodGet, path, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf(
				"public owner read path=%s status=%d body=%s",
				path,
				response.Code,
				response.Body.String(),
			)
		}
		return response.Body.Bytes()
	}
	sourceBody := read(source)
	targetBody := read(target)
	if !bytes.Equal(sourceBody, targetBody) {
		t.Fatalf(
			"restored public owner read differs path=%s source=%s target=%s",
			path,
			sourceBody,
			targetBody,
		)
	}
	return targetBody
}

type combinedAcceptanceClock struct {
	now time.Time
}

type combinedAcceptanceBootstrapIdentityReader struct{}

func (combinedAcceptanceBootstrapIdentityReader) ReadGuestOperationalStateBootstrapIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStateBootstrapIdentity, error) {
	return guestruntimedomain.GuestOperationalStateBootstrapIdentity{
		MigrationReceipt: guestruntimedomain.GuestOperationalStateMigrationReceipt{
			SchemaVersion: "v1",
			State:         "succeeded",
			Revision:      "0006_backup_owner",
			StartedAt:     "2026-07-24T00:00:00Z",
			FinishedAt:    "2026-07-24T00:00:01Z",
		},
		PrivateMaterialSet: guestruntimedomain.GuestOperationalStatePrivateMaterialSetIdentity{
			MaterialCount: 3,
			SHA256:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}, nil
}

func (clock combinedAcceptanceClock) Now() time.Time {
	return clock.now
}

type combinedAcceptanceIdentifierGenerator struct{}

func (combinedAcceptanceIdentifierGenerator) NewRequestCorrelationIdentifier(
	string,
) (string, error) {
	return "combined-acceptance-unused-correlation", nil
}

func runGuestStateOperationToTerminal(
	t *testing.T,
	ctx context.Context,
	service *guestruntimeapplication.GuestOperationalStateBackupApplicationService,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
) guestruntimedomain.GuestOperationalStateBackupOperation {
	t.Helper()
	for attempts := 0; attempts < 16; attempts++ {
		if operation.State == guestruntimedomain.GuestStateBackupSucceededState ||
			operation.State == guestruntimedomain.GuestStateBackupFailedState {
			return operation
		}
		advanced, ran, err := service.RunNextPendingEffect(ctx)
		if err != nil || !ran {
			t.Fatalf(
				"advance Guest operational-state operation=%+v ran=%t err=%v",
				operation,
				ran,
				err,
			)
		}
		if advanced.ID == operation.ID {
			operation = advanced
		}
	}
	t.Fatalf("Guest operational-state operation did not terminate: %+v", operation)
	return operation
}

func openAcceptanceDatabase(t *testing.T, databaseURL string) *sql.DB {
	t.Helper()
	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Ping(); err != nil {
		_ = database.Close()
		t.Fatal(err)
	}
	return database
}

func seedGuestRuntimeSQLiteAcceptanceOperation(
	t *testing.T,
	ctx context.Context,
	path string,
) {
	t.Helper()
	database, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	if _, err := database.ExecContext(
		ctx,
		`INSERT INTO runtime_operations(
			id, request_id, command_digest, document_json
		) VALUES (?, ?, ?, ?)`,
		"combined-sqlite-operation",
		"combined-sqlite-request",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		`{"schemaVersion":"v1","id":"combined-sqlite-operation","state":"succeeded"}`,
	); err != nil {
		t.Fatal(err)
	}
}

func requireRestoredSQLiteAcceptanceOperation(
	t *testing.T,
	ctx context.Context,
	path string,
) {
	t.Helper()
	database, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	var operationID string
	if err := database.QueryRowContext(
		ctx,
		`SELECT id FROM runtime_operations WHERE request_id = ?`,
		"combined-sqlite-request",
	).Scan(&operationID); err != nil {
		t.Fatal(err)
	}
	if operationID != "combined-sqlite-operation" {
		t.Fatalf("restored SQLite operation id=%q", operationID)
	}
}

func requireSeededGuestOwnerEvidence(
	t *testing.T,
	ctx context.Context,
	database *sql.DB,
) {
	t.Helper()
	for _, table := range guestOperationalStateEvidenceTables() {
		if guestOperationalStateTableCount(t, ctx, database, table) < 1 {
			t.Fatalf(
				"seeded source evidence table is empty: %s",
				table,
			)
		}
	}
}

func requireMatchingGuestOwnerEvidence(
	t *testing.T,
	ctx context.Context,
	source *sql.DB,
	target *sql.DB,
) {
	t.Helper()
	for _, table := range append(
		guestOperationalStateEvidenceTables(),
		"recorder_catalog.admission_requests",
		"archive_export.source_admission_requests",
		"guest_operational_state.metadata",
		"public.alembic_version",
	) {
		sourceCount := guestOperationalStateTableCount(
			t,
			ctx,
			source,
			table,
		)
		targetCount := guestOperationalStateTableCount(
			t,
			ctx,
			target,
			table,
		)
		if sourceCount != targetCount {
			t.Fatalf(
				"restored row count mismatch table=%s source=%d target=%d",
				table,
				sourceCount,
				targetCount,
			)
		}
	}
}

func guestOperationalStateEvidenceTables() []string {
	return []string{
		"recorder_catalog.observations",
		"recorder_catalog.recorder_current",
		"recorder_catalog.expectation_events",
		"recorder_catalog.recorder_expectations",
		"archive_export.artifacts",
		"archive_export.recorder_attributions",
		"archive_export.upload_attempts",
		"archive_export.indexing_receipts",
		"recorder_assignment.evidence",
		"recorder_assignment.resolutions",
	}
}

func guestOperationalStateTableCount(
	t *testing.T,
	ctx context.Context,
	database *sql.DB,
	table string,
) int {
	t.Helper()
	var count int
	if err := database.QueryRowContext(
		ctx,
		"SELECT count(*) FROM "+table,
	).Scan(&count); err != nil {
		t.Fatalf("count owner table %s: %v", table, err)
	}
	return count
}
