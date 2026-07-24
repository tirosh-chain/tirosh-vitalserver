package guestruntimecontrolhttpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupsqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestGuestOperationalStateHTTPAdmitsAndReadsDurableBackupOperation(
	t *testing.T,
) {
	ctx := context.Background()
	ledger, err := gueststatebackupsqliterepository.Open(
		ctx,
		filepath.Join(t.TempDir(), "guest-operational-state-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer ledger.Close()
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		ledger,
		unusedGuestOperationalStateStageExecutor{},
		fixedGuestOperationalStateClock{
			now: time.Date(2026, 7, 24, 22, 0, 1, 0, time.UTC),
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	server := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{
			GuestOperationalStateBackup: service,
		},
	)
	command := guestruntimedomain.GuestOperationalStateBackupCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "backup-http-request-1",
		OperationID:   "backup-http-operation-1",
		DestinationReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-backup-destination",
			ResourceID:   "backup-http-destination-1",
		},
		RequestedAt: "2026-07-24T22:00:00Z",
	}
	body, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/operational-state/backups",
		bytes.NewReader(body),
	)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var operation guestruntimedomain.GuestOperationalStateBackupOperation
	if err := json.Unmarshal(response.Body.Bytes(), &operation); err != nil {
		t.Fatal(err)
	}
	if operation.State != guestruntimedomain.GuestStateBackupRequestedState {
		t.Fatalf("operation=%+v", operation)
	}
	readRequest := httptest.NewRequest(
		http.MethodGet,
		"/v1/runtime/operational-state/operations/"+command.OperationID,
		nil,
	)
	readResponse := httptest.NewRecorder()
	server.ServeHTTP(readResponse, readRequest)
	if readResponse.Code != http.StatusOK ||
		!bytes.Contains(readResponse.Body.Bytes(), []byte(`"state":"available"`)) ||
		!bytes.Contains(
			readResponse.Body.Bytes(),
			[]byte(`"id":"backup-http-operation-1"`),
		) {
		t.Fatalf(
			"read status=%d body=%s",
			readResponse.Code,
			readResponse.Body.String(),
		)
	}
	advanced, ran, err := server.RunNextPendingGuestOperationalStateEffect(ctx)
	if err != nil || !ran ||
		advanced.State != guestruntimedomain.GuestStateBackupSnapshottingSQLiteState {
		t.Fatalf("advanced=%+v ran=%t err=%v", advanced, ran, err)
	}
}

func TestGuestOperationalStateHTTPRejectsMalformedRestoreWithoutAdmission(
	t *testing.T,
) {
	server := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{},
	)
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/operational-state/restores",
		bytes.NewBufferString(`{"schemaVersion":"v1"}`),
	)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestGuestOperationalStateHTTPKeepsRestoreUnavailableForBackupOnlyComposition(
	t *testing.T,
) {
	ledger, err := gueststatebackupsqliterepository.Open(
		context.Background(),
		filepath.Join(t.TempDir(), "guest-operational-state-ledger.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer ledger.Close()
	service, err := guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
		ledger,
		unusedGuestOperationalStateStageExecutor{},
		fixedGuestOperationalStateClock{now: time.Now()},
	)
	if err != nil {
		t.Fatal(err)
	}
	server := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{
			GuestOperationalStateBackup: service,
		},
	)
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/operational-state/restores",
		bytes.NewBufferString(`{"schemaVersion":"v1"}`),
	)
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable ||
		!bytes.Contains(
			response.Body.Bytes(),
			[]byte(`"code":"guest-operational-state-restore-owner-unavailable"`),
		) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

type unusedGuestOperationalStateStageExecutor struct{}

func (unusedGuestOperationalStateStageExecutor) ExecuteStage(
	context.Context,
	guestruntimedomain.GuestOperationalStateBackupOperation,
	string,
) (guestruntimeapplication.GuestOperationalStateBackupStageResult, error) {
	return guestruntimeapplication.GuestOperationalStateBackupStageResult{}, nil
}

type fixedGuestOperationalStateClock struct {
	now time.Time
}

func (clock fixedGuestOperationalStateClock) Now() time.Time {
	return clock.now
}
