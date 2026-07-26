// Package recordergatewaycoldpathsource adapts the Guest-loopback Recorder
// Gateway control contract into Archive Export's explicit source port. It
// verifies the Gateway-owned finalization receipt and raw packet sequence
// digest before the application service may form an artifact.
package recordergatewaycoldpathsource

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strconv"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const recorderGatewayPacketSequenceMediaType = "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl"
const maximumRecorderGatewayPacketSequenceBytes int64 = 64 << 20
const maximumRecorderGatewayReceiptBytes int64 = 256 << 10

// RecorderGatewayColdPathHTTPSourceReader has one explicitly configured
// Guest-loopback base URL. It accepts no external topology endpoint, redirect,
// credentials, query, or path because cold-path source access is an internal
// Guest data boundary, not a public control plane.
type RecorderGatewayColdPathHTTPSourceReader struct {
	baseURL *url.URL
	client  *http.Client
}

func NewRecorderGatewayColdPathHTTPSourceReader(endpoint string) (*RecorderGatewayColdPathHTTPSourceReader, error) {
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return nil, fmt.Errorf("parse Recorder Gateway cold-path source endpoint: %w", err)
	}
	if parsed.Scheme != "http" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return nil, fmt.Errorf("Recorder Gateway cold-path source endpoint must be a bare http Guest-loopback URL")
	}
	if parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "::1" {
		return nil, fmt.Errorf("Recorder Gateway cold-path source endpoint must target Guest loopback")
	}
	if parsed.Port() == "" {
		return nil, fmt.Errorf("Recorder Gateway cold-path source endpoint must declare a port")
	}
	port, portError := strconv.Atoi(parsed.Port())
	if portError != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("Recorder Gateway cold-path source endpoint port is invalid")
	}
	parsed.Path = ""
	return &RecorderGatewayColdPathHTTPSourceReader{
		baseURL: parsed,
		client: &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error {
			return fmt.Errorf("Recorder Gateway cold-path source redirects are not allowed")
		}},
	}, nil
}

func (reader *RecorderGatewayColdPathHTTPSourceReader) ReadFinalizedRecorderColdPathPacketSequence(ctx context.Context, source guestruntimedomain.ArtifactExportSource) (guestruntimedomain.FinalizedRecorderColdPathPacketSequence, error) {
	if reader == nil || reader.baseURL == nil || reader.client == nil {
		return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{}, fmt.Errorf("Recorder Gateway cold-path source reader is not configured")
	}
	if source.Kind != guestruntimedomain.RecorderGatewayColdPathArtifactExportSourceKind || !guestruntimedomain.ValidIdentifier(source.ColdPathFinalizationReceiptID) {
		return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{}, guestruntimeapplication.SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "invalid-recorder-cold-path-source", Message: "Archive Export source must name one finalized Recorder Gateway cold-path receipt"}}
	}
	receipt, err := reader.readFinalizationReceipt(ctx, source.ColdPathFinalizationReceiptID)
	if err != nil {
		return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{}, err
	}
	packetSequence, err := reader.readPacketSequence(ctx, receipt.FinalizedPacketSequence.ResourceID)
	if err != nil {
		return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{}, err
	}
	digest := sha256.Sum256(packetSequence)
	if hex.EncodeToString(digest[:]) != receipt.FinalizedPacketSequence.SHA256 {
		return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{}, fmt.Errorf("Recorder Gateway packet sequence digest does not match its finalization receipt")
	}
	return guestruntimedomain.FinalizedRecorderColdPathPacketSequence{
		FinalizationReceiptID: receipt.ID,
		CaptureID:             receipt.CaptureReference.ResourceID,
		RecorderID:            receipt.RecorderID,
		FinalizedAt:           receipt.FinalizedAt,
		MediaType:             receipt.FinalizedPacketSequence.MediaType,
		SHA256:                receipt.FinalizedPacketSequence.SHA256,
		Bytes:                 packetSequence,
	}, nil
}

func (reader *RecorderGatewayColdPathHTTPSourceReader) readFinalizationReceipt(ctx context.Context, receiptID string) (recorderGatewayFinalizationReceipt, error) {
	var result recorderGatewayReadResult[recorderGatewayFinalizationReceipt]
	if err := reader.getJSON(ctx, "/v1/recorder-cold-path/finalization-receipts/"+url.PathEscape(receiptID), maximumRecorderGatewayReceiptBytes, &result); err != nil {
		return recorderGatewayFinalizationReceipt{}, err
	}
	if result.SchemaVersion != "v1" || result.ObservedAt == "" || !knownGatewayReadState(result.State) {
		return recorderGatewayFinalizationReceipt{}, fmt.Errorf("Recorder Gateway finalization receipt read result does not satisfy the control contract")
	}
	if result.State != "available" || result.Value == nil {
		return recorderGatewayFinalizationReceipt{}, sourceReadResultEligibilityError("finalization receipt", result)
	}
	receipt := *result.Value
	if receipt.SchemaVersion != "v1" || receipt.ID != receiptID || receipt.CaptureReference.ResourceType != "recorder-cold-path-capture" || !guestruntimedomain.ValidIdentifier(receipt.CaptureReference.ResourceID) || !guestruntimedomain.ValidIdentifier(receipt.RecorderID) || receipt.FinalizedAt == "" || receipt.FinalizedPacketSequence.ResourceType != "recorder-cold-path-packet-sequence" || receipt.FinalizedPacketSequence.ResourceID != receipt.CaptureReference.ResourceID || receipt.FinalizedPacketSequence.MediaType != recorderGatewayPacketSequenceMediaType || !validSHA256(receipt.FinalizedPacketSequence.SHA256) {
		return recorderGatewayFinalizationReceipt{}, fmt.Errorf("Recorder Gateway finalization receipt does not satisfy the cold-path source contract")
	}
	return receipt, nil
}

