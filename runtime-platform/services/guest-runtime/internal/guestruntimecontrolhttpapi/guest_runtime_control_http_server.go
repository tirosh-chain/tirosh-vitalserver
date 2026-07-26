// Package guestruntimecontrolhttpapi exposes only versioned Guest Runtime control contracts.
package guestruntimecontrolhttpapi

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumCommandBytes int64 = 1 << 20
const maximumArchiveSourceCommandHeaderBytes = 16 << 10
const maximumLabReplaySourceCommandHeaderBytes = 16 << 10
const recorderGatewayCatalogAdmissionSourceIdentity = "recorder-gateway"

// GuestRuntimeControlHTTPServer exposes only versioned Guest Runtime control
// contracts. It formats explicit application outcomes; it does not own
// topology, Lab, archive, external integration, time, catalog, or telemetry state.
type GuestRuntimeControlHTTPServer struct {
	topologyService             *guestruntimeapplication.GuestRuntimeTopologyApplicationService
	lab                         *guestruntimeapplication.GuestRuntimeLabApplicationService
	archive                     *guestruntimeapplication.GuestRuntimeArchiveApplicationService
	archiveLineage              *guestruntimeapplication.GuestRuntimeArchiveLineageApplicationService
	archiveSourceAdmission      *guestruntimeapplication.GuestRuntimeArchiveSourceAdmissionApplicationService
	archiveSourceAdmissionToken string
	archiveSourceMaximumBytes   int64
	labReplaySource             *guestruntimeapplication.GuestRuntimeLabReplaySourceApplicationService
	labReplaySourceMaximumBytes int64
	labReplay                   *guestruntimeapplication.GuestRuntimeLabReplayApplicationService
	archiveCredentialMaterial   *guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialApplicationService
	external                    *guestruntimeapplication.GuestRuntimeExternalUpstreamApplicationService
	relay                       *guestruntimeapplication.GuestRuntimeOutboundRelayApplicationService
	time                        *guestruntimeapplication.GuestRuntimeTimeAuthorityApplicationService
	catalog                     *guestruntimeapplication.GuestRuntimeObservationCatalogApplicationService
	catalogAdmissionBearerToken string
	recorderAssignment          *guestruntimeapplication.GuestRuntimeRecorderAssignmentApplicationService
	operationalStateIdentity    *guestruntimeapplication.GuestOperationalStateIdentityApplicationService
	operationalStateBackup      *guestruntimeapplication.GuestOperationalStateBackupApplicationService
	operationalStateRestore     bool
	telemetry                   *guestruntimeapplication.GuestRuntimeTelemetryPipelineApplicationService
	coordinator                 *guestruntimeapplication.GuestRuntimeLabArchiveLifecycleCoordinator
}

// GuestRuntimeControlModules keeps module composition named as the Guest Runtime grows.
// Callers cannot accidentally swap two state owners through a positional
// constructor argument.
type GuestRuntimeControlModules struct {
	Topology                                       *guestruntimeapplication.GuestRuntimeTopologyApplicationService
	Lab                                            *guestruntimeapplication.GuestRuntimeLabApplicationService
	Archive                                        *guestruntimeapplication.GuestRuntimeArchiveApplicationService
	ArchiveLineage                                 *guestruntimeapplication.GuestRuntimeArchiveLineageApplicationService
	ArchiveSourceAdmission                         *guestruntimeapplication.GuestRuntimeArchiveSourceAdmissionApplicationService
	ArchiveSourceAdmissionBearerToken              string
	ArchiveSourceMaximumBytes                      int64
	LabReplaySource                                *guestruntimeapplication.GuestRuntimeLabReplaySourceApplicationService
	LabReplaySourceMaximumBytes                    int64
	LabReplay                                      *guestruntimeapplication.GuestRuntimeLabReplayApplicationService
	ArchiveCredentialMaterial                      *guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialApplicationService
	ExternalUpstreamIntegration                    *guestruntimeapplication.GuestRuntimeExternalUpstreamApplicationService
	OutboundRelayTarget                            *guestruntimeapplication.GuestRuntimeOutboundRelayApplicationService
	GuestTimeAuthority                             *guestruntimeapplication.GuestRuntimeTimeAuthorityApplicationService
	RecorderObservationCatalog                     *guestruntimeapplication.GuestRuntimeObservationCatalogApplicationService
	RecorderObservationCatalogAdmissionBearerToken string
	RecorderAssignment                             *guestruntimeapplication.GuestRuntimeRecorderAssignmentApplicationService
	GuestOperationalStateIdentity                  *guestruntimeapplication.GuestOperationalStateIdentityApplicationService
	GuestOperationalStateBackup                    *guestruntimeapplication.GuestOperationalStateBackupApplicationService
	GuestOperationalStateRestoreAdmissionEnabled   bool
	GuestTelemetryPipeline                         *guestruntimeapplication.GuestRuntimeTelemetryPipelineApplicationService
	LabArchiveLifecycleCoordinationClock           guestruntimeapplication.GuestRuntimeClock
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
		topologyService:             modules.Topology,
		lab:                         modules.Lab,
		archive:                     modules.Archive,
		archiveLineage:              modules.ArchiveLineage,
		archiveSourceAdmission:      modules.ArchiveSourceAdmission,
		archiveSourceAdmissionToken: modules.ArchiveSourceAdmissionBearerToken,
		archiveSourceMaximumBytes:   modules.ArchiveSourceMaximumBytes,
		labReplaySource:             modules.LabReplaySource,
		labReplaySourceMaximumBytes: modules.LabReplaySourceMaximumBytes,
		labReplay:                   modules.LabReplay,
		archiveCredentialMaterial:   modules.ArchiveCredentialMaterial,
		external:                    modules.ExternalUpstreamIntegration,
		relay:                       modules.OutboundRelayTarget,
		time:                        modules.GuestTimeAuthority,
		catalog:                     modules.RecorderObservationCatalog,
		catalogAdmissionBearerToken: modules.RecorderObservationCatalogAdmissionBearerToken,
		recorderAssignment:          modules.RecorderAssignment,
		operationalStateIdentity:    modules.GuestOperationalStateIdentity,
		operationalStateBackup:      modules.GuestOperationalStateBackup,
		operationalStateRestore:     modules.GuestOperationalStateRestoreAdmissionEnabled,
		telemetry:                   modules.GuestTelemetryPipeline,
		coordinator:                 guestruntimeapplication.NewGuestRuntimeLabArchiveLifecycleCoordinator(modules.Lab, modules.Archive, modules.LabArchiveLifecycleCoordinationClock),
	}
}

