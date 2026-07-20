package guestruntimecontrolhttpapplication

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestOpenGuestRuntimeControlHTTPApplicationServesGuestRuntimeReadiness(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	controlHTTPApplication, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err != nil {
		t.Fatalf("compose Guest Runtime Control HTTP application: %v", err)
	}
	t.Cleanup(func() {
		if closeError := controlHTTPApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			t.Fatalf("close Guest Runtime Control HTTP application: %v", closeError)
		}
	})

	request := httptest.NewRequest(http.MethodGet, "/v1/runtime/readiness", nil)
	response := httptest.NewRecorder()
	controlHTTPApplication.ControlHTTPHandler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("Guest Runtime readiness HTTP status = %d, body=%s", response.Code, response.Body.String())
	}
	var readiness map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &readiness); err != nil {
		t.Fatalf("decode Guest Runtime readiness: %v", err)
	}
	if readiness["state"] != "available" {
		t.Fatalf("Guest Runtime readiness state = %#v", readiness["state"])
	}
	if err := controlHTTPApplication.ReconcilePendingTerminalArchiveExports(context.Background()); err != nil {
		t.Fatalf("reconcile empty durable terminal archive intent set: %v", err)
	}
}

func TestOpenGuestRuntimeControlHTTPApplicationRejectsMissingSelectedOutcomeMode(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.GuestTelemetryExportOutcomeMode = ""

	_, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err == nil || !strings.Contains(err.Error(), "telemetry outcome profile") {
		t.Fatalf("missing selected outcome mode error = %v", err)
	}
}

func TestOpenGuestRuntimeControlHTTPApplicationPublishesArchiveProviderConfigurationWithoutClaimingAnExport(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	application, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err != nil {
		t.Fatalf("compose Guest Runtime Control HTTP application: %v", err)
	}
	t.Cleanup(func() { _ = application.CloseGuestRuntimeControlHTTPApplication() })

	request := httptest.NewRequest(http.MethodGet, "/v1/runtime/archive/export-provider", nil)
	response := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("archive provider status=%d body=%s", response.Code, response.Body.String())
	}
	var document map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &document); err != nil {
		t.Fatalf("decode archive provider configuration: %v", err)
	}
	value, ok := document["value"].(map[string]any)
	if !ok || document["state"] != "available" {
		t.Fatalf("archive provider read=%#v", document)
	}
	provider, ok := value["provider"].(map[string]any)
	if !ok || provider["kind"] != "archive-export-outcome-profile" || provider["id"] != "bundled-archive" || provider["capabilityRevision"] != float64(1) {
		t.Fatalf("archive provider configuration=%#v", document)
	}
	if value["artifactManifestReference"] != nil || value["upload"] != nil || value["indexing"] != nil {
		t.Fatalf("archive provider configuration incorrectly claimed an export: %#v", value)
	}
}

