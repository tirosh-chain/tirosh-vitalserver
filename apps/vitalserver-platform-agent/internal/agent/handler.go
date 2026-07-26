package agent

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

type ServiceObserver interface {
	ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue)
}

type Handler struct {
	config           Config
	services         ServiceObserver
	startedAt        string
	mux              *http.ServeMux
	provider         provider.Controller
	providerMutation sync.Mutex
	delivery         *deliveryController
	deliveryMutation sync.Mutex
	browserSessions  *browserSessionController
}

func NewHandler(config Config, services ServiceObserver, now time.Time) *Handler {
	handler := &Handler{
		config: config, services: services, startedAt: now.UTC().Format(time.RFC3339),
		mux: http.NewServeMux(),
	}
	if controller, ok := services.(provider.Controller); ok {
		handler.provider = controller
	}
	if config.PWA != "" {
		handler.browserSessions, _ = newBrowserSessionController(config.ListenAddress, time.Now)
	}
	handler.delivery = newDeliveryController(config.Delivery)
	handler.routes()
	return handler
}

func (h *Handler) ServeHTTP(response http.ResponseWriter, request *http.Request) {
	if (strings.HasPrefix(request.URL.Path, "/platform") || strings.HasPrefix(request.URL.Path, "/runtime")) &&
		!(request.Method == http.MethodPost && request.URL.Path == browserSessionBootstrapPath) &&
		!h.authorized(request) {
		writeJSON(response, http.StatusUnauthorized, contract.ErrorResponse{
			Code: "unauthorized", Message: "Runtime Control API credentials are missing or invalid.",
		})
		return
	}
	h.mux.ServeHTTP(response, request)
}

func (h *Handler) routes() {
	h.mux.HandleFunc("GET /health", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]string{"state": "healthy"})
	})
	h.mux.HandleFunc("GET /platform", h.getPlatform)
	h.mux.HandleFunc("GET /platform/capabilities", h.getCapabilities)
	h.mux.HandleFunc("GET /platform/settings", h.platformSettingsUnavailable)
	h.mux.HandleFunc("PUT /platform/settings", h.platformSettingsUnavailable)
	h.mux.HandleFunc("GET /platform/release", h.releaseMetadataUnavailable)
	h.mux.HandleFunc("GET /platform/installation", h.installMetadataUnavailable)
	h.mux.HandleFunc("GET /platform/operations", h.getOperations)
	h.mux.HandleFunc("POST /platform/operations/lease/acquire", h.acquireOperationLease)
	h.mux.HandleFunc("POST /platform/operations/lease/heartbeat", h.heartbeatOperationLease)
	h.mux.HandleFunc("POST /platform/operations/lease/release", h.releaseOperationLease)
	h.mux.HandleFunc("GET /platform/runtime-endpoint", h.getRuntimeEndpoint)
	h.mux.HandleFunc("PUT /platform/runtime-endpoint", h.putRuntimeEndpoint)
	h.mux.HandleFunc("GET /platform/runtime-provider", h.getRuntimeProvider)
	h.mux.HandleFunc("PUT /platform/runtime-provider", h.putRuntimeProvider)
	h.mux.HandleFunc("POST /platform/runtime-provider/start", h.controlRuntimeProvider(provider.ActionStart))
	h.mux.HandleFunc("POST /platform/runtime-provider/stop", h.controlRuntimeProvider(provider.ActionStop))
	h.mux.HandleFunc("POST /platform/runtime-provider/restart", h.controlRuntimeProvider(provider.ActionRestart))
	h.mux.HandleFunc("GET /platform/workflows/current", h.getPlatformWorkflow)
	h.mux.HandleFunc("POST /platform/update-bundles/summary", h.summarizeUpdateBundle)
	h.mux.HandleFunc("POST /platform/update-bundles/verify", h.scheduleUpdateBundle("verify"))
	h.mux.HandleFunc("POST /platform/update-bundles/apply", h.scheduleUpdateBundle("apply"))
	h.mux.HandleFunc("POST /platform/releases/rollback", h.scheduleReleaseRollback)
	h.mux.HandleFunc("POST /platform/uninstall", h.schedulePlatformUninstall)
	h.mux.HandleFunc("POST /platform/support-exports", h.schedulePlatformSupportExport)
	h.mux.HandleFunc("/runtime/", h.proxyRuntime)
	if h.config.PWA != "" {
		h.mux.HandleFunc("POST "+browserSessionBootstrapPath, h.createBrowserSession)
		h.mux.Handle("/", http.FileServer(http.Dir(h.config.PWA)))
	}
}

