// Package guestruntimecontrolhttpapi exposes only versioned Guest Runtime control contracts.
package guestruntimecontrolhttpapi

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumCommandBytes int64 = 1 << 20

// GuestRuntimeControlHTTPServer exposes only versioned Guest Runtime control
// contracts. It formats explicit application outcomes; it does not own
// topology, Lab, archive, external integration, time, catalog, or telemetry state.
type GuestRuntimeControlHTTPServer struct {
	topologyService *guestruntimeapplication.GuestRuntimeTopologyApplicationService
	lab             *guestruntimeapplication.GuestRuntimeLabApplicationService
	archive         *guestruntimeapplication.GuestRuntimeArchiveApplicationService
	external        *guestruntimeapplication.GuestRuntimeExternalUpstreamApplicationService
	relay           *guestruntimeapplication.GuestRuntimeOutboundRelayApplicationService
	time            *guestruntimeapplication.GuestRuntimeTimeAuthorityApplicationService
	catalog         *guestruntimeapplication.GuestRuntimeObservationCatalogApplicationService
	telemetry       *guestruntimeapplication.GuestRuntimeTelemetryPipelineApplicationService
	coordinator     *guestruntimeapplication.GuestRuntimeLabArchiveLifecycleCoordinator
}

// GuestRuntimeControlModules keeps module composition named as the Guest Runtime grows.
// Callers cannot accidentally swap two state owners through a positional
// constructor argument.
type GuestRuntimeControlModules struct {
	Topology                             *guestruntimeapplication.GuestRuntimeTopologyApplicationService
	Lab                                  *guestruntimeapplication.GuestRuntimeLabApplicationService
	Archive                              *guestruntimeapplication.GuestRuntimeArchiveApplicationService
	ExternalUpstreamIntegration          *guestruntimeapplication.GuestRuntimeExternalUpstreamApplicationService
	OutboundRelayTarget                  *guestruntimeapplication.GuestRuntimeOutboundRelayApplicationService
	GuestTimeAuthority                   *guestruntimeapplication.GuestRuntimeTimeAuthorityApplicationService
	RecorderObservationCatalog           *guestruntimeapplication.GuestRuntimeObservationCatalogApplicationService
	GuestTelemetryPipeline               *guestruntimeapplication.GuestRuntimeTelemetryPipelineApplicationService
	LabArchiveLifecycleCoordinationClock guestruntimeapplication.GuestRuntimeClock
}

func NewGuestRuntimeTopologyHTTPServer(topologyService *guestruntimeapplication.GuestRuntimeTopologyApplicationService) *GuestRuntimeControlHTTPServer {
	return &GuestRuntimeControlHTTPServer{topologyService: topologyService}
}

// NewGuestRuntimeControlHTTPServer composes explicit Guest Runtime modules. The topology-only constructor
// remains for topology-only unit tests; it does not silently provide Lab or
// Archive behavior when those owners are absent.
func NewGuestRuntimeControlHTTPServer(topologyService *guestruntimeapplication.GuestRuntimeTopologyApplicationService, lab *guestruntimeapplication.GuestRuntimeLabApplicationService, archive *guestruntimeapplication.GuestRuntimeArchiveApplicationService) *GuestRuntimeControlHTTPServer {
	return NewGuestRuntimeControlHTTPServerWithModules(GuestRuntimeControlModules{Topology: topologyService, Lab: lab, Archive: archive})
}

func NewGuestRuntimeControlHTTPServerWithModules(modules GuestRuntimeControlModules) *GuestRuntimeControlHTTPServer {
	return &GuestRuntimeControlHTTPServer{
		topologyService: modules.Topology,
		lab:             modules.Lab,
		archive:         modules.Archive,
		external:        modules.ExternalUpstreamIntegration,
		relay:           modules.OutboundRelayTarget,
		time:            modules.GuestTimeAuthority,
		catalog:         modules.RecorderObservationCatalog,
		telemetry:       modules.GuestTelemetryPipeline,
		coordinator:     guestruntimeapplication.NewGuestRuntimeLabArchiveLifecycleCoordinator(modules.Lab, modules.Archive, modules.LabArchiveLifecycleCoordinationClock),
	}
}

