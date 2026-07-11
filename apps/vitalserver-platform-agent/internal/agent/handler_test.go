package agent

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func TestPlatformDeliveryRoutesPublishDurableWorkflow(t *testing.T) {
	root := t.TempDir()
	bundle := filepath.Join(root, "update.tar.gz")
	if err := os.WriteFile(bundle, []byte("bundle"), 0o600); err != nil {
		t.Fatal(err)
	}
	workflow := filepath.Join(root, "platform-workflow.json")
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument:    workflow,
			UpdateTool:          "update-linux.py",
			SchedulerExecutable: "systemd-run",
			SchedulerKind:       DeliverySchedulerSystemdTransient,
			ApplyPolicy:         DeliveryApplyPolicyVerifyOnly,
		},
	}, stubServices{}, time.Now())
	runner := &stubDeliveryRunner{output: []byte(`{"summary":"VitalServer Linux 2.0.0"}`)}
	handler.delivery.runner = runner

	requestBody := []byte(fmt.Sprintf(`{"bundle":{"kind":"localPath","value":%q}}`, bundle))
	summaryRequest := httptest.NewRequest(http.MethodPost, "/platform/update-bundles/summary", bytes.NewReader(requestBody))
	summaryRequest.Header.Set("Authorization", "Bearer test-token")
	summaryResponse := httptest.NewRecorder()
	handler.ServeHTTP(summaryResponse, summaryRequest)
	if summaryResponse.Code != http.StatusOK || !strings.Contains(summaryResponse.Body.String(), "VitalServer Linux 2.0.0") {
		t.Fatalf("summary status=%d body=%s", summaryResponse.Code, summaryResponse.Body.String())
	}

	verifyRequest := httptest.NewRequest(http.MethodPost, "/platform/update-bundles/verify", bytes.NewReader(requestBody))
	verifyRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	verifyResponse := httptest.NewRecorder()
	handler.ServeHTTP(verifyResponse, verifyRequest)
	if verifyResponse.Code != http.StatusAccepted {
		t.Fatalf("verify status=%d body=%s", verifyResponse.Code, verifyResponse.Body.String())
	}
	var operation contract.PlatformWorkflowOperation
	if err := json.Unmarshal(verifyResponse.Body.Bytes(), &operation); err != nil {
		t.Fatal(err)
	}
	if operation.State != "accepted" || operation.Kind != "update-verify" {
		t.Fatalf("unexpected verify operation: %+v", operation)
	}

	currentRequest := httptest.NewRequest(http.MethodGet, "/platform/workflows/current", nil)
	currentRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	currentResponse := httptest.NewRecorder()
	handler.ServeHTTP(currentResponse, currentRequest)
	if currentResponse.Code != http.StatusOK || !strings.Contains(currentResponse.Body.String(), operation.OperationID) {
		t.Fatalf("current status=%d body=%s", currentResponse.Code, currentResponse.Body.String())
	}
}

