package guestruntimecontrolhttpclient_test

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/guestruntimecontrolhttpclient"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (roundTrip roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return roundTrip(request)
}

func TestForwardStreamPreservesLabReplaySourceMetadataAndBytes(t *testing.T) {
	const commandHeader = "encoded-lab-replay-source-command"
	const content = "complete-vital-source-bytes"
	httpClient := &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
		if request.Method != http.MethodPost ||
			request.URL.Path != "/v1/runtime/lab/replay-sources" ||
			request.Header.Get("Content-Type") != "application/x-vital" ||
			request.Header.Get("X-Vital-Lab-Replay-Source-Command") != commandHeader ||
			request.ContentLength != int64(len(content)) {
			t.Errorf("forwarded request method=%s path=%s contentType=%s command=%s length=%d",
				request.Method,
				request.URL.Path,
				request.Header.Get("Content-Type"),
				request.Header.Get("X-Vital-Lab-Replay-Source-Command"),
				request.ContentLength,
			)
		}
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Errorf("read forwarded request: %v", err)
		}
		if string(body) != content {
			t.Errorf("forwarded body = %q", body)
		}
		return &http.Response{
			StatusCode: http.StatusAccepted,
			Header:     http.Header{"Content-Type": []string{"application/json"}},
			Body:       io.NopCloser(strings.NewReader(`{"state":"accepted"}`)),
			Request:    request,
		}, nil
	})}
	client, err := guestruntimecontrolhttpclient.NewGuestRuntimeControlHTTPClient(httpClient)
	if err != nil {
		t.Fatal(err)
	}
	forwarded, failure := client.ForwardStream(
		context.Background(),
		hostagentdomain.GuestRuntimeControlEndpoint{
			Address: hostagentdomain.ConfiguredGuestRuntimeControlHTTPAddress{
				Scheme: "http",
				Host:   "127.0.0.1",
				Port:   18443,
			},
		},
		hostagentapplication.GuestRuntimeControlHTTPStreamingRequest{
			Method:        http.MethodPost,
			Path:          "/v1/runtime/lab/replay-sources",
			ContentType:   "application/x-vital",
			ContentLength: int64(len(content)),
			Body:          strings.NewReader(content),
			Headers: map[string]string{
				"X-Vital-Lab-Replay-Source-Command": commandHeader,
			},
		},
	)
	if failure != nil {
		t.Fatalf("forward failure = %+v", failure)
	}
	if forwarded.StatusCode != http.StatusAccepted ||
		forwarded.ContentType != "application/json" ||
		string(forwarded.Body) != `{"state":"accepted"}` {
		t.Fatalf("forwarded response = %+v", forwarded)
	}
}
