package guestproductprocesssupervisordomain

import (
	"strings"
	"testing"
)

func TestGuestProductProcessDeploymentPlansEveryServiceInputExplicitly(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	invocations, err := PlanGuestProductProcessInvocations(configuration, validRecorderGatewayVitalServerDeliveryResolution(), nil)
	if err != nil {
		t.Fatalf("valid C37 configuration rejected: %v", err)
	}
	if len(invocations) != 3 {
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
		"--recorder-gateway-cold-path-source-endpoint=http://127.0.0.1:8090",
		"--lab-recorder-runner-endpoint=http://127.0.0.1:8091",
		"--external-upstream-observation-provider-mode=unsupported",
		"--time-adapter-kind=time-authority-outcome-profile",
		"--time-provider-mode=unsupported",
		"--telemetry-adapter-kind=telemetry-export-outcome-profile",
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
	if invocations[2].ProcessName != LabRecorderRunnerProcessName || invocations[2].ExecutablePath != "/opt/vitalserver/node/bin/node" {
		t.Fatalf("Lab recorder Runner invocation = %#v", invocations[2])
	}
	for _, expected := range []string{
		"/opt/vitalserver/lab-recorder-runner/dist/cmd/lab-recorder-runner.js",
		"--listen=127.0.0.1:8091",
		"--recorder-gateway-endpoint=http://127.0.0.1:8090",
		"--scenario-catalog=/etc/vitalserver/lab-scenario-catalog.json",
	} {
		if !contains(invocations[2].Arguments, expected) {
			t.Fatalf("Lab recorder Runner invocation omitted explicit argument %s: %#v", expected, invocations[2].Arguments)
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
	configuration.GuestRuntime.RecorderGatewayColdPathSourceEndpoint = "http://127.0.0.1:8091"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "recorderGatewayColdPathSourceEndpoint") {
		t.Fatalf("Recorder Gateway cold-path endpoint ownership error = %v", err)
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
	configuration.LabRecorderRunner.RecorderGatewayEndpoint = "http://127.0.0.1:8091"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "Lab recorder Runner recorderGatewayEndpoint") {
		t.Fatalf("Lab recorder Runner Recorder Gateway endpoint ownership error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.LabRecorderRunnerEndpoint = "http://127.0.0.1:8090"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "labRecorderRunnerEndpoint") {
		t.Fatalf("Guest Runtime Lab recorder Runner endpoint ownership error = %v", err)
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

func TestGuestProductProcessDeploymentPlansDeclaredTelemetryCollectorBeforeTelemetryConsumer(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.TelemetryPipeline = GuestTelemetryPipeline{
		Kind: "otlp-http", CollectorBaseEndpoint: "http://127.0.0.1:4318", RequestTimeoutMilliseconds: 5000,
	}
	configuration.TelemetryCollector = &GuestTelemetryCollectorDeployment{
		ExecutablePath: "/opt/vitalserver/bin/guest-telemetry-collector", ConfigurationPath: "/etc/vitalserver/guest-telemetry-collector.yaml",
		OTLPHTTPListener: GuestProductProcessListener{BindHost: "127.0.0.1", Port: 4318},
	}

	invocations, err := PlanGuestProductProcessInvocations(configuration, validRecorderGatewayVitalServerDeliveryResolution(), nil)
	if err != nil {
		t.Fatalf("valid local Collector deployment rejected: %v", err)
	}
	if len(invocations) != 4 || invocations[0].ProcessName != GuestTelemetryCollectorProcessName || invocations[0].ExecutablePath != "/opt/vitalserver/bin/guest-telemetry-collector" || !contains(invocations[0].Arguments, "--config=/etc/vitalserver/guest-telemetry-collector.yaml") {
		t.Fatalf("Collector invocation = %#v", invocations)
	}

	configuration.GuestRuntime.TelemetryPipeline.CollectorBaseEndpoint = "http://127.0.0.1:4319"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "collectorBaseEndpoint") {
		t.Fatalf("misdirected local Collector endpoint error = %v", err)
	}

	configuration = validGuestProductProcessDeploymentConfiguration()
	configuration.TelemetryCollector = &GuestTelemetryCollectorDeployment{
		ExecutablePath: "/opt/vitalserver/bin/guest-telemetry-collector", ConfigurationPath: "/etc/vitalserver/guest-telemetry-collector.yaml",
		OTLPHTTPListener: GuestProductProcessListener{BindHost: "127.0.0.1", Port: 4318},
	}
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "requires the otlp-http") {
		t.Fatalf("profile-plus-Collector error = %v", err)
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

func TestRecorderGatewayVitalServerDeliveryResolutionUsesExplicitBundledC64Endpoint(t *testing.T) {
	deployment := validGuestProductProcessDeploymentConfiguration().RecorderGateway
	deployment.ExternalVitalServerDeliveryConfigurationPath = ""
	topology := GuestProductVitalServerTopologyDeployment{
		SchemaVersion: "v1", TopologyDeploymentID: "bundled-upstream-primary-topology", TopologyKind: "bundled-vitalserver",
		VitalServerDeliveryProvider: GuestProductProviderCapabilityReference{Kind: "bundled-vitalserver", ID: "bundled-upstream-primary", CapabilityRevision: 1},
		PublicBrowserExposure:       "not-exposed",
		BundledUpstreamImageSetDeployment: &BundledUpstreamImageSetDeployment{
			ImageSetManagerConfigurationReference:                 GuestProductResourceReference{ResourceType: "guest-bundled-upstream-image-set-manager-configuration", ResourceID: "bundled-upstream-image-set-manager"},
			VitalServerPacketDeliveryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18300},
			VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 5000,
			VitalServerObservationEndpoint:                        VitalServerHTTPObservationEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18300, Path: "/healthz", AcceptedStatusCodes: []int{200}},
			VitalServerArchiveProvider:                            GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "bundled-upstream-primary-library", CapabilityRevision: 1},
			VitalServerIndexedLibraryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18300},
			VitalServerArchiveCredentialReference:                 GuestProductSecretReference{Kind: "vitalserver-library-credential", ID: "bundled-upstream-primary-library"},
			VitalServerArchiveRequestTimeoutMilliseconds:          10000,
		},
	}
	resolution, err := ResolveRecorderGatewayVitalServerDelivery(deployment, topology, nil)
	if err != nil || resolution.RecorderGatewayVitalServerDeliveryURL() != "http://127.0.0.1:18300" || resolution.VitalServerDeliveryAcknowledgementTimeoutMilliseconds != 5000 {
		t.Fatalf("resolution=%+v error=%v", resolution, err)
	}
}

func TestGuestProductProcessDeploymentPlansVitalServerIndexedLibraryWithoutOutcomeProfileFallback(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.ArchiveExportProvider = ArchiveExportProvider{
		GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "external-vitalserver-primary-library", CapabilityRevision: 1},
		CredentialMaterialPath:                  "/run/vitalserver/secrets/external-vitalserver-primary-library.json",
		VitalServerConfiguration:                &VitalServerArchiveProviderConfiguration{Kind: "external-vitalserver-delivery-configuration", ConfigurationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json"},
	}
	external := validExternalVitalServerDeliveryConfiguration()
	invocations, err := PlanGuestProductProcessInvocations(configuration, validRecorderGatewayVitalServerDeliveryResolution(), &external)
	if err != nil {
		t.Fatalf("valid external indexed-library provider rejected: %v", err)
	}
	runtimeArguments := invocations[0].Arguments
	if contains(runtimeArguments, "--archive-provider-mode=succeed") || !contains(runtimeArguments, "--archive-provider-vitalserver-configuration-kind=external-vitalserver-delivery-configuration") || !contains(runtimeArguments, "--archive-provider-vitalserver-configuration=/etc/vitalserver/external-vitalserver-delivery-configuration.json") || !contains(runtimeArguments, "--archive-provider-credential-material-path=/run/vitalserver/secrets/external-vitalserver-primary-library.json") {
		t.Fatalf("indexed-library invocation lost explicit configuration or retained profile fallback: %#v", runtimeArguments)
	}

	external.VitalServerArchiveProvider.ID = "other-library"
	if _, err := PlanGuestProductProcessInvocations(configuration, validRecorderGatewayVitalServerDeliveryResolution(), &external); err == nil || !strings.Contains(err.Error(), "do not describe the same external capability") {
		t.Fatalf("mismatched C37/C46 archive provider error = %v", err)
	}
}

func TestGuestProductProcessDeploymentPlansBundledVitalServerIndexedLibraryFromExplicitC44WithoutExternalConfiguration(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	configuration.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath = ""
	configuration.GuestRuntime.ArchiveExportProvider = ArchiveExportProvider{
		GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "bundled-upstream-primary-library", CapabilityRevision: 1},
		VitalServerConfiguration:                &VitalServerArchiveProviderConfiguration{Kind: "bundled-vitalserver-topology-deployment", ConfigurationPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json"},
		CredentialMaterialPath:                  "/run/vitalserver/secrets/bundled-upstream-primary-library.json",
	}
	resolution := RecorderGatewayVitalServerDeliveryResolution{
		VitalServerPacketDeliveryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "http", Host: "127.0.0.1", Port: 18300},
		VitalServerDeliveryProvider:                           GuestProductProviderCapabilityReference{Kind: "bundled-vitalserver", ID: "bundled-upstream-primary", CapabilityRevision: 1},
		VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 1000,
	}
	invocations, err := PlanGuestProductProcessInvocations(configuration, resolution, nil)
	if err != nil {
		t.Fatalf("valid bundled indexed-library provider rejected: %v", err)
	}
	runtimeArguments := invocations[0].Arguments
	if !contains(runtimeArguments, "--archive-provider-vitalserver-configuration-kind=bundled-vitalserver-topology-deployment") || !contains(runtimeArguments, "--archive-provider-vitalserver-configuration=/etc/vitalserver/guest-product-vitalserver-topology-deployment.json") || contains(runtimeArguments, "--archive-provider-external-vitalserver-delivery-configuration=/etc/vitalserver/external-vitalserver-delivery-configuration.json") {
		t.Fatalf("bundled indexed-library invocation did not preserve the C44 boundary: %#v", runtimeArguments)
	}
}

