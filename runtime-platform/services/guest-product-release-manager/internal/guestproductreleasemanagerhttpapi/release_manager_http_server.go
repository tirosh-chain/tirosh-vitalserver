// Package guestproductreleasemanagerhttpapi exposes the C59 loopback API.
// It is deliberately a narrow adapter: command metadata is strict JSON while
// the release archive remains a streaming multipart part, never base64 state
// embedded in a control document.
package guestproductreleasemanagerhttpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleasemanagerconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

const (
	releaseUpdatesPath       = "/v1/guest-product-release-updates"
	maximumCommandBytes      = 1024 * 1024
	maximumMultipartOverhead = 4 * 1024 * 1024
)

type ReleaseManagementApplication interface {
	ApplyReleaseUpdate(context.Context, guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, io.Reader) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, error)
	ReadReleaseOperation(context.Context, string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error)
}

// NewGuestProductReleaseManagerHTTPHandler validates the complete multipart
// command boundary before calling the application. The archive part must be
// after the command part; this preserves streaming without buffering a
// potentially GiB-sized release in HTTP memory.
func NewGuestProductReleaseManagerHTTPHandler(maximumReleaseArtifactBytes int64, application ReleaseManagementApplication) (http.Handler, error) {
	if maximumReleaseArtifactBytes < 1 || application == nil {
		return nil, fmt.Errorf("C59 HTTP API requires a maximum archive size and release-management application")
	}
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch {
		case request.URL.Path == releaseUpdatesPath:
			handleReleaseUpdateCollection(response, request, maximumReleaseArtifactBytes, application)
		case strings.HasPrefix(request.URL.Path, releaseUpdatesPath+"/"):
			handleReleaseUpdateItem(response, request, application)
		default:
			http.Error(response, "Guest Product Release Manager route was not found", http.StatusNotFound)
		}
	}), nil
}

