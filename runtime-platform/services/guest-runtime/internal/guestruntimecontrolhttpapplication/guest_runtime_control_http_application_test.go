package guestruntimecontrolhttpapplication

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestValidateGuestRuntimeDeploymentRejectsImplicitLabReplayPolicy(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.LabReplayGapPolicy = ""
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("expected missing Lab replay gap policy to be rejected")
	}
	deployment = validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.LabReplaySpoolRootDirectory = "relative/replay-spools"
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("expected relative Lab replay spool root to be rejected")
	}
}

func TestValidateGuestRuntimeDeploymentRequiresOneSecondRealtimeReplayBatch(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.LabReplayFrameBatchSize = 2
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("multi-frame replay batch must not bypass one-second real-time pacing")
	}
}

func TestValidateGuestRuntimeDeploymentRequiresCompleteExplicitRestoreTarget(
	t *testing.T,
) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	configureGuestOperationalStateBackup(t, &deployment)
	deployment.GuestOperationalStateRestoreSQLiteTargetPath =
		filepath.Join(t.TempDir(), "restored.sqlite")
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("partial restore configuration must be rejected")
	}

	deployment = validGuestRuntimeControlHTTPApplicationDeployment(t)
	configureGuestOperationalStateBackup(t, &deployment)
	deployment.GuestOperationalStateRestoreTargetReference =
		guestruntimedomain.ResourceReference{
			ResourceType: "guest-restore-target",
			ResourceID:   "maintenance-target-1",
		}
	deployment.GuestOperationalStateRestoreSQLiteTargetPath =
		filepath.Join(t.TempDir(), "restored.sqlite")
	deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL =
		"postgresql://explicit-test-owner/empty-restore-target"
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err != nil {
		t.Fatalf("complete explicit restore configuration rejected: %v", err)
	}
}

func TestValidateGuestRuntimeDeploymentRejectsLiveStateAsRestoreTarget(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	configureGuestOperationalStateBackup(t, &deployment)
	deployment.GuestOperationalStateRestoreTargetReference =
		guestruntimedomain.ResourceReference{
			ResourceType: "guest-restore-target",
			ResourceID:   "maintenance-target-1",
		}
	deployment.GuestOperationalStateRestoreSQLiteTargetPath =
		deployment.GuestRuntimeStateDatabasePath
	deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL =
		"postgresql://explicit-test-owner/empty-restore-target"
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("live SQLite state must not be accepted as a restore target")
	}

	deployment.GuestOperationalStateRestoreSQLiteTargetPath =
		filepath.Join(t.TempDir(), "restored.sqlite")
	deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL =
		deployment.RecorderCatalogPostgreSQLDatabaseURL
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err == nil {
		t.Fatal("live PostgreSQL state must not be accepted as a restore target")
	}
}

func TestLabReplayWorkerUsesPreparationOutputTimeBeforeNextFrameEffect(t *testing.T) {
	firstOutput := time.Now().Add(120 * time.Millisecond)
	calls := make(chan time.Time, 2)
	callCount := 0
	application := &GuestRuntimeControlHTTPApplication{
		runNextLabReplayEffect: func(context.Context) (guestruntimedomain.LabReplayOperation, bool, error) {
			callCount++
			calls <- time.Now()
			if callCount > 1 {
				return guestruntimedomain.LabReplayOperation{}, false, nil
			}
			return guestruntimedomain.LabReplayOperation{
				State:                 guestruntimedomain.LabReplaySendingState,
				NextFrameOffsetSecond: 0,
				PreparationReceipt: &guestruntimedomain.LabReplayPreparationReceipt{
					OutputStartedAt: float64(firstOutput.UnixNano()) / float64(time.Second),
				},
			}, true, nil
		},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		application.runLabReplayWorker(ctx)
	}()
	<-calls
	select {
	case <-calls:
		t.Fatal("Lab replay worker ran the next frame before its explicit output time")
	case <-time.After(50 * time.Millisecond):
	}
	select {
	case calledAt := <-calls:
		if calledAt.Before(firstOutput.Add(-20 * time.Millisecond)) {
			t.Fatalf("next replay effect ran early: calledAt=%s outputAt=%s", calledAt, firstOutput)
		}
	case <-time.After(time.Second):
		t.Fatal("Lab replay worker did not resume at the explicit output time")
	}
	cancel()
	<-done
}