func (reader *RecorderGatewayColdPathHTTPSourceReader) readPacketSequence(ctx context.Context, captureID string) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, reader.url("/v1/recorder-cold-path/captures/"+url.PathEscape(captureID)+":packet-sequence"), nil)
	if err != nil {
		return nil, fmt.Errorf("construct Recorder Gateway packet sequence request: %w", err)
	}
	response, err := reader.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("read Recorder Gateway packet sequence: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Recorder Gateway packet sequence returned HTTP %d", response.StatusCode)
	}
	mediaType, _, mediaTypeError := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if mediaTypeError != nil || mediaType != recorderGatewayPacketSequenceMediaType {
		return nil, fmt.Errorf("Recorder Gateway packet sequence media type is not %s", recorderGatewayPacketSequenceMediaType)
	}
	if response.ContentLength > maximumRecorderGatewayPacketSequenceBytes {
		return nil, fmt.Errorf("Recorder Gateway packet sequence exceeds the configured source limit")
	}
	bytes, readError := io.ReadAll(io.LimitReader(response.Body, maximumRecorderGatewayPacketSequenceBytes+1))
	if readError != nil {
		return nil, fmt.Errorf("read Recorder Gateway packet sequence body: %w", readError)
	}
	if int64(len(bytes)) > maximumRecorderGatewayPacketSequenceBytes || len(bytes) == 0 {
		return nil, fmt.Errorf("Recorder Gateway packet sequence is empty or exceeds the configured source limit")
	}
	return bytes, nil
}

func (reader *RecorderGatewayColdPathHTTPSourceReader) getJSON(ctx context.Context, path string, maximumBytes int64, target any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, reader.url(path), nil)
	if err != nil {
		return fmt.Errorf("construct Recorder Gateway control request: %w", err)
	}
	request.Header.Set("Accept", "application/json")
	response, err := reader.client.Do(request)
	if err != nil {
		return fmt.Errorf("read Recorder Gateway control response: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("Recorder Gateway control response returned HTTP %d", response.StatusCode)
	}
	mediaType, _, mediaTypeError := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if mediaTypeError != nil || mediaType != "application/json" {
		return fmt.Errorf("Recorder Gateway control response media type is not application/json")
	}
	if response.ContentLength > maximumBytes {
		return fmt.Errorf("Recorder Gateway control response exceeds the configured source limit")
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, maximumBytes+1))
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("decode Recorder Gateway control response: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("Recorder Gateway control response has trailing JSON values")
	}
	return nil
}

func (reader *RecorderGatewayColdPathHTTPSourceReader) url(path string) string {
	copy := *reader.baseURL
	copy.Path = path
	return copy.String()
}

type recorderGatewayReadResult[T any] struct {
	SchemaVersion string        `json:"schemaVersion"`
	State         string        `json:"state"`
	ObservedAt    string        `json:"observedAt"`
	Value         *T            `json:"value,omitempty"`
	Issue         *gatewayIssue `json:"issue,omitempty"`
}

type gatewayIssue struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type recorderGatewayFinalizationReceipt struct {
	SchemaVersion           string                           `json:"schemaVersion"`
	ID                      string                           `json:"id"`
	CaptureReference        recorderGatewayResourceReference `json:"captureReference"`
	RecorderID              string                           `json:"recorderId"`
	FinalizedPacketSequence recorderGatewayPacketSequence    `json:"finalizedPacketSequence"`
	FinalizedAt             string                           `json:"finalizedAt"`
}

type recorderGatewayResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
}

type recorderGatewayPacketSequence struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
	MediaType    string `json:"mediaType"`
	SHA256       string `json:"sha256"`
}

func sourceReadResultEligibilityError(subject string, result recorderGatewayReadResult[recorderGatewayFinalizationReceipt]) error {
	if result.SchemaVersion != "v1" || result.ObservedAt == "" {
		return fmt.Errorf("Recorder Gateway %s read result does not satisfy the control contract", subject)
	}
	if !knownGatewayReadState(result.State) {
		return fmt.Errorf("Recorder Gateway %s read result has an unsupported state %q", subject, result.State)
	}
	message := "Recorder Gateway did not provide an available " + subject
	if result.Issue != nil && result.Issue.Message != "" {
		message += ": " + result.Issue.Message
	}
	return guestruntimeapplication.SourceEligibilityError{Issue: guestruntimedomain.Issue{Code: "recorder-cold-path-source-" + result.State, Message: message, Dependency: "recorder-gateway"}}
}

func knownGatewayReadState(value string) bool {
	switch value {
	case "available", "missing", "invalid", "unavailable", "failed", "stale", "empty", "unsupported":
		return true
	default:
		return false
	}
}

func validSHA256(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	for _, character := range value {
		if !(character >= 'a' && character <= 'f' || character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}

var _ guestruntimeapplication.GuestRuntimeRecorderColdPathPacketSequenceReader = (*RecorderGatewayColdPathHTTPSourceReader)(nil)
