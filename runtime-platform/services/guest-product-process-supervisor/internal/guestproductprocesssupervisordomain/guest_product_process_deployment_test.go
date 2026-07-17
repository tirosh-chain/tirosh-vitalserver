package guestproductprocesssupervisordomain

import (
	"strings"
	"testing"
)

func TestGuestProductProcessDeploymentPlansEveryServiceInputExplicitly(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	invocations, err := PlanGuestProductProcessInvocations(configuration, validRecorderGatewayVitalServerDeliveryResolution())
	if err != nil {
		t.Fatalf("valid C37 configuration rejected: %v", err)
	}
	if len(invocations) != 2 {
		t.Fatalf("planned invocation count = %d", len(invocations))
	}
	if invocations[0].ProcessName != "guest-runtime" || invocations[0].ExecutablePath != "/opt/vitalserver/bin/guest-runtime" {
		t.Fatalf("Guest Runtime invocation = %#v", invocations[0])
	}
	requiredRuntimeArguments := []string{
		"--listen=0.0.0.0:18443",
		"--control-virtio-socket-port=18443",
		"--guest-public-service-virtio-socket-bridge=recorder-gateway,18090,127.0.0.1:8090",
		"--state-db=/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite",
		"--archive-provider-mode=succeed",
		"--external-upstream-observation-provider-mode=unsupported",
		"--time-provider-mode=unsupported",
		"--telemetry-pipeline-mode=unsupported",
	}
	for _, expected := range requiredRuntimeArguments {
		if !contains(invocations[0].Arguments, expected) {
			t.Fatalf("Guest Runtime invocation omitted explicit argument %s: %#v", expected, invocations[0].Arguments)
		}
	}
	if invocations[1].ProcessName != "recorder-gateway" || invocations[1].ExecutablePath != "/opt/vitalserver/node/bin/node" {
		t.Fatalf("Recorder Gateway invocation = %#v", invocations[1])
	}
	requiredGatewayArguments := []string{
		"/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js",
		"--listen=0.0.0.0:8090",
		"--state-dir=/var/lib/vitalserver/recorder-gateway",
		"--vitalserver-delivery-url=https://external-vitalserver.example.test:8443",
		"--vitalserver-delivery-acknowledgement-timeout-ms=1000",
		"--delivery-replay-max-items=1024",
		"--delivery-replay-max-bytes=67108864",
		"--cold-path-capture-max-retained-packets=1024",
		"--cold-path-capture-max-retained-payload-bytes=67108864",
		"--replay-lease-duration-ms=1000",
	}
	for _, expected := range requiredGatewayArguments {
		if !contains(invocations[1].Arguments, expected) {
			t.Fatalf("Recorder Gateway invocation omitted explicit argument %s: %#v", expected, invocations[1].Arguments)
		}
	}
}