func TestOpenGuestRuntimeControlHTTPApplicationStartsWithMissingExternalArchiveCredentialThenProvisionsItThroughTheNamedControlRoute(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	root := t.TempDir()
	configurationPath := filepath.Join(root, "external-vitalserver-delivery.json")
	writeExternalArchiveCredentialDeliveryConfiguration(t, configurationPath)
	deployment.ArchiveExportProviderReference = guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "external-library", CapabilityRevision: 1}
	deployment.ArchiveExportProviderOutcomeMode = ""
	deployment.ArchiveProviderVitalServerConfigurationKind = "external-vitalserver-delivery-configuration"
	deployment.ArchiveProviderVitalServerConfigurationPath = configurationPath
	deployment.ArchiveProviderCredentialMaterialPath = filepath.Join(root, "secrets", "external-library.json")
	deployment.ExternalUpstreamObservationProviderReference = guestruntimedomain.IntegrationProviderReference{Kind: "external-vitalserver-http", ID: "external-vitalserver-primary", CapabilityRevision: 1}
	deployment.ExternalUpstreamObservationProviderOutcomeMode = ""
	deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath = configurationPath
	deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds = 1000

	application, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err != nil {
		t.Fatalf("Guest Runtime must start before C51 exists: %v", err)
	}
	t.Cleanup(func() { _ = application.CloseGuestRuntimeControlHTTPApplication() })

	readRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/archive/credential-material", nil)
	readResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(readResponse, readRequest)
	if readResponse.Code != http.StatusOK {
		t.Fatalf("missing credential status=%d body=%s", readResponse.Code, readResponse.Body.String())
	}
	var before map[string]any
	if err := json.Unmarshal(readResponse.Body.Bytes(), &before); err != nil {
		t.Fatalf("decode missing credential status: %v", err)
	}
	if before["state"] != "missing" || before["userId"] != nil || before["password"] != nil {
		t.Fatalf("missing credential response leaked or changed state: %#v", before)
	}

	provisionRequest := httptest.NewRequest(http.MethodPost, "/v1/runtime/archive/credential-material", strings.NewReader(`{"schemaVersion":"v1","credentialReference":{"kind":"vitalserver-library-credential","id":"external-library"},"userId":"operator","password":"test-only-password"}`))
	provisionResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(provisionResponse, provisionRequest)
	if provisionResponse.Code != http.StatusOK {
		t.Fatalf("credential provision status=%d body=%s", provisionResponse.Code, provisionResponse.Body.String())
	}
	if strings.Contains(provisionResponse.Body.String(), "test-only-password") || strings.Contains(provisionResponse.Body.String(), "\"operator\"") {
		t.Fatalf("credential provision response exposed material: %s", provisionResponse.Body.String())
	}

	readResponse = httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(readResponse, readRequest)
	var after map[string]any
	if err := json.Unmarshal(readResponse.Body.Bytes(), &after); err != nil {
		t.Fatalf("decode provisioned credential status: %v", err)
	}
	if readResponse.Code != http.StatusOK || after["state"] != "available" || after["userId"] != nil || after["password"] != nil {
		t.Fatalf("provisioned credential status leaked or changed state: code=%d body=%#v", readResponse.Code, after)
	}
}

func TestOpenGuestRuntimeControlHTTPApplicationExportsRedactedTelemetryToExplicitOTLPCollector(t *testing.T) {
	var collectorPayloads []string
	collector := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Fatalf("read OTLP Collector request: %v", err)
		}
		collectorPayloads = append(collectorPayloads, request.URL.Path+"\n"+string(body))
		response.WriteHeader(http.StatusAccepted)
	}))
	defer collector.Close()

	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.GuestTelemetryAdapterKind = "otlp-http"
	deployment.GuestTelemetryCollectorBaseEndpoint = collector.URL
	deployment.GuestTelemetryRequestTimeoutMilliseconds = 1000
	deployment.GuestTelemetryCollectorProbeOutcomeMode = ""
	deployment.GuestTelemetryExportOutcomeMode = ""
	application, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err != nil {
		t.Fatalf("compose live OTLP Guest Runtime application: %v", err)
	}
	t.Cleanup(func() { _ = application.CloseGuestRuntimeControlHTTPApplication() })

	pipeline := guestruntimedomain.TelemetryPipelineApplyCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "otlp-pipeline-apply", PipelineID: "otlp-pipeline", ExpectedResourceRevision: 0,
		Node: deployment.GuestRuntimeNode,
		Spec: guestruntimedomain.TelemetryPipelineSpec{Protocol: "otlp-http", CollectorReference: guestruntimedomain.ResourceReference{ResourceType: "otel-collector", ResourceID: "collector-primary"}, SignalKinds: []string{"logs", "metrics", "traces"}, Redaction: guestruntimedomain.TelemetryRedactionPolicy{AllowedAttributeKeys: []string{"operation.kind"}, MaxAttributes: 1, MaxValueLength: 32, MaxDistinctValuesPerKey: 5}},
	}
	pipelineOutcome := postGuestRuntimeControlCommand(t, application.ControlHTTPHandler, "/v1/runtime/telemetry/pipelines", pipeline)
	if pipelineOutcome["state"] != "succeeded" {
		t.Fatalf("live OTLP pipeline outcome=%+v", pipelineOutcome)
	}
	emit := guestruntimedomain.TelemetrySignalEmitCommand{SchemaVersion: guestruntimedomain.SchemaVersion, RequestID: "otlp-signal-emit", PipelineID: "otlp-pipeline", ExpectedResourceRevision: 1, Signal: guestruntimedomain.TelemetryCorrelation{SchemaVersion: guestruntimedomain.SchemaVersion, Service: guestruntimedomain.ServiceIdentity{Name: "guest-runtime", Version: "acceptance", InstanceID: "guest-runtime-acceptance"}, SignalKinds: []string{"logs", "metrics", "traces"}, SignalName: "lab.stop", EmittedAt: "2026-07-19T01:02:03Z"}, Attributes: map[string]string{"operation.kind": "lab-stop", "patient.id": "must-never-leave-process"}}
	emitOutcome := postGuestRuntimeControlCommand(t, application.ControlHTTPHandler, "/v1/runtime/telemetry/signals", emit)
	if emitOutcome["state"] != "succeeded" {
		t.Fatalf("live OTLP emit outcome=%+v", emitOutcome)
	}
	if len(collectorPayloads) != 4 || !strings.HasPrefix(collectorPayloads[0], "/v1/logs\n") || !strings.HasPrefix(collectorPayloads[1], "/v1/logs\n") || !strings.HasPrefix(collectorPayloads[2], "/v1/metrics\n") || !strings.HasPrefix(collectorPayloads[3], "/v1/traces\n") {
		t.Fatalf("OTLP Collector paths=%v", collectorPayloads)
	}
	for _, payload := range collectorPayloads[1:] {
		if !strings.Contains(payload, "operation.kind") || strings.Contains(payload, "patient.id") || strings.Contains(payload, "must-never-leave-process") {
			t.Fatalf("OTLP Collector payload crossed redaction boundary: %s", payload)
		}
	}
}

