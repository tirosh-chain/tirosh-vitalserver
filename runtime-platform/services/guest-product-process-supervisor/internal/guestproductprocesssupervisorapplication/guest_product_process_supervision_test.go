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
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime, "recorder-gateway": gateway}, nil)
	finished := make(chan error, 1)
	go func() {
		finished <- RunGuestProductProcessDeployment(context.Background(), validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	}()
	waitForStartedGuestProductProcess(t, launcher, "guest-runtime")
	waitForStartedGuestProductProcess(t, launcher, "recorder-gateway")
	gateway.exits <- errors.New("upstream process terminated")
	err := <-finished
	var terminated RequiredGuestProductProcessExitedError
	if !errors.As(err, &terminated) || terminated.ProcessName != "recorder-gateway" {
		t.Fatalf("termination error = %T %v", err, err)
	}
	if runtime.terminationCount != 1 || gateway.terminationCount != 0 {
		t.Fatalf("termination counts runtime=%d gateway=%d", runtime.terminationCount, gateway.terminationCount)
	}
}

func TestRunGuestProductProcessDeploymentTerminatesStartedProcessWhenLaterStartFails(t *testing.T) {
	runtime := newFakeGuestProductProcessLifecycleHandle()
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime}, map[string]error{"recorder-gateway": errors.New("node executable missing")})
	err := RunGuestProductProcessDeployment(context.Background(), validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	var startFailure GuestProductProcessStartError
	if !errors.As(err, &startFailure) || startFailure.ProcessName != "recorder-gateway" {
		t.Fatalf("start error = %T %v", err, err)
	}
	if runtime.terminationCount != 1 {
		t.Fatalf("Guest Runtime was not terminated after Gateway startup failure: %d", runtime.terminationCount)
	}
}

func TestRunGuestProductProcessDeploymentTreatsContextCancellationAsExplicitShutdown(t *testing.T) {
	runtime := newFakeGuestProductProcessLifecycleHandle()
	gateway := newFakeGuestProductProcessLifecycleHandle()
	launcher := newFakeGuestProductProcessLauncher(map[string]*fakeGuestProductProcessLifecycleHandle{"guest-runtime": runtime, "recorder-gateway": gateway}, nil)
	context, cancel := context.WithCancel(context.Background())
	finished := make(chan error, 1)
	go func() {
		finished <- RunGuestProductProcessDeployment(context, validDeploymentConfiguration(), validExternalVitalServerTopologyDeployment(), validExternalVitalServerDeliveryConfiguration(), launcher)
	}()
	waitForStartedGuestProductProcess(t, launcher, "guest-runtime")
	waitForStartedGuestProductProcess(t, launcher, "recorder-gateway")
	cancel()
	if err := <-finished; err != nil {
		t.Fatalf("explicit supervisor shutdown error = %v", err)
	}
	if runtime.terminationCount != 1 || gateway.terminationCount != 1 {
		t.Fatalf("shutdown termination counts runtime=%d gateway=%d", runtime.terminationCount, gateway.terminationCount)
	}
}

type fakeGuestProductProcessLauncher struct {
	processes   map[string]*fakeGuestProductProcessLifecycleHandle
	startErrors map[string]error
	started     chan string
}

func newFakeGuestProductProcessLauncher(processes map[string]*fakeGuestProductProcessLifecycleHandle, startErrors map[string]error) *fakeGuestProductProcessLauncher {
	return &fakeGuestProductProcessLauncher{processes: processes, startErrors: startErrors, started: make(chan string, 2)}
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
			StateDatabasePath: "/var/lib/vitalserver/guest-runtime/runtime.sqlite",
			ServiceVersion:    "0.1.0-dev",
			InstanceID:        "guest-runtime",
			ArchiveExportProvider: guestproductprocesssupervisordomain.ArchiveExportProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "archive", ID: "archive", CapabilityRevision: 1},
				OutcomeMode:                             "succeed",
			},
			ExternalUpstreamObservationProvider: guestproductprocesssupervisordomain.ExternalUpstreamObservationProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "external", ID: "external", CapabilityRevision: 1},
				OutcomeMode:                             "unsupported",
			},
			OutboundRelayObservationProvider: guestproductprocesssupervisordomain.OutboundRelayObservationProvider{
				GuestProductProviderCapabilityReference: guestproductprocesssupervisordomain.GuestProductProviderCapabilityReference{Kind: "relay", ID: "relay", CapabilityRevision: 1},
				OutcomeMode:                             "unsupported",
			},
			TimeAuthority:     guestproductprocesssupervisordomain.GuestTimeAuthority{GuestNodeID: "guest", TimeAuthorityID: "time", ProbeOutcomeMode: "unsupported"},
			TelemetryPipeline: guestproductprocesssupervisordomain.GuestTelemetryPipeline{CollectorProbeOutcomeMode: "unsupported", ExportOutcomeMode: "unavailable"},
		},
		RecorderGateway: guestproductprocesssupervisordomain.RecorderGatewayProcessDeployment{
			NodeExecutablePath:                "/opt/vitalserver/node/bin/node",
			ProgramPath:                       "/opt/vitalserver/recorder-gateway.js",
			Listener:                          guestproductprocesssupervisordomain.GuestProductProcessListener{BindHost: "0.0.0.0", Port: 8090},
			DurableIngressStateDirectory:      "/var/lib/vitalserver/recorder-gateway",
			VitalServerTopologyDeploymentPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json",
			ExternalVitalServerDeliveryConfigurationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json",
			DeliveryReplayAdmissionPolicy:                guestproductprocesssupervisordomain.RecorderGatewayDeliveryReplayAdmissionPolicy{MaximumPendingItems: 1, MaximumPendingBytes: 1},
			ColdPathCapturePolicy:                        guestproductprocesssupervisordomain.RecorderGatewayColdPathCapturePolicy{MaximumRetainedPackets: 1, MaximumRetainedPayloadBytes: 1},
			ReplayPolicy:                                 guestproductprocesssupervisordomain.RecorderGatewayReplayPolicy{IntervalMilliseconds: 1, MaximumAttempts: 1, RetryDelayMilliseconds: 1, LeaseDurationMilliseconds: 1},
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
	}
}