// ReconcilePendingTerminalArchiveExports is the process-start recovery hook
// for already durable Lab terminal intents. It is intentionally outside the
// HTTP request switch: a process restart must not require a browser or expose
// a generic recovery route. Missing Lab/Archive dependencies remain explicit
// composition failure rather than an empty successful reconciliation.
func (server *GuestRuntimeControlHTTPServer) ReconcilePendingTerminalArchiveExports(ctx context.Context) error {
	if server.coordinator == nil {
		return fmt.Errorf("Lab terminal archive reconciliation is unavailable because Lab, Archive, or its coordination clock is not composed")
	}
	return server.coordinator.ReconcilePendingTerminalArchiveExports(ctx)
}

// RunNextPendingLabReplayEffect executes one already-durable replay outbox
// effect. Process lifecycle owns repetition; the HTTP adapter does not infer a
// replay transition from request traffic.
func (server *GuestRuntimeControlHTTPServer) RunNextPendingLabReplayEffect(
	ctx context.Context,
) (guestruntimedomain.LabReplayOperation, bool, error) {
	if server.labReplay == nil {
		return guestruntimedomain.LabReplayOperation{}, false,
			fmt.Errorf("Guest Runtime Lab replay module is not composed")
	}
	return server.labReplay.RunNextPendingLabReplayEffect(ctx)
}