func postGuestRuntimeControlCommand(t *testing.T, handler http.Handler, path string, command any) map[string]any {
	t.Helper()
	body, err := json.Marshal(command)
	if err != nil {
		t.Fatalf("encode control command: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(body))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted {
		t.Fatalf("control command %s status=%d body=%s", path, response.Code, response.Body.String())
	}
	var outcome map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &outcome); err != nil {
		t.Fatalf("decode control command outcome: %v", err)
	}
	return outcome
}

func validGuestRuntimeControlHTTPApplicationDeployment(t *testing.T) GuestRuntimeControlHTTPApplicationDeployment {
	t.Helper()
	return GuestRuntimeControlHTTPApplicationDeployment{
		GuestRuntimeStateDatabasePath:                  filepath.Join(t.TempDir(), "guest-runtime.sqlite"),
		GuestRuntimeServiceVersion:                     "acceptance",
		GuestRuntimeInstanceID:                         "guest-runtime-acceptance",
		ArchiveExportProviderReference:                 guestruntimedomain.ArchiveProviderReference{Kind: "archive-export-outcome-profile", ID: "bundled-archive", CapabilityRevision: 1},
		ArchiveExportProviderOutcomeMode:               "succeed",
		RecorderGatewayColdPathSourceEndpoint:          "http://127.0.0.1:8090",
		LabRecorderRunnerEndpoint:                      "http://127.0.0.1:8091",
		ExternalUpstreamObservationProviderReference:   guestruntimedomain.IntegrationProviderReference{Kind: "external-capability-profile", ID: "external-upstream", CapabilityRevision: 1},
		ExternalUpstreamObservationProviderOutcomeMode: "unsupported",
		OutboundRelayObservationProviderReference:      guestruntimedomain.IntegrationProviderReference{Kind: "outbound-relay-profile", ID: "outbound-relay", CapabilityRevision: 1},
		OutboundRelayObservationProviderOutcomeMode:    "unsupported",
		GuestRuntimeNode:                               guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-runtime-acceptance"},
		GuestTimeAuthorityID:                           "guest-time-authority",
		GuestTimeAuthorityAdapterKind:                  "time-authority-outcome-profile",
		GuestTimeAuthorityProbeOutcomeMode:             "unsupported",
		GuestTelemetryAdapterKind:                      "telemetry-export-outcome-profile",
		GuestTelemetryCollectorProbeOutcomeMode:        "unsupported",
		GuestTelemetryExportOutcomeMode:                "unavailable",
	}
}

func writeExternalArchiveCredentialDeliveryConfiguration(t *testing.T, path string) {
	t.Helper()
	contents := []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"external-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"external-library"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}`)
	if err := os.WriteFile(path, contents, 0o644); err != nil {
		t.Fatalf("write C46 external delivery configuration: %v", err)
	}
}
