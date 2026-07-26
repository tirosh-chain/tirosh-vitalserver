package agent

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestOperationLeaseHTTPMutationLifecycle(t *testing.T) {
	handler := NewHandler(Config{
		APIToken:               "test-token",
		OperationLeaseDocument: filepath.Join(t.TempDir(), "operation-lease.json"),
	}, stubServices{}, time.Now())

	assertLeaseMutation(t, handler, "/platform/operations/lease/acquire", `{
  "document": {
    "schemaVersion": 1,
    "operationId": "operation-1",
    "operation": "install",
    "ownerPID": null,
    "startedAt": "2026-07-11T00:00:00Z",
    "heartbeatAt": "2026-07-11T00:00:00Z",
    "expiresAt": null,
    "message": null
  }
}`, http.StatusOK, `"state":"acquired"`)
	assertLeaseMutation(t, handler, "/platform/operations/lease/acquire", `{
  "document": {
    "schemaVersion": 1,
    "operationId": "operation-2",
    "operation": "install",
    "ownerPID": null,
    "startedAt": "2026-07-11T00:00:00Z",
    "heartbeatAt": "2026-07-11T00:00:00Z",
    "expiresAt": null,
    "message": null
  }
}`, http.StatusConflict, `"code":"operationConflict"`)
	assertLeaseMutation(t, handler, "/platform/operations/lease/heartbeat", `{
  "operationId": "operation-1",
  "heartbeatAt": "2026-07-11T00:01:00Z",
  "expiresAt": null
}`, http.StatusOK, `"state":"heartbeatRecorded"`)
	assertLeaseMutation(t, handler, "/platform/operations/lease/release", `{
  "operationId": "operation-1"
}`, http.StatusOK, `"state":"released"`)
}

func assertLeaseMutation(
	t *testing.T,
	handler http.Handler,
	path string,
	body string,
	status int,
	contains string,
) {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != status || !strings.Contains(response.Body.String(), contains) {
		t.Fatalf("path=%s status=%d body=%s", path, response.Code, response.Body.String())
	}
}