func validGuestProductProcessDeploymentConfiguration() GuestProductProcessDeploymentConfiguration {
	return GuestProductProcessDeploymentConfiguration{
		SchemaVersion: GuestProductProcessDeploymentConfigurationSchemaVersion, DeploymentID: "vitalserver-guest-product", RequiredProcessExitPolicy: "terminate-guest-product",
		GuestRuntime: GuestRuntimeProcessDeployment{
			ExecutablePath: "/opt/vitalserver/bin/guest-runtime", Listener: GuestProductProcessListener{BindHost: "0.0.0.0", Port: 18443}, ControlVirtioSocketListener: GuestRuntimeControlVirtioSocketListener{Port: 18443}, PublicServiceVirtioSocketBridges: []GuestPublicServiceVirtioSocketBridge{
				{RouteID: "recorder-gateway", GuestProductProcessName: RecorderGatewayProcessName, VirtioSocketPort: 18090, TargetHost: "127.0.0.1", TargetPort: 8090},
			}, StateDatabasePath: "/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite", ServiceVersion: "0.1.0-dev", InstanceID: "guest-runtime-primary",
			ArchiveExportProvider:                 ArchiveExportProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "archive-export-outcome-profile", ID: "bundled-archive", CapabilityRevision: 1}, OutcomeMode: "succeed"},
			RecorderGatewayColdPathSourceEndpoint: "http://127.0.0.1:8090",
			LabRecorderRunnerEndpoint:             "http://127.0.0.1:8091",
			ExternalUpstreamObservationProvider:   ExternalUpstreamObservationProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "external-capability-profile", ID: "external-upstream", CapabilityRevision: 1}, OutcomeMode: "unsupported"},
			OutboundRelayObservationProvider:      OutboundRelayObservationProvider{GuestProductProviderCapabilityReference: GuestProductProviderCapabilityReference{Kind: "outbound-relay-profile", ID: "outbound-relay", CapabilityRevision: 1}, OutcomeMode: "unsupported"},
			TimeAuthority:                         GuestTimeAuthority{GuestNodeID: "guest-primary", TimeAuthorityID: "guest-time-authority", Kind: "time-authority-outcome-profile", ProbeOutcomeMode: "unsupported"},
			TelemetryPipeline:                     GuestTelemetryPipeline{Kind: "telemetry-export-outcome-profile", CollectorProbeOutcomeMode: "unsupported", ExportOutcomeMode: "unavailable"},
		},
		RecorderGateway: RecorderGatewayProcessDeployment{
			NodeExecutablePath: "/opt/vitalserver/node/bin/node", ProgramPath: "/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js", Listener: GuestProductProcessListener{BindHost: "0.0.0.0", Port: 8090}, DurableIngressStateDirectory: "/var/lib/vitalserver/recorder-gateway", VitalServerTopologyDeploymentPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json", ExternalVitalServerDeliveryConfigurationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json",
			DeliveryReplayAdmissionPolicy: RecorderGatewayDeliveryReplayAdmissionPolicy{MaximumPendingItems: 1024, MaximumPendingBytes: 67108864}, ColdPathCapturePolicy: RecorderGatewayColdPathCapturePolicy{MaximumRetainedPackets: 1024, MaximumRetainedPayloadBytes: 67108864}, ReplayPolicy: RecorderGatewayReplayPolicy{IntervalMilliseconds: 100, MaximumAttempts: 3, RetryDelayMilliseconds: 100, LeaseDurationMilliseconds: 1000},
		},
		LabRecorderRunner: LabRecorderRunnerProcessDeployment{
			NodeExecutablePath: "/opt/vitalserver/node/bin/node", ProgramPath: "/opt/vitalserver/lab-recorder-runner/dist/cmd/lab-recorder-runner.js", Listener: GuestProductProcessListener{BindHost: "127.0.0.1", Port: 8091}, RecorderGatewayEndpoint: "http://127.0.0.1:8090", GuestRuntimeObservationCatalogEndpoint: "http://127.0.0.1:18443", ScenarioCatalogPath: "/etc/vitalserver/lab-scenario-catalog.json",
		},
	}
}

