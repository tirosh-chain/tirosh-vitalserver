package gueststatepostgresqlbackup

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

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestPostgreSQLLogicalBackupRestoresToExplicitEmptyDatabase(
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
			"explicit source URL, empty target URL, pg_dump, and pg_restore are required",
		)
	}
	ctx := context.Background()
	source, err := Open(ctx, Configuration{
		DatabaseURL:             sourceDatabaseURL,
		PGDumpExecutablePath:    pgDumpPath,
		PGRestoreExecutablePath: pgRestorePath,
		ExpectedAlembicRevision: gueststatepostgresqlrepository.ExpectedRecorderCatalogRevision,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	snapshotPath := filepath.Join(t.TempDir(), "guest-operational-state.dump")
	snapshot, err := source.CreateLogicalSnapshot(ctx, snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	expected := guestruntimedomain.GuestOperationalStatePostgreSQLSnapshotReceipt{
		DatabaseID:           snapshot.DatabaseID,
		AlembicRevision:      snapshot.AlembicRevision,
		IncludedOwnerSchemas: append([]string{}, snapshot.IncludedOwnerSchemas...),
		Snapshot: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-object",
				ResourceID:   "postgresql-empty-target-integration-1",
			},
			ByteSize: snapshot.ByteSize,
			SHA256:   snapshot.SHA256,
		},
	}
	target, err := gueststatepostgresqlrestore.Open(
		ctx,
		targetDatabaseURL,
		pgRestorePath,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	proof, err := target.ProveEmptyTarget(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if proof.State !=
		guestruntimedomain.GuestOperationalStatePostgreSQLRestoreTargetEmpty {
		t.Fatalf("empty-target proof=%+v", proof)
	}
	restoreSnapshot := gueststatepostgresqlrestore.Snapshot{
		DatabaseID:           expected.DatabaseID,
		AlembicRevision:      expected.AlembicRevision,
		IncludedOwnerSchemas: append([]string{}, expected.IncludedOwnerSchemas...),
		ByteSize:             expected.Snapshot.ByteSize,
		SHA256:               expected.Snapshot.SHA256,
	}
	if err := target.RestoreSnapshot(ctx, snapshotPath, restoreSnapshot); err != nil {
		t.Fatal(err)
	}
	if _, err := target.VerifyOwnerReads(ctx, restoreSnapshot); err != nil {
		t.Fatal(err)
	}
	sourceDatabase, err := sql.Open("pgx", sourceDatabaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer sourceDatabase.Close()
	targetDatabase, err := sql.Open("pgx", targetDatabaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer targetDatabase.Close()
	for _, table := range []string{
		"recorder_catalog.admission_requests",
		"recorder_catalog.observations",
		"recorder_catalog.recorder_current",
		"recorder_catalog.expectation_events",
		"recorder_catalog.recorder_expectations",
		"archive_export.artifacts",
		"archive_export.recorder_attributions",
		"archive_export.upload_attempts",
		"archive_export.indexing_receipts",
		"archive_export.source_admission_requests",
		"recorder_assignment.evidence",
		"recorder_assignment.resolutions",
		"guest_operational_state.metadata",
		"public.alembic_version",
	} {
		sourceCount := postgreSQLIntegrationTableCount(
			t,
			ctx,
			sourceDatabase,
			table,
		)
		targetCount := postgreSQLIntegrationTableCount(
			t,
			ctx,
			targetDatabase,
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
	for _, table := range []string{
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
	} {
		if postgreSQLIntegrationTableCount(
			t,
			ctx,
			targetDatabase,
			table,
		) < 1 {
			t.Fatalf("restored owner evidence table is empty: %s", table)
		}
	}
	proveRestoredPublicOwnerAPIParity(
		t,
		sourceDatabaseURL,
		targetDatabaseURL,
		sourceDatabase,
	)
	if err := target.RestoreSnapshot(
		ctx,
		snapshotPath,
		restoreSnapshot,
	); err == nil {
		t.Fatal("second restore must reject the non-empty target")
	} else if !errors.Is(err, gueststatepostgresqlrestore.ErrTargetNotEmpty) {
		t.Fatalf("second restore error=%v", err)
	}
}

func proveRestoredPublicOwnerAPIParity(
	t *testing.T,
	sourceDatabaseURL string,
	targetDatabaseURL string,
	sourceDatabase *sql.DB,
) {
	t.Helper()
	observedAt := time.Now().UTC()
	sourceHandler, closeSource := openPostgreSQLPublicOwnerReadHandler(
		t,
		sourceDatabaseURL,
		observedAt,
	)
	defer closeSource()
	targetHandler, closeTarget := openPostgreSQLPublicOwnerReadHandler(
		t,
		targetDatabaseURL,
		observedAt,
	)
	defer closeTarget()

	recorderPage := comparePublicOwnerRead(
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
		t.Fatalf("decode restored Recorder owner page: %v", err)
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
			comparePublicOwnerRead(
				t,
				sourceHandler,
				targetHandler,
				"/v1/runtime/recorders/"+recorder.RecorderID+suffix,
			)
		}
	}
	matchedRecorderIDs := postgreSQLIntegrationMatchedRecorderIDs(
		t,
		context.Background(),
		sourceDatabase,
	)
	if len(matchedRecorderIDs) == 0 {
		t.Fatal("source fixture has no matched Archive attribution owner evidence")
	}
	for _, recorderID := range matchedRecorderIDs {
		artifactPage := comparePublicOwnerRead(
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
			t.Fatalf("decode restored Recorder artifact page: %v", err)
		}
		if artifacts.State != "available" {
			t.Fatalf("restored Recorder artifact owner read failed: %s", artifactPage)
		}
		if len(artifacts.Value.Items) == 0 {
			t.Fatalf(
				"restored Recorder artifact owner page has no evidence: %s",
				artifactPage,
			)
		}
		for _, detail := range artifacts.Value.Items {
			comparePublicOwnerRead(
				t,
				sourceHandler,
				targetHandler,
				"/v1/runtime/artifacts/"+detail.Artifact.ArtifactID,
			)
		}
	}
}

func postgreSQLIntegrationMatchedRecorderIDs(
	t *testing.T,
	ctx context.Context,
	database *sql.DB,
) []string {
	t.Helper()
	rows, err := database.QueryContext(
		ctx,
		`SELECT DISTINCT matched_recorder_id
		   FROM archive_export.recorder_attributions
		  WHERE outcome = 'matched'
		    AND matched_recorder_id IS NOT NULL
		  ORDER BY matched_recorder_id`,
	)
	if err != nil {
		t.Fatalf("read source matched Recorder fixture identities: %v", err)
	}
	defer rows.Close()
	var recorderIDs []string
	for rows.Next() {
		var recorderID string
		if err := rows.Scan(&recorderID); err != nil {
			t.Fatalf("scan source matched Recorder fixture identity: %v", err)
		}
		recorderIDs = append(recorderIDs, recorderID)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate source matched Recorder fixture identities: %v", err)
	}
	return recorderIDs
}

func openPostgreSQLPublicOwnerReadHandler(
	t *testing.T,
	databaseURL string,
	observedAt time.Time,
) (http.Handler, func()) {
	t.Helper()
	ctx := context.Background()
	catalogRepository, err :=
		gueststatepostgresqlrepository.OpenRecorderCatalogPostgreSQLRepository(
			ctx,
			databaseURL,
		)
	if err != nil {
		t.Fatalf("open restored Recorder Catalog owner: %v", err)
	}
	archiveRepository, err :=
		gueststatepostgresqlrepository.OpenArchiveExportPostgreSQLRepository(
			ctx,
			databaseURL,
		)
	if err != nil {
		_ = catalogRepository.Close()
		t.Fatalf("open restored Archive lineage owner: %v", err)
	}
	clock := fixedPostgreSQLBackupIntegrationClock{now: observedAt}
	catalogService, err :=
		guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
			catalogRepository,
			clock,
			guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
			guestruntimedomain.RecorderObservationFreshnessPolicy{
				MaxReportAgeSeconds: 300,
			},
		)
	if err != nil {
		_ = archiveRepository.Close()
		_ = catalogRepository.Close()
		t.Fatalf("compose restored Recorder Catalog owner API: %v", err)
	}
	archiveService, err :=
		guestruntimeapplication.NewGuestRuntimeArchiveLineageApplicationService(
			archiveRepository,
			clock,
		)
	if err != nil {
		_ = archiveRepository.Close()
		_ = catalogRepository.Close()
		t.Fatalf("compose restored Archive lineage owner API: %v", err)
	}
	handler := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{
			RecorderObservationCatalog: catalogService,
			ArchiveLineage:             archiveService,
		},
	)
	return handler, func() {
		if err := errors.Join(
			archiveRepository.Close(),
			catalogRepository.Close(),
		); err != nil {
			t.Errorf("close restored owner repositories: %v", err)
		}
	}
}

func comparePublicOwnerRead(
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

type fixedPostgreSQLBackupIntegrationClock struct {
	now time.Time
}

func (clock fixedPostgreSQLBackupIntegrationClock) Now() time.Time {
	return clock.now
}

func postgreSQLIntegrationTableCount(
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
