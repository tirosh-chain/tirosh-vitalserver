package imagesetmanagerhttpclient

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

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

const maximumOperationBytes int64 = 1024 * 1024
type Client struct { httpClient *http.Client }
func New(timeout time.Duration) (*Client, error) { if timeout <= 0 { return nil, fmt.Errorf("C66 request timeout must be positive") }; return &Client{httpClient: &http.Client{Timeout: timeout}}, nil }
func (client *Client) ApplyImageSetUpdate(context context.Context, endpoint guestbundledupstreamimageseteffectexecutordomain.ImageSetManagerEndpoint, command guestbundledupstreamimageseteffectexecutordomain.ImageSetUpdateCommand, artifact guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact) (guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation, error) {
	if client == nil || client.httpClient == nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, failure(guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "image-set-manager-client-not-composed", "C64 HTTP client is not composed", "guest-bundled-upstream-image-set-manager") }
	reader, writer := io.Pipe(); multipartWriter := multipart.NewWriter(writer); writing := make(chan error, 1); go writeUpload(multipartWriter, writer, command, artifact, writing)
	request, err := http.NewRequestWithContext(context, http.MethodPost, endpoint.Scheme+"://"+endpoint.Host+":"+strconv.Itoa(endpoint.Port)+endpoint.Path, reader); if err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, failure(guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "c64-request-invalid", "create C64 upload request: "+err.Error(), "guest-bundled-upstream-image-set-manager") }; request.Header.Set("Content-Type", multipartWriter.FormDataContentType())
	response, requestErr := client.httpClient.Do(request); writeErr := <-writing
	if requestErr != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, failure(guestbundledupstreamimageseteffectexecutordomain.ReceiptStateUnavailable, "c64-transport-unavailable", "send C64 image-set upload: "+requestErr.Error(), "guest-bundled-upstream-image-set-manager") }; defer response.Body.Close()
	if writeErr != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, failure(guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "c55-artifact-stream-failed", "stream C64 image-set archive: "+writeErr.Error(), "host-update-staging") }
	operation, err := decodeOperation(response.Body); if err != nil { state, code := guestbundledupstreamimageseteffectexecutordomain.ReceiptStateFailed, "c64-response-invalid"; if response.StatusCode >= 500 { state, code = guestbundledupstreamimageseteffectexecutordomain.ReceiptStateUnavailable, "c64-response-unavailable" } else if response.StatusCode >= 400 { code = "c64-request-rejected" }; return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, failure(state, code, fmt.Sprintf("decode C64 image-set operation HTTP status %d: %v", response.StatusCode, err), "guest-bundled-upstream-image-set-manager") }
	return operation, nil
}
func writeUpload(multipartWriter *multipart.Writer, pipeWriter *io.PipeWriter, command guestbundledupstreamimageseteffectexecutordomain.ImageSetUpdateCommand, artifact guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact, completed chan<- error) { defer close(completed); finish := func(err error) { if closeErr := multipartWriter.Close(); err == nil && closeErr != nil { err = closeErr }; if err != nil { _ = pipeWriter.CloseWithError(err) } else { err = pipeWriter.Close() }; completed <- err }; commandPart, err := multipartWriter.CreateFormField("command"); if err != nil { finish(err); return }; if err := json.NewEncoder(commandPart).Encode(command); err != nil { finish(err); return }; archivePart, err := multipartWriter.CreateFormFile("imageSetArchive", "bundled-upstream-image-set.tar.gz"); if err != nil { finish(err); return }; file, err := os.Open(artifact.Path); if err != nil { finish(err); return }; defer file.Close(); if _, err := io.Copy(archivePart, file); err != nil { finish(err); return }; finish(nil) }
func decodeOperation(source io.Reader) (guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation, error) { contents, err := io.ReadAll(io.LimitReader(source, maximumOperationBytes+1)); if err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, err }; if int64(len(contents)) > maximumOperationBytes { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, fmt.Errorf("C64 image-set operation response exceeds maximum size") }; decoder := json.NewDecoder(strings.NewReader(string(contents))); decoder.DisallowUnknownFields(); var operation guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation; if err := decoder.Decode(&operation); err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, err }; if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) { return guestbundledupstreamimageseteffectexecutordomain.ImageSetOperation{}, fmt.Errorf("C64 image-set operation response contains multiple documents") }; return operation, nil }
func failure(state, code, message, dependency string) error { return guestbundledupstreamimageseteffectexecutordomain.ImageSetManagerRequestFailure{State: state, Issue: guestbundledupstreamimageseteffectexecutordomain.Issue{Code: code, Message: message, Dependency: dependency}} }