// RunNextPendingGuestOperationalStateEffect executes one durable C76 outbox
// effect. Process lifecycle owns repetition; HTTP traffic never advances the
// backup or restore state machine implicitly.
func (server *GuestRuntimeControlHTTPServer) RunNextPendingGuestOperationalStateEffect(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStateBackupOperation, bool, error) {
	if server.operationalStateBackup == nil {
		return guestruntimedomain.GuestOperationalStateBackupOperation{}, false,
			fmt.Errorf("Guest operational-state backup module is not composed")
	}
	return server.operationalStateBackup.RunNextPendingEffect(ctx)
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
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/lab/replay-sources":
		server.admitLabReplaySource(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/lab/replays":
		server.admitLabReplay(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/replays/") != "":
		server.getLabReplay(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/replays/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/operational-state/backups":
		server.admitGuestOperationalStateBackup(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/operational-state/restores":
		server.admitGuestOperationalStateRestore(response, request)
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/operational-state/identity":
		server.getGuestOperationalStateIdentity(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/operational-state/operations/") != "":
		server.getGuestOperationalStateOperation(
			response,
			request,
			runtimePathParameter(
				request.URL.Path,
				"/v1/runtime/operational-state/operations/",
			),
		)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/lab/deletion-receipts/") != "":
		server.getDeletionReceipt(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/lab/deletion-receipts/"))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/archive/exports":
		server.exportArtifact(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/internal/v1/archive/recorder-uploads":
		server.admitRecorderVitalUpload(response, request)
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/archive/export-provider":
		server.getArchiveExportProviderConfiguration(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/archive/manifests/") != "":
		server.getArtifactManifest(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/archive/manifests/"))
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/archive/export-receipts/") != "":
		server.getExportReceipt(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/archive/export-receipts/"))
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/artifacts/") != "":
		server.getArchiveArtifact(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/artifacts/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/archive/credential-material":
		server.getArchiveCredentialMaterialAvailability(response, request)
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/archive/credential-material":
		server.provisionArchiveCredentialMaterial(response, request)
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
	case request.Method == http.MethodPost && request.URL.Path == "/internal/v1/recorder-catalog/observations":
		server.ingestCatalogObservation(response, request)
	case request.Method == http.MethodGet && runtimePathParameter(request.URL.Path, "/v1/runtime/catalog/recorder-observations/") != "":
		server.getCatalogObservation(response, request, runtimePathParameter(request.URL.Path, "/v1/runtime/catalog/recorder-observations/"))
	case request.Method == http.MethodGet && request.URL.Path == "/v1/runtime/recorders":
		server.getRecorderObservabilitySummaryPage(response, request)
	case request.Method == http.MethodGet && recorderObservabilityPathParameter(request.URL.Path, "/observability") != "":
		server.getRecorderObservabilitySummary(response, request, recorderObservabilityPathParameter(request.URL.Path, "/observability"))
	case request.Method == http.MethodGet && recorderObservabilityPathParameter(request.URL.Path, "/observability/timeline") != "":
		server.getRecorderObservationTimeline(response, request, recorderObservabilityPathParameter(request.URL.Path, "/observability/timeline"))
	case request.Method == http.MethodGet && recorderObservabilityPathParameter(request.URL.Path, "/observability/incidents") != "":
		server.getRecorderIncidentHistory(response, request, recorderObservabilityPathParameter(request.URL.Path, "/observability/incidents"))
	case request.Method == http.MethodGet && recorderObservabilityPathParameter(request.URL.Path, "/artifacts") != "":
		server.getRecorderArtifacts(response, request, recorderObservabilityPathParameter(request.URL.Path, "/artifacts"))
	case request.Method == http.MethodPost && recorderExpectationPathParameter(request.URL.Path) != "":
		server.applyRecorderExpectation(response, request, recorderExpectationPathParameter(request.URL.Path))
	case request.Method == http.MethodPost && request.URL.Path == "/v1/runtime/recorder-assignments":
		server.admitRecorderAssignmentEvidence(response, request)
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

func (server *GuestRuntimeControlHTTPServer) getArchiveCredentialMaterialAvailability(response http.ResponseWriter, request *http.Request) {
	if server.archiveCredentialMaterial == nil {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialAvailability{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "failed",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue:         &guestruntimedomain.Issue{Code: "credential-material-owner-unavailable", Message: "Guest credential-material owner is not configured", Retryable: boolPointer(true), Dependency: "guest-secret-material"},
		})
		return
	}
	writeJSON(response, http.StatusOK, server.archiveCredentialMaterial.ReadVitalServerIndexedLibraryCredentialMaterialAvailability(request.Context()))
}

func (server *GuestRuntimeControlHTTPServer) provisionArchiveCredentialMaterial(response http.ResponseWriter, request *http.Request) {
	if server.archiveCredentialMaterial == nil {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "failed",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue:         &guestruntimedomain.Issue{Code: "credential-material-owner-unavailable", Message: "Guest credential-material owner is not configured", Retryable: boolPointer(true), Dependency: "guest-secret-material"},
		})
		return
	}
	var material guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial
	if _, err := decodeCommand(request, &material); err != nil {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "rejected",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue:         &guestruntimedomain.Issue{Code: "invalid-credential-material-command", Message: "credential material command is invalid"},
		})
		return
	}
	outcome := server.archiveCredentialMaterial.ProvisionVitalServerIndexedLibraryCredentialMaterial(request.Context(), material)
	if outcome.State == "provisioned" {
		writeJSON(response, http.StatusOK, outcome)
		return
	}
	if outcome.State == "rejected" {
		writeJSON(response, http.StatusBadRequest, outcome)
		return
	}
	writeJSON(response, http.StatusServiceUnavailable, outcome)
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

func validBearerAuthorization(authorization string, bearerToken string) bool {
	if bearerToken == "" {
		return false
	}
	expected := "Bearer " + bearerToken
	return len(authorization) == len(expected) && subtle.ConstantTimeCompare([]byte(authorization), []byte(expected)) == 1
}

func (server *GuestRuntimeControlHTTPServer) ingestCatalogObservation(response http.ResponseWriter, request *http.Request) {
	if server.catalog == nil {
		server.writeCatalogCommandUnavailable(response, request)
		return
	}
	if !validBearerAuthorization(request.Header.Get("Authorization"), server.catalogAdmissionBearerToken) {
		writeJSON(response, http.StatusUnauthorized, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			AdmissionState: "not-admitted",
			Issue:          guestruntimedomain.Issue{Code: "recorder-catalog-source-authentication-failed", Message: "Recorder Catalog admission requires the configured Recorder Gateway credential", Retryable: boolPointer(false), Dependency: "recorder-gateway"},
		})
		return
	}
	var command guestruntimedomain.CatalogObservationIngestCommand
	requestID, receivedBytes, sourceDocument, err := decodeCatalogObservationCommand(request, &command)
	evidence := guestruntimeapplication.CatalogObservationAdmissionEvidence{
		SourceIdentity: recorderGatewayCatalogAdmissionSourceIdentity,
		MediaType:      request.Header.Get("Content-Type"),
		ReceivedBytes:  receivedBytes,
	}
	if err != nil {
		if sourceDocument != nil && guestruntimedomain.ValidIdentifier(requestID) && evidence.MediaType != "" {
			admission, rejection, admissionFailure := server.catalog.QuarantineCatalogObservation(
				request.Context(),
				requestID,
				sourceDocument,
				guestruntimedomain.Issue{Code: "invalid-recorder-observation-document", Message: "Recorder observation document did not match the v1 Catalog command contract", Retryable: boolPointer(false), Dependency: "recorder-gateway"},
				evidence,
			)
			if rejection != nil {
				writeJSON(response, http.StatusBadRequest, rejection)
				return
			}
			if admissionFailure != nil {
				writeJSON(response, http.StatusInternalServerError, admissionFailure)
				return
			}
			writeJSON(response, http.StatusAccepted, admission)
			return
		}
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-catalog-observation-command-envelope", err.Error()))
		return
	}
	admission, rejection, admissionFailure := server.catalog.IngestCatalogObservation(
		request.Context(),
		command,
		evidence,
	)
	if rejection != nil {
		writeJSON(response, http.StatusBadRequest, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusInternalServerError, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, admission)
}

func (server *GuestRuntimeControlHTTPServer) admitRecorderVitalUpload(
	response http.ResponseWriter,
	request *http.Request,
) {
	observedAt := guestruntimedomain.Timestamp(
		guestruntimeapplication.SystemGuestRuntimeClock{}.Now(),
	)
	if server.archiveSourceAdmission == nil ||
		server.archiveSourceMaximumBytes < 1 {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:       "archive-source-admission-unavailable",
				Message:    "Guest Runtime Archive source admission is not configured",
				Dependency: "archive-export",
			},
		})
		return
	}
	if !validBearerAuthorization(
		request.Header.Get("Authorization"),
		server.archiveSourceAdmissionToken,
	) {
		writeJSON(response, http.StatusUnauthorized, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:       "archive-source-authentication-failed",
				Message:    "Archive source admission requires the configured Recorder Gateway credential",
				Dependency: "recorder-gateway",
			},
		})
		return
	}
	if request.Header.Get("Content-Type") != "application/x-vital" {
		writeJSON(response, http.StatusUnsupportedMediaType, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "archive-source-media-type-invalid",
				Message: "Archive source body must use application/x-vital",
			},
		})
		return
	}
	command, err := decodeArchiveSourceAdmissionCommandHeader(
		request.Header.Get("X-Vital-Archive-Source-Command"),
	)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "archive-source-command-header-invalid",
				Message: err.Error(),
			},
		})
		return
	}
	if command.Source.ByteSize > server.archiveSourceMaximumBytes {
		writeJSON(response, http.StatusRequestEntityTooLarge, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "archive-source-size-exceeded",
				Message: "Archive source receipt exceeds the configured byte limit",
			},
		})
		return
	}
	request.Body = http.MaxBytesReader(
		response,
		request.Body,
		server.archiveSourceMaximumBytes+1,
	)
	receipt, err := server.archiveSourceAdmission.AdmitRecorderVitalUpload(
		request.Context(),
		command,
		request.Body,
	)
	if err == nil {
		status := http.StatusAccepted
		if receipt.Outcome == "duplicate" {
			status = http.StatusOK
		} else if receipt.Outcome == "quarantined" {
			status = http.StatusUnprocessableEntity
		}
		writeJSON(response, status, receipt)
		return
	}
	var rejected guestruntimeapplication.ArchiveSourceAdmissionRejectedError
	if errors.As(err, &rejected) {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue:          rejected.Issue,
		})
		return
	}
	var unknown guestruntimeapplication.ArchiveSourceAdmissionUnknownError
	if errors.As(err, &unknown) {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "unknown",
			Issue:          unknown.Issue,
		})
		return
	}
	writeJSON(response, http.StatusInternalServerError, guestruntimedomain.CommandAdmissionFailure{
		SchemaVersion:  guestruntimedomain.SchemaVersion,
		State:          "failed",
		RequestID:      command.RequestID,
		ObservedAt:     observedAt,
		AdmissionState: "unknown",
		Issue: guestruntimedomain.Issue{
			Code:       "archive-source-admission-unclassified",
			Message:    err.Error(),
			Dependency: "archive-export",
		},
	})
}