func (h *Handler) platformSettingsUnavailable(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
		Code:    "platformSettingsUnavailable",
		Message: "Platform settings are not supported by this Platform Agent.",
	})
}

func (h *Handler) releaseMetadataUnavailable(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
		Code:    "releaseMetadataUnavailable",
		Message: "Release metadata is not provided by this Platform Agent.",
	})
}

func (h *Handler) installMetadataUnavailable(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
		Code:    "installMetadataUnavailable",
		Message: "Installation metadata is not provided by this Platform Agent.",
	})
}

func (h *Handler) getPlatform(response http.ResponseWriter, _ *http.Request) {
	services, issues := h.services.ReadPlatformServices()
	provider := owner.ReadRuntimeProvider(h.config.RuntimeProviderDocument)
	endpoint := owner.ReadEndpoint(h.config.RuntimeEndpointDocument)
	installState, installedVersion, installIssue := readInstallDocument(h.config.InstallDocument)
	state := contract.PlatformState{
		RuntimeInstallationState: installState,
		Services:                 services,
		ReadIssues:               issues,
		InstalledVersion:         installedVersion,
		PlatformAPIStartedAt:     &h.startedAt,
		HealthIssues:             []string{},
	}
	if installIssue != nil {
		state.ReadIssues = append(state.ReadIssues, *installIssue)
	}
	reachable := "reachable"
	state.PlatformAPIHTTP = &reachable
	if provider.State == "loaded" {
		var document struct {
			State string `json:"state"`
		}
		if json.Unmarshal(provider.Document, &document) == nil && document.State != "" {
			state.RuntimeProviderState = &document.State
		}
	} else if provider.ReadError != nil {
		state.ReadIssues = append(state.ReadIssues, contract.ReadIssue{
			Source: "runtime-provider", Message: *provider.ReadError,
		})
	}
	if endpoint.State == "loaded" && endpoint.Read != nil {
		state.RuntimeEndpoint = endpoint.Read.Address
	} else if endpoint.ReadError != nil {
		state.ReadIssues = append(state.ReadIssues, contract.ReadIssue{
			Source: "runtime-endpoint", Message: *endpoint.ReadError,
		})
	}
	writeJSON(response, http.StatusOK, state)
}

func (h *Handler) getCapabilities(response http.ResponseWriter, _ *http.Request) {
	canControlRuntimeProvider := h.provider != nil && h.provider.RuntimeProviderControlAvailable()
	canApplyBundle := h.delivery != nil && h.delivery.canApplyBundle()
	writeJSON(response, http.StatusOK, contract.PlatformCapabilities{
		CanInstallRuntime: false, CanUninstallRuntime: h.delivery != nil && h.delivery.config.UninstallTool != "",
		CanApplyBundle: canApplyBundle, CanRollback: false,
		CanRollbackRelease:              h.delivery != nil,
		CanEditRuntimeProviderResources: false, CanEditNetworkExposure: false,
		CanResetAdminPassword: false, CanOpenLocalFiles: false,
		CanStreamLogs: false, CanControlRuntimeServices: canControlRuntimeProvider,
		CanExportLogs: h.delivery != nil && h.delivery.config.SupportExportTool != "", CanViewReleaseMetadata: false,
	})
}

