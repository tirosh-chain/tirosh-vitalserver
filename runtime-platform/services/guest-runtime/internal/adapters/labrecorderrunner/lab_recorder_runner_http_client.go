// Package labrecorderrunner adapts the explicit Guest-loopback Lab recorder
// Runner control contract. It owns HTTP decode and transport failure mapping;
// it does not read Lab persistence, Gateway state files, or Archive state.
package labrecorderrunner

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumLabRecorderRunnerResponseBytes int64 = 64 << 10

type LabRecorderRunnerHTTPClient struct {
	endpoint *url.URL
	client   *http.Client
}

func NewLabRecorderRunnerHTTPClient(endpoint string) (*LabRecorderRunnerHTTPClient, error) {
	parsed, err := parseGuestLoopbackEndpoint(endpoint)
	if err != nil {
		return nil, err
	}
	return &LabRecorderRunnerHTTPClient{
		endpoint: parsed,
		client: &http.Client{
			Timeout: 3 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return fmt.Errorf("Lab recorder Runner control redirect is not allowed")
			},
		},
	}, nil
}

func (client *LabRecorderRunnerHTTPClient) StartLabVirtualRecorderRun(ctx context.Context, requestID string, virtualRecorderID string, recorderGatewayRecorderCode string, scenario string) (guestruntimedomain.LabRecorderRunnerStartReceipt, error) {
	response, err := client.post(ctx, "/v1/lab-recorder-runs", map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "virtualRecorderId": virtualRecorderID, "recorderGatewayRecorderCode": recorderGatewayRecorderCode, "scenarioId": scenario,
	})
	if err != nil {
		return guestruntimedomain.LabRecorderRunnerStartReceipt{}, err
	}
	if response.StatusCode == http.StatusBadRequest {
		return guestruntimedomain.LabRecorderRunnerStartReceipt{}, knownRunnerRejection("Lab recorder Runner rejected start", response.Body)
	}
	if response.StatusCode != http.StatusCreated {
		return guestruntimedomain.LabRecorderRunnerStartReceipt{}, fmt.Errorf("Lab recorder Runner start returned HTTP %d", response.StatusCode)
	}
	var decoded runnerRunDocument
	if err := decodeRunnerResponse(response.Body, &decoded); err != nil {
		return guestruntimedomain.LabRecorderRunnerStartReceipt{}, fmt.Errorf("decode Lab recorder Runner start result: %w", err)
	}
	if decoded.SchemaVersion != guestruntimedomain.SchemaVersion || decoded.State != "running" || decoded.RequestID != requestID || decoded.VirtualRecorderID != virtualRecorderID || decoded.RecorderGatewayRecorderCode != recorderGatewayRecorderCode || decoded.ResourceRevision != 1 || decoded.ArchiveOnTerminalStop == nil || !guestruntimedomain.ValidIdentifier(decoded.ID) || !guestruntimedomain.ValidIdentifier(decoded.RecorderGatewayRecorderID) || !guestruntimedomain.ValidIdentifier(decoded.ColdPathCaptureID) {
		return guestruntimedomain.LabRecorderRunnerStartReceipt{}, fmt.Errorf("Lab recorder Runner start result is incomplete or mismatched")
	}
	return guestruntimedomain.LabRecorderRunnerStartReceipt{RunID: decoded.ID, RunRevision: decoded.ResourceRevision, RecorderGatewayRecorderID: decoded.RecorderGatewayRecorderID, ColdPathCaptureID: decoded.ColdPathCaptureID, ArchiveOnTerminalStop: *decoded.ArchiveOnTerminalStop}, nil
}

