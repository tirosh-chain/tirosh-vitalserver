package agent

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

func (h *Handler) putRuntimeEndpoint(response http.ResponseWriter, request *http.Request) {
	var body struct {
		Address string `json:"address"`
	}
	if err := decodeRequestJSON(response, request, &body); err != nil {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{
			Code: "badRequest", Message: err.Error(),
		})
		return
	}
	if net.ParseIP(body.Address) == nil {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{
			Code: "badRequest", Message: "Runtime endpoint address must be an IP address.",
		})
		return
	}
	if err := owner.WriteEndpoint(h.config.RuntimeEndpointDocument, body.Address); err != nil {
		writeJSON(response, http.StatusInternalServerError, contract.ErrorResponse{
			Code: "ownerWriteFailed", Message: err.Error(),
		})
		return
	}
	writeJSON(response, http.StatusOK, owner.ReadEndpoint(h.config.RuntimeEndpointDocument))
}

func (h *Handler) putRuntimeProvider(response http.ResponseWriter, request *http.Request) {
	var body struct {
		Document json.RawMessage `json:"document"`
	}
	if err := decodeRequestJSON(response, request, &body); err != nil {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{
			Code: "badRequest", Message: err.Error(),
		})
		return
	}
	if err := owner.WriteRuntimeProvider(h.config.RuntimeProviderDocument, body.Document); err != nil {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{
			Code: "ownerWriteFailed", Message: err.Error(),
		})
		return
	}
	writeJSON(response, http.StatusOK, owner.ReadRuntimeProvider(h.config.RuntimeProviderDocument))
}

func decodeRequestJSON(response http.ResponseWriter, request *http.Request, destination any) error {
	decoder := json.NewDecoder(http.MaxBytesReader(response, request.Body, 1024*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return fmt.Errorf("request JSON decode failed: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		if err == nil {
			return fmt.Errorf("request JSON must contain one object")
		}
		return fmt.Errorf("request JSON trailing data invalid: %w", err)
	}
	return nil
}