func (h *Handler) getPlatformWorkflow(response http.ResponseWriter, _ *http.Request) {
	if h.delivery == nil {
		reason := "platform delivery owner is not configured"
		writeJSON(response, http.StatusOK, contract.PlatformWorkflowResource{
			State: "unavailable", ReadError: &reason,
		})
		return
	}
	writeJSON(response, http.StatusOK, owner.ReadPlatformWorkflow(h.delivery.config.WorkflowDocument))
}

func (h *Handler) summarizeUpdateBundle(response http.ResponseWriter, request *http.Request) {
	if h.delivery == nil {
		writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
			Code: "platformDeliveryUnavailable", Message: "Platform delivery is not configured.",
		})
		return
	}
	bundle, err := requiredLocalBundle(request)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{Code: "updateBundleInvalid", Message: err.Error()})
		return
	}
	summary, err := h.delivery.summarize(request.Context(), bundle)
	if err != nil {
		writeJSON(response, http.StatusUnprocessableEntity, contract.ErrorResponse{Code: "updateBundleInvalid", Message: err.Error()})
		return
	}
	writeJSON(response, http.StatusOK, summary)
}

func (h *Handler) scheduleUpdateBundle(action string) http.HandlerFunc {
	return func(response http.ResponseWriter, request *http.Request) {
		if h.delivery == nil {
			writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
				Code: "platformDeliveryUnavailable", Message: "Platform delivery is not configured.",
			})
			return
		}
		if action == "apply" && !h.delivery.canApplyBundle() {
			writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
				Code:    "updateApplyUnavailable",
				Message: "Update apply is disabled until trusted publisher verification is configured.",
			})
			return
		}
		bundle, err := requiredLocalBundle(request)
		if err != nil {
			writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{Code: "updateBundleInvalid", Message: err.Error()})
			return
		}
		h.deliveryMutation.Lock()
		defer h.deliveryMutation.Unlock()
		operation, err := h.delivery.schedule(request.Context(), action, bundle)
		if err != nil {
			if errors.Is(err, errUpdateBundleUntrusted) {
				writeJSON(response, http.StatusUnprocessableEntity, contract.ErrorResponse{Code: "updateBundleUntrusted", Message: err.Error()})
				return
			}
			if errors.Is(err, errTrustedDigestUnavailable) {
				writeJSON(response, http.StatusServiceUnavailable, contract.ErrorResponse{Code: "trustedBundleDigestUnavailable", Message: err.Error()})
				return
			}
			status := http.StatusServiceUnavailable
			if strings.Contains(err.Error(), "already active") {
				status = http.StatusConflict
			}
			if operation.SchemaVersion == 1 {
				writeJSON(response, status, operation)
			} else {
				writeJSON(response, status, contract.ErrorResponse{Code: "platformWorkflowFailed", Message: err.Error()})
			}
			return
		}
		writeJSON(response, http.StatusAccepted, operation)
	}
}

