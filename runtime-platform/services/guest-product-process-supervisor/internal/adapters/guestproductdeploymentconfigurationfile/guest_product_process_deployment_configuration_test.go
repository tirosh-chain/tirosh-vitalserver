package guestproductdeploymentconfigurationfile

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

func TestLoadGuestProductProcessDeploymentConfigurationDoesNotCreateMissingInput(t *testing.T) {
	_, err := LoadGuestProductProcessDeploymentConfiguration(filepath.Join(t.TempDir(), "missing.json"))
	var unavailable GuestProductProcessDeploymentConfigurationUnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("missing configuration error = %T %v", err, err)
	}
}

func TestLoadVitalServerTopologyAndExternalDeliveryConfigurationKeepUnavailableSeparate(t *testing.T) {
	missingPath := filepath.Join(t.TempDir(), "missing.json")
	if _, err := LoadGuestProductVitalServerTopologyDeployment(missingPath); err == nil {
		t.Fatal("missing C44 topology was accepted")
	} else {
		var unavailable GuestProductVitalServerTopologyDeploymentUnavailableError
		if !errors.As(err, &unavailable) {
			t.Fatalf("missing C44 error = %T %v", err, err)
		}
	}
	if _, err := LoadExternalVitalServerDeliveryConfiguration(missingPath); err == nil {
		t.Fatal("missing C46 configuration was accepted")
	} else {
		var unavailable ExternalVitalServerDeliveryConfigurationUnavailableError
		if !errors.As(err, &unavailable) {
			t.Fatalf("missing C46 error = %T %v", err, err)
		}
	}
}

func TestLoadVitalServerTopologyAndExternalDeliveryConfigurationRejectInvalidDocuments(t *testing.T) {
	configurationPath := filepath.Join(t.TempDir(), "configuration.json")
	if err := os.WriteFile(configurationPath, []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadGuestProductVitalServerTopologyDeployment(configurationPath); err == nil {
		t.Fatal("invalid C44 topology was accepted")
	} else {
		var invalid GuestProductVitalServerTopologyDeploymentInvalidError
		if !errors.As(err, &invalid) {
			t.Fatalf("invalid C44 error = %T %v", err, err)
		}
	}

	validExternalConfiguration := guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{
		SchemaVersion: "v1", ConfigurationID: "external-vitalserver-primary-delivery",
		ExternalUpstreamIntegrationReference:                  guestproductprocesssupervisordomain.GuestProductResourceReference{ResourceType: "external-upstream-integration", ResourceID: "external-vitalserver-primary"},
		VitalServerDeliveryProvider:                           guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		VitalServerPacketDeliveryEndpoint:                     guestproductprocesssupervisordomain.VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "vitalserver.example.test", Port: 443},
		VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 1000,
		VitalServerObservationEndpoint:                        guestproductprocesssupervisordomain.VitalServerHTTPObservationEndpoint{Scheme: "https", Host: "vitalserver.example.test", Port: 443, Path: "/healthz", AcceptedStatusCodes: []int{200}},
		VitalServerArchiveProvider:                            guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "external-vitalserver-library", CapabilityRevision: 1},
		VitalServerIndexedLibraryEndpoint:                     guestproductprocesssupervisordomain.VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerArchiveCredentialReference:                 guestproductprocesssupervisordomain.GuestProductSecretReference{Kind: "vitalserver-library-credential", ID: "external-vitalserver-library"},
		VitalServerArchiveRequestTimeoutMilliseconds:          10000,
	}
	encoded, err := json.Marshal(validExternalConfiguration)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configurationPath, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadExternalVitalServerDeliveryConfiguration(configurationPath); err != nil {
		t.Fatalf("valid C46 configuration rejected: %v", err)
	}
}

func TestLoadGuestProductProcessDeploymentConfigurationRejectsUnknownFields(t *testing.T) {
	configurationPath := filepath.Join(t.TempDir(), "guest-product.json")
	contents := `{"schemaVersion":"v1","deploymentId":"guest-product","requiredProcessExitPolicy":"terminate-guest-product","guestRuntime":{"executablePath":"/opt/vitalserver/bin/guest-runtime","listener":{"bindHost":"0.0.0.0","port":18443},"controlVirtioSocketListener":{"port":18443},"publicServiceVirtioSocketBridges":[{"routeId":"recorder-gateway","guestProductProcessName":"recorder-gateway","virtioSocketPort":18090,"targetHost":"127.0.0.1","targetPort":8090}],"stateDatabasePath":"/var/lib/vitalserver/runtime.sqlite","serviceVersion":"0.1.0-dev","instanceId":"guest-runtime","archiveExportProvider":{"kind":"archive-export-outcome-profile","id":"archive","capabilityRevision":1,"outcomeMode":"succeed"},"recorderGatewayColdPathSourceEndpoint":"http://127.0.0.1:8090","externalUpstreamObservationProvider":{"kind":"external","id":"external","capabilityRevision":1,"outcomeMode":"unsupported"},"outboundRelayObservationProvider":{"kind":"relay","id":"relay","capabilityRevision":1,"outcomeMode":"unsupported"},"timeAuthority":{"guestNodeId":"guest","timeAuthorityId":"time","probeOutcomeMode":"unsupported"},"telemetryPipeline":{"collectorProbeOutcomeMode":"unsupported","exportOutcomeMode":"unavailable"}},"recorderGateway":{"nodeExecutablePath":"/opt/vitalserver/node/bin/node","programPath":"/opt/vitalserver/gateway.js","listener":{"bindHost":"0.0.0.0","port":8090},"durableIngressStateDirectory":"/var/lib/vitalserver/gateway","vitalServerTopologyDeploymentPath":"/etc/vitalserver/guest-product-vitalserver-topology-deployment.json","externalVitalServerDeliveryConfigurationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json","deliveryReplayAdmissionPolicy":{"maximumPendingItems":1,"maximumPendingBytes":1},"coldPathCapturePolicy":{"maximumRetainedPackets":1,"maximumRetainedPayloadBytes":1},"replayPolicy":{"intervalMilliseconds":1,"maximumAttempts":1,"retryDelayMilliseconds":1,"leaseDurationMilliseconds":1},"unexpected":true}}`
	if err := os.WriteFile(configurationPath, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := LoadGuestProductProcessDeploymentConfiguration(configurationPath)
	var invalid GuestProductProcessDeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("unknown/missing field error = %T %v", err, err)
	}
}
