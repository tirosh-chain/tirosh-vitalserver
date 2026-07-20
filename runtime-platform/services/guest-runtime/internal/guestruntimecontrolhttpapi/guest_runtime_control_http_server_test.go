package guestruntimecontrolhttpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func newServerWithRepository(t *testing.T, repository guestruntimeapplication.GuestRuntimeTopologyStateRepository) http.Handler {
	t.Helper()
	service, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationService(repository, guestruntimeapplication.SystemGuestRuntimeClock{}, guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{}, "test", "guest-test")
	if err != nil {
		t.Fatalf("new service: %v", err)
	}
	return guestruntimecontrolhttpapi.NewGuestRuntimeTopologyHTTPServer(service)
}

func newServer(t *testing.T) http.Handler {
	t.Helper()
	repository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	return newServerWithRepository(t, repository)
}

func validCommand() guestruntimedomain.TopologyApplyCommand {
	return guestruntimedomain.TopologyApplyCommand{
		SchemaVersion:            "v1",
		RequestID:                "http-request-1",
		TopologyID:               "primary-topology",
		ExpectedResourceRevision: 0,
		Spec: guestruntimedomain.RuntimeTopologySpec{
			ProfileKind:  "external-upstream",
			ProviderKind: "vitalserver",
			EndpointReference: guestruntimedomain.ResourceReference{
				ResourceType: guestruntimedomain.ExternalUpstreamIntegrationResourceType,
				ResourceID:   "primary",
			},
		},
	}
}

func TestTopologyApplyRoundTripUsesOnlyGuestOwnedDocuments(t *testing.T) {
	server := newServer(t)
	payload, err := json.Marshal(validCommand())
	if err != nil {
		t.Fatal(err)
	}
	applyRequest := httptest.NewRequest(http.MethodPost, "/v1/runtime/topology:apply", bytes.NewReader(payload))
	applyResponse := httptest.NewRecorder()
	server.ServeHTTP(applyResponse, applyRequest)
	if applyResponse.Code != http.StatusAccepted {
		t.Fatalf("apply status = %d body=%s", applyResponse.Code, applyResponse.Body.String())
	}
	var operation guestruntimedomain.Operation
	if err := json.Unmarshal(applyResponse.Body.Bytes(), &operation); err != nil {
		t.Fatalf("decode operation: %v", err)
	}
	if operation.State != "succeeded" {
		t.Fatalf("operation state = %s", operation.State)
	}

	topologyRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/topology", nil)
	topologyResponse := httptest.NewRecorder()
	server.ServeHTTP(topologyResponse, topologyRequest)
	var read guestruntimedomain.ReadResult
	if err := json.Unmarshal(topologyResponse.Body.Bytes(), &read); err != nil {
		t.Fatalf("decode topology read: %v", err)
	}
	if read.State != "available" {
		t.Fatalf("topology read state = %s", read.State)
	}
	encodedValue, _ := json.Marshal(read.Value)
	var topology guestruntimedomain.RuntimeTopology
	if err := json.Unmarshal(encodedValue, &topology); err != nil {
		t.Fatalf("decode topology value: %v", err)
	}
	if topology.Status.ReadState != "unsupported" {
		t.Fatalf("topology status = %+v", topology.Status)
	}
}

func TestBundledTopologyPublishesDurableCapabilityWithoutClaimingConnection(t *testing.T) {
	server := newServer(t)
	command := validCommand()
	command.RequestID = "http-bundled-request-1"
	command.Spec.ProfileKind = "bundled-upstream"
	command.Spec.EndpointReference.ResourceID = "bundled-vitalserver"
	payload, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	applyRequest := httptest.NewRequest(http.MethodPost, "/v1/runtime/topology:apply", bytes.NewReader(payload))
	applyResponse := httptest.NewRecorder()
	server.ServeHTTP(applyResponse, applyRequest)
	if applyResponse.Code != http.StatusAccepted {
		t.Fatalf("apply status = %d body=%s", applyResponse.Code, applyResponse.Body.String())
	}

	capabilityRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/capabilities", nil)
	capabilityResponse := httptest.NewRecorder()
	server.ServeHTTP(capabilityResponse, capabilityRequest)
	if capabilityResponse.Code != http.StatusOK {
		t.Fatalf("capability status = %d body=%s", capabilityResponse.Code, capabilityResponse.Body.String())
	}
	var read guestruntimedomain.ReadResult
	if err := json.Unmarshal(capabilityResponse.Body.Bytes(), &read); err != nil {
		t.Fatalf("decode capability read: %v", err)
	}
	if read.State != "available" {
		t.Fatalf("capability state = %s issue=%+v", read.State, read.Issue)
	}
	encodedValue, _ := json.Marshal(read.Value)
	var capability guestruntimedomain.CapabilityDocument
	if err := json.Unmarshal(encodedValue, &capability); err != nil {
		t.Fatalf("decode capability value: %v", err)
	}
	if capability.Provider.ID != "bundled-vitalserver" || len(capability.Commands) != 1 || capability.Commands[0].Name != "upstream.recorder.deliver" {
		t.Fatalf("capability = %+v", capability)
	}

	topologyRequest := httptest.NewRequest(http.MethodGet, "/v1/runtime/topology", nil)
	topologyResponse := httptest.NewRecorder()
	server.ServeHTTP(topologyResponse, topologyRequest)
	var topologyRead guestruntimedomain.ReadResult
	if err := json.Unmarshal(topologyResponse.Body.Bytes(), &topologyRead); err != nil {
		t.Fatalf("decode topology read: %v", err)
	}
	encodedTopology, _ := json.Marshal(topologyRead.Value)
	var topology guestruntimedomain.RuntimeTopology
	if err := json.Unmarshal(encodedTopology, &topology); err != nil {
		t.Fatalf("decode topology: %v", err)
	}
	if topology.Status.ReadState != "available" || topology.Status.Connection.State != "not-checked" || topology.Status.CapabilityDocumentReference == nil {
		t.Fatalf("topology status = %+v", topology.Status)
	}
}