func (h *Handler) scheduleReleaseRollback(response http.ResponseWriter, request *http.Request) {
	if h.delivery == nil {
		writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
			Code: "platformDeliveryUnavailable", Message: "Platform delivery is not configured.",
		})
		return
	}
	h.deliveryMutation.Lock()
	defer h.deliveryMutation.Unlock()
	operation, err := h.delivery.scheduleRollback(request.Context())
	if err != nil {
		status := http.StatusServiceUnavailable
		if strings.Contains(err.Error(), "already active") {
			status = http.StatusConflict
		}
		if operation.SchemaVersion == 1 {
			writeJSON(response, status, operation)
		} else {
			writeJSON(response, status, contract.ErrorResponse{Code: "platformWorkflowFailed", Message: err.Error()})
		}
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (h *Handler) schedulePlatformUninstall(response http.ResponseWriter, request *http.Request) {
	if h.delivery == nil || h.delivery.config.UninstallTool == "" {
		writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
			Code: "platformUninstallUnavailable", Message: "Platform uninstall is not configured.",
		})
		return
	}
	var body struct {
		Mode string `json:"mode"`
	}
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil || (body.Mode != "standard" && body.Mode != "clean") {
		writeJSON(response, http.StatusBadRequest, contract.ErrorResponse{Code: "uninstallRequestInvalid", Message: "Uninstall mode must be standard or clean."})
		return
	}
	h.deliveryMutation.Lock()
	defer h.deliveryMutation.Unlock()
	operation, err := h.delivery.scheduleUninstall(request.Context(), body.Mode)
	if err != nil {
		status := http.StatusServiceUnavailable
		if strings.Contains(err.Error(), "already active") {
			status = http.StatusConflict
		}
		if operation.SchemaVersion == 1 {
			writeJSON(response, status, operation)
		} else {
			writeJSON(response, status, contract.ErrorResponse{Code: "platformWorkflowFailed", Message: err.Error()})
		}
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (h *Handler) schedulePlatformSupportExport(response http.ResponseWriter, request *http.Request) {
	if h.delivery == nil || h.delivery.config.SupportExportTool == "" {
		writeJSON(response, http.StatusNotImplemented, contract.ErrorResponse{
			Code: "platformSupportExportUnavailable", Message: "Platform support export is not configured.",
		})
		return
	}
	h.deliveryMutation.Lock()
	defer h.deliveryMutation.Unlock()
	operation, err := h.delivery.scheduleSupportExport(request.Context())
	if err != nil {
		status := http.StatusServiceUnavailable
		if strings.Contains(err.Error(), "already active") {
			status = http.StatusConflict
		}
		if operation.SchemaVersion == 1 {
			writeJSON(response, status, operation)
		} else {
			writeJSON(response, status, contract.ErrorResponse{Code: "platformWorkflowFailed", Message: err.Error()})
		}
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (h *Handler) getOperations(response http.ResponseWriter, _ *http.Request) {
	lease := owner.PresentOperationAt(owner.ReadOperation(h.config.OperationLeaseDocument), time.Now())
	writeJSON(response, http.StatusOK, contract.PlatformOperations{
		ActiveOperation: owner.ActiveOperation(lease),
		Install:         readInstallOperation(h.config.InstallDocument),
		Lease:           lease,
	})
}

func (h *Handler) getRuntimeEndpoint(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusOK, owner.ReadEndpoint(h.config.RuntimeEndpointDocument))
}

func (h *Handler) getRuntimeProvider(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusOK, owner.ReadRuntimeProvider(h.config.RuntimeProviderDocument))
}

func (h *Handler) authorized(request *http.Request) bool {
	if h.config.APIToken != "" &&
		(request.Header.Get("X-Runtime-Control-Token") == h.config.APIToken ||
			request.Header.Get("Authorization") == "Bearer "+h.config.APIToken) {
		return true
	}
	return h.browserSessions != nil && h.browserSessions.allows(request)
}

func (h *Handler) createBrowserSession(response http.ResponseWriter, request *http.Request) {
	if h.browserSessions == nil {
		writeJSON(response, http.StatusServiceUnavailable, contract.ErrorResponse{
			Code: "browserSessionUnavailable", Message: "Local browser session support is unavailable.",
		})
		return
	}
	cookie, err := h.browserSessions.issue(request)
	if err != nil {
		if errors.Is(err, errBrowserSessionOrigin) {
			writeJSON(response, http.StatusUnauthorized, contract.ErrorResponse{
				Code: "browserSessionOriginInvalid", Message: "Local browser session origin is missing or invalid.",
			})
			return
		}
		writeJSON(response, http.StatusServiceUnavailable, contract.ErrorResponse{
			Code: "browserSessionUnavailable", Message: err.Error(),
		})
		return
	}
	http.SetCookie(response, cookie)
	response.WriteHeader(http.StatusNoContent)
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(value)
}

func ValidatePWA(path string) error {
	if path == "" {
		return nil
	}
	_, err := os.Stat(filepath.Join(path, "index.html"))
	return err
}
