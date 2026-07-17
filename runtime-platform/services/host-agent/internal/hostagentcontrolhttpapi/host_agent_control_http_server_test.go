package hostagentcontrolhttpapi_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentcontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type provider struct{}

func (provider) Execute(_ context.Context, invocation hostagentdomain.PlatformProviderLifecycleInvocation) hostagentdomain.ProviderLifecycleResult {
	request := invocation.Lifecycle
	return hostagentdomain.ProviderLifecycleResult{SchemaVersion: "v1", RequestID: request.RequestID, ProviderID: request.ProviderID, ObservedState: "running", ObservedAt: "2026-07-17T00:00:00Z"}
}

type guest struct {
	body       []byte
	statusCode int
}

func (guest) Probe(context.Context, hostagentdomain.GuestRuntimeControlEndpoint) hostagentapplication.GuestRuntimeControlHTTPProbeResult {
	return hostagentapplication.GuestRuntimeControlHTTPProbeResult{Reachable: true}
}

func (guest guest) Forward(context.Context, hostagentdomain.GuestRuntimeControlEndpoint, string, string, []byte, string) (hostagentapplication.GuestRuntimeControlHTTPForwardedResponse, *hostagentapplication.GuestRuntimeControlHTTPForwardingFailure) {
	statusCode := guest.statusCode
	if statusCode == 0 {
		statusCode = http.StatusOK
	}
	return hostagentapplication.GuestRuntimeControlHTTPForwardedResponse{StatusCode: statusCode, ContentType: "application/json; charset=utf-8", Body: guest.body}, nil
}

func newHandlerWithRepository(t *testing.T, repository hostagentapplication.HostAgentControlStateRepository, rawGuestBody []byte) http.Handler {
	return newHandlerWithGuestResponse(t, repository, http.StatusOK, rawGuestBody)
}

func newHandlerWithGuestResponse(t *testing.T, repository hostagentapplication.HostAgentControlStateRepository, guestStatus int, rawGuestBody []byte) http.Handler {
	t.Helper()
	service, err := hostagentapplication.NewHostAgentControlApplicationService(repository, provider{}, guest{body: rawGuestBody, statusCode: guestStatus}, hostagentapplication.SystemHostAgentClock{}, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		t.Fatalf("new Host service: %v", err)
	}
	if err := service.InitializeHostAgentControlState(context.Background(), hostagentapplication.HostAgentControlStateInitialization{
		InstallationID:                "host-installation",
		ProductVersion:                "test",
		RuntimeVersion:                "test",
		DataDirectory:                 "/var/lib/vitalserver-helper",
		GuestRuntimeControlEndpointID: "guest-control",
		GuestRuntimeControlHTTPScheme: "http",
		GuestRuntimeControlHTTPHost:   "127.0.0.1",
		GuestRuntimeControlHTTPPort:   18443,
		ProviderKind:                  "macos-virtualization",
		ProviderID:                    "guest-vm",
	}); err != nil {
		t.Fatalf("configure Host service: %v", err)
	}
	return hostagentcontrolhttpapi.NewHostAgentControlHTTPServer(service)
}

func newHandler(t *testing.T, rawGuestBody []byte) http.Handler {
	t.Helper()
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "host.sqlite"))
	if err != nil {
		t.Fatalf("open Host state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	return newHandlerWithRepository(t, repository, rawGuestBody)
}

func TestGuestFacadeDoesNotDecodeOrRewriteSuccessfulGuestResponse(t *testing.T) {
	rawGuestBody := []byte("{\n  \"schemaVersion\": \"v1\",\n  \"state\": \"available\",\n  \"value\": { \"preserve\": true }\n}\n")
	handler := newHandler(t, rawGuestBody)
	request := httptest.NewRequest(http.MethodGet, "/v1/runtime/readiness", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	if response.Header().Get("Content-Type") != "application/json; charset=utf-8" {
		t.Fatalf("content type = %q", response.Header().Get("Content-Type"))
	}
	if response.Body.String() != string(rawGuestBody) {
		t.Fatalf("Host facade rewrote Guest response:\nwant %q\n got %q", string(rawGuestBody), response.Body.String())
	}
}

func TestHostFacadeForwardsPublishedOperationalRuntimeRoutesWithoutRewriting(t *testing.T) {
	rawGuestBody := []byte(`{"schemaVersion":"v1"}`)
	handler := newHandler(t, rawGuestBody)
	request := httptest.NewRequest(http.MethodGet, "/v1/time/clock-quality", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	if response.Body.String() != string(rawGuestBody) {
		t.Fatalf("Host facade rewrote published Guest response:\nwant %q\n got %q", string(rawGuestBody), response.Body.String())
	}
}

func TestGuestFacadePreservesTypedGuestAdmissionFailureResponse(t *testing.T) {
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "host.sqlite"))
	if err != nil {
		t.Fatalf("open Host state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	rawGuestBody := []byte("{\n  \"schemaVersion\": \"v1\",\n  \"state\": \"failed\",\n  \"requestId\": \"topology-apply-1\",\n  \"observedAt\": \"2026-07-17T00:00:00Z\",\n  \"admissionState\": \"unknown\",\n  \"issue\": { \"code\": \"guest-state-store-write-outcome-unknown\" }\n}\n")
	handler := newHandlerWithGuestResponse(t, repository, http.StatusInternalServerError, rawGuestBody)
	request := httptest.NewRequest(http.MethodPost, "/v1/runtime/topology:apply", strings.NewReader(`{
  "schemaVersion": "v1",
  "requestId": "topology-apply-1",
  "topologyId": "primary-topology",
  "expectedResourceRevision": 0,
  "spec": {
    "profileKind": "external-upstream",
    "providerKind": "vitalserver",
    "endpointReference": { "resourceType": "upstream-endpoint", "resourceId": "primary" }
  }
}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	if response.Body.String() != string(rawGuestBody) {
		t.Fatalf("Host facade rewrote Guest admission failure:\nwant %q\n got %q", string(rawGuestBody), response.Body.String())
	}
}

type createFailureRepository struct {
	hostagentapplication.HostAgentControlStateRepository
}

func (repository createFailureRepository) PersistNewHostOperation(context.Context, hostagentdomain.Operation) error {
	return errors.New("simulated Host state write failure")
}

func TestLifecycleAdmissionFailureUsesTypedPublicResponse(t *testing.T) {
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "host.sqlite"))
	if err != nil {
		t.Fatalf("open Host state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	handler := newHandlerWithRepository(t, createFailureRepository{HostAgentControlStateRepository: repository}, []byte(`{"schemaVersion":"v1"}`))
	request := httptest.NewRequest(http.MethodPost, "/v1/platform/guest:start", strings.NewReader(`{
  "schemaVersion": "v1",
  "requestId": "host-start-1",
  "guestRuntimeControlEndpointId": "guest-control",
  "expectedResourceRevision": 1,
  "action": "start"
}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	var failure hostagentdomain.CommandAdmissionFailure
	if err := json.Unmarshal(response.Body.Bytes(), &failure); err != nil {
		t.Fatalf("decode failure response: %v body=%s", err, response.Body.String())
	}
	if failure.State != "failed" || failure.AdmissionState != "unknown" || failure.Issue.Code != "host-state-store-write-outcome-unknown" {
		t.Fatalf("failure = %+v", failure)
	}
}
