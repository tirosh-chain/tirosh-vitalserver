// Package guestproductreleasemanagerhttpclient owns C61's declared Host-local
// HTTP transport to the C32 bridge. It does not decide C59/C55 semantics.
package guestproductreleasemanagerhttpclient

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

const maximumOperationBytes int64 = 1024 * 1024

type Client struct {
	httpClient *http.Client
}

func New(requestTimeout time.Duration) (*Client, error) {
	if requestTimeout <= 0 {
		return nil, fmt.Errorf("C61 request timeout must be positive")
	}
	return &Client{httpClient: &http.Client{Timeout: requestTimeout}}, nil
}

func (client *Client) ApplyReleaseUpdate(
	ctx context.Context,
	endpoint guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint,
	command guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand,
	artifact guestproductreleaseeffectexecutordomain.ReleaseArtifact,
) (guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation, error) {
	if client == nil || client.httpClient == nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, requestFailure(guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "guest-product-release-client-not-composed", "C59 HTTP client is not composed", "guest-product-release-manager")
	}
	reader, writer := io.Pipe()
	multipartWriter := multipart.NewWriter(writer)
	writing := make(chan error, 1)
	go writeReleaseUpload(multipartWriter, writer, command, artifact, writing)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpointURL(endpoint), reader)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, requestFailure(guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "c59-request-invalid", "create C59 upload request: "+err.Error(), "guest-product-release-manager")
	}
	request.Header.Set("Content-Type", multipartWriter.FormDataContentType())
	response, requestErr := client.httpClient.Do(request)
	writeErr := <-writing
	if requestErr != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, requestFailure(guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable, "c59-transport-unavailable", "send C59 release upload: "+requestErr.Error(), "guest-product-release-manager")
	}
	defer response.Body.Close()
	if writeErr != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, requestFailure(guestproductreleaseeffectexecutordomain.ReceiptStateFailed, "c55-artifact-stream-failed", "stream C59 release archive: "+writeErr.Error(), "host-update-staging")
	}
	operation, err := decodeOperation(response.Body)
	if err != nil {
		state := guestproductreleaseeffectexecutordomain.ReceiptStateFailed
		code := "c59-response-invalid"
		if response.StatusCode >= http.StatusInternalServerError {
			state = guestproductreleaseeffectexecutordomain.ReceiptStateUnavailable
			code = "c59-response-unavailable"
		} else if response.StatusCode >= http.StatusBadRequest {
			code = "c59-request-rejected"
		}
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, requestFailure(state, code, fmt.Sprintf("decode C59 release operation HTTP status %d: %v", response.StatusCode, err), "guest-product-release-manager")
	}
	return operation, nil
}

func requestFailure(state string, code string, message string, dependency string) error {
	return guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerRequestFailure{State: state, Issue: guestproductreleaseeffectexecutordomain.Issue{Code: code, Message: message, Dependency: dependency}}
}

func writeReleaseUpload(
	multipartWriter *multipart.Writer,
	pipeWriter *io.PipeWriter,
	command guestproductreleaseeffectexecutordomain.GuestProductReleaseUpdateCommand,
	artifact guestproductreleaseeffectexecutordomain.ReleaseArtifact,
	completed chan<- error,
) {
	defer close(completed)
	finish := func(err error) {
		if closeErr := multipartWriter.Close(); err == nil && closeErr != nil {
			err = closeErr
		}
		if err != nil {
			_ = pipeWriter.CloseWithError(err)
		} else {
			err = pipeWriter.Close()
		}
		completed <- err
	}
	commandPart, err := multipartWriter.CreateFormField("command")
	if err != nil {
		finish(err)
		return
	}
	if err := json.NewEncoder(commandPart).Encode(command); err != nil {
		finish(err)
		return
	}
	archivePart, err := multipartWriter.CreateFormFile("releaseArchive", "guest-product-release.tar.gz")
	if err != nil {
		finish(err)
		return
	}
	file, err := os.Open(artifact.Path)
	if err != nil {
		finish(err)
		return
	}
	defer file.Close()
	if _, err := io.Copy(archivePart, file); err != nil {
		finish(err)
		return
	}
	finish(nil)
}

func endpointURL(endpoint guestproductreleaseeffectexecutordomain.GuestProductReleaseManagerEndpoint) string {
	return endpoint.Scheme + "://" + endpoint.Host + ":" + strconv.Itoa(endpoint.Port) + endpoint.Path
}

func decodeOperation(source io.Reader) (guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation, error) {
	contents, err := io.ReadAll(io.LimitReader(source, maximumOperationBytes+1))
	if err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, err
	}
	if int64(len(contents)) > maximumOperationBytes {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 release operation response exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var operation guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation
	if err := decoder.Decode(&operation); err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 release operation response contains multiple documents")
	}
	return operation, nil
}
