package hostagentcontrolhttpapi_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/hoststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/updatebundlestore"
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

func (guest guest) ForwardStream(
	context.Context,
	hostagentdomain.GuestRuntimeControlEndpoint,
	hostagentapplication.GuestRuntimeControlHTTPStreamingRequest,
) (
	hostagentapplication.GuestRuntimeControlHTTPForwardedResponse,
	*hostagentapplication.GuestRuntimeControlHTTPForwardingFailure,
) {
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

func TestLabReplaySourceFacadeStreamsBeyondJSONCommandLimit(t *testing.T) {
	rawGuestBody := []byte(`{"schemaVersion":"v1","outcome":"accepted"}`)
	handler := newHandler(t, rawGuestBody)
	body := strings.NewReader(strings.Repeat("v", 2<<20))
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/lab/replay-sources",
		body,
	)
	request.Header.Set("Content-Type", "application/x-vital")
	request.Header.Set(
		"X-Vital-Lab-Replay-Source-Command",
		base64.RawURLEncoding.EncodeToString(
			[]byte(`{"requestId":"lab-replay-stream-1"}`),
		),
	)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if response.Body.String() != string(rawGuestBody) {
		t.Fatalf("Guest response changed: %q", response.Body.String())
	}
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

func TestHostFacadeImportsAndReadsAnExplicitUpdateBundleWithoutClaimingTrustVerification(t *testing.T) {
	repository, err := hoststatesqliterepository.OpenHostStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "host.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	lifecycle, err := hostagentapplication.NewHostAgentControlApplicationService(repository, provider{}, guest{}, hostagentapplication.SystemHostAgentClock{}, hostagentapplication.CryptoHostAgentRequestCorrelationIdentifierGenerator{})
	if err != nil {
		t.Fatal(err)
	}
	storeRoot := filepath.Join(t.TempDir(), "update-bundles")
	if err := os.Mkdir(storeRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	store, err := updatebundlestore.NewFileSystemStore(updatebundlestore.FileSystemStoreConfig{Directory: storeRoot, Clock: hostagentapplication.SystemHostAgentClock{}})
	if err != nil {
		t.Fatal(err)
	}
	bundles, err := hostagentapplication.NewHostUpdateBundleApplicationService(store, &hostagentapplication.HostUpdateApplicationService{}, hostagentapplication.SystemHostAgentClock{})
	if err != nil {
		t.Fatal(err)
	}
	handler := hostagentcontrolhttpapi.NewHostAgentControlHTTPServerWithModules(hostagentcontrolhttpapi.HostAgentControlHTTPModules{Lifecycle: lifecycle, Bundles: bundles})
	source := writeHTTPUpdateBundle(t)
	request := httptest.NewRequest(http.MethodPost, "/v1/platform/update-bundles:import", strings.NewReader(`{"schemaVersion":"v1","requestId":"import-020","sourceDirectory":"`+source+`"}`))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("import status=%d body=%s", response.Code, response.Body.String())
	}
	var receipt hostagentdomain.HostUpdateBundleImportReceipt
	if err := json.Unmarshal(response.Body.Bytes(), &receipt); err != nil {
		t.Fatalf("decode receipt: %v", err)
	}
	if receipt.State != "imported" || receipt.Bundle.State != "declared" || receipt.Bundle.ID != "release-bootstrap-020" {
		t.Fatalf("receipt=%+v", receipt)
	}
	readRequest := httptest.NewRequest(http.MethodGet, "/v1/platform/update-bundles/release-bootstrap-020", nil)
	readResponse := httptest.NewRecorder()
	handler.ServeHTTP(readResponse, readRequest)
	if readResponse.Code != http.StatusOK || !strings.Contains(readResponse.Body.String(), `"state":"available"`) || !strings.Contains(readResponse.Body.String(), `"state":"declared"`) {
		t.Fatalf("read status=%d body=%s", readResponse.Code, readResponse.Body.String())
	}
}

func writeHTTPUpdateBundle(t *testing.T) string {
	t.Helper()
	directory := filepath.Join(t.TempDir(), "release")
	if err := os.MkdirAll(filepath.Join(directory, "payload"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "payload", "host-updater"), []byte("updater"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "payload", "product-update.json"), []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	envelope := hostagentdomain.UpdateBootstrapEnvelope{
		SchemaVersion: "v1", ID: "release-bootstrap-020", ProductID: "vitalserver-runtime-platform",
		Target: hostagentdomain.UpdateTarget{Platform: "macos", Architecture: "arm64"}, TargetRelease: hostagentdomain.Release{ProductVersion: "0.2.0", RuntimeVersion: "0.2.0"},
		LayerOrder:          []string{hostagentdomain.UpdateLayerGuestRuntime, hostagentdomain.UpdateLayerHostPlatform},
		NextUpdaterArtifact: hostagentdomain.UpdateArtifact{ID: "host-updater-020", RelativePath: "payload/host-updater", SHA256: strings.Repeat("a", 64), SizeBytes: 1, MediaType: "application/octet-stream"},
		Specification:       hostagentdomain.UpdateArtifact{ID: "product-update-020", RelativePath: "payload/product-update.json", SHA256: strings.Repeat("b", 64), SizeBytes: 1, MediaType: "application/json"},
		Signature:           hostagentdomain.UpdateSignature{Algorithm: "ed25519", KeyID: "release-key-2026", SignedSHA256: strings.Repeat("c", 64), Value: "signature"},
		IssuedAt:            time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC).Format(time.RFC3339),
	}
	encoded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "bootstrap-envelope.json"), encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	return directory
}