func (client *LabRecorderRunnerHTTPClient) StopLabVirtualRecorderRun(ctx context.Context, requestID string, runnerRunID string, expectedRunRevision int) (guestruntimedomain.LabRecorderRunnerFinalizationReceipt, error) {
	if !guestruntimedomain.ValidIdentifier(runnerRunID) || expectedRunRevision < 1 {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, guestruntimeapplication.SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "invalid-lab-recorder-runner-stop-reference", Message: "Runner run ID and expected revision must be valid"}}
	}
	response, err := client.post(ctx, "/v1/lab-recorder-runs/"+url.PathEscape(runnerRunID)+":stop", map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "expectedRunRevision": expectedRunRevision,
	})
	if err != nil {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, err
	}
	if response.StatusCode == http.StatusBadRequest {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, knownRunnerRejection("Lab recorder Runner rejected stop", response.Body)
	}
	if response.StatusCode != http.StatusCreated {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, fmt.Errorf("Lab recorder Runner stop returned HTTP %d", response.StatusCode)
	}
	var decoded runnerRunDocument
	if err := decodeRunnerResponse(response.Body, &decoded); err != nil {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, fmt.Errorf("decode Lab recorder Runner stop result: %w", err)
	}
	if decoded.SchemaVersion != guestruntimedomain.SchemaVersion || decoded.ID != runnerRunID || decoded.State != "finalized" || decoded.ResourceRevision != expectedRunRevision+1 || !guestruntimedomain.ValidIdentifier(decoded.RecorderGatewayRecorderID) || !guestruntimedomain.ValidIdentifier(decoded.ColdPathCaptureID) || decoded.FinalizationReceipt == nil || decoded.FinalizationReceipt.Kind != "recorder-gateway-cold-path-finalization-receipt" || !guestruntimedomain.ValidIdentifier(decoded.FinalizationReceipt.ID) || decoded.FinalizationReceipt.FinalizedAt == "" || decoded.FinalizationReceipt.CaptureID != decoded.ColdPathCaptureID || decoded.FinalizationReceipt.RecorderID != decoded.RecorderGatewayRecorderID {
		return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{}, fmt.Errorf("Lab recorder Runner stop result is incomplete or mismatched")
	}
	return guestruntimedomain.LabRecorderRunnerFinalizationReceipt{RunID: decoded.ID, RunRevision: decoded.ResourceRevision, RecorderGatewayRecorderID: decoded.RecorderGatewayRecorderID, ColdPathCaptureID: decoded.ColdPathCaptureID, FinalizationReceiptID: decoded.FinalizationReceipt.ID}, nil
}

func (client *LabRecorderRunnerHTTPClient) PrepareLabReplay(
	ctx context.Context,
	effect guestruntimeapplication.LabReplayPrepareEffect,
) (guestruntimedomain.LabReplayPreparationReceipt, error) {
	response, err := client.post(ctx, "/internal/v1/lab-replays:prepare", map[string]any{
		"schemaVersion":               guestruntimedomain.SchemaVersion,
		"replayId":                    effect.ReplayID,
		"recorderGatewayRecorderCode": effect.RecorderGatewayRecorderCode,
		"spoolDatabaseSha256":         effect.SpoolReceipt.DatabaseSHA256,
		"frameCount":                  effect.SpoolReceipt.DurationSeconds,
	})
	if err != nil {
		return guestruntimedomain.LabReplayPreparationReceipt{}, err
	}
	if response.StatusCode >= 400 && response.StatusCode < 500 {
		return guestruntimedomain.LabReplayPreparationReceipt{},
			knownReplayRejection("Lab recorder Runner rejected replay preparation", response.Body)
	}
	if response.StatusCode != http.StatusCreated && response.StatusCode != http.StatusOK {
		return guestruntimedomain.LabReplayPreparationReceipt{},
			fmt.Errorf("Lab recorder Runner replay preparation returned HTTP %d", response.StatusCode)
	}
	var receipt guestruntimedomain.LabReplayPreparationReceipt
	if err := decodeRunnerResponse(response.Body, &receipt); err != nil {
		return guestruntimedomain.LabReplayPreparationReceipt{},
			fmt.Errorf("decode Lab recorder Runner replay preparation receipt: %w", err)
	}
	if receipt.SchemaVersion != guestruntimedomain.SchemaVersion ||
		receipt.ReplayID != effect.ReplayID ||
		receipt.SpoolDatabaseSHA256 != effect.SpoolReceipt.DatabaseSHA256 ||
		receipt.FrameCount != effect.SpoolReceipt.DurationSeconds {
		return guestruntimedomain.LabReplayPreparationReceipt{},
			fmt.Errorf("Lab recorder Runner replay preparation receipt is mismatched")
	}
	return receipt, nil
}

