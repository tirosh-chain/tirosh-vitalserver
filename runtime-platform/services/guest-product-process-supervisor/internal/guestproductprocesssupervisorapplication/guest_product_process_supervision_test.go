package guestproductprocesssupervisorapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

func TestRunGuestProductProcessDeploymentTerminatesOtherRequiredProcessAfterObservedExit(t *testing.T) {
	runtime := newFakeGuestProductProcessLifecycleHandle()
	gateway := newFakeGuestProductProcessLifecycleHandle()
	runner := newFakeGuestProductProcessLifecycleHandle()
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime, "recorder-gateway": gateway, "lab-recorder-runner": runner}, nil)
	finished := make(chan error, 1)
	go func() {
		finished <- RunGuestProductProcessDeployment(context.Background(), validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	}()
	waitForStartedGuestProductProcess(t, launcher, "guest-runtime")
	waitForStartedGuestProductProcess(t, launcher, "recorder-gateway")
	waitForStartedGuestProductProcess(t, launcher, "lab-recorder-runner")
	gateway.exits <- errors.New("upstream process terminated")
	err := <-finished
	var terminated RequiredGuestProductProcessExitedError
	if !errors.As(err, &terminated) || terminated.ProcessName != "recorder-gateway" {
		t.Fatalf("termination error = %T %v", err, err)
	}
	if runtime.terminationCount != 1 || gateway.terminationCount != 0 || runner.terminationCount != 1 {
		t.Fatalf("termination counts runtime=%d gateway=%d runner=%d", runtime.terminationCount, gateway.terminationCount, runner.terminationCount)
	}
}

func TestRunGuestProductProcessDeploymentTerminatesStartedProcessWhenLaterStartFails(t *testing.T) {
	runtime := newFakeGuestProductProcessLifecycleHandle()
	gateway := newFakeGuestProductProcessLifecycleHandle()
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime, "recorder-gateway": gateway}, map[string]error{"lab-recorder-runner": errors.New("node executable missing")})
	err := RunGuestProductProcessDeployment(context.Background(), validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	var startFailure GuestProductProcessStartError
	if !errors.As(err, &startFailure) || startFailure.ProcessName != "lab-recorder-runner" {
		t.Fatalf("start error = %T %v", err, err)
	}
	if runtime.terminationCount != 1 || gateway.terminationCount != 1 {
		t.Fatalf("Guest Runtime and Recorder Gateway were not terminated after Runner startup failure: runtime=%d gateway=%d", runtime.terminationCount, gateway.terminationCount)
	}
}

func TestRunGuestProductProcessDeploymentTreatsContextCancellationAsExplicitShutdown(t *testing.T) {
	runtime := newFakeGuestProductProcessLifecycleHandle()
	gateway := newFakeGuestProductProcessLifecycleHandle()
	runner := newFakeGuestProductProcessLifecycleHandle()
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime, "recorder-gateway": gateway, "lab-recorder-runner": runner}, nil)
	context, cancel := context.WithCancel(context.Background())
	finished := make(chan error, 1)
	go func() {
		finished <- RunGuestProductProcessDeployment(context, validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	}()
	waitForStartedGuestProductProcess(t, launcher, "guest-runtime")
	waitForStartedGuestProductProcess(t, launcher, "recorder-gateway")
	waitForStartedGuestProductProcess(t, launcher, "lab-recorder-runner")
	cancel()
	if err := <-finished; err != nil {
		t.Fatalf("explicit supervisor shutdown error = %v", err)
	}
	if runtime.terminationCount != 1 || gateway.terminationCount != 1 || runner.terminationCount != 1 {
		t.Fatalf("shutdown termination counts runtime=%d gateway=%d runner=%d", runtime.terminationCount, gateway.terminationCount, runner.terminationCount)
	}
}

type fakeGuestProductProcessLauncher struct {
	processes   map[string]*fakeGuestProductProcessLifecycleHandle
	startErrors map[string]error
	started     chan string
}

