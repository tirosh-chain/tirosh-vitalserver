package agent

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

func (h *Handler) acquireOperationLease(response http.ResponseWriter, request *http.Request) {
	var body struct {
		Document json.RawMessage `json:"document"`
	}
	if err := decodeRequestJSON(response, request, &body); err != nil {
		writeLeaseRequestError(response, err)
		return
	}
	if err := owner.AcquireLease(h.config.OperationLeaseDocument, body.Document); err != nil {
		writeLeaseMutationError(response, err)
		return
	}
	var document struct {
		OperationID string `json:"operationId"`
	}
	_ = json.Unmarshal(body.Document, &document)
	writeJSON(response, http.StatusOK, map[string]string{
		"operationId": document.OperationID,
		"state":       "acquired",
	})
}

func (h *Handler) heartbeatOperationLease(response http.ResponseWriter, request *http.Request) {
	var body struct {
		OperationID string  `json:"operationId"`
		HeartbeatAt string  `json:"heartbeatAt"`
		ExpiresAt   *string `json:"expiresAt"`
	}
	if err := decodeRequestJSON(response, request, &body); err != nil {
		writeLeaseRequestError(response, err)
		return
	}
	if err := owner.HeartbeatLease(
		h.config.OperationLeaseDocument,
		body.OperationID,
		body.HeartbeatAt,
		body.ExpiresAt,
	); err != nil {
		writeLeaseMutationError(response, err)
		return
	}
	writeJSON(response, http.StatusOK, map[string]string{
		"operationId": body.OperationID,
		"state":       "heartbeatRecorded",
	})
}

func (h *Handler) releaseOperationLease(response http.ResponseWriter, request *http.Request) {
	var body struct {
		OperationID string `json:"operationId"`
	}
	if err := decodeRequestJSON(response, request, &body); err != nil {
		writeLeaseRequestError(response, err)
		return
	}
	if err := owner.ReleaseLease(h.config.OperationLeaseDocument, body.OperationID); err != nil {
		writeLeaseMutationError(response, err)
		return
	}
	writeJSON(response, http.StatusOK, map[string]string{
		"operationId": body.OperationID,
		"state":       "released",
	})
}

func writeLeaseRequestError(response http.ResponseWriter, err error) {
	writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{
		Code: "badRequest", Message: err.Error(),
	})
}

func writeLeaseMutationError(response http.ResponseWriter, err error) {
	status := http.StatusInternalServerError
	code := "operationLeaseOwnerFailed"
	var leaseError owner.LeaseError
	if errors.As(err, &leaseError) {
		switch leaseError.Kind {
		case owner.LeaseInvalid:
			status = http.StatusBadRequest
			code = "badRequest"
		case owner.LeaseConflict:
			status = http.StatusConflict
			code = "operationConflict"
		}
	}
	writeJSON(response, status, contract.ErrorResponse{Code: code, Message: err.Error()})
}
