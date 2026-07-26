// Package guestbundledupstreamimagesetmanagerhttpapi exposes the C64
// loopback/AF_VSOCK API. The archive remains a streaming multipart part.
package guestbundledupstreamimagesetmanagerhttpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetmanagerconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

const imageSetUpdatesPath = "/v1/bundled-upstream-image-set-updates"
const maximumCommandBytes int64 = 1024 * 1024
const maximumMultipartOverhead int64 = 4 * 1024 * 1024

type ImageSetManagementApplication interface {
	ApplyImageSetUpdate(context.Context, guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, io.Reader) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, error)
	ReadImageSetOperation(context.Context, string) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, bool, error)
}

func NewImageSetManagerHTTPHandler(maximumImageSetArtifactBytes int64, application ImageSetManagementApplication) (http.Handler, error) {
	if maximumImageSetArtifactBytes < 1 || application == nil { return nil, fmt.Errorf("C64 HTTP API requires an archive limit and application") }
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch {
		case request.URL.Path == imageSetUpdatesPath: handleCollection(response, request, maximumImageSetArtifactBytes, application)
		case strings.HasPrefix(request.URL.Path, imageSetUpdatesPath+"/"): handleItem(response, request, application)
		default: http.Error(response, "Guest Bundled Upstream Image-set Manager route was not found", http.StatusNotFound)
		}
	}), nil
}

func handleCollection(response http.ResponseWriter, request *http.Request, maximumArtifactBytes int64, application ImageSetManagementApplication) {
	if request.Method != http.MethodPost { methodNotAllowed(response, http.MethodPost); return }
	if request.ContentLength > maximumArtifactBytes+maximumMultipartOverhead { http.Error(response, "C64 image-set upload exceeds the configured maximum archive size", http.StatusRequestEntityTooLarge); return }
	request.Body = http.MaxBytesReader(response, request.Body, maximumArtifactBytes+maximumMultipartOverhead)
	reader, err := request.MultipartReader()
	if err != nil { http.Error(response, "C64 image-set upload must be multipart/form-data", http.StatusUnsupportedMediaType); return }
	command, archive, err := readUploadParts(reader)
	if err != nil { writeUploadError(response, err); return }
	operation, applyErr := application.ApplyImageSetUpdate(request.Context(), command, archive)
	if applyErr != nil { http.Error(response, "C64 image-set update could not be applied: "+applyErr.Error(), http.StatusInternalServerError); return }
	writeJSON(response, statusForOperation(operation), operation)
}

func handleItem(response http.ResponseWriter, request *http.Request, application ImageSetManagementApplication) {
	if request.Method != http.MethodGet { methodNotAllowed(response, http.MethodGet); return }
	updateID := strings.TrimPrefix(request.URL.Path, imageSetUpdatesPath+"/")
	if updateID == "" || strings.Contains(updateID, "/") { http.Error(response, "C64 image-set update id is invalid", http.StatusBadRequest); return }
	operation, found, err := application.ReadImageSetOperation(request.Context(), updateID)
	if err != nil { http.Error(response, "C64 image-set operation could not be read: "+err.Error(), http.StatusInternalServerError); return }
	if !found { http.Error(response, "C64 image-set operation was not found", http.StatusNotFound); return }
	writeJSON(response, http.StatusOK, operation)
}

func readUploadParts(reader *multipart.Reader) (guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, io.Reader, error) {
	var command guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand
	commandReceived := false
	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload requires exactly one command and one imageSetArchive part"} }
		if err != nil { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload could not read its next part"} }
		switch part.FormName() {
		case "command":
			if commandReceived { part.Close(); return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload contains more than one command part"} }
			decoded, err := guestbundledupstreamimagesetmanagerconfigurationfile.ParseImageSetUpdateCommand(io.LimitReader(part, maximumCommandBytes+1)); part.Close()
			if err != nil { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload command is invalid: "+err.Error()} }
			command, commandReceived = decoded, true
		case "imageSetArchive":
			if !commandReceived { part.Close(); return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload requires command before imageSetArchive"} }
			return command, &finalArchiveReader{part: part, reader: reader}, nil
		default:
			part.Close(); return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, nil, uploadError{http.StatusBadRequest, "C64 image-set upload contains an unsupported multipart part"}
		}
	}
}

type finalArchiveReader struct { part *multipart.Part; reader *multipart.Reader; validated bool; validationError error }
func (archive *finalArchiveReader) Read(buffer []byte) (int, error) { if archive.validated { return 0, archive.validationError }; count, err := archive.part.Read(buffer); if !errors.Is(err, io.EOF) { return count, err }; archive.validated = true; if closeErr := archive.part.Close(); closeErr != nil { archive.validationError = closeErr; return count, closeErr }; next, nextErr := archive.reader.NextPart(); if errors.Is(nextErr, io.EOF) { archive.validationError = io.EOF; return count, io.EOF }; if next != nil { next.Close() }; if nextErr != nil { archive.validationError = uploadError{http.StatusBadRequest, "C64 image-set upload could not validate its terminal archive part"} } else { archive.validationError = uploadError{http.StatusBadRequest, "C64 image-set upload requires exactly one command and one imageSetArchive part"} }; return count, archive.validationError }
type uploadError struct { status int; message string }
func (value uploadError) Error() string { return value.message }
func writeUploadError(response http.ResponseWriter, err error) { var value uploadError; if errors.As(err, &value) { http.Error(response, value.message, value.status); return }; http.Error(response, "C64 image-set upload is invalid", http.StatusBadRequest) }
func statusForOperation(operation guestbundledupstreamimagesetmanagerdomain.ImageSetOperation) int { switch operation.State { case guestbundledupstreamimagesetmanagerdomain.OperationStateSucceeded: return http.StatusOK; case guestbundledupstreamimagesetmanagerdomain.OperationStateUnavailable: return http.StatusServiceUnavailable; case guestbundledupstreamimagesetmanagerdomain.OperationStateFailed: return http.StatusUnprocessableEntity; default: return http.StatusAccepted } }
func methodNotAllowed(response http.ResponseWriter, allowed string) { response.Header().Set("Allow", allowed); http.Error(response, "C64 image-set management route does not allow this HTTP method", http.StatusMethodNotAllowed) }
func writeJSON(response http.ResponseWriter, valueStatus int, value any) { response.Header().Set("Content-Type", "application/json"); response.WriteHeader(valueStatus); _ = json.NewEncoder(response).Encode(value) }