func decodeArchiveSourceAdmissionCommandHeader(
	encoded string,
) (guestruntimedomain.ArchiveSourceAdmissionCommand, error) {
	var command guestruntimedomain.ArchiveSourceAdmissionCommand
	if encoded == "" || len(encoded) > maximumArchiveSourceCommandHeaderBytes {
		return command, fmt.Errorf("X-Vital-Archive-Source-Command is missing or too large")
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(raw) > maximumArchiveSourceCommandHeaderBytes {
		return command, fmt.Errorf("X-Vital-Archive-Source-Command is not bounded base64url JSON")
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&command); err != nil {
		return command, fmt.Errorf("decode Archive source command: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return command, fmt.Errorf("Archive source command must contain one JSON document")
	}
	if err := guestruntimedomain.ValidateArchiveSourceAdmissionCommand(command); err != nil {
		return command, err
	}
	return command, nil
}

func (server *GuestRuntimeControlHTTPServer) admitLabReplaySource(
	response http.ResponseWriter,
	request *http.Request,
) {
	observedAt := guestruntimedomain.Timestamp(
		guestruntimeapplication.SystemGuestRuntimeClock{}.Now(),
	)
	if server.labReplaySource == nil ||
		server.labReplaySourceMaximumBytes < 1 {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:       "lab-replay-source-owner-unavailable",
				Message:    "Lab replay source owner is not composed",
				Dependency: "lab-replay-source-owner",
			},
		})
		return
	}
	if request.Header.Get("Content-Type") != guestruntimedomain.LabReplaySourceMediaType {
		writeJSON(response, http.StatusUnsupportedMediaType, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "lab-replay-source-media-type-invalid",
				Message: "Lab replay source body must use application/x-vital",
			},
		})
		return
	}
	command, err := decodeLabReplaySourceAdmissionCommandHeader(
		request.Header.Get("X-Vital-Lab-Replay-Source-Command"),
	)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      requestIDFromRequest(request),
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "lab-replay-source-command-header-invalid",
				Message: err.Error(),
			},
		})
		return
	}
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		server.labReplaySourceMaximumBytes,
	); err != nil {
		status := http.StatusBadRequest
		if command.ByteSize > server.labReplaySourceMaximumBytes {
			status = http.StatusRequestEntityTooLarge
		}
		writeJSON(response, status, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue: guestruntimedomain.Issue{
				Code:    "lab-replay-source-command-invalid",
				Message: err.Error(),
			},
		})
		return
	}
	request.Body = http.MaxBytesReader(
		response,
		request.Body,
		server.labReplaySourceMaximumBytes+1,
	)
	receipt, err := server.labReplaySource.AdmitLabReplaySource(
		request.Context(),
		command,
		request.Body,
	)
	if err == nil {
		status := http.StatusAccepted
		if receipt.Outcome == "duplicate" {
			status = http.StatusOK
		}
		writeJSON(response, status, receipt)
		return
	}
	var rejected guestruntimeapplication.LabReplaySourceAdmissionRejectedError
	if errors.As(err, &rejected) {
		writeJSON(response, http.StatusUnprocessableEntity, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "not-admitted",
			Issue:          rejected.Issue,
		})
		return
	}
	var unknown guestruntimeapplication.LabReplaySourceAdmissionUnknownError
	if errors.As(err, &unknown) {
		writeJSON(response, http.StatusServiceUnavailable, guestruntimedomain.CommandAdmissionFailure{
			SchemaVersion:  guestruntimedomain.SchemaVersion,
			State:          "failed",
			RequestID:      command.RequestID,
			ObservedAt:     observedAt,
			AdmissionState: "unknown",
			Issue:          unknown.Issue,
		})
		return
	}
	writeJSON(response, http.StatusInternalServerError, guestruntimedomain.CommandAdmissionFailure{
		SchemaVersion:  guestruntimedomain.SchemaVersion,
		State:          "failed",
		RequestID:      command.RequestID,
		ObservedAt:     observedAt,
		AdmissionState: "unknown",
		Issue: guestruntimedomain.Issue{
			Code:       "lab-replay-source-admission-unclassified",
			Message:    err.Error(),
			Dependency: "lab-replay-source-owner",
		},
	})
}

