// Package hostagentcontrolhttpapi exposes Host-owned control state and an
// allowlisted Guest Runtime Control facade.
package hostagentcontrolhttpapi

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const maximumCommandBytes int64 = 1 << 20
const maximumLabReplaySourceBytes int64 = 1 << 30
const maximumLabReplaySourceCommandHeaderBytes = 16 << 10

type HostAgentControlHTTPServer struct {
	service   *hostagentapplication.HostAgentControlApplicationService
	updates   *hostagentapplication.HostUpdateApplicationService
	bundles   *hostagentapplication.HostUpdateBundleApplicationService
	time      *hostagentapplication.HostTimeAuthorityApplicationService
	telemetry *hostagentapplication.HostTelemetryPipelineApplicationService
}

func NewHostAgentControlHTTPServer(service *hostagentapplication.HostAgentControlApplicationService) *HostAgentControlHTTPServer {
	return &HostAgentControlHTTPServer{service: service}
}

// HostAgentControlHTTPModules makes the Host-owned lifecycle, time, and
// diagnostic telemetry application services explicit at HTTP composition time.
// NewHostAgentControlHTTPServer remains available to focused lifecycle tests;
// it does not manufacture the optional application services.
type HostAgentControlHTTPModules struct {
	Lifecycle *hostagentapplication.HostAgentControlApplicationService
	Update    *hostagentapplication.HostUpdateApplicationService
	Bundles   *hostagentapplication.HostUpdateBundleApplicationService
	Time      *hostagentapplication.HostTimeAuthorityApplicationService
	Telemetry *hostagentapplication.HostTelemetryPipelineApplicationService
}

func NewHostAgentControlHTTPServerWithModules(modules HostAgentControlHTTPModules) *HostAgentControlHTTPServer {
	return &HostAgentControlHTTPServer{
		service:   modules.Lifecycle,
		updates:   modules.Update,
		bundles:   modules.Bundles,
		time:      modules.Time,
		telemetry: modules.Telemetry,
	}
}