func TestLabReplayWorkerBacksOffUnknownEffectFailure(t *testing.T) {
	calls := make(chan struct{}, 2)
	application := &GuestRuntimeControlHTTPApplication{
		runNextLabReplayEffect: func(context.Context) (guestruntimedomain.LabReplayOperation, bool, error) {
			calls <- struct{}{}
			return guestruntimedomain.LabReplayOperation{}, true, errors.New("Runner unavailable")
		},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		application.runLabReplayWorker(ctx)
	}()
	<-calls
	select {
	case <-calls:
		t.Fatal("unknown replay effect failure caused a busy retry loop")
	case <-time.After(100 * time.Millisecond):
	}
	cancel()
	<-done
}

func TestLabReplayWorkerRetriesUnknownEffectAfterBackoff(t *testing.T) {
	calls := make(chan int, 2)
	callCount := 0
	application := &GuestRuntimeControlHTTPApplication{
		runNextLabReplayEffect: func(context.Context) (guestruntimedomain.LabReplayOperation, bool, error) {
			callCount++
			if callCount == 1 {
				calls <- callCount
				return guestruntimedomain.LabReplayOperation{
					ID:    "retry-replay-1",
					State: guestruntimedomain.LabReplayAwaitingUpstreamDeliveryState,
				}, true, errors.New("upstream evidence is not terminal yet")
			}
			if callCount == 2 {
				calls <- callCount
				return guestruntimedomain.LabReplayOperation{
					ID:    "retry-replay-1",
					State: guestruntimedomain.LabReplayFailedState,
				}, true, nil
			}
			return guestruntimedomain.LabReplayOperation{
				ID: "retry-replay-1",
			}, false, nil
		},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		application.runLabReplayWorker(ctx)
	}()
	if first := <-calls; first != 1 {
		t.Fatalf("first call=%d", first)
	}
	select {
	case second := <-calls:
		if second != 2 {
			t.Fatalf("second call=%d", second)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Lab replay worker did not retry an unknown effect outcome")
	}
	cancel()
	<-done
}

func TestArchiveSourceAdmissionRequiresGatewayCredentialAndPersistsExactObject(
	t *testing.T,
) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	controlHTTPApplication, err := openTestGuestRuntimeControlHTTPApplication(
		context.Background(),
		deployment,
	)
	if err != nil {
		t.Fatalf("compose Guest Runtime Control HTTP application: %v", err)
	}
	t.Cleanup(func() {
		if closeError := controlHTTPApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			t.Fatalf("close Guest Runtime Control HTTP application: %v", closeError)
		}
	})
	assignmentCommand := `{"schemaVersion":"v1","requestId":"archive-assignment-request-1","evidenceId":"archive-assignment-evidence-1","recorderId":"recorder-OR-01","bedName":"OR-01","effectiveFrom":"2026-07-24T13:00:00Z","observedAt":"2026-07-24T13:00:00Z","sourceKind":"administrator","sourceReference":{"kind":"administrator-command","id":"archive-assignment-command-1"}}`
	assignmentRequest := httptest.NewRequest(
		http.MethodPost,
		"/v1/runtime/recorder-assignments",
		strings.NewReader(assignmentCommand),
	)
	assignmentResponse := httptest.NewRecorder()
	controlHTTPApplication.ControlHTTPHandler.ServeHTTP(
		assignmentResponse,
		assignmentRequest,
	)
	if assignmentResponse.Code != http.StatusAccepted {
		t.Fatalf(
			"assignment admission status=%d body=%s",
			assignmentResponse.Code,
			assignmentResponse.Body.String(),
		)
	}
	content := []byte("complete-vital-content")
	sum := sha256.Sum256(content)
	sourceReceiptID := "recorder-vital-upload-http-test"
	command := guestruntimedomain.ArchiveSourceAdmissionCommand{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		RequestID:     "archive-source-http-request-1",
		Source: guestruntimedomain.RecorderVitalUploadSourceReceipt{
			SchemaVersion:    guestruntimedomain.SchemaVersion,
			ID:               sourceReceiptID,
			SourceKind:       guestruntimedomain.RecorderUploadArchiveSourceKind,
			UploadID:         "http-upload-1",
			OriginalFileName: "OR-01.vital",
			MediaType:        "application/x-vital",
			ByteSize:         int64(len(content)),
			SHA256:           hex.EncodeToString(sum[:]),
			ReportedBedName:  "OR-01",
			State:            "admitted",
			ContentReference: guestruntimedomain.ResourceReference{
				ResourceType: "recorder-vital-upload-content",
				ResourceID:   sourceReceiptID,
			},
			ReceivedAt:  "2026-07-24T14:00:00Z",
			FinalizedAt: "2026-07-24T14:00:00Z",
		},
	}
	encodedCommand, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	newRequest := func() *http.Request {
		request := httptest.NewRequest(
			http.MethodPost,
			"/internal/v1/archive/recorder-uploads",
			bytes.NewReader(content),
		)
		request.Header.Set("Content-Type", "application/x-vital")
		request.Header.Set(
			"X-Vital-Archive-Source-Command",
			base64.RawURLEncoding.EncodeToString(encodedCommand),
		)
		return request
	}
	unauthorizedResponse := httptest.NewRecorder()
	controlHTTPApplication.ControlHTTPHandler.ServeHTTP(
		unauthorizedResponse,
		newRequest(),
	)
	if unauthorizedResponse.Code != http.StatusUnauthorized {
		t.Fatalf(
			"unauthorized Archive source status=%d body=%s",
			unauthorizedResponse.Code,
			unauthorizedResponse.Body.String(),
		)
	}

	authorized := newRequest()
	authorized.Header.Set(
		"Authorization",
		"Bearer "+deployment.ArchiveSourceAdmissionBearerToken,
	)
	authorizedResponse := httptest.NewRecorder()
	controlHTTPApplication.ControlHTTPHandler.ServeHTTP(
		authorizedResponse,
		authorized,
	)
	if authorizedResponse.Code != http.StatusAccepted {
		t.Fatalf(
			"authorized Archive source status=%d body=%s",
			authorizedResponse.Code,
			authorizedResponse.Body.String(),
		)
	}
	artifactID, err := guestruntimedomain.ArchiveArtifactIDForSourceReceipt(
		command.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		command.Source.ID,
	)
	if err != nil {
		t.Fatal(err)
	}
	stored, err := os.ReadFile(filepath.Join(
		deployment.ArchiveArtifactObjectRootDirectory,
		"objects",
		artifactID,
		"content.vital",
	))
	if err != nil {
		t.Fatalf("read admitted Archive object: %v", err)
	}
	if !bytes.Equal(stored, content) {
		t.Fatalf("admitted Archive object bytes differ: %q", stored)
	}
	detailRequest := httptest.NewRequest(
		http.MethodGet,
		"/v1/runtime/artifacts/"+artifactID,
		nil,
	)
	detailResponse := httptest.NewRecorder()
	controlHTTPApplication.ControlHTTPHandler.ServeHTTP(
		detailResponse,
		detailRequest,
	)
	if detailResponse.Code != http.StatusOK ||
		!strings.Contains(detailResponse.Body.String(), `"outcome":"matched"`) ||
		!strings.Contains(detailResponse.Body.String(), `"matchedRecorderId":"recorder-OR-01"`) ||
		!strings.Contains(detailResponse.Body.String(), `"kind":"recorder-assignment-resolution"`) {
		t.Fatalf(
			"assigned Archive detail status=%d body=%s",
			detailResponse.Code,
			detailResponse.Body.String(),
		)
	}
}