func decodeLabReplaySourceAdmissionCommandHeader(
	encoded string,
) (guestruntimedomain.LabReplaySourceAdmissionCommand, error) {
	var command guestruntimedomain.LabReplaySourceAdmissionCommand
	if encoded == "" || len(encoded) > maximumLabReplaySourceCommandHeaderBytes {
		return command, fmt.Errorf("X-Vital-Lab-Replay-Source-Command is missing or too large")
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(raw) > maximumLabReplaySourceCommandHeaderBytes {
		return command, fmt.Errorf("X-Vital-Lab-Replay-Source-Command is not bounded base64url JSON")
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&command); err != nil {
		return command, fmt.Errorf("decode Lab replay source command: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return command, fmt.Errorf("Lab replay source command must contain one JSON document")
	}
	return command, nil
}

func (server *GuestRuntimeControlHTTPServer) getCatalogObservation(response http.ResponseWriter, request *http.Request, id string) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ReadCatalogObservation(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) getRecorderObservabilitySummary(response http.ResponseWriter, request *http.Request, recorderID string) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ReadRecorderObservabilitySummary(request.Context(), recorderID))
}

func (server *GuestRuntimeControlHTTPServer) getRecorderObservabilitySummaryPage(response http.ResponseWriter, request *http.Request) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	limit, ok := recorderSummaryPageLimit(response, request)
	if !ok {
		return
	}
	writeJSON(
		response,
		http.StatusOK,
		server.catalog.ReadRecorderObservabilitySummaryPage(
			request.Context(),
			limit,
			request.URL.Query().Get("cursor"),
		),
	)
}

func recorderSummaryPageLimit(response http.ResponseWriter, request *http.Request) (int, bool) {
	raw := request.URL.Query().Get("limit")
	limit, err := strconv.Atoi(raw)
	if raw == "" || err != nil {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.ReadResult{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "invalid",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue:         &guestruntimedomain.Issue{Code: "invalid-recorder-summary-page-limit", Message: "limit query parameter must be an integer between 1 and 100"},
		})
		return 0, false
	}
	return limit, true
}