func TestStaticPWAGetsLoopbackBrowserSessionWithoutInstalledAPIToken(t *testing.T) {
	pwa := t.TempDir()
	const installedToken = "installer-owned-secret"
	if err := os.WriteFile(filepath.Join(pwa, "index.html"), []byte("<html>Runtime PWA</html>"), 0o600); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		ListenAddress: "127.0.0.1:18321",
		APIToken:      installedToken,
		PWA:           pwa,
	}, stubServices{}, time.Now())

	staticRequest := httptest.NewRequest(http.MethodGet, "/", nil)
	staticResponse := httptest.NewRecorder()
	handler.ServeHTTP(staticResponse, staticRequest)
	if staticResponse.Code != http.StatusOK || strings.Contains(staticResponse.Body.String(), installedToken) {
		t.Fatalf("static PWA response must not expose the installed API token: status=%d body=%s", staticResponse.Code, staticResponse.Body.String())
	}

	bootstrapRequest := httptest.NewRequest(http.MethodPost, browserSessionBootstrapPath, nil)
	bootstrapRequest.Header.Set("Origin", "http://127.0.0.1:18321")
	bootstrapResponse := httptest.NewRecorder()
	handler.ServeHTTP(bootstrapResponse, bootstrapRequest)
	if bootstrapResponse.Code != http.StatusNoContent || bootstrapResponse.Body.Len() != 0 {
		t.Fatalf("browser bootstrap status=%d body=%q", bootstrapResponse.Code, bootstrapResponse.Body.String())
	}
	cookies := bootstrapResponse.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != browserSessionCookieName || !cookies[0].HttpOnly ||
		cookies[0].SameSite != http.SameSiteStrictMode || strings.Contains(cookies[0].Value, installedToken) {
		t.Fatalf("browser session cookie must be opaque and HttpOnly: %+v", cookies)
	}

	readRequest := httptest.NewRequest(http.MethodGet, "/platform/capabilities", nil)
	readRequest.AddCookie(cookies[0])
	readResponse := httptest.NewRecorder()
	handler.ServeHTTP(readResponse, readRequest)
	if readResponse.Code != http.StatusOK {
		t.Fatalf("session-authenticated PWA read status=%d body=%s", readResponse.Code, readResponse.Body.String())
	}

	unsafeRequest := httptest.NewRequest(http.MethodPost, "/platform/uninstall", nil)
	unsafeRequest.AddCookie(cookies[0])
	unsafeRequest.Header.Set("Origin", "http://127.0.0.1:5174")
	unsafeResponse := httptest.NewRecorder()
	handler.ServeHTTP(unsafeResponse, unsafeRequest)
	if unsafeResponse.Code != http.StatusUnauthorized {
		t.Fatalf("cross-origin session mutation status=%d body=%s", unsafeResponse.Code, unsafeResponse.Body.String())
	}
}

func TestBrowserSessionBootstrapRejectsCrossOriginRequest(t *testing.T) {
	pwa := t.TempDir()
	if err := os.WriteFile(filepath.Join(pwa, "index.html"), []byte("<html>Runtime PWA</html>"), 0o600); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		ListenAddress: "127.0.0.1:18321",
		APIToken:      "installer-owned-secret",
		PWA:           pwa,
	}, stubServices{}, time.Now())

	request := httptest.NewRequest(http.MethodPost, browserSessionBootstrapPath, nil)
	request.Header.Set("Origin", "https://attacker.example")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized || response.Header().Get("Set-Cookie") != "" ||
		!strings.Contains(response.Body.String(), "browserSessionOriginInvalid") {
		t.Fatalf("cross-origin bootstrap status=%d headers=%v body=%s", response.Code, response.Header(), response.Body.String())
	}
}

func TestProtectedRoutesDoNotTreatAnEmptyConfiguredTokenAsCredentials(t *testing.T) {
	handler := NewHandler(Config{}, stubServices{}, time.Now())
	request := httptest.NewRequest(http.MethodGet, "/platform/capabilities", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("empty token protected route status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestPlatformDeliveryKeepsApplyUnavailableWithoutTrustedPublisherPolicy(t *testing.T) {
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument: filepath.Join(t.TempDir(), "workflow.json"),
			UpdateTool:       "update-linux.py", SchedulerExecutable: "systemd-run",
			SchedulerKind: DeliverySchedulerSystemdTransient,
			ApplyPolicy:   DeliveryApplyPolicyVerifyOnly,
		},
	}, stubServices{}, time.Now())
	request := httptest.NewRequest(http.MethodPost, "/platform/update-bundles/apply", strings.NewReader(`{}`))
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusNotImplemented || !strings.Contains(response.Body.String(), "updateApplyUnavailable") {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestPlatformDeliverySchedulesReleaseRollbackIndependentlyOfApplyTrust(t *testing.T) {
	root := t.TempDir()
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument: filepath.Join(root, "workflow.json"),
			UpdateTool:       "update-linux.py", RollbackTool: "rollback-linux.py",
			SchedulerExecutable: "systemd-run", ApplyPolicy: DeliveryApplyPolicyVerifyOnly,
			SchedulerKind: DeliverySchedulerSystemdTransient,
		},
	}, stubServices{}, time.Now())
	handler.delivery.runner = &stubDeliveryRunner{}
	request := httptest.NewRequest(http.MethodPost, "/platform/releases/rollback", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"kind":"rollback"`) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestPlatformDeliverySchedulesExplicitUninstallMode(t *testing.T) {
	root := t.TempDir()
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument: filepath.Join(root, "workflow.json"),
			UninstallTool:    "uninstall-windows.ps1", SchedulerExecutable: "powershell.exe",
			SchedulerScript: "schedule-workflow-windows.ps1", SchedulerKind: DeliverySchedulerWindowsTask,
			ApplyPolicy: DeliveryApplyPolicyVerifyOnly,
		},
	}, stubServices{}, time.Now())
	handler.delivery.runner = &stubDeliveryRunner{}

	request := httptest.NewRequest(http.MethodPost, "/platform/uninstall", strings.NewReader(`{"mode":"clean"}`))
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"kind":"uninstall"`) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}

	invalidRequest := httptest.NewRequest(http.MethodPost, "/platform/uninstall", strings.NewReader(`{"mode":"unknown"}`))
	invalidRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	invalidResponse := httptest.NewRecorder()
	handler.ServeHTTP(invalidResponse, invalidRequest)
	if invalidResponse.Code != http.StatusBadRequest || !strings.Contains(invalidResponse.Body.String(), "uninstallRequestInvalid") {
		t.Fatalf("status=%d body=%s", invalidResponse.Code, invalidResponse.Body.String())
	}
}