func TestTopologyApplyRejectsUnknownFieldsWithoutCreatingAnOperation(t *testing.T) {
	server := newServer(t)
	payload := []byte(`{"schemaVersion":"v1","requestId":"http-request-2","topologyId":"primary-topology","expectedResourceRevision":0,"spec":{},"unexpected":true}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/runtime/topology:apply", bytes.NewReader(payload))
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	var rejection guestruntimedomain.CommandRejection
	if err := json.Unmarshal(response.Body.Bytes(), &rejection); err != nil {
		t.Fatalf("decode rejection: %v", err)
	}
	if rejection.Issue.Code != "invalid-command-envelope" {
		t.Fatalf("rejection = %+v", rejection)
	}
}

type commitFailureRepository struct {
	guestruntimeapplication.GuestRuntimeTopologyStateRepository
}

func (repository commitFailureRepository) CommitRuntimeTopologyApplication(context.Context, guestruntimedomain.RuntimeTopology, *guestruntimedomain.CapabilityDocument, guestruntimedomain.Operation) error {
	return errors.New("simulated Guest state write failure")
}

func TestTopologyAdmissionAmbiguityUsesTypedPublicResponse(t *testing.T) {
	repository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(context.Background(), filepath.Join(t.TempDir(), "guest.sqlite"))
	if err != nil {
		t.Fatalf("open state database: %v", err)
	}
	t.Cleanup(func() { _ = repository.Close() })
	server := newServerWithRepository(t, commitFailureRepository{GuestRuntimeTopologyStateRepository: repository})
	payload, err := json.Marshal(validCommand())
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/runtime/topology:apply", bytes.NewReader(payload))
	response := httptest.NewRecorder()

	server.ServeHTTP(response, request)

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d body=%s", response.Code, response.Body.String())
	}
	var failure guestruntimedomain.CommandAdmissionFailure
	if err := json.Unmarshal(response.Body.Bytes(), &failure); err != nil {
		t.Fatalf("decode admission failure: %v body=%s", err, response.Body.String())
	}
	if failure.State != "failed" || failure.AdmissionState != "unknown" || failure.Issue.Code != "guest-state-store-write-outcome-unknown" {
		t.Fatalf("failure = %+v", failure)
	}
}

func TestArchiveRoutesReportAnUnavailableOwnerWithoutInventingOwnerState(t *testing.T) {
	server := guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(
		guestruntimecontrolhttpapi.GuestRuntimeControlModules{},
	)
	for _, expectation := range []struct {
		request       *http.Request
		expectedState string
	}{
		{httptest.NewRequest(http.MethodGet, "/v1/runtime/archive/export-provider", nil), "unavailable"},
		{httptest.NewRequest(http.MethodGet, "/v1/runtime/archive/credential-material", nil), "failed"},
		{httptest.NewRequest(http.MethodPost, "/v1/runtime/archive/credential-material", bytes.NewBufferString(`{}`)), "failed"},
	} {
		response := httptest.NewRecorder()
		server.ServeHTTP(response, expectation.request)
		if response.Code != http.StatusServiceUnavailable {
			t.Fatalf("archive owner unavailable status = %d body=%s", response.Code, response.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode archive owner unavailable response: %v", err)
		}
		if body["state"] != expectation.expectedState || body["credentialReference"] != nil || body["value"] != nil {
			t.Fatalf("archive owner error must preserve its explicit state without inventing owner configuration: %#v", body)
		}
	}
}