func newFakeGuestProductProcessLauncher(processes map[string]*fakeGuestProductProcessLifecycleHandle, startErrors map[string]error) *fakeGuestProductProcessLauncher {
	return &fakeGuestProductProcessLauncher{processes: processes, startErrors: startErrors, started: make(chan string, 3)}
}

func (launcher *fakeGuestProductProcessLauncher) StartGuestProductProcess(invocation guestproductprocesssupervisordomain.GuestProductProcessInvocation) (GuestProductProcessLifecycleHandle, error) {
	launcher.started <- invocation.ProcessName
	if err := launcher.startErrors[invocation.ProcessName]; err != nil {
		return nil, err
	}
	return launcher.processes[invocation.ProcessName], nil
}

type fakeGuestProductProcessLifecycleHandle struct {
	exits            chan error
	terminationCount int
}

func newFakeGuestProductProcessLifecycleHandle() *fakeGuestProductProcessLifecycleHandle {
	return &fakeGuestProductProcessLifecycleHandle{exits: make(chan error, 1)}
}

func (process *fakeGuestProductProcessLifecycleHandle) WaitForGuestProductProcessExit() <-chan error {
	return process.exits
}
func (process *fakeGuestProductProcessLifecycleHandle) TerminateGuestProductProcess() error {
	process.terminationCount++
	select {
	case process.exits <- nil:
	default:
	}
	return nil
}

func waitForStartedGuestProductProcess(t *testing.T, launcher *fakeGuestProductProcessLauncher, name string) {
	t.Helper()
	select {
	case started := <-launcher.started:
		if started != name {
			t.Fatalf("required process start order = %s, expected %s", started, name)
		}
	case <-time.After(time.Second):
		t.Fatalf("required process %s did not start", name)
	}
}