func TestOpenGuestRuntimeControlHTTPApplicationServesGuestRuntimeReadiness(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	controlHTTPApplication, err := openTestGuestRuntimeControlHTTPApplication(context.Background(), deployment)
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

func TestRecorderCatalogInternalAdmissionRequiresConfiguredGatewayCredential(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	application, err := openTestGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = application.CloseGuestRuntimeControlHTTPApplication() })
	command := `{"schemaVersion":"v1","requestId":"gateway-admission-1","observationId":"gateway-observation-1","envelope":{"schemaVersion":"v1","protocolVersion":"v1","recorderId":"gateway-recorder-1","bootId":"gateway-boot-1","sequence":1,"occurredAt":"2026-07-24T01:02:03Z","time":{"state":"not-reported"},"runtime":{"state":"ready","version":"1.2.3"}}}`

	unauthorized := httptest.NewRequest(http.MethodPost, "/internal/v1/recorder-catalog/observations", strings.NewReader(command))
	unauthorizedResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(unauthorizedResponse, unauthorized)
	if unauthorizedResponse.Code != http.StatusUnauthorized || !strings.Contains(unauthorizedResponse.Body.String(), "recorder-catalog-source-authentication-failed") {
		t.Fatalf("unauthorized Catalog admission status=%d body=%s", unauthorizedResponse.Code, unauthorizedResponse.Body.String())
	}

	authorized := httptest.NewRequest(http.MethodPost, "/internal/v1/recorder-catalog/observations", strings.NewReader(command))
	authorized.Header.Set("Authorization", "Bearer "+deployment.RecorderCatalogAdmissionBearerToken)
	authorized.Header.Set("Content-Type", "application/json")
	authorizedResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(authorizedResponse, authorized)
	if authorizedResponse.Code != http.StatusAccepted || !strings.Contains(authorizedResponse.Body.String(), `"outcome":"accepted"`) {
		t.Fatalf("authorized Catalog admission status=%d body=%s", authorizedResponse.Code, authorizedResponse.Body.String())
	}
	invalidCommand := `{"schemaVersion":"v1","requestId":"gateway-quarantine-1","observationId":"gateway-invalid-1","envelope":{"schemaVersion":"v1","protocolVersion":"v1","recorderId":"gateway-recorder-1","bootId":"gateway-boot-1","sequence":2,"occurredAt":"not-a-time","time":{"state":"not-reported"},"runtime":{"state":"ready","version":"1.2.3"}}}`
	quarantineRequest := httptest.NewRequest(http.MethodPost, "/internal/v1/recorder-catalog/observations", strings.NewReader(invalidCommand))
	quarantineRequest.Header.Set("Authorization", "Bearer "+deployment.RecorderCatalogAdmissionBearerToken)
	quarantineRequest.Header.Set("Content-Type", "application/json")
	quarantineResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(quarantineResponse, quarantineRequest)
	if quarantineResponse.Code != http.StatusAccepted || !strings.Contains(quarantineResponse.Body.String(), `"outcome":"quarantined"`) || !strings.Contains(quarantineResponse.Body.String(), `"invalid-recorder-observation-document"`) {
		t.Fatalf("quarantined Catalog admission status=%d body=%s", quarantineResponse.Code, quarantineResponse.Body.String())
	}

	expectationCommand := `{"schemaVersion":"v1","requestId":"gateway-recorder-expectation-1","expectedResourceRevision":0,"action":"set","expectationState":"expected","source":"operator-console","evidence":{"ticketId":"support-1"}}`
	expectationRequest := httptest.NewRequest(http.MethodPost, "/v1/runtime/recorders/gateway-recorder-1/observability-expectation", strings.NewReader(expectationCommand))
	expectationResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(expectationResponse, expectationRequest)
	if expectationResponse.Code != http.StatusAccepted || !strings.Contains(expectationResponse.Body.String(), `"state":"persisted"`) {
		t.Fatalf("Recorder expectation status=%d body=%s", expectationResponse.Code, expectationResponse.Body.String())
	}
	assignmentCommand := `{"schemaVersion":"v1","requestId":"gateway-recorder-assignment-1","evidenceId":"gateway-recorder-assignment-evidence-1","recorderId":"gateway-recorder-1","bedName":"OR-01","effectiveFrom":"2026-07-24T00:00:00Z","observedAt":"2026-07-24T00:00:00Z","sourceKind":"administrator","sourceReference":{"kind":"administrator-command","id":"operator-assignment-1"}}`
	assignmentRequest := httptest.NewRequest(http.MethodPost, "/v1/runtime/recorder-assignments", strings.NewReader(assignmentCommand))
	assignmentResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(assignmentResponse, assignmentRequest)
	if assignmentResponse.Code != http.StatusAccepted ||
		!strings.Contains(assignmentResponse.Body.String(), `"outcome":"accepted"`) {
		t.Fatalf("Recorder assignment status=%d body=%s", assignmentResponse.Code, assignmentResponse.Body.String())
	}
	summaryRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/recorders/gateway-recorder-1/observability", nil)
	summaryResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(summaryResponse, summaryRequest)
	if summaryResponse.Code != http.StatusOK || !strings.Contains(summaryResponse.Body.String(), `"resourceRevision":2`) || !strings.Contains(summaryResponse.Body.String(), `"expectationState":"expected"`) {
		t.Fatalf("Recorder expectation summary status=%d body=%s", summaryResponse.Code, summaryResponse.Body.String())
	}
	summaryPageRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/recorders?limit=25", nil)
	summaryPageResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(summaryPageResponse, summaryPageRequest)
	if summaryPageResponse.Code != http.StatusOK ||
		!strings.Contains(summaryPageResponse.Body.String(), `"recorderId":"gateway-recorder-1"`) ||
		!strings.Contains(summaryPageResponse.Body.String(), `"expectationState":"expected"`) {
		t.Fatalf("Recorder summary page status=%d body=%s", summaryPageResponse.Code, summaryPageResponse.Body.String())
	}
	timelineRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/recorders/gateway-recorder-1/observability/timeline?limit=1", nil)
	timelineResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(timelineResponse, timelineRequest)
	if timelineResponse.Code != http.StatusOK || !strings.Contains(timelineResponse.Body.String(), `"observationId"`) && !strings.Contains(timelineResponse.Body.String(), `"gateway-observation-1"`) {
		t.Fatalf("Recorder timeline status=%d body=%s", timelineResponse.Code, timelineResponse.Body.String())
	}
	incidentRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/recorders/gateway-recorder-1/observability/incidents?limit=10", nil)
	incidentResponse := httptest.NewRecorder()
	application.ControlHTTPHandler.ServeHTTP(incidentResponse, incidentRequest)
	if incidentResponse.Code != http.StatusOK || !strings.Contains(incidentResponse.Body.String(), `"state":"empty"`) {
		t.Fatalf("Recorder incident history status=%d body=%s", incidentResponse.Code, incidentResponse.Body.String())
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
	application, err := openTestGuestRuntimeControlHTTPApplication(context.Background(), deployment)
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

	application, err := openTestGuestRuntimeControlHTTPApplication(context.Background(), deployment)
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
	application, err := openTestGuestRuntimeControlHTTPApplication(context.Background(), deployment)
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
	bootstrapRoot := t.TempDir()
	databaseURLMaterialPath := filepath.Join(
		bootstrapRoot,
		"recorder-catalog-database-url",
	)
	migrationReceiptPath := filepath.Join(
		bootstrapRoot,
		"recorder-catalog-migration-receipt.json",
	)
	catalogTokenMaterialPath := filepath.Join(
		bootstrapRoot,
		"recorder-catalog-admission-token",
	)
	archiveTokenMaterialPath := filepath.Join(
		bootstrapRoot,
		"archive-source-admission-token",
	)
	for _, material := range []struct {
		path     string
		contents string
	}{
		{databaseURLMaterialPath, "postgresql://explicit-test-owner/not-opened"},
		{catalogTokenMaterialPath, "test-only-recorder-gateway-token"},
		{archiveTokenMaterialPath, "test-only-archive-source-token"},
		{migrationReceiptPath, `{"schemaVersion":"v1","state":"succeeded","revision":"0006_backup_owner","startedAt":"2026-07-24T00:00:00Z","finishedAt":"2026-07-24T00:00:01Z"}`},
	} {
		if err := os.WriteFile(material.path, []byte(material.contents), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return GuestRuntimeControlHTTPApplicationDeployment{
		GuestRuntimeStateDatabasePath:                   filepath.Join(t.TempDir(), "guest-runtime.sqlite"),
		RecorderCatalogPostgreSQLDatabaseURL:            "postgresql://explicit-test-owner/not-opened",
		RecorderCatalogDatabaseURLMaterialPath:          databaseURLMaterialPath,
		RecorderCatalogMigrationReceiptPath:             migrationReceiptPath,
		RecorderCatalogAdmissionBearerToken:             "test-only-recorder-gateway-token",
		RecorderCatalogAdmissionBearerTokenMaterialPath: catalogTokenMaterialPath,
		RecorderObservationMaxReportAgeSeconds:          300,
		ArchiveSourceAdmissionBearerToken:               "test-only-archive-source-token",
		ArchiveSourceAdmissionBearerTokenMaterialPath:   archiveTokenMaterialPath,
		ArchiveArtifactObjectRootDirectory:              filepath.Join(t.TempDir(), "archive-objects"),
		ArchiveSourceMaximumBytes:                       64 << 20,
		LabReplaySourceObjectRootDirectory:              filepath.Join(t.TempDir(), "lab-replay-sources"),
		LabReplaySourceMaximumBytes:                     64 << 20,
		LabReplaySpoolRootDirectory:                     filepath.Join(t.TempDir(), "lab-replay-spools"),
		LabReplayStringTrackPolicy:                      guestruntimedomain.VitalFileStringTrackPolicySkip,
		LabReplayGapPolicy:                              guestruntimedomain.VitalFileReplayGapPolicyFailFrame,
		LabReplayFrameBatchSize:                         1,
		RecorderAttributionPolicyKind:                   "recorder-assignment-owner",
		GuestRuntimeServiceVersion:                      "acceptance",
		GuestRuntimeInstanceID:                          "guest-runtime-acceptance",
		ArchiveExportProviderReference:                  guestruntimedomain.ArchiveProviderReference{Kind: "archive-export-outcome-profile", ID: "bundled-archive", CapabilityRevision: 1},
		ArchiveExportProviderOutcomeMode:                "succeed",
		RecorderGatewayColdPathSourceEndpoint:           "http://127.0.0.1:8090",
		LabRecorderRunnerEndpoint:                       "http://127.0.0.1:8091",
		ExternalUpstreamObservationProviderReference:    guestruntimedomain.IntegrationProviderReference{Kind: "external-capability-profile", ID: "external-upstream", CapabilityRevision: 1},
		ExternalUpstreamObservationProviderOutcomeMode:  "unsupported",
		OutboundRelayObservationProviderReference:       guestruntimedomain.IntegrationProviderReference{Kind: "outbound-relay-profile", ID: "outbound-relay", CapabilityRevision: 1},
		OutboundRelayObservationProviderOutcomeMode:     "unsupported",
		GuestRuntimeNode:                                guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-runtime-acceptance"},
		GuestTimeAuthorityID:                            "guest-time-authority",
		GuestTimeAuthorityAdapterKind:                   "time-authority-outcome-profile",
		GuestTimeAuthorityProbeOutcomeMode:              "unsupported",
		GuestTelemetryAdapterKind:                       "telemetry-export-outcome-profile",
		GuestTelemetryCollectorProbeOutcomeMode:         "unsupported",
		GuestTelemetryExportOutcomeMode:                 "unavailable",
	}
}

func configureGuestOperationalStateBackup(
	t *testing.T,
	deployment *GuestRuntimeControlHTTPApplicationDeployment,
) {
	t.Helper()
	root := t.TempDir()
	deployment.GuestOperationalStateBackupRootDirectory = root
	deployment.GuestOperationalStateBackupLedgerDatabasePath =
		filepath.Join(root, "backup-ledger.sqlite")
	deployment.GuestOperationalStateBackupDestinationReference =
		guestruntimedomain.ResourceReference{
			ResourceType: "guest-backup-destination",
			ResourceID:   "local-backup-root-1",
		}
	deployment.GuestOperationalStatePostgreSQLDumpExecutablePath =
		filepath.Join(root, "pg_dump")
	deployment.GuestOperationalStatePostgreSQLRestoreExecutablePath =
		filepath.Join(root, "pg_restore")
}

func writeExternalArchiveCredentialDeliveryConfiguration(t *testing.T, path string) {
	t.Helper()
	contents := []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"external-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"external-library"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}`)
	if err := os.WriteFile(path, contents, 0o644); err != nil {
		t.Fatalf("write C46 external delivery configuration: %v", err)
	}
}