func (client *LabRecorderRunnerHTTPClient) SendLabReplayMessageBatch(
	ctx context.Context,
	effect guestruntimeapplication.LabReplayMessageBatchEffect,
) (guestruntimedomain.LabReplayMessageBatchReceipt, error) {
	response, err := client.post(
		ctx,
		"/internal/v1/lab-replays/"+url.PathEscape(effect.RunnerSessionID)+"/batches",
		map[string]any{
			"schemaVersion":     guestruntimedomain.SchemaVersion,
			"replayId":          effect.ReplayID,
			"runnerSessionId":   effect.RunnerSessionID,
			"batchId":           effect.BatchID,
			"startOffsetSecond": effect.StartOffsetSecond,
			"frames":            effect.Frames,
			"finalBatch":        effect.FinalBatch,
		},
	)
	if err != nil {
		return guestruntimedomain.LabReplayMessageBatchReceipt{}, err
	}
	if response.StatusCode >= 400 && response.StatusCode < 500 {
		return guestruntimedomain.LabReplayMessageBatchReceipt{},
			knownReplayRejection("Lab recorder Runner rejected replay message batch", response.Body)
	}
	if response.StatusCode != http.StatusAccepted && response.StatusCode != http.StatusOK {
		return guestruntimedomain.LabReplayMessageBatchReceipt{},
			fmt.Errorf("Lab recorder Runner replay message batch returned HTTP %d", response.StatusCode)
	}
	var receipt guestruntimedomain.LabReplayMessageBatchReceipt
	if err := decodeRunnerResponse(response.Body, &receipt); err != nil {
		return guestruntimedomain.LabReplayMessageBatchReceipt{},
			fmt.Errorf("decode Lab recorder Runner replay message batch receipt: %w", err)
	}
	if receipt.SchemaVersion != guestruntimedomain.SchemaVersion ||
		receipt.ReplayID != effect.ReplayID ||
		receipt.RunnerSessionID != effect.RunnerSessionID ||
		receipt.BatchID != effect.BatchID ||
		receipt.StartOffsetSecond != effect.StartOffsetSecond ||
		receipt.FrameCount != len(effect.Frames) ||
		receipt.FinalBatch != effect.FinalBatch {
		return guestruntimedomain.LabReplayMessageBatchReceipt{},
			fmt.Errorf("Lab recorder Runner replay message batch receipt is mismatched")
	}
	return receipt, nil
}

func (client *LabRecorderRunnerHTTPClient) ConfirmLabReplayUpstreamDelivery(
	ctx context.Context,
	effect guestruntimeapplication.LabReplayUpstreamDeliveryEffect,
) (guestruntimedomain.LabReplayUpstreamDeliveryReceipt, error) {
	response, err := client.post(
		ctx,
		"/internal/v1/lab-replays/"+url.PathEscape(effect.RunnerSessionID)+":confirm-upstream",
		map[string]any{
			"schemaVersion":      guestruntimedomain.SchemaVersion,
			"replayId":           effect.ReplayID,
			"runnerSessionId":    effect.RunnerSessionID,
			"expectedFrameCount": effect.ExpectedFrameCount,
		},
	)
	if err != nil {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{}, err
	}
	if response.StatusCode >= 400 && response.StatusCode < 500 {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{},
			knownReplayRejection("Lab recorder Runner rejected replay delivery confirmation", response.Body)
	}
	if response.StatusCode != http.StatusOK {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{},
			fmt.Errorf("Lab recorder Runner replay delivery confirmation returned HTTP %d", response.StatusCode)
	}
	var receipt guestruntimedomain.LabReplayUpstreamDeliveryReceipt
	if err := decodeRunnerResponse(response.Body, &receipt); err != nil {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{},
			fmt.Errorf("decode Lab recorder Runner replay delivery receipt: %w", err)
	}
	if receipt.SchemaVersion != guestruntimedomain.SchemaVersion ||
		receipt.ReplayID != effect.ReplayID ||
		receipt.RunnerSessionID != effect.RunnerSessionID ||
		receipt.DeliveredFrameCount != effect.ExpectedFrameCount {
		return guestruntimedomain.LabReplayUpstreamDeliveryReceipt{},
			fmt.Errorf("Lab recorder Runner replay delivery receipt is mismatched")
	}
	return receipt, nil
}

type runnerHTTPResponse struct {
	StatusCode int
	Body       []byte
}

func (client *LabRecorderRunnerHTTPClient) post(ctx context.Context, path string, body any) (runnerHTTPResponse, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return runnerHTTPResponse{}, fmt.Errorf("encode Lab recorder Runner command: %w", err)
	}
	target := *client.endpoint
	target.Path = path
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, target.String(), bytes.NewReader(encoded))
	if err != nil {
		return runnerHTTPResponse{}, fmt.Errorf("create Lab recorder Runner request: %w", err)
	}
	request.Header.Set("content-type", "application/json")
	request.Header.Set("accept", "application/json")
	response, err := client.client.Do(request)
	if err != nil {
		return runnerHTTPResponse{}, fmt.Errorf("Lab recorder Runner control request failed: %w", err)
	}
	defer response.Body.Close()
	if contentType := response.Header.Get("content-type"); !strings.HasPrefix(strings.ToLower(contentType), "application/json") {
		return runnerHTTPResponse{}, fmt.Errorf("Lab recorder Runner response content type is not JSON")
	}
	decoded, err := io.ReadAll(io.LimitReader(response.Body, maximumLabRecorderRunnerResponseBytes+1))
	if err != nil {
		return runnerHTTPResponse{}, fmt.Errorf("read Lab recorder Runner response: %w", err)
	}
	if len(decoded) > int(maximumLabRecorderRunnerResponseBytes) {
		return runnerHTTPResponse{}, fmt.Errorf("Lab recorder Runner response exceeds 64 KiB")
	}
	return runnerHTTPResponse{StatusCode: response.StatusCode, Body: decoded}, nil
}

