package labrecorderrunner

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
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

func TestLabRecorderRunnerHTTPClientMapsReplayEffectReceipts(t *testing.T) {
	batchID, err := guestruntimedomain.LabReplayMessageBatchID("replay-1", 0, 1)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		switch request.URL.Path {
		case "/internal/v1/lab-replays:prepare":
			response.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": "v1", "replayId": "replay-1",
				"runnerSessionId":     "runner-session-1",
				"spoolDatabaseSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				"frameCount":          1, "outputStartedAt": 1784908800.0,
				"preparedAt": "2026-07-25T00:00:00Z",
			})
		case "/internal/v1/lab-replays/runner-session-1/batches":
			response.WriteHeader(http.StatusAccepted)
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": "v1", "replayId": "replay-1",
				"runnerSessionId": "runner-session-1",
				"batchId":         batchID, "startOffsetSecond": 0,
				"frameCount": 1, "finalBatch": true,
				"acceptedAt": "2026-07-25T00:00:01Z",
			})
		case "/internal/v1/lab-replays/runner-session-1:confirm-upstream":
			_ = json.NewEncoder(response).Encode(map[string]any{
				"schemaVersion": "v1", "replayId": "replay-1",
				"runnerSessionId":     "runner-session-1",
				"deliveryReceiptId":   "lab-upstream-1",
				"deliveredFrameCount": 1,
				"deliveryConfirmedAt": "2026-07-25T00:00:02Z",
			})
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()
	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	preparation, err := client.PrepareLabReplay(
		context.Background(),
		guestruntimeapplication.LabReplayPrepareEffect{
			ReplayID:                    "replay-1",
			RecorderGatewayRecorderCode: "LAB-01",
			SpoolReceipt: guestruntimedomain.VitalFileReplaySpoolReceipt{
				SchemaVersion: "v1", ReplayID: "replay-1",
				DatabaseSHA256:  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				DurationSeconds: 1,
			},
		},
	)
	if err != nil || preparation.RunnerSessionID != "runner-session-1" {
		t.Fatalf("preparation=%+v err=%v", preparation, err)
	}
	batch, err := client.SendLabReplayMessageBatch(
		context.Background(),
		guestruntimeapplication.LabReplayMessageBatchEffect{
			ReplayID: "replay-1", RunnerSessionID: preparation.RunnerSessionID,
			BatchID: batchID, StartOffsetSecond: 0,
			Frames: []guestruntimedomain.VitalFileReplayFrame{{
				OffsetSeconds: 0, OutputTime: preparation.OutputStartedAt,
				Tracks: []guestruntimedomain.VitalFileReplayFrameTrack{{
					OutputTrackID: 1, SourceTrackID: 1,
					Kind: guestruntimedomain.VitalFileNumericTrack,
					Name: "HR", DeviceName: "Monitor",
					MonitorType:  guestruntimedomain.VitalServerMonitorECGHeartRate,
					NumericValue: func() *float64 { value := 70.0; return &value }(),
				}},
			}},
			FinalBatch: true,
		},
	)
	if err != nil || batch.BatchID != batchID {
		t.Fatalf("batch=%+v err=%v", batch, err)
	}
	delivery, err := client.ConfirmLabReplayUpstreamDelivery(
		context.Background(),
		guestruntimeapplication.LabReplayUpstreamDeliveryEffect{
			ReplayID: "replay-1", RunnerSessionID: preparation.RunnerSessionID,
			ExpectedFrameCount: 1,
		},
	)
	if err != nil || delivery.DeliveryReceiptID != "lab-upstream-1" {
		t.Fatalf("delivery=%+v err=%v", delivery, err)
	}
}

func TestLabRecorderRunnerHTTPClientPreservesTypedReplayRejection(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("content-type", "application/json")
		response.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(response).Encode(map[string]any{
			"schemaVersion": "v1", "state": "rejected",
			"issue": map[string]any{
				"code":       "vitalserver-delivery-terminal-failure",
				"message":    "delivery failed",
				"retryable":  false,
				"dependency": "lab-recorder-runner",
			},
		})
	}))
	defer server.Close()
	client, err := NewLabRecorderRunnerHTTPClient(server.URL)
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.ConfirmLabReplayUpstreamDelivery(
		context.Background(),
		guestruntimeapplication.LabReplayUpstreamDeliveryEffect{
			ReplayID: "replay-1", RunnerSessionID: "runner-session-1",
			ExpectedFrameCount: 1,
		},
	)
	var rejected guestruntimeapplication.LabReplayEffectRejectedError
	if !errors.As(err, &rejected) ||
		rejected.Code != "vitalserver-delivery-terminal-failure" {
		t.Fatalf("rejection=%v", err)
	}
}

func TestLabRecorderRunnerHTTPClientDoesNotInventTerminalReplayRejection(t *testing.T) {
	for _, fixture := range []struct {
		name  string
		issue map[string]any
	}{
		{
			name: "missing retryability",
			issue: map[string]any{
				"code":       "vitalserver-delivery-terminal-failure",
				"message":    "delivery failed",
				"dependency": "lab-recorder-runner",
			},
		},
		{
			name: "retryable issue",
			issue: map[string]any{
				"code":       "vitalserver-delivery-terminal-failure",
				"message":    "delivery failed",
				"retryable":  true,
				"dependency": "lab-recorder-runner",
			},
		},
		{
			name: "missing dependency",
			issue: map[string]any{
				"code":      "vitalserver-delivery-terminal-failure",
				"message":   "delivery failed",
				"retryable": false,
			},
		},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
				response.Header().Set("content-type", "application/json")
				response.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(response).Encode(map[string]any{
					"schemaVersion": "v1",
					"state":         "rejected",
					"issue":         fixture.issue,
				})
			}))
			defer server.Close()
			client, err := NewLabRecorderRunnerHTTPClient(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			_, err = client.ConfirmLabReplayUpstreamDelivery(
				context.Background(),
				guestruntimeapplication.LabReplayUpstreamDeliveryEffect{
					ReplayID:           "replay-1",
					RunnerSessionID:    "runner-session-1",
					ExpectedFrameCount: 1,
				},
			)
			var rejected guestruntimeapplication.LabReplayEffectRejectedError
			if err == nil || errors.As(err, &rejected) {
				t.Fatalf("invalid rejection contract became terminal: %v", err)
			}
		})
	}
}