func TestGuestProductProcessDeploymentAcceptsExplicitChronySourceAndRejectsShellLikeHost(t *testing.T) {
	configuration := validGuestProductProcessDeploymentConfiguration()
	configuration.GuestRuntime.TimeAuthority = GuestTimeAuthority{
		GuestNodeID: "guest-primary", TimeAuthorityID: "guest-time-authority", Kind: "chrony-tracking",
		ChronyExecutablePath: "/usr/bin/chronyc", NTPServerHost: "ntp.example.test", NTPServerPort: 123,
		RequestTimeoutMilliseconds: 5000,
	}
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err != nil {
		t.Fatalf("explicit Chrony source rejected: %v", err)
	}
	configuration.GuestRuntime.TimeAuthority.NTPServerHost = "ntp.example.test;echo-unexpected"
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "timeAuthority") {
		t.Fatalf("unsafe Chrony host was accepted: %v", err)
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
		VitalServerObservationEndpoint:                        VitalServerHTTPObservationEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443, Path: "/healthz", AcceptedStatusCodes: []int{200}},
		VitalServerArchiveProvider:                            GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "external-vitalserver-primary-library", CapabilityRevision: 1},
		VitalServerIndexedLibraryEndpoint:                     VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerArchiveCredentialReference:                 GuestProductSecretReference{Kind: "vitalserver-library-credential", ID: "external-vitalserver-primary-library"},
		VitalServerArchiveRequestTimeoutMilliseconds:          10000,
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
