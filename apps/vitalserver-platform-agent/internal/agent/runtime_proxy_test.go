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
	"strings"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func TestRuntimeControllerRouteMapIsMethodScopedAndClosed(t *testing.T) {
	seen := map[string]struct{}{}
	for _, route := range runtimeControllerRoutes {
		route := route
		t.Run(route.method+" "+route.template, func(t *testing.T) {
			key := route.method + " " + route.template
			if _, exists := seen[key]; exists {
				t.Fatalf("duplicate closed forwarding route: %s", key)
			}
			seen[key] = struct{}{}
			path := runtimeControllerConcreteRoutePath(route.template)
			target, ok := runtimeControllerPath(route.method, path)
			if !ok || target != path {
				t.Fatalf("route=(%q,%v) want=(%q,true)", target, ok, path)
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

func TestRuntimeControllerRouteMapIncludesForwardedReadCoreManifestRoutes(t *testing.T) {
	type manifestRoute struct {
		Owner    string `json:"owner"`
		Delivery string `json:"delivery"`
		Method   string `json:"method"`
		Path     string `json:"path"`
	}
	type manifest struct {
		Routes []manifestRoute `json:"routes"`
	}

	manifestPath := filepath.Join("..", "..", "..", "..", "docs", "runtime", "runtime-v2-route-manifest.json")
	data, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatalf("read Runtime v2 route manifest: %v", err)
	}
	var document manifest
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatalf("decode Runtime v2 route manifest: %v", err)
	}

	allowed := make(map[string]struct{}, len(runtimeControllerRoutes))
	for _, route := range runtimeControllerRoutes {
		allowed[route.method+" "+route.template] = struct{}{}
	}
	for _, route := range document.Routes {
		if route.Owner != "runtime-controller" || route.Delivery != "forwarded" {
			continue
		}
		key := route.Method + " " + route.Path
		if _, ok := allowed[key]; !ok {
			t.Fatalf("Runtime v2 manifest forwarded route is not in Platform Agent allowlist: %s", key)
		}
	}
}

func runtimeControllerConcreteRoutePath(template string) string {
	replacements := strings.NewReplacer(
		"{service}", "app",
		"{sessionID}", "session-1",
		"{recorderID}", "recorder-1",
		"{vrcode}", "VR-A",
		"{bedID}", "BED-A",
		"{operationID}", "op-1",
	)
	return replacements.Replace(template)
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