func (server *GuestRuntimeControlHTTPServer) getRecorderObservationTimeline(response http.ResponseWriter, request *http.Request, recorderID string) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	limit, ok := recorderHistoryLimit(response, request)
	if !ok {
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ReadRecorderObservationTimeline(request.Context(), recorderID, limit, request.URL.Query().Get("cursor")))
}

func (server *GuestRuntimeControlHTTPServer) getRecorderIncidentHistory(response http.ResponseWriter, request *http.Request, recorderID string) {
	if server.catalog == nil {
		server.writeCatalogUnavailable(response, request)
		return
	}
	limit, ok := recorderHistoryLimit(response, request)
	if !ok {
		return
	}
	writeJSON(response, http.StatusOK, server.catalog.ReadRecorderIncidentHistory(request.Context(), recorderID, limit, request.URL.Query().Get("cursor")))
}

func recorderHistoryLimit(response http.ResponseWriter, request *http.Request) (int, bool) {
	raw := request.URL.Query().Get("limit")
	limit, err := strconv.Atoi(raw)
	if raw == "" || err != nil {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.ReadResult{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "invalid",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue:         &guestruntimedomain.Issue{Code: "invalid-recorder-history-limit", Message: "limit query parameter must be an integer between 1 and 100"},
		})
		return 0, false
	}
	return limit, true
}

func (server *GuestRuntimeControlHTTPServer) applyRecorderExpectation(response http.ResponseWriter, request *http.Request, recorderID string) {
	if server.catalog == nil {
		server.writeCatalogCommandUnavailable(response, request)
		return
	}
	var command guestruntimedomain.RecorderObservabilityExpectationCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(response, http.StatusBadRequest, malformedRejection(requestID, "invalid-recorder-expectation-command-envelope", err.Error()))
		return
	}
	receipt, rejection, admissionFailure := server.catalog.ApplyRecorderExpectation(request.Context(), recorderID, command)
	if rejection != nil {
		status := http.StatusBadRequest
		if rejection.Issue.Code == "recorder-expectation-revision-conflict" || rejection.Issue.Code == "request-id-reused-with-different-command" {
			status = http.StatusConflict
		}
		writeJSON(response, status, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusInternalServerError, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, receipt)
}

func (server *GuestRuntimeControlHTTPServer) admitRecorderAssignmentEvidence(
	response http.ResponseWriter,
	request *http.Request,
) {
	if server.recorderAssignment == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			unavailableAdmission(
				requestIDFromRequest(request),
				"recorder-assignment-owner-unavailable",
				"Guest Runtime Recorder Assignment module is not configured",
			),
		)
		return
	}
	var command guestruntimedomain.RecorderAssignmentEvidenceCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				requestID,
				"invalid-recorder-assignment-command-envelope",
				err.Error(),
			),
		)
		return
	}
	receipt, rejection, admissionFailure := server.recorderAssignment.AdmitRecorderAssignmentEvidence(
		request.Context(),
		command,
	)
	if rejection != nil {
		status := http.StatusBadRequest
		if rejection.Issue.Code == "recorder-assignment-request-id-conflict" {
			status = http.StatusConflict
		}
		writeJSON(response, status, rejection)
		return
	}
	if admissionFailure != nil {
		writeJSON(response, http.StatusServiceUnavailable, admissionFailure)
		return
	}
	writeJSON(response, http.StatusAccepted, receipt)
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

func (server *GuestRuntimeControlHTTPServer) getLabReplay(
	response http.ResponseWriter,
	request *http.Request,
	replayID string,
) {
	if server.labReplay == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			guestruntimedomain.ReadResult{
				SchemaVersion: guestruntimedomain.SchemaVersion,
				State:         "failed",
				ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
				Issue: &guestruntimedomain.Issue{
					Code:       "lab-replay-owner-unavailable",
					Message:    "Guest Runtime Lab replay module is not configured",
					Retryable:  boolPointer(true),
					Dependency: "guest-runtime-lab-replay",
				},
			},
		)
		return
	}
	writeJSON(
		response,
		http.StatusOK,
		server.labReplay.ReadLabReplay(request.Context(), replayID),
	)
}

