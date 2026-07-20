package labrecorderrunner

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
)

func TestLabRecorderRunnerHTTPClientMapsCompleteStartAndFinalizationReceipts(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		switch request.URL.Path {
		case "/v1/lab-recorder-runs":
			if request.Method != http.MethodPost {
				t.Fatalf("start method = %s", request.Method)
			}
			response.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": "v1", "id": "lab-run-1", "requestId": "start-request-1", "virtualRecorderId": "lab-recorder-1", "recorderGatewayRecorderCode": "lab-recorder-1", "recorderGatewayRecorderId": "recorder-lab-recorder-1", "coldPathCaptureId": "capture-1", "scenarioId": "baseline-monitoring", "archiveOnTerminalStop": true, "resourceRevision": 1, "state": "running", "emittedPacketCount": 1, "startedAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
			})
		case "/v1/lab-recorder-runs/lab-run-1:stop":
			if request.Method != http.MethodPost {
				t.Fatalf("stop method = %s", request.Method)
			}
			response.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": "v1", "id": "lab-run-1", "requestId": "stop-request-1", "virtualRecorderId": "lab-recorder-1", "recorderGatewayRecorderCode": "lab-recorder-1", "recorderGatewayRecorderId": "recorder-lab-recorder-1", "coldPathCaptureId": "capture-1", "scenarioId": "baseline-monitoring", "archiveOnTerminalStop": true, "resourceRevision": 2, "state": "finalized", "emittedPacketCount": 3, "startedAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:01:00Z",
				"finalizationReceipt": map[string]any{"kind": "recorder-gateway-cold-path-finalization-receipt", "id": "finalization-1", "captureId": "capture-1", "recorderId": "recorder-lab-recorder-1", "finalizedAt": "2026-07-19T00:01:00Z"},
			})
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatalf("open client: %v", err)
	}
	start, err := client.StartLabVirtualRecorderRun(context.Background(), "start-request-1", "lab-recorder-1", "lab-recorder-1", "baseline-monitoring")
	if err != nil {
		t.Fatalf("start run: %v", err)
	}
	if start.RunID != "lab-run-1" || start.RunRevision != 1 || start.RecorderGatewayRecorderID != "recorder-lab-recorder-1" || start.ColdPathCaptureID != "capture-1" || !start.ArchiveOnTerminalStop {
		t.Fatalf("start receipt = %+v", start)
	}
	stop, err := client.StopLabVirtualRecorderRun(context.Background(), "stop-request-1", start.RunID, start.RunRevision)
	if err != nil {
		t.Fatalf("stop run: %v", err)
	}
	if stop.RunID != "lab-run-1" || stop.RunRevision != 2 || stop.RecorderGatewayRecorderID != "recorder-lab-recorder-1" || stop.ColdPathCaptureID != "capture-1" || stop.FinalizationReceiptID != "finalization-1" {
		t.Fatalf("finalization receipt = %+v", stop)
	}
}

func TestLabRecorderRunnerHTTPClientReturnsKnownRunnerRejection(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		response.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(response).Encode(map[string]any{
			"schemaVersion": "v1", "state": "rejected", "issue": map[string]any{"code": "lab-scenario-not-configured", "message": "scenarioId is not present in the declared Lab scenario catalog", "retryable": false, "dependency": "lab-recorder-runner"},
		})
	}))
	defer server.Close()

	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatalf("open client: %v", err)
	}
	_, err = client.StartLabVirtualRecorderRun(context.Background(), "start-request-1", "lab-recorder-1", "lab-recorder-1", "unconfigured")
	var known guestruntimeapplication.SourceEligibilityError
	if !errors.As(err, &known) || known.Issue.Code != "lab-scenario-not-configured" {
		t.Fatalf("known Runner rejection = %v", err)
	}
}

func TestLabRecorderRunnerHTTPClientRejectsMalformedSuccessfulResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		_ = json.NewEncoder(response).Encode(map[string]any{"schemaVersion": "v1", "state": "running"})
	}))
	defer server.Close()

	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatalf("open client: %v", err)
	}
	_, err = client.StartLabVirtualRecorderRun(context.Background(), "start-request-1", "lab-recorder-1", "lab-recorder-1", "baseline-monitoring")
	if err == nil {
		t.Fatal("incomplete success response must not become a start receipt")
	}
}

func TestLabRecorderRunnerHTTPClientDoesNotTreatMissingArchivePolicyAsNoExport(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		response.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(response).Encode(map[string]any{
			"schemaVersion": "v1", "id": "lab-run-1", "requestId": "start-request-1", "virtualRecorderId": "lab-recorder-1", "recorderGatewayRecorderCode": "lab-recorder-1", "recorderGatewayRecorderId": "recorder-lab-recorder-1", "coldPathCaptureId": "capture-1", "scenarioId": "baseline-monitoring", "resourceRevision": 1, "state": "running", "emittedPacketCount": 1, "startedAt": "2026-07-19T00:00:00Z", "updatedAt": "2026-07-19T00:00:00Z",
		})
	}))
	defer server.Close()

	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatalf("open client: %v", err)
	}
	if _, err := client.StartLabVirtualRecorderRun(context.Background(), "start-request-1", "lab-recorder-1", "lab-recorder-1", "baseline-monitoring"); err == nil {
		t.Fatal("missing archive policy must not be decoded as no-export")
	}
}