func validDeploymentConfiguration() guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration {
	return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{
		SchemaVersion:             guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfigurationSchemaVersion,
		DeploymentID:              "guest-product",
		RequiredProcessExitPolicy: "terminate-guest-product",
		GuestRuntime: guestproductprocesssupervisordomain.GuestRuntimeProcessDeployment{
			ExecutablePath:              "/opt/vitalserver/bin/guest-runtime",
			Listener:                    guestproductprocesssupervisordomain.GuestProductProcessListener{BindHost: "0.0.0.0", Port: 18443},
			ControlVirtioSocketListener: guestproductprocesssupervisordomain.GuestRuntimeControlVirtioSocketListener{Port: 18443},
			PublicServiceVirtioSocketBridges: []guestproductprocesssupervisordomain.GuestPublicServiceVirtioSocketBridge{
				{RouteID: "recorder-gateway", GuestProductProcessName: guestproductprocesssupervisordomain.RecorderGatewayProcessName, VirtioSocketPort: 18090, TargetHost: "127.0.0.1", TargetPort: 8090},
			},
			StateDatabasePath:                               "/var/lib/vitalserver/guest-runtime/runtime.sqlite",
			RecorderCatalogDatabaseURLMaterialPath:          "/var/lib/vitalserver/private/recorder-catalog-database-url",
			RecorderCatalogMigrationReceiptPath:             "/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json",
			RecorderCatalogAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-admission-token",
			RecorderObservationMaxReportAgeSeconds:          300,
			ArchiveSourceAdmissionBearerTokenMaterialPath:   "/var/lib/vitalserver/private/archive-source-admission-token",
			ArchiveArtifactObjectRootDirectory:              "/var/lib/vitalserver/archive-artifacts",
			ArchiveSourceMaximumBytes:                       67108864,
			LabReplaySourceObjectRootDirectory:              "/var/lib/vitalserver/lab-replay-sources",
			LabReplaySourceMaximumBytes:                     67108864,
			LabReplaySpoolRootDirectory:                     "/var/lib/vitalserver/lab-replay-spools",
			LabReplayStringTrackPolicy:                      "skip",
			LabReplayGapPolicy:                              "fail-frame",
			LabReplayFrameBatchSize:                         1,
			RecorderAttributionPolicyKind:                   "recorder-assignment-owner",
			ServiceVersion:                                  "0.1.0-dev",
			InstanceID:                                      "guest-runtime",
			ArchiveExportProvider: guestproductprocesssupervisordomain.ArchiveExportProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "archive-export-outcome-profile", ID: "archive", CapabilityRevision: 1},
				OutcomeMode:                             "succeed",
			},
			RecorderGatewayColdPathSourceEndpoint: "http://127.0.0.1:8090",
			LabRecorderRunnerEndpoint:             "http://127.0.0.1:8091",
			ExternalUpstreamObservationProvider: guestproductprocesssupervisordomain.ExternalUpstreamObservationProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "external-capability-profile", ID: "external", CapabilityRevision: 1},
				OutcomeMode:                             "unsupported",
			},
			OutboundRelayObservationProvider: guestproductprocesssupervisordomain.OutboundRelayObservationProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "relay", ID: "relay", CapabilityRevision: 1},
				OutcomeMode:                             "unsupported",
			},
			TimeAuthority:     guestproductprocesssupervisordomain.GuestTimeAuthority{GuestNodeID: "guest", TimeAuthorityID: "time", Kind: "time-authority-outcome-profile", ProbeOutcomeMode: "unsupported"},
			TelemetryPipeline: guestproductprocesssupervisordomain.GuestTelemetryPipeline{Kind: "telemetry-export-outcome-profile", CollectorProbeOutcomeMode: "unsupported", ExportOutcomeMode: "unavailable"},
			OperationalStateBackup: guestproductprocesssupervisordomain.GuestOperationalStateBackupDeployment{
				RootDirectory:      "/var/lib/vitalserver/guest-runtime",
				LedgerDatabasePath: "/var/lib/vitalserver/guest-runtime/operational-state-backup-ledger.sqlite",
				DestinationReference: guestproductprocesssupervisordomain.GuestProductResourceReference{
					ResourceType: "guest-backup-destination",
					ResourceID:   "guest-local-operational-state",
				},
				PGDumpExecutablePath:    "/usr/bin/pg_dump",
				PGRestoreExecutablePath: "/usr/bin/pg_restore",
			},
		},
		RecorderGateway: guestproductprocesssupervisordomain.RecorderGatewayProcessDeployment{
			NodeExecutablePath:                "/opt/vitalserver/node/bin/node",
			ProgramPath:                       "/opt/vitalserver/recorder-gateway.js",
			Listener:                          guestproductprocesssupervisordomain.GuestProductProcessListener{BindHost: "0.0.0.0", Port: 8090},
			DurableIngressStateDirectory:      "/var/lib/vitalserver/recorder-gateway",
			VitalServerTopologyDeploymentPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json",
			ExternalVitalServerDeliveryConfigurationPath:     "/etc/vitalserver/external-vitalserver-delivery-configuration.json",
			DeliveryReplayAdmissionPolicy:                    guestproductprocesssupervisordomain.RecorderGatewayDeliveryReplayAdmissionPolicy{MaximumPendingItems: 1, MaximumPendingBytes: 1},
			ColdPathCapturePolicy:                            guestproductprocesssupervisordomain.RecorderGatewayColdPathCapturePolicy{MaximumRetainedPackets: 1, MaximumRetainedPayloadBytes: 1},
			ReplayPolicy:                                     guestproductprocesssupervisordomain.RecorderGatewayReplayPolicy{IntervalMilliseconds: 1, MaximumAttempts: 1, RetryDelayMilliseconds: 1, LeaseDurationMilliseconds: 1},
			GuestRuntimeObservationCatalogEndpoint:           "http://127.0.0.1:18443",
			ObservationCatalogBearerTokenMaterialPath:        "/var/lib/vitalserver/private/recorder-catalog-admission-token",
			VitalUploadPolicy:                                guestproductprocesssupervisordomain.RecorderGatewayVitalUploadPolicy{MaximumBytes: 67108864, RecoveryIntervalMilliseconds: 1000, RecoveryMaximumItems: 100},
			GuestRuntimeArchiveSourceAdmissionEndpoint:       "http://127.0.0.1:18443/internal/v1/archive/recorder-uploads",
			ArchiveSourceAdmissionBearerTokenMaterialPath:    "/var/lib/vitalserver/private/archive-source-admission-token",
			ArchiveSourceAdmissionRequestTimeoutMilliseconds: 30000,
		},
		LabRecorderRunner: guestproductprocesssupervisordomain.LabRecorderRunnerProcessDeployment{
			NodeExecutablePath: "/opt/vitalserver/node/bin/node", ProgramPath: "/opt/vitalserver/lab-recorder-runner.js", Listener: guestproductprocesssupervisordomain.GuestProductProcessListener{BindHost: "127.0.0.1", Port: 8091}, RecorderGatewayEndpoint: "http://127.0.0.1:8090", ScenarioCatalogPath: "/etc/vitalserver/lab-scenario-catalog.json", ReplayStateDirectory: "/var/lib/vitalserver/lab-replay-runner",
		},
	}
}