func (server *GuestRuntimeControlHTTPServer) ServeHTTP(response http.ResponseWriter, request *http.Request) {
	switch {
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/topology":
		writeJSON(response, http.StatusOK, server.topologyService.ReadRuntimeTopology(request.Context()))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/capabilities":
		writeJSON(response, http.StatusOK, server.topologyService.ReadRuntimeTopologyCapabilityDocument(request.Context()))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/readiness":
		writeJSON(response, http.StatusOK, server.topologyService.ReadGuestRuntimeReadiness(request.Context()))
	case request.Method == http.MethodGet && strings.HasPrefix(request.URL.Path, "/v1/runtime/operations/"):
		operationID := strings.TrimPrefix(request.URL.Path, "/v1/runtime/operations/")
		if operationID == "" || strings.Contains(operationID, "/") {
			writeJSON(response, http.StatusOK, server.topologyService.ReadRuntimeTopologyOperation(request.Context(), "invalid"))
			return
		}
		writeJSON(response, http.StatusOK, server.topologyService.ReadRuntimeTopologyOperation(request.Context(), operationID))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/topology:apply":
		server.applyTopology(response, request)
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/lab/sessions":
		server.listLabSessions(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/lab/sessions":
		server.createLabSession(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/sessions/") != "":
		server.getLabSession(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/sessions/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/lab/beds":
		server.listLabBeds(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/beds/") != "":
		server.getLabBed(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/beds/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/lab/recorders":
		server.listVirtualRecorders(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/recorders/") != "":
		server.getVirtualRecorder(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/recorders/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/lab/resources:command":
		server.executeLabResource(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/deletion-receipts/") != "":
		server.getDeletionReceipt(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/deletion-receipts/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/archive/exports":
		server.exportArtifact(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/archive/manifests/") != "":
		server.getArtifactManifest(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/archive/manifests/"))
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/archive/export-receipts/") != "":
		server.getExportReceipt(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/archive/export-receipts/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/external-upstreams":
		server.listExternalUpstreams(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/external-upstreams":
		server.applyExternalUpstream(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/external-upstreams/") != "":
		server.getExternalUpstream(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/external-upstreams/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/relay-targets":
		server.listRelayTargets(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/relay-targets":
		server.applyRelayTarget(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/relay-targets/") != "":
		server.getRelayTarget(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/relay-targets/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/time/authorities":
		server.applyTimeAuthority(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/time/authorities/") != "":
		server.getTimeAuthority(response, request, runtimePathParameter(request.URL.Path, "/v1/time/authorities/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/time/clock-quality":
		server.getClockQuality(response, request)
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/catalog/recorder-observations":
		server.listCatalogObservations(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/catalog/recorder-observations":
		server.ingestCatalogObservation(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/catalog/recorder-observations/") != "":
		server.getCatalogObservation(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/catalog/recorder-observations/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/telemetry/pipelines":
		server.applyTelemetryPipeline(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/telemetry/pipelines/") != "":
		server.getTelemetryPipeline(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/telemetry/pipelines/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/telemetry/signals":
		server.emitTelemetrySignal(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/telemetry/receipts/") != "":
		server.getTelemetryReceipt(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/telemetry/receipts/"))
	default:
		response.Header().Set("Allow", "GET, POST")
		writeJSON(response, http.StatusNotFound, map[string]string{"error": "control route is not implemented by Guest Runtime"})
	}
}

func (server *GuestRuntimeControlHTTPServer) applyTimeAuthority(response http.ResponseWriter, request *http.Request) {
	if server.time == nil {
		server.writeTimeCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.TimeAuthorityApplyCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-time-authority-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.time.ApplyTimeAuthority(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) getTimeAuthority(response http.ResponseWriter, request *http.Request, id string) {
	if server.time == nil {
		server.writeTimeUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.time.ReadTimeAuthority(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) getClockQuality(response http.ResponseWriter, request *http.Request) {
	if server.time == nil {
		server.writeTimeUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.time.ReadGuestClockQuality(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) listCatalogObservations(response http.ResponseWriter, request *http.Request) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ListCatalogObservations(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) ingestCatalogObservation(response http.ResponseWriter, request *http.Request) {
	if server.catalog == nil {
		server.writeCatalogCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.CatalogObservationIngestCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-catalog-observation-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.catalog.IngestCatalogObservation(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) getCatalogObservation(response http.ResponseWriter, request *http.Request, id string) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ReadCatalogObservation(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) applyTelemetryPipeline(response http.ResponseWriter, request *http.Request) {
	if server.telemetry == nil {
		server.writeTelemetryCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.TelemetryPipelineApplyCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-telemetry-pipeline-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.telemetry.ApplyTelemetryPipeline(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) getTelemetryPipeline(response http.ResponseWriter, request *http.Request, id string) {
	if server.telemetry == nil {
		server.writeTelemetryUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.telemetry.ReadTelemetryPipeline(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) emitTelemetrySignal(response http.ResponseWriter, request *http.Request) {
	if server.telemetry == nil {
		server.writeTelemetryCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.TelemetrySignalEmitCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-telemetry-signal-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.telemetry.EmitTelemetrySignal(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) getTelemetryReceipt(response http.ResponseWriter, request *http.Request, id string) {
	if server.telemetry == nil {
		server.writeTelemetryUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.telemetry.ReadTelemetryEmissionReceipt(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) listExternalUpstreams(response http.ResponseWriter, request *http.Request) {
	if server.external == nil {
		server.writeExternalUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.external.ListExternalUpstreamIntegrationDocuments(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) getExternalUpstream(response http.ResponseWriter, request *http.Request, id string) {
	if server.external == nil {
		server.writeExternalUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.external.ReadExternalUpstreamIntegrationDocument(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) applyExternalUpstream(response http.ResponseWriter, request *http.Request) {
	if server.external == nil {
		server.writeExternalCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.ExternalUpstreamApplyCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-external-upstream-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.external.ApplyExternalUpstreamIntegration(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) listRelayTargets(response http.ResponseWriter, request *http.Request) {
	if server.relay == nil {
		server.writeRelayUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.relay.ListOutboundRelayTargets(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) getRelayTarget(response http.ResponseWriter, request *http.Request, id string) {
	if server.relay == nil {
		server.writeRelayUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.relay.ReadOutboundRelayTarget(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) applyRelayTarget(response http.ResponseWriter, request *http.Request) {
	if server.relay == nil {
		server.writeRelayCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.OutboundRelayApplyCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-outbound-relay-command-envelope", err.Error()))
		return
	}
	operation, rejection, admissionFailure := server.relay.ApplyOutboundRelayTarget(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) listLabSessions(response http.ResponseWriter, request *http.Request) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ListLabSessions(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) getLabSession(response http.ResponseWriter, request *http.Request, id string) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ReadLabSession(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) listLabBeds(response http.ResponseWriter, request *http.Request) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ListLabBeds(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) getLabBed(response http.ResponseWriter, request *http.Request, id string) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ReadLabBed(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) listVirtualRecorders(response http.ResponseWriter, request *http.Request) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ListLabVirtualRecorders(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) getVirtualRecorder(response http.ResponseWriter, request *http.Request, id string) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ReadLabVirtualRecorder(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) getDeletionReceipt(response http.ResponseWriter, request *http.Request, id string) {
	if server.lab == nil {
		server.writeLabUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.lab.ReadLabResourceDeletionReceipt(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) createLabSession(response http.ResponseWriter, request *http.Request) {
	if server.lab == nil {
		server.writeLabCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.CreateLabSessionCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		server.writeMalformedLabCommand(response, requestID, err)
		return
	}
	operation, rejection, admissionFailure := server.lab.CreateLabSession(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) executeLabResource(response http.ResponseWriter, request *http.Request) {
	if server.lab == nil || server.archive == nil || server.coordinator == nil {
		server.writeLabCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.LabResourceCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		server.writeMalformedLabCommand(response, requestID, err)
		return
	}
	operation, rejection, admissionFailure := server.coordinator.ExecuteLabResourceCommand(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) exportArtifact(response http.ResponseWriter, request *http.Request) {
	if server.archive == nil || server.coordinator == nil {
		server.writeArchiveCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.ArtifactExportCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		server.writeMalformedArchiveCommand(response, requestID, err)
		return
	}
	operation, rejection, admissionFailure := server.coordinator.ExecuteArtifactExportCommand(request.Context(), command)
	server.writeCommandOutcome(response, operation, rejection, admissionFailure)
}

func (server *GuestRuntimeControlHTTPServer) getArtifactManifest(response http.ResponseWriter, request *http.Request, id string) {
	if server.archive == nil {
		server.writeArchiveUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.archive.ReadArtifactManifest(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) getExportReceipt(response http.ResponseWriter, request *http.Request, id string) {
	if server.archive == nil {
		server.writeArchiveUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.archive.ReadArtifactExportReceipt(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) writeMalformedLabCommand(response http.ResponseWriter, requestID string, err error) {
	// A malformed request has no valid owner command to dispatch. This standard
	// rejection still preserves the request correlation when it was decodable.
	writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-lab-command-envelope", err.Error()))
}

func (server *GuestRuntimeControlHTTPServer) writeMalformedArchiveCommand(response http.ResponseWriter, requestID string, err error) {
	writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-artifact-export-command-envelope", err.Error()))
}

func (server *GuestRuntimeControlHTTPServer) writeCommandOutcome(response http.ResponseWriter, operation guestruntimedomain.Operation, rejection *guestruntimedomain.CommandRejection, admissionFailure *guestruntimedomain.CommandAdmissionFailure) {
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusInternalServerError, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (server *GuestRuntimeControlHTTPServer) writeLabUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("guest-runtime-lab-unavailable", "Guest Runtime Lab module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeArchiveUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("archive-export-unavailable", "Guest Runtime Archive Export module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeExternalUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("external-upstream-unavailable", "Guest Runtime External Upstream module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeRelayUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("outbound-relay-unavailable", "Guest Runtime Outbound Relay module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeTimeUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("time-authority-unavailable", "Guest Runtime Time Authority module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeCatalogUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("observation-catalog-unavailable", "Guest Runtime Observation Catalog module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeTelemetryUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableRead("telemetry-pipeline-unavailable", "Guest Runtime Telemetry Pipeline module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeLabCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "guest-runtime-lab-unavailable", "Guest Runtime Lab module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeArchiveCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "archive-export-unavailable", "Guest Runtime Archive Export module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeExternalCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "external-upstream-unavailable", "Guest Runtime External Upstream module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeRelayCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "outbound-relay-unavailable", "Guest Runtime Outbound Relay module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeTimeCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "time-authority-unavailable", "Guest Runtime Time Authority module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeCatalogCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "observation-catalog-unavailable", "Guest Runtime Observation Catalog module is not configured"))
}

func (server *GuestRuntimeControlHTTPServer) writeTelemetryCommandUnavailable(response http.ResponseWriter, request *http.Request) {
	writeJSON(response, http.StatusServiceUnavailable, unavailableAdmission(requestIDFromRequest(request), "telemetry-pipeline-unavailable", "Guest Runtime Telemetry Pipeline module is not configured"))
}

func runtimePathParameter(path string, prefix string) string {
	value := strings.TrimPrefix(path, prefix)
	if value == path || value == "" || strings.Contains(value, "/") {
		return ""
	}
	return value
}

func malformedRejection(requestID string, code string, message string) guestruntimedomain.CommandRejection {
	return guestruntimedomain.CommandRejection{SchemaVersion: guestruntimedomain.SchemaVersion, State: "rejected", RequestID: requestIDOrGenerated(requestID), RejectedAt: guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()), Issue: guestruntimedomain.Issue{Code: code, Message: message}}
}

func unavailableRead(code string, message string) guestruntimedomain.ReadResult {
	return guestruntimedomain.ReadResult{SchemaVersion: guestruntimedomain.SchemaVersion, State: "unavailable", ObservedAt: guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()), Issue: &guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(true), Dependency: "guest-runtime"}}
}

func unavailableAdmission(requestID string, code string, message string) guestruntimedomain.CommandAdmissionFailure {
	return guestruntimedomain.CommandAdmissionFailure{SchemaVersion: guestruntimedomain.SchemaVersion, State: "failed", RequestID: requestID, ObservedAt: guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()), AdmissionState: "not-admitted", Issue: guestruntimedomain.Issue{Code: code, Message: message, Retryable: boolPointer(true), Dependency: "guest-runtime"}}
}

func requestIDFromRequest(request *http.Request) string {
	if request == nil {
		return ""
	}
	return request.Header.Get("X-Request-Id")
}

func requestIDOrGenerated(requestID string) string {
	if guestruntimedomain.ValidIdentifier(requestID) {
		return requestID
	}
	return "rejection-unavailable-request-id"
}

func boolPointer(value bool) *bool {
	return &value
}

func (server *GuestRuntimeControlHTTPServer) applyTopology(response http.ResponseWriter, request *http.Request) {
	var command guestruntimedomain.TopologyApplyCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		rejection, rejectionErr := server.topologyService.RejectMalformedRuntimeTopologyCommand(requestID, err.Error())
		if rejectionErr != nil {
			writeJSON(response, http.StatusInternalServerError, map[string]string{"error": "Guest Runtime could not create a rejection correlation id"})
			return
		}
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	operation, rejection, admissionFailure := server.topologyService.ApplyRuntimeTopology(request.Context(), command)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusInternalServerError, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func decodeCommand(request *http.Request, destination any) (string, error) {
	raw, err := io.ReadAll(io.LimitReader(request.Body, maximumCommandBytes+1))
	if err != nil {
		return "", err
	}
	if len(raw) > int(maximumCommandBytes) {
		return requestIDFromRaw(raw), errors.New("command body exceeds the 1 MiB limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return requestIDFromRaw(raw), err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return requestIDFromRaw(raw), errors.New("command body must contain exactly one JSON object")
	}
	return requestIDFromRaw(raw), nil
}

func requestIDFromRaw(raw []byte) string {
	var envelope struct {
		RequestID string `json:"requestId"`
	}
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return ""
	}
	return envelope.RequestID
}

func writeJSON(response http.ResponseWriter, status int, document any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(document)
}