func TestPlatformDeliveryPublishesAndSchedulesSupportExport(t *testing.T) {
	root := t.TempDir()
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument:  filepath.Join(root, "workflow.json"),
			SupportExportTool: "support-export-linux.py", SchedulerExecutable: "systemd-run",
			SchedulerKind: DeliverySchedulerSystemdTransient, ApplyPolicy: DeliveryApplyPolicyVerifyOnly,
		},
	}, stubServices{}, time.Now())
	handler.delivery.runner = &stubDeliveryRunner{}

	capabilityRequest := httptest.NewRequest(http.MethodGet, "/platform/capabilities", nil)
	capabilityRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	capabilityResponse := httptest.NewRecorder()
	handler.ServeHTTP(capabilityResponse, capabilityRequest)
	if capabilityResponse.Code != http.StatusOK || !strings.Contains(capabilityResponse.Body.String(), `"canExportLogs":true`) {
		t.Fatalf("capabilities status=%d body=%s", capabilityResponse.Code, capabilityResponse.Body.String())
	}

	request := httptest.NewRequest(http.MethodPost, "/platform/support-exports", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"kind":"support-export"`) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestPlatformDeliveryAppliesOnlyAllowlistedBundleDigest(t *testing.T) {
	root := t.TempDir()
	bundle := filepath.Join(root, "update.tar.gz")
	inbox := filepath.Join(root, "trusted-inbox")
	if err := os.WriteFile(bundle, []byte("trusted bundle"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(inbox, 0o700); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256([]byte("trusted bundle"))
	digests := filepath.Join(root, "trusted-bundle-digests.json")
	if err := os.WriteFile(digests, []byte(fmt.Sprintf(`{"schemaVersion":1,"sha256":["%x"]}`, digest)), 0o600); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		APIToken: "test-token",
		Delivery: &DeliveryConfig{
			WorkflowDocument: filepath.Join(root, "workflow.json"),
			UpdateTool:       "update-linux.py", SchedulerExecutable: "systemd-run",
			SchedulerKind:        DeliverySchedulerSystemdTransient,
			ApplyPolicy:          DeliveryApplyPolicySHA256Allowlist,
			TrustedBundleDigests: digests,
			TrustedBundleInbox:   inbox,
		},
	}, stubServices{}, time.Now())
	handler.delivery.runner = &stubDeliveryRunner{}

	capabilityRequest := httptest.NewRequest(http.MethodGet, "/platform/capabilities", nil)
	capabilityRequest.Header.Set("X-Runtime-Control-Token", "test-token")
	capabilityResponse := httptest.NewRecorder()
	handler.ServeHTTP(capabilityResponse, capabilityRequest)
	if !strings.Contains(capabilityResponse.Body.String(), `"canApplyBundle":true`) {
		t.Fatalf("capabilities body=%s", capabilityResponse.Body.String())
	}

	body := []byte(fmt.Sprintf(`{"bundle":{"kind":"localPath","value":%q}}`, bundle))
	request := httptest.NewRequest(http.MethodPost, "/platform/update-bundles/apply", bytes.NewReader(body))
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted || !strings.Contains(response.Body.String(), `"kind":"update-apply"`) {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestPlatformDeliveryRejectsNonLocalAndRelativeBundleReferences(t *testing.T) {
	for name, body := range map[string]string{
		"remote":   `{"bundle":{"kind":"remoteURL","value":"https://example.test/update.tar.gz"}}`,
		"relative": `{"bundle":{"kind":"localPath","value":"update.tar.gz"}}`,
	} {
		t.Run(name, func(t *testing.T) {
			handler := NewHandler(Config{
				APIToken: "test-token",
				Delivery: &DeliveryConfig{WorkflowDocument: filepath.Join(t.TempDir(), "workflow.json"), UpdateTool: "update", SchedulerExecutable: "schedule", SchedulerKind: DeliverySchedulerSystemdTransient, ApplyPolicy: DeliveryApplyPolicyVerifyOnly},
			}, stubServices{}, time.Now())
			request := httptest.NewRequest(http.MethodPost, "/platform/update-bundles/verify", strings.NewReader(body))
			request.Header.Set("X-Runtime-Control-Token", "test-token")
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if response.Code != http.StatusBadRequest {
				t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
			}
		})
	}
}

type stubServices struct{}

func (stubServices) ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	services := make([]contract.PlatformServiceStatus, 0, len(contract.PlatformServiceRoles))
	for _, role := range contract.PlatformServiceRoles {
		services = append(services, contract.PlatformServiceStatus{Role: role, State: "stopped"})
	}
	return services, []contract.ReadIssue{}
}

func TestRuntimeRoutesForwardToExplicitControllerEndpoint(t *testing.T) {
	seen := make(chan string, 3)
	runtimeController := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Header.Get("X-Runtime-Control-Token") != "" || request.Header.Get("Authorization") != "" {
			t.Error("Platform API credentials must not be forwarded to Runtime Controller")
		}
		seen <- request.URL.Path
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"ok":true}`))
	}))
	defer runtimeController.Close()
	controllerURL, err := url.Parse(runtimeController.URL)
	if err != nil {
		t.Fatal(err)
	}
	port := controllerURL.Port()
	root := t.TempDir()
	endpoint := filepath.Join(root, "runtime-endpoint.json")
	if err := os.WriteFile(endpoint, []byte(`{"address":"127.0.0.1","source":"platform-agent","state":"loaded"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	var controllerPort int
	if _, err := fmt.Sscanf(port, "%d", &controllerPort); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeEndpointDocument: endpoint,
		RuntimeControllerPort: controllerPort,
	}, stubServices{}, time.Now())

	for clientPath, controllerPath := range map[string]string{
		"/runtime/capabilities": "/runtime/capabilities",
		"/runtime/services":     "/runtime/services",
		"/runtime/stack":        "/runtime/stack",
	} {
		request := httptest.NewRequest(http.MethodGet, clientPath, nil)
		request.Header.Set("X-Runtime-Control-Token", "test-token")
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf("%s returned %d body=%s", clientPath, response.Code, response.Body.String())
		}
		if actual := <-seen; actual != controllerPath {
			t.Fatalf("%s forwarded to %s want=%s", clientPath, actual, controllerPath)
		}
	}
}

func TestRuntimeRouteReportsMissingEndpointAsUnavailable(t *testing.T) {
	handler := NewHandler(Config{
		APIToken:                "test-token",
		RuntimeEndpointDocument: filepath.Join(t.TempDir(), "missing-endpoint.json"),
		RuntimeControllerPort:   18330,
	}, stubServices{}, time.Now())
	request := httptest.NewRequest(http.MethodGet, "/runtime/stack", nil)
	request.Header.Set("Authorization", "Bearer test-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), "missing-endpoint.json") {
		t.Fatalf("missing endpoint evidence must be explicit: %s", response.Body.String())
	}
}

func TestPlatformOnlySurfacePreservesExplicitResourceStates(t *testing.T) {
	root := t.TempDir()
	executable := filepath.Join(root, "runtime")
	if err := os.WriteFile(executable, []byte("runtime"), 0o755); err != nil {
		t.Fatal(err)
	}
	provider := filepath.Join(root, "runtime-provider.json")
	if err := os.WriteFile(provider, []byte(`{"schemaVersion":1,"state":"running","operation":null,"operationID":null,"bootID":null,"startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":null}`), 0o600); err != nil {
		t.Fatal(err)
	}
	endpoint := filepath.Join(root, "runtime-endpoint.json")
	if err := os.WriteFile(endpoint, []byte(`{"address":"127.0.0.1","source":"platform-agent","state":"loaded"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	lease := filepath.Join(root, "operation-lease.json")
	if err := os.WriteFile(lease, []byte(`{"schemaVersion":1,"operationId":"op-1","operation":"install","ownerPID":null,"startedAt":"2026-07-11T00:00:00Z","heartbeatAt":"2026-07-11T00:00:00Z","expiresAt":null,"message":null}`), 0o600); err != nil {
		t.Fatal(err)
	}

	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeExecutable: executable,
		RuntimeEndpointDocument: endpoint, RuntimeProviderDocument: provider,
		OperationLeaseDocument: lease,
	}, stubServices{}, time.Date(2026, 7, 11, 0, 0, 0, 0, time.UTC))
	server := httptest.NewServer(handler)
	defer server.Close()

	for _, path := range []string{
		"/platform", "/platform/capabilities", "/platform/operations",
		"/platform/runtime-endpoint", "/platform/runtime-provider",
	} {
		request, err := http.NewRequest(http.MethodGet, server.URL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		request.Header.Set("X-Runtime-Control-Token", "test-token")
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			t.Fatalf("%s returned %d", path, response.StatusCode)
		}
		var document map[string]any
		if err := json.NewDecoder(response.Body).Decode(&document); err != nil {
			t.Fatalf("%s returned invalid JSON: %v", path, err)
		}
	}
}

