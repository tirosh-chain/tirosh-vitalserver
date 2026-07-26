package guestruntimecontrolhttpapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type operationalStatePostgreSQLIdentityHTTPStub struct{}

func (operationalStatePostgreSQLIdentityHTTPStub) ReadGuestOperationalStatePostgreSQLIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStatePostgreSQLIdentity, error) {
	return guestruntimedomain.GuestOperationalStatePostgreSQLIdentity{
		DatabaseID:      "guest-postgresql-00000000-0000-0000-0000-000000000001",
		AlembicRevision: "0006_backup_owner",
		OwnerSchemas: append(
			[]string(nil),
			guestruntimedomain.GuestOperationalStatePostgreSQLOwnerSchemas...,
		),
	}, nil
}

type operationalStateIdentityHTTPClock struct{}

func (operationalStateIdentityHTTPClock) Now() time.Time {
	return time.Date(2026, 7, 24, 23, 0, 0, 0, time.UTC)
}

type operationalStateBootstrapIdentityHTTPStub struct{}

func (operationalStateBootstrapIdentityHTTPStub) ReadGuestOperationalStateBootstrapIdentity(
	context.Context,
) (guestruntimedomain.GuestOperationalStateBootstrapIdentity, error) {
	return guestruntimedomain.GuestOperationalStateBootstrapIdentity{
		MigrationReceipt: guestruntimedomain.GuestOperationalStateMigrationReceipt{
			SchemaVersion: "v1",
			State:         "succeeded",
			Revision:      "0006_backup_owner",
			StartedAt:     "2026-07-24T22:59:00Z",
			FinishedAt:    "2026-07-24T22:59:05Z",
		},
		PrivateMaterialSet: guestruntimedomain.GuestOperationalStatePrivateMaterialSetIdentity{
			MaterialCount: 3,
			SHA256:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}, nil
}

func TestGuestOperationalStateIdentityHTTPReturnsGuestOwnerObservation(t *testing.T) {
	sqlite, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		context.Background(),
		filepath.Join(t.TempDir(), "guest.sqlite"),
	)
	if err != nil {
		t.Fatal(err)
	}
	defer sqlite.Close()
	service, err := guestruntimeapplication.NewGuestOperationalStateIdentityApplicationService(
		sqlite,
		operationalStatePostgreSQLIdentityHTTPStub{},
		operationalStateBootstrapIdentityHTTPStub{},
		operationalStateIdentityHTTPClock{},
	)
	if err != nil {
		t.Fatal(err)
	}
	server := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{
			GuestOperationalStateIdentity: service,
		},
	)
	response := httptest.NewRecorder()
	server.ServeHTTP(
		response,
		httptest.NewRequest(
			http.MethodGet,
			"/v1/runtime/operational-state/identity",
			nil,
		),
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var result guestruntimedomain.ReadResult
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.State != "available" {
		t.Fatalf("result=%+v", result)
	}
}