func TestGuestProductProcessDeploymentRejectsImplicitProcessPolicyAndOverlappingStores(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	configuration.RequiredProcessExitPolicy = ""
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "requiredProcessExitPolicy") {
		t.Fatalf("implicit exit policy error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.RecorderGateway.DurableIngressStateDirectory = configuration.GuestRuntime.StateDatabasePath
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "separate owned stores") {
		t.Fatalf("shared owned store error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.RecorderGateway.Listener.Port = configuration.GuestRuntime.Listener.Port
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "same Guest socket") {
		t.Fatalf("shared listener error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.PublicServiceVirtioSocketBridges = append(configuration.GuestRuntime.PublicServiceVirtioSocketBridges, GuestPublicServiceVirtioSocketBridge{RouteID: "duplicate-recorder-gateway", GuestProductProcessName: RecorderGatewayProcessName, VirtioSocketPort: 18090, TargetHost: "127.0.0.1", TargetPort: 8090})
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "virtioSocketPort must be unique") {
		t.Fatalf("duplicate public virtio-socket port error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.PublicServiceVirtioSocketBridges[0].TargetHost = "192.168.64.2"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "publicServiceVirtioSocketBridge is invalid") {
		t.Fatalf("Guest IP public route error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.PublicServiceVirtioSocketBridges[0].GuestProductProcessName = "vitalserver-browser"
	configuration.GuestRuntime.PublicServiceVirtioSocketBridges[0].TargetPort = 8088
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "must name an invoked Guest Product process") {
		t.Fatalf("unplanned public service process error = %v", err)
	}
}

func TestRecorderGatewayVitalServerDeliveryResolutionRequiresMatchingExternalConfiguration(t *testing.T) {
	deployment := validGuestProductProcessDeploymentConfiguration().RecorderGateway
	topology := validExternalVitalServerTopologyDeployment()
	externalConfiguration := validExternalVitalServerDeliveryConfiguration()

	resolution, err := ResolveRecorderGatewayVitalServerDelivery(deployment, topology, &externalConfiguration)
	if err != nil {
		t.Fatalf("matching C44 and C46 were rejected: %v", err)
	}
	if got := resolution.RecorderGatewayVitalServerDeliveryURL(); got != "https://external-vitalserver.example.test:8443" {
		t.Fatalf("resolved VitalServer delivery URL = %s", got)
	}

	deployment.ExternalVitalServerDeliveryConfigurationPath = ""
	if _, err := ResolveRecorderGatewayVitalServerDelivery(deployment, topology, &externalConfiguration); err == nil || !strings.Contains(err.Error(), "requires C46") {
		t.Fatalf("missing C46 path error = %v", err)
	}

	deployment = validGuestProductProcessDeploymentConfiguration().RecorderGateway
	externalConfiguration.ConfigurationID = "other-external-vitalserver-delivery"
	if _, err := ResolveRecorderGatewayVitalServerDelivery(deployment, topology, &externalConfiguration); err == nil || !strings.Contains(err.Error(), "do not describe the same") {
		t.Fatalf("mismatched C44/C46 error = %v", err)
	}

	externalConfiguration = validExternalVitalServerDeliveryConfiguration()
	externalConfiguration.VitalServerPacketDeliveryEndpoint.Host = "127.0.0.1"
	if _, err := ResolveRecorderGatewayVitalServerDelivery(deployment, topology, &externalConfiguration); err == nil || !strings.Contains(err.Error(), "must not use a Guest-loopback") {
		t.Fatalf("Guest-loopback external endpoint error = %v", err)
	}
}

func validGuestProductProcessDeploymentConfiguration() GuestProductProcessDeploymentConfiguration {
	return GuestProductProcessDeploymentConfiguration{
		SchemaVersion: GuestProductProcessDeploymentConfigurationSchemaVersion, DeploymentID: "vitalserver-guest-product", RequiredProcessExitPolicy: "terminate-guest-product",
		GuestRuntime: GuestRuntimeProcessDeployment{
			ExecutablePath: "/opt/vitalserver/bin/guest-runtime", Listener: GuestProductProcessListener{BindHost: "0.0.0.0", Port: 18443}, ControlVirtioSocketListener: GuestRuntimeControlVirtioSocketListener{Port: 18443}, PublicServiceVirtioSocketBridges: []GuestPublicServiceVirtioSocketBridge{
				{RouteID: "recorder-gateway", GuestProductProcessName: RecorderGatewayProcessName, VirtioSocketPort: 18090, TargetHost: "127.0.0.1", TargetPort: 8090},
			}, StateDatabasePath: "/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite", ServiceVersion: "0.1.0-dev", InstanceID: "guest-runtime-primary",
			ArchiveExportProvider:               ArchiveExportProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "lab-simulation-archive", ID: "bundled-archive", CapabilityRevision: 1}, OutcomeMode: "succeed"},
			ExternalUpstreamObservationProvider: ExternalUpstreamObservationProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "external-capability-profile", ID: "external-upstream", CapabilityRevision: 1}, OutcomeMode: "unsupported"},
			OutboundRelayObservationProvider:    OutboundRelayObservationProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "outbound-relay-profile", ID: "outbound-relay", CapabilityRevision: 1}, OutcomeMode: "unsupported"},
			TimeAuthority:                       GuestTimeAuthority{GuestNodeID: "guest-primary", TimeAuthorityID: "guest-time-authority", ProbeOutcomeMode: "unsupported"},
			TelemetryPipeline:                   GuestTelemetryPipeline{CollectorProbeOutcomeMode: "unsupported", ExportOutcomeMode: "unavailable"},
		},
		RecorderGateway: RecorderGatewayProcessDeployment{
			NodeExecutablePath: "/opt/vitalserver/node/bin/node", ProgramPath: "/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js", Listener: GuestProductProcessListener{BindHost: "0.0.0.0", Port: 8090}, DurableIngressStateDirectory: "/var/lib/vitalserver/recorder-gateway", VitalServerTopologyDeploymentPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json", ExternalVitalServerDeliveryConfigurationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json",
			DeliveryReplayAdmissionPolicy: RecorderGatewayDeliveryReplayAdmissionPolicy{MaximumPendingItems: 1024, MaximumPendingBytes: 67108864}, ColdPathCapturePolicy: RecorderGatewayColdPathCapturePolicy{MaximumRetainedPackets: 1024, MaximumRetainedPayloadBytes: 67108864}, ReplayPolicy: RecorderGatewayReplayPolicy{IntervalMilliseconds: 100, MaximumAttempts: 3, RetryDelayMilliseconds: 100, LeaseDurationMilliseconds: 1000},
		},
	}
}

func validRecorderGatewayVitalServerDeliveryResolution() RecorderGatewayVitalServerDeliveryResolution {
	return RecorderGatewayVitalServerDeliveryResolution{
		VitalServerPacketDeliveryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerDeliveryProvider:                           GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 1000,
	}
}

func validExternalVitalServerTopologyDeployment() GuestProductVitalServerTopologyDeployment {
	return GuestProductVitalServerTopologyDeployment{
		SchemaVersion: "v1", TopologyDeploymentID: "external-vitalserver-primary-topology", TopologyKind: "external-vitalserver",
		VitalServerDeliveryProvider: GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		PublicBrowserExposure:       "not-exposed",
		ExternalVitalServerDeploymentConfiguration: &ExternalVitalServerDeploymentConfiguration{
			ExternalUpstreamIntegrationReference:              GuestProductResourceReference{ResourceType: "external-upstream-integration", ResourceID: "external-vitalserver-primary"},
			ExternalVitalServerDeliveryConfigurationReference: GuestProductResourceReference{ResourceType: "external-vitalserver-delivery-configuration", ResourceID: "external-vitalserver-primary-delivery"},
		},
	}
}

func validExternalVitalServerDeliveryConfiguration() ExternalVitalServerDeliveryConfiguration {
	return ExternalVitalServerDeliveryConfiguration{
		SchemaVersion: "v1", ConfigurationID: "external-vitalserver-primary-delivery",
		ExternalUpstreamIntegrationReference:                  GuestProductResourceReference{ResourceType: "external-upstream-integration", ResourceID: "external-vitalserver-primary"},
		VitalServerDeliveryProvider:                           GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		VitalServerPacketDeliveryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 1000,
	}
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
