package agent

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func TestRuntimeControllerRouteMapIsMethodScopedAndClosed(t *testing.T) {
	accepted := []struct {
		method string
		path   string
		target string
	}{
		{http.MethodGet, "/runtime/capabilities", "/runtime/capabilities"},
		{http.MethodGet, "/runtime/services", "/runtime/services"},
		{http.MethodGet, "/runtime/stack", "/runtime/stack"},
		{http.MethodGet, "/runtime/events", "/runtime/events"},
		{http.MethodGet, "/runtime/settings", "/runtime/settings"},
		{http.MethodPut, "/runtime/settings", "/runtime/settings"},
		{http.MethodPost, "/runtime/admin-password", "/runtime/admin-password"},
		{http.MethodGet, "/runtime/recorder-ingress/status", "/runtime/recorder-ingress/status"},
		{http.MethodGet, "/runtime/services/app/status", "/runtime/services/app/status"},
		{http.MethodGet, "/runtime/services/app/resource", "/runtime/services/app/resource"},
		{http.MethodPost, "/runtime/services/app/restart", "/runtime/services/app/restart"},
		{http.MethodGet, "/runtime/redis-relay/status", "/runtime/redis-relay/status"},
		{http.MethodGet, "/runtime/redis-relay/settings", "/runtime/redis-relay/settings"},
		{http.MethodPut, "/runtime/redis-relay/settings", "/runtime/redis-relay/settings"},
		{http.MethodPost, "/runtime/maintenance/datastore/repair", "/runtime/maintenance/datastore/repair"},
		{http.MethodGet, "/runtime/lab/scenarios", "/runtime/lab/scenarios"},
		{http.MethodPost, "/runtime/lab/sessions", "/runtime/lab/sessions"},
		{http.MethodPost, "/runtime/lab/sessions/session-1/start", "/runtime/lab/sessions/session-1/start"},
		{http.MethodGet, "/runtime/vitaldb/observations/latest", "/runtime/vitaldb/observations/latest"},
		{http.MethodPost, "/runtime/vitaldb/recorders/hide", "/runtime/vitaldb/recorders/hide"},
		{http.MethodGet, "/runtime/vitaldb/recorders/VR-A/activity", "/runtime/vitaldb/recorders/VR-A/activity"},
		{http.MethodGet, "/runtime/vitaldb/recorders/VR-A", "/runtime/vitaldb/recorders/VR-A"},
		{http.MethodGet, "/runtime/vitaldb/beds/BED-A", "/runtime/vitaldb/beds/BED-A"},
		{http.MethodGet, "/runtime/operations/op-1", "/runtime/operations/op-1"},
	}
	for _, item := range accepted {
		t.Run(item.method+" "+item.path, func(t *testing.T) {
			target, ok := runtimeControllerPath(item.method, item.path)
			if !ok || target != item.target {
				t.Fatalf("route=(%q,%v) want=(%q,true)", target, ok, item.target)
			}
		})
	}

	rejected := []struct{ method, path string }{
		{http.MethodPost, "/runtime/capabilities"},
		{http.MethodGet, "/runtime/overview"},
		{http.MethodPost, "/runtime/stack/reconcile"},
		{http.MethodPut, "/runtime/services/app/spec"},
		{http.MethodPost, "/runtime/services/app/observe"},
		{http.MethodGet, "/runtime/services/app/status/"},
		{http.MethodGet, "/runtime/services/../status"},
	}
	for _, item := range rejected {
		if target, ok := runtimeControllerPath(item.method, item.path); ok {
			t.Fatalf("unexpected route method=%s path=%s target=%s", item.method, item.path, target)
		}
	}
}

func TestRuntimeProxyUsesExplicitEndpointAndPreservesRuntimeResponse(t *testing.T) {
	var received struct {
		method, path, query, body, runtimeToken, authorization string
	}
	runtimeController := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Error(err)
		}
		received.method = request.Method
		received.path = request.URL.Path
		received.query = request.URL.RawQuery
		received.body = string(body)
		received.runtimeToken = request.Header.Get("X-Runtime-Control-Token")
		received.authorization = request.Header.Get("Authorization")
		response.Header().Set("X-Runtime-Owner", "runtime-controller")
		response.WriteHeader(http.StatusAccepted)
		_, _ = response.Write([]byte(`{"state":"accepted"}`))
	}))
	defer runtimeController.Close()

	address, port := serverAddress(t, runtimeController.URL)
	endpointPath := writeRuntimeEndpoint(t, address)
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeEndpointDocument: endpointPath,
		RuntimeControllerPort: port,
	}, stubServices{}, time.Now())
	request := httptest.NewRequest(
		http.MethodPost,
		"/runtime/lab/sessions?source=pwa",
		bytes.NewBufferString(`{"scenarioId":"basic"}`),
	)
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	request.Header.Set("Authorization", "Bearer test-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusAccepted || response.Header().Get("X-Runtime-Owner") != "runtime-controller" {
		t.Fatalf("proxy response code=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
	}
	if received.method != http.MethodPost || received.path != "/runtime/lab/sessions" || received.query != "source=pwa" {
		t.Fatalf("forwarded request=%+v", received)
	}
	if received.body != `{"scenarioId":"basic"}` {
		t.Fatalf("forwarded body=%s", received.body)
	}
	if received.runtimeToken != "" || received.authorization != "" {
		t.Fatalf("Platform credentials leaked to Runtime Controller: %+v", received)
	}
}

func TestRuntimeProxySeparatesUnavailableEndpointAndTransportFailure(t *testing.T) {
	root := t.TempDir()
	missingHandler := NewHandler(Config{
		APIToken: "test-token", RuntimeEndpointDocument: filepath.Join(root, "missing-endpoint.json"),
		RuntimeControllerPort: 18330,
	}, stubServices{}, time.Now())
	assertProxyError(t, missingHandler, http.StatusServiceUnavailable, "runtimeControllerUnavailable")

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address, portText, err := net.SplitHostPort(listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatal(err)
	}
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	transportHandler := NewHandler(Config{
		APIToken: "test-token", RuntimeEndpointDocument: writeRuntimeEndpoint(t, address),
		RuntimeControllerPort: port,
	}, stubServices{}, time.Now())
	assertProxyError(t, transportHandler, http.StatusBadGateway, "runtimeControllerTransportFailed")
}

func assertProxyError(t *testing.T, handler http.Handler, status int, code string) {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet, "/runtime/capabilities", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != status {
		t.Fatalf("status=%d want=%d body=%s", response.Code, status, response.Body.String())
	}
	var document contract.ErrorResponse
	if err := json.Unmarshal(response.Body.Bytes(), &document); err != nil {
		t.Fatal(err)
	}
	if document.Code != code || document.Message == "" {
		t.Fatalf("error=%+v", document)
	}
}

func writeRuntimeEndpoint(t *testing.T, address string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "runtime-endpoint.json")
	document := fmt.Sprintf(`{"address":%q,"source":"platform-agent","state":"loaded"}`, address)
	if err := os.WriteFile(path, []byte(document), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func serverAddress(t *testing.T, rawURL string) (string, int) {
	t.Helper()
	parsed, err := url.Parse(rawURL)
	if err != nil {
		t.Fatal(err)
	}
	address, portText, err := net.SplitHostPort(parsed.Host)
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatal(err)
	}
	return address, port
}
