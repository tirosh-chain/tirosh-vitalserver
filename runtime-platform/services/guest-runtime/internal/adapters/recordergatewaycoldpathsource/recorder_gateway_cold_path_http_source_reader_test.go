package recordergatewaycoldpathsource

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestRecorderGatewayColdPathHTTPSourceReaderReturnsReceiptVerifiedSequence(t *testing.T) {
	sequence := []byte("{\"payloadBase64\":\"e30=\"}\n")
	digest := sha256.Sum256(sequence)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/v1/recorder-cold-path/finalization-receipts/finalization-1":
			response.Header().Set("content-type", "application/json")
			_, _ = fmt.Fprintf(response, `{"schemaVersion":"v1","state":"available","observedAt":"2026-07-19T00:00:00Z","value":{"schemaVersion":"v1","id":"finalization-1","requestId":"finalize-1","captureReference":{"resourceType":"recorder-cold-path-capture","resourceId":"capture-1"},"expectedCaptureRevision":1,"finalizedCaptureRevision":2,"recorderId":"recorder-1","connection":{"sessionId":"session-1","protocolVersion":"v2"},"finalizedPacketSequence":{"resourceType":"recorder-cold-path-packet-sequence","resourceId":"capture-1","format":"recorder-gateway-cold-path-packet-sequence-v1","mediaType":"application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl","packetCount":1,"payloadByteCount":2,"sha256":"%s"},"finalizedAt":"2026-07-19T00:00:00Z"}}`, hex.EncodeToString(digest[:]))
		case "/v1/recorder-cold-path/captures/capture-1:packet-sequence":
			response.Header().Set("content-type", recorderGatewayPacketSequenceMediaType)
			_, _ = response.Write(sequence)
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	reader, err := NewRecorderGatewayColdPathHTTPSourceReader(server.URL)
	if err != nil {
		t.Fatalf("new source reader: %v", err)
	}
	value, err := reader.ReadFinalizedRecorderColdPathPacketSequence(context.Background(), guestruntimedomain.ArtifactExportSource{Kind: guestruntimedomain.RecorderGatewayColdPathArtifactExportSourceKind, ColdPathFinalizationReceiptID: "finalization-1"})
	if err != nil {
		t.Fatalf("read finalized packet sequence: %v", err)
	}
	if value.RecorderID != "recorder-1" || value.CaptureID != "capture-1" || string(value.Bytes) != string(sequence) {
		t.Fatalf("source value = %#v", value)
	}
}

func TestRecorderGatewayColdPathHTTPSourceReaderRejectsMismatchedDigest(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/v1/recorder-cold-path/finalization-receipts/finalization-1":
			response.Header().Set("content-type", "application/json")
			_, _ = response.Write([]byte(`{"schemaVersion":"v1","state":"available","value":{"schemaVersion":"v1","id":"finalization-1","captureReference":{"resourceType":"recorder-cold-path-capture","resourceId":"capture-1"},"recorderId":"recorder-1","finalizedPacketSequence":{"resourceType":"recorder-cold-path-packet-sequence","resourceId":"capture-1","mediaType":"application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"finalizedAt":"2026-07-19T00:00:00Z"}}`))
		case "/v1/recorder-cold-path/captures/capture-1:packet-sequence":
			response.Header().Set("content-type", recorderGatewayPacketSequenceMediaType)
			_, _ = response.Write([]byte("packet\n"))
		}
	}))
	defer server.Close()
	reader, err := NewRecorderGatewayColdPathHTTPSourceReader(server.URL)
	if err != nil {
		t.Fatalf("new source reader: %v", err)
	}
	_, err = reader.ReadFinalizedRecorderColdPathPacketSequence(context.Background(), guestruntimedomain.ArtifactExportSource{Kind: guestruntimedomain.RecorderGatewayColdPathArtifactExportSourceKind, ColdPathFinalizationReceiptID: "finalization-1"})
	if err == nil {
		t.Fatal("mismatched source digest was accepted")
	}
}

func TestRecorderGatewayColdPathHTTPSourceReaderPreservesKnownMissingReceiptAsEligibilityError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("content-type", "application/json")
		_, _ = response.Write([]byte(`{"schemaVersion":"v1","state":"missing","observedAt":"2026-07-19T00:00:00Z","issue":{"code":"receipt-missing","message":"not found"}}`))
	}))
	defer server.Close()
	reader, err := NewRecorderGatewayColdPathHTTPSourceReader(server.URL)
	if err != nil {
		t.Fatalf("new source reader: %v", err)
	}
	_, err = reader.ReadFinalizedRecorderColdPathPacketSequence(context.Background(), guestruntimedomain.ArtifactExportSource{Kind: guestruntimedomain.RecorderGatewayColdPathArtifactExportSourceKind, ColdPathFinalizationReceiptID: "finalization-1"})
	var eligibility guestruntimeapplication.SourceEligibilityError
	if !errors.As(err, &eligibility) || eligibility.Issue.Code != "recorder-cold-path-source-missing" {
		t.Fatalf("missing result error = %T %v", err, err)
	}
}