type runnerRunDocument struct {
	SchemaVersion               string `json:"schemaVersion"`
	ID                          string `json:"id"`
	RequestID                   string `json:"requestId"`
	VirtualRecorderID           string `json:"virtualRecorderId"`
	RecorderGatewayRecorderCode string `json:"recorderGatewayRecorderCode"`
	RecorderGatewayRecorderID   string `json:"recorderGatewayRecorderId"`
	ColdPathCaptureID           string `json:"coldPathCaptureId"`
	ScenarioID                  string `json:"scenarioId"`
	ArchiveOnTerminalStop       *bool  `json:"archiveOnTerminalStop"`
	ResourceRevision            int    `json:"resourceRevision"`
	State                       string `json:"state"`
	EmittedPacketCount          int    `json:"emittedPacketCount"`
	StartedAt                   string `json:"startedAt"`
	UpdatedAt                   string `json:"updatedAt"`
	FinalizationReceipt         *struct {
		Kind        string `json:"kind"`
		ID          string `json:"id"`
		CaptureID   string `json:"captureId"`
		RecorderID  string `json:"recorderId"`
		FinalizedAt string `json:"finalizedAt"`
	} `json:"finalizationReceipt"`
}

func decodeRunnerResponse(body []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("response contains multiple JSON values")
	}
	return nil
}

func knownRunnerRejection(subject string, body []byte) error {
	var decoded struct {
		SchemaVersion string `json:"schemaVersion"`
		State         string `json:"state"`
		Issue         *struct {
			Code       string `json:"code"`
			Message    string `json:"message"`
			Retryable  *bool  `json:"retryable"`
			Dependency string `json:"dependency"`
		} `json:"issue"`
	}
	if err := decodeRunnerResponse(body, &decoded); err != nil || decoded.SchemaVersion != guestruntimedomain.SchemaVersion || decoded.State != "rejected" || decoded.Issue == nil || decoded.Issue.Code == "" {
		return fmt.Errorf("%s without a valid rejection contract", subject)
	}
	return guestruntimeapplication.SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: decoded.Issue.Code, Message: decoded.Issue.Message, Retryable: decoded.Issue.Retryable, Dependency: decoded.Issue.Dependency}}
}

func knownReplayRejection(subject string, body []byte) error {
	var decoded struct {
		SchemaVersion string `json:"schemaVersion"`
		State         string `json:"state"`
		Issue         *struct {
			Code       string `json:"code"`
			Message    string `json:"message"`
			Retryable  *bool  `json:"retryable"`
			Dependency string `json:"dependency"`
		} `json:"issue"`
	}
	if err := decodeRunnerResponse(body, &decoded); err != nil ||
		decoded.SchemaVersion != guestruntimedomain.SchemaVersion ||
		decoded.State != "rejected" ||
		decoded.Issue == nil ||
		!guestruntimedomain.ValidIdentifier(decoded.Issue.Code) ||
		decoded.Issue.Message == "" ||
		decoded.Issue.Retryable == nil ||
		*decoded.Issue.Retryable ||
		!guestruntimedomain.ValidIdentifier(decoded.Issue.Dependency) {
		return fmt.Errorf("%s without a valid replay rejection contract", subject)
	}
	return guestruntimeapplication.LabReplayEffectRejectedError{
		Code:    decoded.Issue.Code,
		Message: decoded.Issue.Message,
	}
}

func parseGuestLoopbackEndpoint(value string) (*url.URL, error) {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "http" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return nil, fmt.Errorf("Lab recorder Runner endpoint must be a bare Guest-loopback HTTP URL")
	}
	if parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "::1" {
		return nil, fmt.Errorf("Lab recorder Runner endpoint must use a Guest-loopback host")
	}
	port, err := strconv.Atoi(parsed.Port())
	if parsed.Port() == "" || err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("Lab recorder Runner endpoint must include a valid explicit port")
	}
	if host, _, err := net.SplitHostPort(parsed.Host); err != nil || (host != "127.0.0.1" && host != "::1") {
		return nil, fmt.Errorf("Lab recorder Runner endpoint host is invalid")
	}
	parsed.Path = ""
	return parsed, nil
}

var _ guestruntimeapplication.GuestRuntimeLabRecorderRunner = (*LabRecorderRunnerHTTPClient)(nil)
var _ guestruntimeapplication.GuestRuntimeLabReplayEffectRunner = (*LabRecorderRunnerHTTPClient)(nil)