func TestMissingAndInvalidResourcesDoNotBecomeEmptySuccess(t *testing.T) {
	root := t.TempDir()
	invalidProvider := filepath.Join(root, "runtime-provider.json")
	if err := os.WriteFile(invalidProvider, []byte("not-json"), 0o600); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeExecutable: filepath.Join(root, "missing-runtime"),
		RuntimeEndpointDocument: filepath.Join(root, "missing-endpoint.json"),
		RuntimeProviderDocument: invalidProvider,
		OperationLeaseDocument:  filepath.Join(root, "missing-lease.json"),
	}, stubServices{}, time.Now())

	assertResourceState(t, handler, "/platform/runtime-endpoint", "missing")
	assertResourceState(t, handler, "/platform/runtime-provider", "failed")
	assertResourceState(t, handler, "/platform/operations", "")
}

func TestIncompleteOwnerDocumentsAreFailedReads(t *testing.T) {
	root := t.TempDir()
	provider := filepath.Join(root, "runtime-provider.json")
	if err := os.WriteFile(provider, []byte(`{"state":"running"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	lease := filepath.Join(root, "operation-lease.json")
	if err := os.WriteFile(lease, []byte(`{"operation":"install"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeExecutable: filepath.Join(root, "runtime"),
		RuntimeEndpointDocument: filepath.Join(root, "runtime-endpoint.json"),
		RuntimeProviderDocument: provider, OperationLeaseDocument: lease,
	}, stubServices{}, time.Now())

	assertResourceState(t, handler, "/platform/runtime-provider", "failed")

	request := httptest.NewRequest(http.MethodGet, "/platform/operations", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	var operations contract.PlatformOperations
	if err := json.Unmarshal(response.Body.Bytes(), &operations); err != nil {
		t.Fatal(err)
	}
	if operations.Lease.State != "failed" || operations.Lease.ReadError == nil {
		t.Fatalf("incomplete lease must be failed with readError: %s", response.Body.String())
	}
}

func assertResourceState(t *testing.T, handler http.Handler, path, state string) {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet, path, nil)
	request.Header.Set("Authorization", "Bearer test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("%s returned %d", path, response.Code)
	}
	if state == "" {
		return
	}
	var document struct {
		State string `json:"state"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &document); err != nil {
		t.Fatal(err)
	}
	if document.State != state {
		t.Fatalf("%s state=%q want=%q body=%s", path, document.State, state, response.Body.String())
	}
}