func (server *GuestRuntimeControlHTTPServer) admitLabReplay(
	response http.ResponseWriter,
	request *http.Request,
) {
	if server.labReplay == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			unavailableAdmission(
				requestIDFromRequest(request),
				"lab-replay-owner-unavailable",
				"Guest Runtime Lab replay module is not configured",
			),
		)
		return
	}
	var command guestruntimedomain.LabReplayCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				requestID,
				"invalid-lab-replay-command-envelope",
				err.Error(),
			),
		)
		return
	}
	if _, err := guestruntimedomain.NewLabReplayOperation(command); err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				command.RequestID,
				"invalid-lab-replay-command",
				err.Error(),
			),
		)
		return
	}
	operation, err := server.labReplay.AdmitLabReplay(request.Context(), command)
	if errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict) {
		writeJSON(
			response,
			http.StatusConflict,
			malformedRejection(
				command.RequestID,
				"lab-replay-request-conflict",
				err.Error(),
			),
		)
		return
	}
	var rejected guestruntimedomain.LabReplayAdmissionRejectedError
	if errors.As(err, &rejected) {
		writeJSON(
			response,
			http.StatusBadRequest,
			guestruntimedomain.CommandRejection{
				SchemaVersion: guestruntimedomain.SchemaVersion,
				State:         "rejected",
				RequestID:     command.RequestID,
				RejectedAt:    rejected.RejectedAt,
				Issue:         rejected.Issue,
			},
		)
		return
	}
	if err != nil {
		writeJSON(
			response,
			http.StatusInternalServerError,
			guestruntimedomain.CommandAdmissionFailure{
				SchemaVersion:  guestruntimedomain.SchemaVersion,
				State:          "failed",
				RequestID:      command.RequestID,
				ObservedAt:     guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
				AdmissionState: "unknown",
				Issue: guestruntimedomain.Issue{
					Code:       "lab-replay-admission-failed",
					Message:    err.Error(),
					Retryable:  boolPointer(true),
					Dependency: "guest-state-store",
				},
			},
		)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (server *GuestRuntimeControlHTTPServer) admitGuestOperationalStateBackup(
	response http.ResponseWriter,
	request *http.Request,
) {
	if server.operationalStateBackup == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			unavailableAdmission(
				requestIDFromRequest(request),
				"guest-operational-state-backup-owner-unavailable",
				"Guest operational-state backup module is not configured",
			),
		)
		return
	}
	var command guestruntimedomain.GuestOperationalStateBackupCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				requestID,
				"invalid-guest-operational-state-backup-command-envelope",
				err.Error(),
			),
		)
		return
	}
	if _, err := guestruntimedomain.NewGuestOperationalStateBackupOperation(
		command,
	); err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				command.RequestID,
				"invalid-guest-operational-state-backup-command",
				err.Error(),
			),
		)
		return
	}
	operation, err := server.operationalStateBackup.AdmitBackup(
		request.Context(),
		command,
	)
	server.writeGuestOperationalStateAdmission(
		response,
		command.RequestID,
		operation,
		err,
	)
}

func (server *GuestRuntimeControlHTTPServer) admitGuestOperationalStateRestore(
	response http.ResponseWriter,
	request *http.Request,
) {
	if server.operationalStateBackup == nil ||
		!server.operationalStateRestore {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			unavailableAdmission(
				requestIDFromRequest(request),
				"guest-operational-state-restore-owner-unavailable",
				"Guest operational-state restore module is not configured",
			),
		)
		return
	}
	var command guestruntimedomain.GuestOperationalStateRestoreCommand
	requestID, err := decodeCommand(request, &command)
	if err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				requestID,
				"invalid-guest-operational-state-restore-command-envelope",
				err.Error(),
			),
		)
		return
	}
	if _, err := guestruntimedomain.NewGuestOperationalStateRestoreOperation(
		command,
	); err != nil {
		writeJSON(
			response,
			http.StatusBadRequest,
			malformedRejection(
				command.RequestID,
				"invalid-guest-operational-state-restore-command",
				err.Error(),
			),
		)
		return
	}
	operation, err := server.operationalStateBackup.AdmitRestore(
		request.Context(),
		command,
	)
	server.writeGuestOperationalStateAdmission(
		response,
		command.RequestID,
		operation,
		err,
	)
}

func (server *GuestRuntimeControlHTTPServer) writeGuestOperationalStateAdmission(
	response http.ResponseWriter,
	requestID string,
	operation guestruntimedomain.GuestOperationalStateBackupOperation,
	err error,
) {
	if errors.Is(err, guestruntimeapplication.ErrGuestRuntimeOwnedResourceConflict) {
		writeJSON(
			response,
			http.StatusConflict,
			malformedRejection(
				requestID,
				"guest-operational-state-request-conflict",
				err.Error(),
			),
		)
		return
	}
	if err != nil {
		writeJSON(
			response,
			http.StatusInternalServerError,
			guestruntimedomain.CommandAdmissionFailure{
				SchemaVersion:  guestruntimedomain.SchemaVersion,
				State:          "failed",
				RequestID:      requestID,
				ObservedAt:     guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
				AdmissionState: "unknown",
				Issue: guestruntimedomain.Issue{
					Code:       "guest-operational-state-admission-failed",
					Message:    err.Error(),
					Retryable:  boolPointer(true),
					Dependency: "guest-operational-state-ledger",
				},
			},
		)
		return
	}
	writeJSON(response, http.StatusAccepted, operation)
}

func (server *GuestRuntimeControlHTTPServer) getGuestOperationalStateOperation(
	response http.ResponseWriter,
	request *http.Request,
	operationID string,
) {
	if server.operationalStateBackup == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			guestruntimedomain.ReadResult{
				SchemaVersion: guestruntimedomain.SchemaVersion,
				State:         "failed",
				ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
				Issue: &guestruntimedomain.Issue{
					Code:       "guest-operational-state-owner-unavailable",
					Message:    "Guest operational-state backup module is not configured",
					Retryable:  boolPointer(true),
					Dependency: "guest-operational-state-ledger",
				},
			},
		)
		return
	}
	writeJSON(
		response,
		http.StatusOK,
		server.operationalStateBackup.ReadOperation(
			request.Context(),
			operationID,
		),
	)
}

