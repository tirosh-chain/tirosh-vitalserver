package gueststatesqliterepository

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestGuestRuntimeStateSQLiteOwnerCreatesConsistentOnlineSnapshot(t *testing.T) {
	ctx := context.Background()
	directory := t.TempDir()
	databasePath := filepath.Join(directory, "guest-runtime.sqlite")
	repository, err := OpenGuestRuntimeStateSQLiteRepository(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := repository.database.ExecContext(
		ctx,
		`INSERT INTO runtime_operations(
			id, request_id, command_digest, document_json
		) VALUES (?, ?, ?, ?)`,
		"snapshot-operation-1",
		"snapshot-request-1",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		`{"state":"succeeded"}`,
	); err != nil {
		t.Fatal(err)
	}
	snapshotPath := filepath.Join(directory, "snapshot.sqlite")
	receipt, err := repository.CreateOnlineSnapshot(ctx, snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	if receipt.DatabaseID == "" ||
		receipt.SchemaVersion != guestRuntimeStateSQLiteSchemaVersion ||
		receipt.ByteSize < 1 ||
		len(receipt.SHA256) != 64 {
		t.Fatalf("snapshot receipt=%+v", receipt)
	}
	snapshotDatabase, err := sql.Open("sqlite", snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	defer snapshotDatabase.Close()
	var operationID string
	if err := snapshotDatabase.QueryRowContext(
		ctx,
		`SELECT id FROM runtime_operations WHERE request_id = ?`,
		"snapshot-request-1",
	).Scan(&operationID); err != nil {
		t.Fatal(err)
	}
	if operationID != "snapshot-operation-1" {
		t.Fatalf("snapshot operation id=%q", operationID)
	}
	var snapshotDatabaseID string
	var snapshotSchemaVersion int
	if err := snapshotDatabase.QueryRowContext(
		ctx,
		`SELECT database_id, schema_version
		   FROM state_store_metadata
		  WHERE singleton = 1`,
	).Scan(&snapshotDatabaseID, &snapshotSchemaVersion); err != nil {
		t.Fatal(err)
	}
	if snapshotDatabaseID != receipt.DatabaseID ||
		snapshotSchemaVersion != receipt.SchemaVersion {
		t.Fatalf(
			"snapshot metadata databaseId=%q schemaVersion=%d receipt=%+v",
			snapshotDatabaseID,
			snapshotSchemaVersion,
			receipt,
		)
	}
	recovered, err := repository.CreateOnlineSnapshot(ctx, snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	if recovered != receipt {
		t.Fatalf("recovered snapshot receipt=%+v original=%+v", recovered, receipt)
	}
	if err := repository.Close(); err != nil {
		t.Fatal(err)
	}
	repository, err = OpenGuestRuntimeStateSQLiteRepository(ctx, databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	var reopenedDatabaseID string
	if err := repository.database.QueryRowContext(
		ctx,
		`SELECT database_id FROM state_store_metadata WHERE singleton = 1`,
	).Scan(&reopenedDatabaseID); err != nil {
		t.Fatal(err)
	}
	if reopenedDatabaseID != receipt.DatabaseID {
		t.Fatalf(
			"database identity changed after restart: before=%q after=%q",
			receipt.DatabaseID,
			reopenedDatabaseID,
		)
	}
}

func TestGuestRuntimeStateSQLiteRestorePreservesPublicOwnerReads(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	sourcePath := filepath.Join(root, "source.sqlite")
	source, err := OpenGuestRuntimeStateSQLiteRepository(ctx, sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	defer source.Close()
	ownerClock := fixedSQLiteBackupOwnerClock{
		now: time.Date(2026, 7, 24, 10, 0, 0, 0, time.UTC),
	}
	sourceHandler := sqliteBackupTopologyOwnerHandler(
		t,
		source,
		ownerClock,
	)
	command := guestruntimedomain.TopologyApplyCommand{
		SchemaVersion:            guestruntimedomain.SchemaVersion,
		RequestID:                "sqlite-backup-topology-request-1",
		TopologyID:               "sqlite-backup-topology-1",
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:  "external-upstream",
			ProviderKind: "vitalserver",
			EndpointReference: guestruntimedomain.ResourceReference{
				ResourceType: guestruntimedomain.ExternalUpstreamIntegrationResourceType,
				ResourceID:   "sqlite-backup-upstream-1",
			},
		},
	}
	payload, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	apply := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/topology:apply",
		bytes.NewReader(payload),
	)
	applyResponse := httptest.NewRecorder()
	sourceHandler.ServeHTTP(applyResponse, apply)
	if applyResponse.Code != http.StatusAccepted {
		t.Fatalf(
			"seed source topology status=%d body=%s",
			applyResponse.Code,
			applyResponse.Body.String(),
		)
	}
	var operation guestruntimedomain.Operation
	if err := json.Unmarshal(applyResponse.Body.Bytes(), &operation); err != nil {
		t.Fatal(err)
	}
	snapshotPath := filepath.Join(root, "snapshot.sqlite")
	snapshot, err := source.CreateOnlineSnapshot(ctx, snapshotPath)
	if err != nil {
		t.Fatal(err)
	}
	targetPath := filepath.Join(root, "target.sqlite")
	restoreOwner, err := gueststatesqliterestore.New(targetPath)
	if err != nil {
		t.Fatal(err)
	}
	expected := guestruntimedomain.GuestOperationalStateSQLiteSnapshotReceipt{
		DatabaseID:    snapshot.DatabaseID,
		SchemaVersion: snapshot.SchemaVersion,
		Snapshot: guestruntimedomain.GuestOperationalStateBackupSnapshotArtifact{
			Reference: guestruntimedomain.ResourceReference{
				ResourceType: "guest-backup-object",
				ResourceID:   "sqlite-public-owner-parity-1",
			},
			ByteSize: snapshot.ByteSize,
			SHA256:   snapshot.SHA256,
		},
	}
	if _, err := restoreOwner.ProveEmpty(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := restoreOwner.Restore(ctx, snapshotPath, expected); err != nil {
		t.Fatal(err)
	}
	if _, err := restoreOwner.Verify(ctx, expected); err != nil {
		t.Fatal(err)
	}
	target, err := OpenGuestRuntimeStateSQLiteRepository(ctx, targetPath)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	targetHandler := sqliteBackupTopologyOwnerHandler(
		t,
		target,
		ownerClock,
	)
	for _, path := range []string{
		"/v1/runtime/topology",
		"/v1/runtime/operations/" + operation.ID,
	} {
		sourceBody := readSQLiteBackupPublicOwner(t, sourceHandler, path)
		targetBody := readSQLiteBackupPublicOwner(t, targetHandler, path)
		if !bytes.Equal(sourceBody, targetBody) {
			t.Fatalf(
				"restored SQLite public owner read differs path=%s source=%s target=%s",
				path,
				sourceBody,
				targetBody,
			)
		}
	}
}

func sqliteBackupTopologyOwnerHandler(
	t *testing.T,
	repository *GuestRuntimeStateSQLiteRepository,
	clock fixedSQLiteBackupOwnerClock,
) http.Handler {
	t.Helper()
	service, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationService(
		repository,
		clock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		"sqlite-backup-acceptance",
		"sqlite-backup-owner-1",
	)
	if err != nil {
		t.Fatal(err)
	}
	return guestruntimecontrolhttpapi.NewGuestRuntimeTopologyHTTPServer(service)
}

func readSQLiteBackupPublicOwner(
	t *testing.T,
	handler http.Handler,
	path string,
) []byte {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet, path, nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf(
			"SQLite public owner read path=%s status=%d body=%s",
			path,
			response.Code,
			response.Body.String(),
		)
	}
	return response.Body.Bytes()
}

type fixedSQLiteBackupOwnerClock struct {
	now time.Time
}

func (clock fixedSQLiteBackupOwnerClock) Now() time.Time {
	return clock.now
}