func validExternalVitalServerTopologyDeployment() guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment {
	return guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment{
		SchemaVersion: "v1", TopologyDeploymentID: "external-vitalserver-primary-topology", TopologyKind: "external-vitalserver",
		VitalServerDeliveryProvider: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		PublicBrowserExposure:       "not-exposed",
		ExternalVitalServerDeploymentConfiguration: &guestproductprocesssupervisordomain.ExternalVitalServerDeploymentConfiguration{
			ExternalUpstreamIntegrationReference:              guestproductprocesssupervisordomain.GuestProductResourceReference{ResourceType: "external-upstream-integration", ResourceID: "external-vitalserver-primary"},
			ExternalVitalServerDeliveryConfigurationReference: guestproductprocesssupervisordomain.GuestProductResourceReference{ResourceType: "external-vitalserver-delivery-configuration", ResourceID: "external-vitalserver-primary-delivery"},
		},
	}
}

func validExternalVitalServerDeliveryConfiguration() *guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration {
	return &guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{
		SchemaVersion: "v1", ConfigurationID: "external-vitalserver-primary-delivery",
		ExternalUpstreamIntegrationReference:                  guestproductprocesssupervisordomain.GuestProductResourceReference{ResourceType: "external-upstream-integration", ResourceID: "external-vitalserver-primary"},
		VitalServerDeliveryProvider:                           guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "external-vitalserver", ID: "external-vitalserver-primary", CapabilityRevision: 1},
		VitalServerPacketDeliveryEndpoint:                     guestproductprocesssupervisordomain.VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerDeliveryAcknowledgementTimeoutMilliseconds: 1000,
		VitalServerObservationEndpoint:                        guestproductprocesssupervisordomain.VitalServerHTTPObservationEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443, Path: "/healthz", AcceptedStatusCodes: []int{200}},
		VitalServerArchiveProvider:                            guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "vitalserver-indexed-library", ID: "external-vitalserver-primary-library", CapabilityRevision: 1},
		VitalServerIndexedLibraryEndpoint:                     guestproductprocesssupervisordomain.VitalServerPacketDeliveryEndpoint{Scheme: "https", Host: "external-vitalserver.example.test", Port: 8443},
		VitalServerArchiveCredentialReference:                 guestproductprocesssupervisordomain.GuestProductSecretReference{Kind: "vitalserver-library-credential", ID: "external-vitalserver-primary-library"},
		VitalServerArchiveRequestTimeoutMilliseconds:          10000,
	}
}