func (server *HostAgentControlHTTPServer) ServeHTTP(response http.ResponseWriter, request *http.Request) {
	switch {
	case request.Method == http.MethodGet && request.URL.Path == "/v1/platform/installation":
		writeJSON(response, http.StatusOK, server.service.ReadHostPlatformInstallation(request.Context()))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/platform/guest-runtime-control-endpoint":
		writeJSON(response, http.StatusOK, server.service.ReadGuestRuntimeControlEndpoint(request.Context()))
	case request.Method == http.MethodGet && strings.HasPrefix(request.URL.Path, "/v1/platform/operations/"):
		operationID := strings.TrimPrefix(request.URL.Path, "/v1/platform/operations/")
		if operationID == "" || strings.Contains(operationID, "/") {
			writeJSON(response, http.StatusOK, server.service.ReadHostGuestLifecycleOperation(request.Context(), "invalid"))
			return
		}
		writeJSON(response, http.StatusOK, server.service.ReadHostGuestLifecycleOperation(request.Context(), operationID))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/guest:start":
		server.executeLifecycle(response, request, "start")
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/guest:stop":
		server.executeLifecycle(response, request, "stop")
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/guest:reboot":
		server.executeLifecycle(response, request, "reboot")
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/updates":
		server.applyUpdate(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/update-bundles:import":
		server.importUpdateBundle(response, request)
	case request.Method == http.MethodPost && updateBundleApplyID(request.URL.Path) != "":
		server.applyImportedUpdateBundle(response, request, updateBundleApplyID(request.URL.Path))
	case request.Method == http.MethodGet && pathParameter(request.URL.Path, "/v1/platform/update-bundles/") != "":
		server.getUpdateBundle(response, request, pathParameter(request.URL.Path, "/v1/platform/update-bundles/"))
	case request.Method == http.MethodGet && pathParameter(request.URL.Path, "/v1/platform/updates/") != "":
		server.getUpdate(response, request, pathParameter(request.URL.Path, "/v1/platform/updates/"))
	case request.Method == http.MethodPost && updateCompletionID(request.URL.Path) != "":
		server.completeUpdate(response, request, updateCompletionID(request.URL.Path))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/time/authorities":
		server.applyTimeAuthority(response, request)
	case request.Method == http.MethodGet && pathParameter(request.URL.Path, "/v1/platform/time/authorities/") != "":
		server.getTimeAuthority(response, request, pathParameter(request.URL.Path, "/v1/platform/time/authorities/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/platform/time/clock-quality":
		server.getClockQuality(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/telemetry/pipelines":
		server.applyTelemetryPipeline(response, request)
	case request.Method == http.MethodGet && pathParameter(request.URL.Path, "/v1/platform/telemetry/pipelines/") != "":
		server.getTelemetryPipeline(response, request, pathParameter(request.URL.Path, "/v1/platform/telemetry/pipelines/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/platform/telemetry/signals":
		server.emitTelemetrySignal(response, request)
	case request.Method == http.MethodGet && pathParameter(request.URL.Path, "/v1/platform/telemetry/receipts/") != "":
		server.getTelemetryReceipt(response, request, pathParameter(request.URL.Path, "/v1/platform/telemetry/receipts/"))
	case request.Method == http.MethodGet && allowedRuntimeRead(request.URL.Path):
		server.forwardRuntimeRead(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/lab/replay-sources":
		server.forwardRuntimeStream(response, request)
	case request.Method == http.MethodPost && allowedRuntimeCommand(request.URL.Path):
		server.forwardRuntimeCommand(response, request)
	default:
		writeJSON(response, http.StatusNotFound, map[string]string{"error": "control route is not implemented by Host Agent"})
	}
}

func (server *HostAgentControlHTTPServer) importUpdateBundle(response http.ResponseWriter, request *http.Request) {
	if server.bundles == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "host-update-bundle-unavailable", "Host update bundle store is not configured"))
		return
	}
	var command hostagentdomain.HostUpdateBundleImportCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-host-update-bundle-import-command-envelope", err.Error()))
		return
	}
	receipt, rejection, admissionFailure := server.bundles.ImportHostUpdateBundleCommand(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusCreated, receipt)
}

func (server *HostAgentControlHTTPServer) getUpdateBundle(response http.ResponseWriter, request *http.Request, bundleID string) {
	if server.bundles == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableRead("host-update-bundle-unavailable", "Host update bundle store is not configured"))
		return
	}
	writeJSON(response, http.StatusOK, server.bundles.ReadHostUpdateBundle(request.Context(), bundleID))
}

func (server *HostAgentControlHTTPServer) applyImportedUpdateBundle(response http.ResponseWriter, request *http.Request, bundleID string) {
	if server.bundles == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "host-update-bundle-unavailable", "Host update bundle store is not configured"))
		return
	}
	var command hostagentdomain.HostUpdateBundleApplyCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-host-update-bundle-apply-command-envelope", err.Error()))
		return
	}
	if command.BundleReferenceID != bundleID {
		writeJSON(response, http.StatusBadRequest, malformedRejection(command.RequestID, "update-bundle-id-route-mismatch", "bundleReferenceId must match the requested route"))
		return
	}
	outcome, rejection, admissionFailure := server.bundles.ApplyHostUpdateBundleCommand(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, outcome)
}

func (server *HostAgentControlHTTPServer) applyUpdate(response http.ResponseWriter, request *http.Request) {
	if server.updates == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "host-update-unavailable", "Host update module is not configured"))
		return
	}
	var command hostagentdomain.HostUpdateCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-host-update-command-envelope", err.Error()))
		return
	}
	outcome, rejection, admissionFailure := server.updates.ExecuteHostUpdateCommand(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, outcome)
}

func (server *HostAgentControlHTTPServer) getUpdate(response http.ResponseWriter, request *http.Request, updateID string) {
	if server.updates == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableRead("host-update-unavailable", "Host update module is not configured"))
		return
	}
	writeJSON(response, http.StatusOK, server.updates.ReadHostUpdateJournal(request.Context(), updateID))
}

func (server *HostAgentControlHTTPServer) completeUpdate(response http.ResponseWriter, request *http.Request, updateID string) {
	if server.updates == nil {
		writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "host-update-unavailable", "Host update module is not configured"))
		return
	}
	var command hostagentdomain.UpdateCompletionCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-update-completion-command-envelope", err.Error()))
		return
	}
	if command.UpdateID != updateID {
		writeJSON(response, http.StatusBadRequest, malformedRejection(command.Report.RequestID, "update-id-route-mismatch", "updateId must match the requested route"))
		return
	}
	outcome, rejection, admissionFailure := server.updates.CompleteHostUpdateExecution(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, outcome)
}