func (server *GuestRuntimeControlHTTPServer) getGuestOperationalStateIdentity(
	response http.ResponseWriter,
	request *http.Request,
) {
	if server.operationalStateIdentity == nil {
		writeJSON(
			response,
			http.StatusServiceUnavailable,
			guestruntimedomain.ReadResult{
				SchemaVersion: guestruntimedomain.SchemaVersion,
				State:         "failed",
				ObservedAt: guestruntimedomain.Timestamp(
					guestruntimeapplication.SystemGuestRuntimeClock{}.Now(),
				),
				Issue: &guestruntimedomain.Issue{
					Code:       "guest-operational-state-identity-owner-unavailable",
					Message:    "Guest operational-state identity module is not configured",
					Retryable:  boolPointer(true),
					Dependency: "guest-operational-state",
				},
			},
		)
		return
	}
	writeJSON(
		response,
		http.StatusOK,
		server.operationalStateIdentity.Read(request.Context()),
	)
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

func (server *GuestRuntimeControlHTTPServer) getArchiveExportProviderConfiguration(response http.ResponseWriter, request *http.Request) {
	if server.archive == nil {
		server.writeArchiveUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.archive.ReadArchiveExportProviderConfiguration(request.Context()))
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

func (server *GuestRuntimeControlHTTPServer) getArchiveArtifact(response http.ResponseWriter, request *http.Request, id string) {
	if server.archiveLineage == nil {
		server.writeArchiveUnavailable(response, request)
		return
	}
	writeJSON(response, http.StatusOK, server.archiveLineage.ReadArchiveArtifact(request.Context(), id))
}

func (server *GuestRuntimeControlHTTPServer) getRecorderArtifacts(response http.ResponseWriter, request *http.Request, recorderID string) {
	if server.archiveLineage == nil {
		server.writeArchiveUnavailable(response, request)
		return
	}
	limit, ok := recorderArtifactLimit(response, request)
	if !ok {
		return
	}
	writeJSON(response, http.StatusOK, server.archiveLineage.ReadRecorderArtifacts(request.Context(), recorderID, limit, request.URL.Query().Get("cursor")))
}

func recorderArtifactLimit(response http.ResponseWriter, request *http.Request) (int, bool) {
	raw := request.URL.Query().Get("limit")
	limit, err := strconv.Atoi(raw)
	if raw == "" || err != nil || limit < 1 || limit > 100 {
		writeJSON(response, http.StatusBadRequest, guestruntimedomain.ReadResult{
			SchemaVersion: guestruntimedomain.SchemaVersion,
			State:         "invalid",
			ObservedAt:    guestruntimedomain.Timestamp(guestruntimeapplication.SystemGuestRuntimeClock{}.Now()),
			Issue: &guestruntimedomain.Issue{
				Code:    "invalid-recorder-artifact-limit",
				Message: "limit query parameter must be an integer between 1 and 100",
			},
		})
		return 0, false
	}
	return limit, true
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

func recorderExpectationPathParameter(path string) string {
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

func recorderObservabilityPathParameter(path string, suffix string) string {
	const prefix = "/v1/runtime/recorders/"
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
	requestID, _, err := decodeCommandWithReceivedBytes(request, destination)
	return requestID, err
}

func decodeCommandWithReceivedBytes(request *http.Request, destination any) (string, int64, error) {
	raw, err := io.ReadAll(io.LimitReader(request.Body, maximumCommandBytes+1))
	if err != nil {
		return "", 0, err
	}
	if len(raw) > int(maximumCommandBytes) {
		return requestIDFromRaw(raw), int64(len(raw)), errors.New("command body exceeds the 1 MiB limit")
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return requestIDFromRaw(raw), int64(len(raw)), err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return requestIDFromRaw(raw), int64(len(raw)), errors.New("command body must contain exactly one JSON object")
	}
	return requestIDFromRaw(raw), int64(len(raw)), nil
}

func decodeCatalogObservationCommand(request *http.Request, destination *guestruntimedomain.CatalogObservationIngestCommand) (string, int64, map[string]any, error) {
	raw, err := io.ReadAll(io.LimitReader(request.Body, maximumCommandBytes+1))
	if err != nil {
		return "", 0, nil, err
	}
	requestID := requestIDFromRaw(raw)
	if len(raw) > int(maximumCommandBytes) {
		return requestID, int64(len(raw)), nil, errors.New("command body exceeds the 1 MiB limit")
	}
	var sourceDocument map[string]any
	if err := json.Unmarshal(raw, &sourceDocument); err != nil || sourceDocument == nil {
		if err == nil {
			err = errors.New("command body must be a JSON object")
		}
		return requestID, int64(len(raw)), nil, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return requestID, int64(len(raw)), sourceDocument, err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return requestID, int64(len(raw)), sourceDocument, errors.New("command body must contain exactly one JSON object")
	}
	if issue := guestruntimedomain.ValidateCatalogObservationIngestCommand(*destination); issue != nil {
		return requestID, int64(len(raw)), sourceDocument, errors.New(issue.Code)
	}
	return requestID, int64(len(raw)), sourceDocument, nil
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