func handleReleaseUpdateCollection(response http.ResponseWriter, request *http.Request, maximumReleaseArtifactBytes int64, application ReleaseManagementApplication) {
	if request.Method != http.MethodPost {
		methodNotAllowed(response, http.MethodPost)
		return
	}
	if request.ContentLength > maximumReleaseArtifactBytes+maximumMultipartOverhead {
		http.Error(response, "C59 release upload exceeds the configured maximum archive size", http.StatusRequestEntityTooLarge)
		return
	}
	request.Body = http.MaxBytesReader(response, request.Body, maximumReleaseArtifactBytes+maximumMultipartOverhead)
	multipartReader, err := request.MultipartReader()
	if err != nil {
		http.Error(response, "C59 release upload must be multipart/form-data", http.StatusUnsupportedMediaType)
		return
	}
	command, archive, err := readReleaseUploadParts(multipartReader)
	if err != nil {
		writeReleaseUploadError(response, err)
		return
	}
	operation, applyErr := application.ApplyReleaseUpdate(request.Context(), command, archive)
	if applyErr != nil {
		http.Error(response, "C59 release update could not be applied: "+applyErr.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(response, statusForOperation(operation), operation)
}

func handleReleaseUpdateItem(response http.ResponseWriter, request *http.Request, application ReleaseManagementApplication) {
	if request.Method != http.MethodGet {
		methodNotAllowed(response, http.MethodGet)
		return
	}
	updateID := strings.TrimPrefix(request.URL.Path, releaseUpdatesPath+"/")
	if updateID == "" || strings.Contains(updateID, "/") {
		http.Error(response, "C59 release update id is invalid", http.StatusBadRequest)
		return
	}
	operation, found, err := application.ReadReleaseOperation(request.Context(), updateID)
	if err != nil {
		http.Error(response, "C59 release operation could not be read: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if !found {
		http.Error(response, "C59 release operation was not found", http.StatusNotFound)
		return
	}
	writeJSON(response, http.StatusOK, operation)
}

func readReleaseUploadParts(reader *multipart.Reader) (guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, io.Reader, error) {
	var command guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand
	commandReceived := false
	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload requires exactly one command and one releaseArchive part"}
		}
		if err != nil {
			return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload could not read its next part"}
		}
		switch part.FormName() {
		case "command":
			if commandReceived {
				part.Close()
				return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload contains more than one command part"}
			}
			decoded, decodeErr := guestproductreleasemanagerconfigurationfile.ParseReleaseUpdateCommand(io.LimitReader(part, maximumCommandBytes+1))
			part.Close()
			if decodeErr != nil {
				return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload command is invalid: " + decodeErr.Error()}
			}
			command = decoded
			commandReceived = true
		case "releaseArchive":
			if !commandReceived {
				part.Close()
				return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload requires command before releaseArchive"}
			}
			// The multipart Part remains valid until the application has read the
			// archive. The wrapper makes that full consumption meaningful: after
			// the stager reaches EOF it proves there is no third, undeclared part.
			// A prefix is therefore neither an accepted archive nor an accepted
			// multipart request.
			return command, &finalReleaseArchiveReader{part: part, reader: reader}, nil
		default:
			part.Close()
			return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, nil, releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload contains an unsupported multipart part"}
		}
	}
}

// finalReleaseArchiveReader preserves streaming while proving the archive is
// the terminal multipart part. It intentionally performs that check only at
// EOF: an earlier stager failure remains the stager's explicit failure and
// cannot be converted into a successful upload by draining unrelated bytes.
type finalReleaseArchiveReader struct {
	part            *multipart.Part
	reader          *multipart.Reader
	validated       bool
	validationError error
}

func (archive *finalReleaseArchiveReader) Read(buffer []byte) (int, error) {
	if archive.validated {
		return 0, archive.validationError
	}
	read, err := archive.part.Read(buffer)
	if !errors.Is(err, io.EOF) {
		return read, err
	}
	archive.validated = true
	if closeErr := archive.part.Close(); closeErr != nil {
		archive.validationError = fmt.Errorf("C59 release archive could not be closed: %w", closeErr)
		return read, archive.validationError
	}
	next, nextErr := archive.reader.NextPart()
	if errors.Is(nextErr, io.EOF) {
		archive.validationError = io.EOF
		return read, io.EOF
	}
	if next != nil {
		next.Close()
	}
	if nextErr != nil {
		archive.validationError = releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload could not validate its terminal archive part"}
		return read, archive.validationError
	}
	archive.validationError = releaseUploadError{status: http.StatusBadRequest, message: "C59 release upload requires exactly one command and one releaseArchive part"}
	return read, archive.validationError
}

type releaseUploadError struct {
	status  int
	message string
}

func (err releaseUploadError) Error() string { return err.message }

func writeReleaseUploadError(response http.ResponseWriter, err error) {
	var uploadError releaseUploadError
	if errors.As(err, &uploadError) {
		http.Error(response, uploadError.message, uploadError.status)
		return
	}
	http.Error(response, "C59 release upload is invalid", http.StatusBadRequest)
}

func statusForOperation(operation guestproductreleasemanagerdomain.GuestProductReleaseOperation) int {
	switch operation.State {
	case guestproductreleasemanagerdomain.OperationStateSucceeded, guestproductreleasemanagerdomain.OperationStateRolledBack:
		return http.StatusOK
	case guestproductreleasemanagerdomain.OperationStateUnavailable:
		return http.StatusServiceUnavailable
	case guestproductreleasemanagerdomain.OperationStateFailed:
		return http.StatusUnprocessableEntity
	default:
		return http.StatusAccepted
	}
}

func methodNotAllowed(response http.ResponseWriter, allowed string) {
	response.Header().Set("Allow", allowed)
	http.Error(response, "C59 release management route does not allow this HTTP method", http.StatusMethodNotAllowed)
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	if err := json.NewEncoder(response).Encode(value); err != nil {
		return
	}
}