func (server *HostAgentControlHTTPServer) applyTimeAuthority(response http.ResponseWriter, request *http.Request) {
	if server.time == nil {
		server.writeTimeCommandUnavailable(response, request)
		return
	}
	var command hostagentdomain.TimeAuthorityApplyCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-time-authority-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.time.ApplyHostTimeAuthorityCommand(request.Context(), command)
	writeOperationalCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *HostAgentControlHTTPServer) getTimeAuthority(response http.ResponseWriter, request *http.Request, id string) {
	if server.time == nil {
		server.writeTimeUnavailable(response)
		return
	}
	writeJSON(response, http.StatusOK, server.time.ReadHostTimeAuthority(request.Context(), id))
}

func (server *HostAgentControlHTTPServer) getClockQuality(response http.ResponseWriter, request *http.Request) {
	if server.time == nil {
		server.writeTimeUnavailable(response)
		return
	}
	writeJSON(response, http.StatusOK, server.time.ReadHostClockQuality(request.Context()))
}

func (server *HostAgentControlHTTPServer) applyTelemetryPipeline(response http.ResponseWriter, request *http.Request) {
	if server.telemetry == nil {
		server.writeTelemetryCommandUnavailable(response, request)
		return
	}
	var command hostagentdomain.TelemetryPipelineApplyCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-telemetry-pipeline-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.telemetry.ApplyHostTelemetryPipelineCommand(request.Context(), command)
	writeOperationalCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *HostAgentControlHTTPServer) getTelemetryPipeline(response http.ResponseWriter, request *http.Request, id string) {
	if server.telemetry == nil {
		server.writeTelemetryUnavailable(response)
		return
	}
	writeJSON(response, http.StatusOK, server.telemetry.ReadHostTelemetryPipeline(request.Context(), id))
}

func (server *HostAgentControlHTTPServer) emitTelemetrySignal(response http.ResponseWriter, request *http.Request) {
	if server.telemetry == nil {
		server.writeTelemetryCommandUnavailable(response, request)
		return
	}
	var command hostagentdomain.TelemetrySignalEmitCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-telemetry-signal-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.telemetry.EmitHostTelemetrySignal(request.Context(), command)
	writeOperationalCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *HostAgentControlHTTPServer) getTelemetryReceipt(response http.ResponseWriter, request *http.Request, id string) {
	if server.telemetry == nil {
		server.writeTelemetryUnavailable(response)
		return
	}
	writeJSON(response, http.StatusOK, server.telemetry.ReadHostTelemetryEmissionReceipt(request.Context(), id))
}

