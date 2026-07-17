package guestruntimecontrolhttpapplication

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
}

func TestOpenGuestRuntimeControlHTTPApplicationRejectsMissingSelectedOutcomeMode(t *testing.T) {
	deployment := validGuestRuntimeControlHTTPApplicationDeployment(t)
	deployment.GuestTelemetryExportOutcomeMode = ""

	_, err := OpenGuestRuntimeControlHTTPApplication(context.Background(), deployment)
	if err == nil || !strings.Contains(err.Error(), "selected provider outcome modes are required") {
		t.Fatalf("missing selected outcome mode error = %v", err)
	}
}

func validGuestRuntimeControlHTTPApplicationDeployment(t *testing.T) GuestRuntimeControlHTTPApplicationDeployment {
	t.Helper()
	return GuestRuntimeControlHTTPApplicationDeployment{
		GuestRuntimeStateDatabasePath:                  filepath.Join(t.TempDir(), "guest-runtime.sqlite"),
		GuestRuntimeServiceVersion:                     "acceptance",
		GuestRuntimeInstanceID:                         "guest-runtime-acceptance",
		ArchiveExportProviderReference:                 guestruntimedomain.ArchiveProviderReference{Kind: "lab-simulation-archive", ID: "bundled-archive", CapabilityRevision: 1},
		ArchiveExportProviderOutcomeMode:               "succeed",
		ExternalUpstreamObservationProviderReference:   guestruntimedomain.IntegrationProviderReference{Kind: "external-capability-profile", ID: "external-upstream", CapabilityRevision: 1},
		ExternalUpstreamObservationProviderOutcomeMode: "unsupported",
		OutboundRelayObservationProviderReference:      guestruntimedomain.IntegrationProviderReference{Kind: "outbound-relay-profile", ID: "outbound-relay", CapabilityRevision: 1},
		OutboundRelayObservationProviderOutcomeMode:    "unsupported",
		GuestRuntimeNode:                               guestruntimedomain.NodeReference{Kind: "guest", ID: "guest-runtime-acceptance"},
		GuestTimeAuthorityID:                           "guest-time-authority",
		GuestTimeAuthorityProbeOutcomeMode:             "unsupported",
		GuestTelemetryCollectorProbeOutcomeMode:        "unsupported",
		GuestTelemetryExportOutcomeMode:                "unavailable",
	}
}
