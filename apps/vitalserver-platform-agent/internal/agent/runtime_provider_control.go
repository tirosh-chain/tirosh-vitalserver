package agent

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

func (h *Handler) controlRuntimeProvider(action provider.Action) http.HandlerFunc {
	return func(response http.ResponseWriter, request *http.Request) {
		if h.provider == nil || !h.provider.RuntimeProviderControlAvailable() {
			writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
				Code: "runtimeProviderControlUnavailable", Message: "Runtime Provider control is unavailable on this Platform Agent.",
			})
			return
		}
		h.providerMutation.Lock()
		defer h.providerMutation.Unlock()

		operationID, err := newProviderOperationID()
		if err != nil {
			writeJSON(response, http.StatusInternalServerError, contract.ErrorResponse{
				Code: "operationIdentityFailed", Message: err.Error(),
			})
			return
		}
		effectErr := h.provider.ControlRuntimeProvider(request.Context(), action)
		if effectErr != nil {
			kind := "runtime-provider-control-failed"
			var typed provider.EffectError
			if errors.As(effectErr, &typed) && typed.Kind != "" {
				kind = typed.Kind
			}
			message := effectErr.Error()
			writeJSON(response, http.StatusServiceUnavailable, contract.RuntimeProviderCommandResponse{
				OperationID: operationID, Action: string(action), State: "failed",
				Provider: owner.ReadRuntimeProvider(h.config.RuntimeProviderDocument),
				Failure:  &contract.PlatformCommandFailure{Kind: kind, Message: message},
			})
			return
		}

		writeJSON(response, http.StatusOK, contract.RuntimeProviderCommandResponse{
			OperationID: operationID, Action: string(action), State: "completed",
			Provider: owner.ReadRuntimeProvider(h.config.RuntimeProviderDocument), Failure: nil,
		})
	}
}

func newProviderOperationID() (string, error) {
	data := make([]byte, 16)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("Runtime Provider operation identity generation failed: %w", err)
	}
	return "provider-" + hex.EncodeToString(data), nil
}