func (server *HostAgentControlHTTPServer) executeLifecycle(response http.ResponseWriter, request *http.Request, action string) {
	var command hostagentdomain.GuestLifecycleCommand
	requestID, err := decodeStrictCommand(request, &command)
	if err != nil {
		rejection, rejectionErr := server.service.RejectMalformedGuestRuntimeControlCommand(requestID, err.Error())
		if rejectionErr != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if command.Action != action {
		rejection, rejectionErr := server.service.RejectMalformedGuestRuntimeControlCommand(command.RequestID, "lifecycle command action must match the requested route")
		if rejectionErr != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	operation, rejection, admissionFailure := server.service.ExecuteGuestLifecycleCommand(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (server *HostAgentControlHTTPServer) forwardRuntimeRead(response http.ResponseWriter, request *http.Request) {
	outcome, err := server.service.ForwardGuestRuntimeControlRead(request.Context(), request.URL.Path)
	if err != nil {
		writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent Guest facade failed"})
		return
	}
	if outcome.Response != nil {
		writeRaw(response, outcome.Response.StatusCode, outcome.Response.ContentType, outcome.Response.Body)
		return
	}
	writeJSON(response, http.StatusOK, outcome.ReadResult)
}

func (server *HostAgentControlHTTPServer) forwardRuntimeCommand(response http.ResponseWriter, request *http.Request) {
	body, requestID, err := readRawCommand(request)
	if err != nil {
		rejection, rejectionErr := server.service.RejectMalformedGuestRuntimeControlCommand(requestID, "Host Agent could not read forwarded command: "+err.Error())
		if rejectionErr != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	outcome, err := server.service.ForwardGuestRuntimeControlCommand(request.Context(), request.URL.Path, body, request.Header.Get("Content-Type"), requestID)
	if err != nil {
		writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent Guest command facade failed"})
		return
	}
	if outcome.Response != nil {
		writeRaw(response, outcome.Response.StatusCode, outcome.Response.ContentType, outcome.Response.Body)
		return
	}
	if outcome.Rejected != nil {
		writeJSON(response, http.StatusServiceUnavailable, outcome.Rejected)
		return
	}
	writeJSON(response, http.StatusBadGateway, outcome.Failure)
}

func (server *HostAgentControlHTTPServer) forwardRuntimeStream(
	response http.ResponseWriter,
	request *http.Request,
) {
	commandHeader := request.Header.Get("X-Vital-Lab-Replay-Source-Command")
	requestID := requestIDFromLabReplaySourceCommandHeader(commandHeader)
	switch {
	case request.Header.Get("Content-Type") != "application/x-vital":
		rejection, err := server.service.RejectMalformedGuestRuntimeControlCommand(
			requestID,
			"Lab replay source body must use application/x-vital",
		)
		if err != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusUnsupportedMediaType, rejection)
		return
	case commandHeader == "" ||
		len(commandHeader) > maximumLabReplaySourceCommandHeaderBytes:
		rejection, err := server.service.RejectMalformedGuestRuntimeControlCommand(
			requestID,
			"Lab replay source command header is missing or too large",
		)
		if err != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	case request.ContentLength < 0:
		rejection, err := server.service.RejectMalformedGuestRuntimeControlCommand(
			requestID,
			"Lab replay source requires an explicit Content-Length",
		)
		if err != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusLengthRequired, rejection)
		return
	case request.ContentLength > maximumLabReplaySourceBytes:
		rejection, err := server.service.RejectMalformedGuestRuntimeControlCommand(
			requestID,
			"Lab replay source exceeds the 1 GiB facade limit",
		)
		if err != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent could not create rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusRequestEntityTooLarge, rejection)
		return
	}
	request.Body = http.MaxBytesReader(
		response,
		request.Body,
		maximumLabReplaySourceBytes+1,
	)
	outcome, err := server.service.ForwardGuestRuntimeControlStream(
		request.Context(),
		hostagentapplication.GuestRuntimeControlHTTPStreamingRequest{
			Method:        http.MethodPost,
			Path:          request.URL.Path,
			ContentType:   request.Header.Get("Content-Type"),
			ContentLength: request.ContentLength,
			Body:          request.Body,
			Headers: map[string]string{
				"X-Vital-Lab-Replay-Source-Command": commandHeader,
			},
		},
		requestID,
	)
	if err != nil {
		writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Host Agent Guest streaming facade failed"})
		return
	}
	if outcome.Response != nil {
		writeRaw(response, outcome.Response.StatusCode, outcome.Response.ContentType, outcome.Response.Body)
		return
	}
	if outcome.Rejected != nil {
		writeJSON(response, http.StatusServiceUnavailable, outcome.Rejected)
		return
	}
	writeJSON(response, http.StatusBadGateway, outcome.Failure)
}

func requestIDFromLabReplaySourceCommandHeader(encoded string) string {
	if encoded == "" || len(encoded) > maximumLabReplaySourceCommandHeaderBytes {
		return ""
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(raw) > maximumLabReplaySourceCommandHeaderBytes {
		return ""
	}
	return requestIDFromRaw(raw)
}

func allowedRuntimeRead(path string) bool {
	if recorderObservabilityReadPathParameter(path) != "" {
		return true
	}
	if path == "/v1/runtime/topology" || path == "/v1/runtime/capabilities" || path == "/v1/runtime/readiness" ||
		path == "/v1/runtime/lab/sessions" || path == "/v1/runtime/lab/beds" || path == "/v1/runtime/lab/recorders" ||
		path == "/v1/runtime/recorders" ||
		path == "/v1/runtime/operational-state/identity" ||
		path == "/v1/runtime/archive/export-provider" ||
		path == "/v1/runtime/archive/credential-material" ||
		path == "/v1/runtime/external-upstreams" || path == "/v1/runtime/relay-targets" ||
		path == "/v1/time/clock-quality" {
		return true
	}
	guestOperationalStateOperationID := strings.TrimPrefix(
		path,
		"/v1/runtime/operational-state/operations/",
	)
	if guestOperationalStateOperationID != path &&
		guestOperationalStateOperationID != "" &&
		!strings.Contains(guestOperationalStateOperationID, "/") {
		return true
	}
	operationID := strings.TrimPrefix(path, "/v1/runtime/operations/")
	if operationID != path && operationID != "" && !strings.Contains(operationID, "/") {
		return true
	}
	for _, prefix := range []string{
		"/v1/runtime/lab/sessions/",
		"/v1/runtime/lab/beds/",
		"/v1/runtime/lab/recorders/",
		"/v1/runtime/lab/replays/",
		"/v1/runtime/lab/deletion-receipts/",
		"/v1/runtime/archive/manifests/",
		"/v1/runtime/archive/export-receipts/",
		"/v1/runtime/artifacts/",
		"/v1/runtime/external-upstreams/",
		"/v1/runtime/relay-targets/",
		"/v1/time/authorities/",
		"/v1/runtime/catalog/recorder-observations/",
		"/v1/runtime/telemetry/pipelines/",
		"/v1/runtime/telemetry/receipts/",
	} {
		value := strings.TrimPrefix(path, prefix)
		if value != path && value != "" && !strings.Contains(value, "/") {
			return true
		}
	}
	return false
}

func recorderObservabilityReadPathParameter(path string) string {
	const prefix = "/v1/runtime/recorders/"
	value := strings.TrimPrefix(path, prefix)
	if value == path {
		return ""
	}
	for _, suffix := range []string{"/observability", "/observability/timeline", "/observability/incidents", "/artifacts"} {
		if strings.HasSuffix(value, suffix) {
			recorderID := strings.TrimSuffix(value, suffix)
			if recorderID != "" && !strings.Contains(recorderID, "/") {
				return recorderID
			}
		}
	}
	return ""
}

func allowedRuntimeCommand(path string) bool {
	if recorderExpectationCommandPathParameter(path) != "" {
		return true
	}
	return path == "/v1/runtime/topology:apply" ||
		path == "/v1/runtime/recorder-assignments" ||
		path == "/v1/runtime/operational-state/backups" ||
		path == "/v1/runtime/operational-state/restores" ||
		path == "/v1/runtime/lab/sessions" ||
		path == "/v1/runtime/lab/replays" ||
		path == "/v1/runtime/lab/resources:command" ||
		path == "/v1/runtime/archive/exports" ||
		path == "/v1/runtime/archive/credential-material" ||
		path == "/v1/runtime/external-upstreams" ||
		path == "/v1/runtime/relay-targets" ||
		path == "/v1/time/authorities" ||
		path == "/v1/runtime/telemetry/pipelines" ||
		path == "/v1/runtime/telemetry/signals"
}

func recorderExpectationCommandPathParameter(path string) string {
	const prefix = "/v1/runtime/recorders/"
	const suffix = "/observability-expectation"
	value := strings.TrimPrefix(path, prefix)
	if value == path || !strings.HasSuffix(value, suffix) {
		return ""
	}
	value = strings.TrimSuffix(value, suffix)
	if value == "" || strings.Contains(value, "/") {
		return ""
	}
	return value
}

func pathParameter(path string, prefix string) string {
	value := strings.TrimPrefix(path, prefix)
	if value == path || value == "" || strings.Contains(value, "/") {
		return ""
	}
	return value
}

func updateCompletionID(path string) string {
	const prefix = "/v1/platform/updates/"
	const suffix = ":complete"
	if !strings.HasPrefix(path, prefix) || !strings.HasSuffix(path, suffix) {
		return ""
	}
	value := strings.TrimSuffix(strings.TrimPrefix(path, prefix), suffix)
	if value == "" || strings.Contains(value, "/") {
		return ""
	}
	return value
}

func updateBundleApplyID(path string) string {
	const prefix = "/v1/platform/update-bundles/"
	const suffix = ":apply"
	if !strings.HasPrefix(path, prefix) || !strings.HasSuffix(path, suffix) {
		return ""
	}
	value := strings.TrimSuffix(strings.TrimPrefix(path, prefix), suffix)
	if value == "" || strings.Contains(value, "/") {
		return ""
	}
	return value
}

func decodeStrictCommand(request *http.Request, destination any) (string, error) {
	body, requestID, err := readRawCommand(request)
	if err != nil {
		return requestID, err
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return requestID, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return requestID, errors.New("command body must contain exactly one JSON object")
	}
	return requestID, nil
}

func readRawCommand(request *http.Request) ([]byte, string, error) {
	body, err := io.ReadAll(io.LimitReader(request.Body, maximumCommandBytes+1))
	if err != nil {
		return nil, "", err
	}
	requestID := requestIDFromRaw(body)
	if len(body) > int(maximumCommandBytes) {
		return nil, requestID, errors.New("command body exceeds the 1 MiB limit")
	}
	return body, requestID, nil
}

func requestIDFromRaw(body []byte) string {
	var envelope struct {
		RequestID string `json:"requestId"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return ""
	}
	return envelope.RequestID
}

func writeOperationalCommandOutcome(response http.ResponseWriter, operation hostagentdomain.Operation, rejection *hostagentdomain.CommandRejection, admissionFailure *hostagentdomain.CommandAdmissionFailure) {
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func malformedRejection(requestID string, code string, message string) hostagentdomain.CommandRejection {
	if !hostagentdomain.ValidIdentifier(requestID) {
		requestID = "rejection-unavailable-request-id"
	}
	return hostagentdomain.CommandRejection{
		SchemaVersion: hostagentdomain.SchemaVersion,
		State:         "rejected",
		RequestID:     requestID,
		RejectedAt:    hostagentdomain.Timestamp(hostagentapplication.SystemHostAgentClock{}.Now()),
		Issue:         hostagentdomain.Issue{Code: code, Message: message},
	}
}

func (server *HostAgentControlHTTPServer) writeTimeUnavailable(response http.ResponseWriter) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("time-authority-unavailable", "Host Time Authority module is not configured"))
}

func (server *HostAgentControlHTTPServer) writeTimeCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "time-authority-unavailable", "Host Time Authority module is not configured"))
}

func (server *HostAgentControlHTTPServer) writeTelemetryUnavailable(response http.ResponseWriter) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("telemetry-pipeline-unavailable", "Host Telemetry Pipeline module is not configured"))
}

func (server *HostAgentControlHTTPServer) writeTelemetryCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "telemetry-pipeline-unavailable", "Host Telemetry Pipeline module is not configured"))
}

func unavailableRead(code string, message string) hostagentdomain.ReadResult {
	return hostagentdomain.ReadResult{
		SchemaVersion: hostagentdomain.SchemaVersion,
		State:         "unavailable",
		ObservedAt:    hostagentdomain.Timestamp(hostagentapplication.SystemHostAgentClock{}.Now()),
		Issue:         &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(true), Dependency: "host-agent"},
	}
}

func unavailableAdmission(requestID string, code string, message string) hostagentdomain.CommandAdmissionFailure {
	return hostagentdomain.CommandAdmissionFailure{
		SchemaVersion:  hostagentdomain.SchemaVersion,
		State:          "failed",
		RequestID:      requestID,
		ObservedAt:     hostagentdomain.Timestamp(hostagentapplication.SystemHostAgentClock{}.Now()),
		AdmissionState: "not-admitted",
		Issue:          hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(true), Dependency: "host-agent"},
	}
}

func requestIDFromRequest(request *http.Request) string {
	if request == nil {
		return ""
	}
	return request.Header.Get("X-Request-Id")
}

func writeJSON(response http.ResponseWriter, status int, document any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(document)
}

func writeRaw(response http.ResponseWriter, status int, contentType string, body []byte) {
	if contentType != "" {
		response.Header().Set("Content-Type", contentType)
	}
	response.WriteHeader(status)
	_, _ = response.Write(body)
}
