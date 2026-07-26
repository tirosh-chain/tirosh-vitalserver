package agent

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

func TestPlatformResourcePutWritesAndReturnsDurableOwnerState(t *testing.T) {
	root := t.TempDir()
	providerPath := filepath.Join(root, "runtime-provider.json")
	endpointPath := filepath.Join(root, "runtime-endpoint.json")
	handler := NewHandler(Config{
		APIToken:                "test-token",
		RuntimeProviderDocument: providerPath,
		RuntimeEndpointDocument: endpointPath,
	}, stubServices{}, time.Now())

	providerRequest := httptest.NewRequest(
		http.MethodPut,
		"/platform/runtime-provider",
		strings.NewReader(`{"document":{"schemaVersion":1,"state":"running","operation":null,"operationID":null,"bootID":null,"startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":null}}`),
	)
	providerRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	providerResponse := httptest.NewRecorder()
	handler.ServeHTTP(providerResponse, providerRequest)
	if providerResponse.Code != http.StatusOK {
		t.Fatalf("provider PUT status=%d body=%s", providerResponse.Code, providerResponse.Body.String())
	}
	if state := owner.ReadRuntimeProvider(providerPath); state.State != "loaded" {
		t.Fatalf("provider owner state=%+v", state)
	}

	endpointRequest := httptest.NewRequest(
		http.MethodPut,
		"/platform/runtime-endpoint",
		strings.NewReader(`{"address":"127.0.0.1"}`),
	)
	endpointRequest.Header.Set("Authorization", "Bearer test-token")
	endpointResponse := httptest.NewRecorder()
	handler.ServeHTTP(endpointResponse, endpointRequest)
	if endpointResponse.Code != http.StatusOK {
		t.Fatalf("endpoint PUT status=%d body=%s", endpointResponse.Code, endpointResponse.Body.String())
	}
	if state := owner.ReadEndpoint(endpointPath); state.State != "loaded" {
		t.Fatalf("endpoint owner state=%+v", state)
	}
}

func TestPlatformResourcePutRejectsIncompleteOrUnknownInputWithoutMutation(t *testing.T) {
	root := t.TempDir()
	providerPath := filepath.Join(root, "runtime-provider.json")
	if err := owner.WriteRuntimeProvider(providerPath, providerDocumentForRequest("stopped")); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		APIToken:                "test-token",
		RuntimeProviderDocument: providerPath,
		RuntimeEndpointDocument: filepath.Join(root, "runtime-endpoint.json"),
	}, stubServices{}, time.Now())
	request := httptest.NewRequest(
		http.MethodPut,
		"/platform/runtime-provider",
		strings.NewReader(`{"document":{"state":"running"},"fallback":true}`),
	)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	resource := owner.ReadRuntimeProvider(providerPath)
	if !strings.Contains(string(resource.Document), `"state":"stopped"`) {
		t.Fatalf("invalid request changed owner state: %s", resource.Document)
	}
}

func providerDocumentForRequest(state string) []byte {
	return []byte(`{"schemaVersion":1,"state":"` + state + `","operation":null,"operationID":null,"bootID":null,"startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":null}`)
}
