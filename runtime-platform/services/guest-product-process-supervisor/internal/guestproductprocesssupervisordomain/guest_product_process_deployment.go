// Package guestproductprocesssupervisordomain contains pure Guest Product process deployment policy.
package guestproductprocesssupervisordomain

import (
	"fmt"
	"net"
	"net/url"
	"path"
	"strconv"
	"strings"
)

// GuestProductProcessDeploymentConfigurationSchemaVersion is the only C37
// deployment document version this bounded context accepts.
const GuestProductProcessDeploymentConfigurationSchemaVersion = "v1"

const (
	// GuestRuntimeProcessName identifies the C37 process that owns Guest control
	// and public-service virtio-socket listeners.
	GuestRuntimeProcessName = "guest-runtime"
	// RecorderGatewayProcessName identifies the C37 process that owns Recorder
	// Socket.IO ingress and its Guest-loopback listener.
	RecorderGatewayProcessName = "recorder-gateway"
	// LabRecorderRunnerProcessName identifies the Guest-local process that owns
	// virtual-recorder Socket.IO effects. It does not own Lab lifecycle,
	// Gateway capture persistence, or Archive upload state.
	LabRecorderRunnerProcessName = "lab-recorder-runner"
	// GuestTelemetryCollectorProcessName identifies the Guest-local OpenTelemetry
	// Collector process. It owns only its declared loopback OTLP and health
	// listeners; it does not own product operations or infer exporter outcomes.
	GuestTelemetryCollectorProcessName = "guest-telemetry-collector"
)

// GuestProductProcessDeploymentConfiguration is C37 after strict decoding. It
// is desired Guest-local process configuration, not process, packet, or
// upstream state.
type GuestProductProcessDeploymentConfiguration struct {
	SchemaVersion             string                             `json:"schemaVersion"`
	DeploymentID              string                             `json:"deploymentId"`
	RequiredProcessExitPolicy string                             `json:"requiredProcessExitPolicy"`
	GuestRuntime              GuestRuntimeProcessDeployment      `json:"guestRuntime"`
	RecorderGateway           RecorderGatewayProcessDeployment   `json:"recorderGateway"`
	LabRecorderRunner         LabRecorderRunnerProcessDeployment `json:"labRecorderRunner"`
	TelemetryCollector        *GuestTelemetryCollectorDeployment `json:"telemetryCollector,omitempty"`
}

type GuestRuntimeProcessDeployment struct {
	ExecutablePath                        string                                  `json:"executablePath"`
	Listener                              GuestProductProcessListener             `json:"listener"`
	ControlVirtioSocketListener           GuestRuntimeControlVirtioSocketListener `json:"controlVirtioSocketListener"`
	PublicServiceVirtioSocketBridges      []GuestPublicServiceVirtioSocketBridge  `json:"publicServiceVirtioSocketBridges"`
	StateDatabasePath                     string                                  `json:"stateDatabasePath"`
	ServiceVersion                        string                                  `json:"serviceVersion"`
	InstanceID                            string                                  `json:"instanceId"`
	ArchiveExportProvider                 ArchiveExportProvider                   `json:"archiveExportProvider"`
	RecorderGatewayColdPathSourceEndpoint string                                  `json:"recorderGatewayColdPathSourceEndpoint"`
	LabRecorderRunnerEndpoint             string                                  `json:"labRecorderRunnerEndpoint"`
	ExternalUpstreamObservationProvider   ExternalUpstreamObservationProvider     `json:"externalUpstreamObservationProvider"`
	OutboundRelayObservationProvider      OutboundRelayObservationProvider        `json:"outboundRelayObservationProvider"`
	TimeAuthority                         GuestTimeAuthority                      `json:"timeAuthority"`
	TelemetryPipeline                     GuestTelemetryPipeline                  `json:"telemetryPipeline"`
}

// GuestRuntimeControlVirtioSocketListener declares the Guest-owned socket
// port that accepts Host Runtime-control traffic. It carries no Host address:
// C32 owns the Host-local HTTP bridge that reaches this Guest port.
type GuestRuntimeControlVirtioSocketListener struct {
	Port int `json:"port"`
}

// GuestPublicServiceVirtioSocketBridge declares one C37-owned data-plane
// transport. C32 owns the matching Host-loopback listener and C36 owns the
// public HTTP route. GuestProductProcessName makes the owning planned process
// explicit; TargetHost and TargetPort must equal that process's declared
// Guest-loopback listener. This declaration never derives a Guest network
// address or claims process readiness.
type GuestPublicServiceVirtioSocketBridge struct {
	RouteID                 string `json:"routeId"`
	GuestProductProcessName string `json:"guestProductProcessName"`
	VirtioSocketPort        int    `json:"virtioSocketPort"`
	TargetHost              string `json:"targetHost"`
	TargetPort              int    `json:"targetPort"`
}

type RecorderGatewayProcessDeployment struct {
	NodeExecutablePath                           string                                       `json:"nodeExecutablePath"`
	ProgramPath                                  string                                       `json:"programPath"`
	Listener                                     GuestProductProcessListener                  `json:"listener"`
	DurableIngressStateDirectory                 string                                       `json:"durableIngressStateDirectory"`
	VitalServerTopologyDeploymentPath            string                                       `json:"vitalServerTopologyDeploymentPath"`
	ExternalVitalServerDeliveryConfigurationPath string                                       `json:"externalVitalServerDeliveryConfigurationPath"`
	DeliveryReplayAdmissionPolicy                RecorderGatewayDeliveryReplayAdmissionPolicy `json:"deliveryReplayAdmissionPolicy"`
	ColdPathCapturePolicy                        RecorderGatewayColdPathCapturePolicy         `json:"coldPathCapturePolicy"`
	ReplayPolicy                                 RecorderGatewayReplayPolicy                  `json:"replayPolicy"`
}

// LabRecorderRunnerProcessDeployment declares the dedicated Guest-local
// virtual-recorder execution service. It must receive both its own loopback
// listener and the exact Recorder Gateway loopback endpoint; it never derives
// a target from an address, process name, or public route.
type LabRecorderRunnerProcessDeployment struct {
	NodeExecutablePath                     string                      `json:"nodeExecutablePath"`
	ProgramPath                            string                      `json:"programPath"`
	Listener                               GuestProductProcessListener `json:"listener"`
	RecorderGatewayEndpoint                string                      `json:"recorderGatewayEndpoint"`
	GuestRuntimeObservationCatalogEndpoint string                      `json:"guestRuntimeObservationCatalogEndpoint"`
	ScenarioCatalogPath                    string                      `json:"scenarioCatalogPath"`
}

// GuestTelemetryCollectorDeployment is the selected Guest-local Collector
// process. Its local listeners are desired deployment addresses, not an
// observation that an OTLP request was accepted or exported downstream.
type GuestTelemetryCollectorDeployment struct {
	ExecutablePath    string                      `json:"executablePath"`
	ConfigurationPath string                      `json:"configurationPath"`
	OTLPHTTPListener  GuestProductProcessListener `json:"otlpHttpListener"`
}

type GuestProductProcessListener struct {
	BindHost string `json:"bindHost"`
	Port     int    `json:"port"`
}

// GuestProductProviderCapabilityReference identifies the specific provider
// capability selected by a Guest Product deployment. It is desired
// configuration, not an observation that the provider is reachable or
// accepted an operation.
type GuestProductProviderCapabilityReference struct {
	Kind               string `json:"kind"`
	ID                 string `json:"id"`
	CapabilityRevision int    `json:"capabilityRevision"`
}

type ArchiveExportProvider struct {
	GuestProductProviderCapabilityReference
	// OutcomeMode is an explicit development-only outcome profile setting. It
	// is intentionally absent for the VitalServer indexed-library adapter.
	OutcomeMode string `json:"outcomeMode"`
	// CredentialMaterialPath names Guest-owned secret material. It is a path
	// reference only: C37 never carries credential bytes.
	CredentialMaterialPath string `json:"credentialMaterialPath"`
	// VitalServerConfiguration names the desired endpoint document for the
	// indexed-library adapter. Its kind keeps C44 bundled loopback and C46
	// external deployment ownership distinct.
	VitalServerConfiguration *VitalServerArchiveProviderConfiguration `json:"vitalServerConfiguration,omitempty"`
}

type VitalServerArchiveProviderConfiguration struct {
	Kind              string `json:"kind"`
	ConfigurationPath string `json:"configurationPath"`
}

// ExternalUpstreamObservationProvider selects the adapter that observes an
// External Upstream integration. It never represents Recorder delivery.
type ExternalUpstreamObservationProvider struct {
	GuestProductProviderCapabilityReference
	// OutcomeMode belongs only to the deterministic acceptance profile. A
	// production external VitalServer probe instead receives the explicit C46
	// document that names its permitted endpoint and accepted response codes.
	OutcomeMode                                  string `json:"outcomeMode"`
	ExternalVitalServerDeliveryConfigurationPath string `json:"externalVitalServerDeliveryConfigurationPath"`
	RequestTimeoutMilliseconds                   int    `json:"requestTimeoutMilliseconds"`
}

// OutboundRelayObservationProvider selects the adapter that observes an
// Outbound Relay target. It remains distinct from External Upstream because
// the two resources have separate owners and lifecycle state.
type OutboundRelayObservationProvider struct {
	GuestProductProviderCapabilityReference
	OutcomeMode string `json:"outcomeMode"`
}

type GuestTimeAuthority struct {
	GuestNodeID                string `json:"guestNodeId"`
	TimeAuthorityID            string `json:"timeAuthorityId"`
	Kind                       string `json:"kind"`
	ChronyExecutablePath       string `json:"chronyExecutablePath"`
	NTPServerHost              string `json:"ntpServerHost"`
	NTPServerPort              int    `json:"ntpServerPort"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
	ProbeOutcomeMode           string `json:"probeOutcomeMode"`
}

type GuestTelemetryPipeline struct {
	// Kind selects either a deterministic acceptance-only profile or the live
	// OTLP/HTTP adapter. It is deliberately explicit so a missing Collector
	// endpoint cannot be mistaken for a local success path.
	Kind                       string `json:"kind"`
	CollectorBaseEndpoint      string `json:"collectorBaseEndpoint"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
	CollectorProbeOutcomeMode  string `json:"collectorProbeOutcomeMode"`
	ExportOutcomeMode          string `json:"exportOutcomeMode"`
}

// VitalServerPacketDeliveryEndpoint identifies only the network target used
// for Recorder Gateway Socket.IO packet delivery. It does not select a
// topology, report reachability, or imply that a VitalServer accepted a packet.
type VitalServerPacketDeliveryEndpoint struct {
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

// GuestProductResourceReference preserves the referenced owner's resource
// vocabulary. A resolver must compare both resource type and identifier; it
// must never infer a related resource from a hostname or provider label.
type GuestProductResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
}

// GuestProductSecretReference identifies material owned outside C37/C46. The
// reference is safe desired configuration; the matching user/password values
// are read by the Guest Runtime secret-material adapter only.
type GuestProductSecretReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

// GuestProductVitalServerTopologyDeployment is C44 as consumed by the
// Supervisor boundary. It is desired placement only and intentionally omits
// endpoint material and every process/delivery observation.
type GuestProductVitalServerTopologyDeployment struct {
	SchemaVersion                              string                                      `json:"schemaVersion"`
	TopologyDeploymentID                       string                                      `json:"topologyDeploymentId"`
	TopologyKind                               string                                      `json:"topologyKind"`
	VitalServerDeliveryProvider                GuestProductProviderCapabilityReference     `json:"vitalServerDeliveryProvider"`
	PublicBrowserExposure                      string                                      `json:"publicBrowserExposure"`
	BundledUpstreamImageSetDeployment          *BundledUpstreamImageSetDeployment          `json:"bundledUpstreamImageSetDeployment"`
	ExternalVitalServerDeploymentConfiguration *ExternalVitalServerDeploymentConfiguration `json:"externalVitalServerDeploymentConfiguration"`
}

type BundledUpstreamImageSetDeployment struct {
	ImageSetManagerConfigurationReference                 GuestProductResourceReference           `json:"imageSetManagerConfigurationReference"`
	VitalServerPacketDeliveryEndpoint                     VitalServerPacketDeliveryEndpoint       `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int                                     `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
	VitalServerObservationEndpoint                        VitalServerHTTPObservationEndpoint      `json:"vitalServerObservationEndpoint"`
	VitalServerArchiveProvider                            GuestProductProviderCapabilityReference `json:"vitalServerArchiveProvider"`
	VitalServerIndexedLibraryEndpoint                     VitalServerPacketDeliveryEndpoint       `json:"vitalServerIndexedLibraryEndpoint"`
	VitalServerArchiveCredentialReference                 GuestProductSecretReference             `json:"vitalServerArchiveCredentialReference"`
	VitalServerArchiveRequestTimeoutMilliseconds          int                                     `json:"vitalServerArchiveRequestTimeoutMilliseconds"`
}

type ExternalVitalServerDeploymentConfiguration struct {
	ExternalUpstreamIntegrationReference              GuestProductResourceReference `json:"externalUpstreamIntegrationReference"`
	ExternalVitalServerDeliveryConfigurationReference GuestProductResourceReference `json:"externalVitalServerDeliveryConfigurationReference"`
}

// ExternalVitalServerDeliveryConfiguration is C46. Its deployment
// administrator owns this input; the Supervisor only consumes the complete
// document and does not create a default endpoint when it is unavailable.
type ExternalVitalServerDeliveryConfiguration struct {
	SchemaVersion                                         string                                  `json:"schemaVersion"`
	ConfigurationID                                       string                                  `json:"configurationId"`
	ExternalUpstreamIntegrationReference                  GuestProductResourceReference           `json:"externalUpstreamIntegrationReference"`
	VitalServerDeliveryProvider                           GuestProductProviderCapabilityReference `json:"vitalServerDeliveryProvider"`
	VitalServerPacketDeliveryEndpoint                     VitalServerPacketDeliveryEndpoint       `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int                                     `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
	VitalServerObservationEndpoint                        VitalServerHTTPObservationEndpoint      `json:"vitalServerObservationEndpoint"`
	VitalServerArchiveProvider                            GuestProductProviderCapabilityReference `json:"vitalServerArchiveProvider"`
	VitalServerIndexedLibraryEndpoint                     VitalServerPacketDeliveryEndpoint       `json:"vitalServerIndexedLibraryEndpoint"`
	VitalServerArchiveCredentialReference                 GuestProductSecretReference             `json:"vitalServerArchiveCredentialReference"`
	VitalServerArchiveRequestTimeoutMilliseconds          int                                     `json:"vitalServerArchiveRequestTimeoutMilliseconds"`
}

// VitalServerHTTPObservationEndpoint is an operator-approved exact HTTP
// probe contract. It is separate from packet delivery and archive endpoints:
// neither a route name nor a HTTP success range may be inferred.
type VitalServerHTTPObservationEndpoint struct {
	Scheme              string `json:"scheme"`
	Host                string `json:"host"`
	Port                int    `json:"port"`
	Path                string `json:"path"`
	AcceptedStatusCodes []int  `json:"acceptedStatusCodes"`
}

// RecorderGatewayVitalServerDeliveryResolution is a pure, complete input to
// one Gateway process invocation. It is deliberately separate from C44
// topology selection and C46 external deployment configuration.
type RecorderGatewayVitalServerDeliveryResolution struct {
	VitalServerPacketDeliveryEndpoint                     VitalServerPacketDeliveryEndpoint
	VitalServerDeliveryProvider                           GuestProductProviderCapabilityReference
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int
}

// RecorderGatewayDeliveryReplayAdmissionPolicy bounds temporary payloads
// retained only while an accepted packet still requires VitalServer delivery.
type RecorderGatewayDeliveryReplayAdmissionPolicy struct {
	MaximumPendingItems int `json:"maximumPendingItems"`
	MaximumPendingBytes int `json:"maximumPendingBytes"`
}

// RecorderGatewayColdPathCapturePolicy bounds retained packet source bytes
// used by the separately finalized cold-path capture aggregate.
type RecorderGatewayColdPathCapturePolicy struct {
	MaximumRetainedPackets      int `json:"maximumRetainedPackets"`
	MaximumRetainedPayloadBytes int `json:"maximumRetainedPayloadBytes"`
}

type RecorderGatewayReplayPolicy struct {
	IntervalMilliseconds      int `json:"intervalMilliseconds"`
	MaximumAttempts           int `json:"maximumAttempts"`
	RetryDelayMilliseconds    int `json:"retryDelayMilliseconds"`
	LeaseDurationMilliseconds int `json:"leaseDurationMilliseconds"`
}

// GuestProductProcessInvocation is the complete, named process effect that
// the application layer may give an operating-system process adapter.
type GuestProductProcessInvocation struct {
	ProcessName    string
	ExecutablePath string
	Arguments      []string
}

// ValidateGuestProductProcessDeploymentConfiguration checks C37 semantic
// rules without reading Guest files, starting a process, or probing upstream.
func ValidateGuestProductProcessDeploymentConfiguration(configuration GuestProductProcessDeploymentConfiguration) error {
	if configuration.SchemaVersion != GuestProductProcessDeploymentConfigurationSchemaVersion {
		return fmt.Errorf("Guest Product process deployment schemaVersion must be %q", GuestProductProcessDeploymentConfigurationSchemaVersion)
	}
	if !validIdentifier(configuration.DeploymentID) {
		return fmt.Errorf("Guest Product process deploymentId is invalid")
	}
	if configuration.RequiredProcessExitPolicy != "terminate-guest-product" {
		return fmt.Errorf("Guest Product requiredProcessExitPolicy must be terminate-guest-product")
	}
	if err := validateGuestRuntimeProcessDeployment(configuration.GuestRuntime); err != nil {
		return err
	}
	if err := validateRecorderGatewayProcessDeployment(configuration.RecorderGateway); err != nil {
		return err
	}
	if err := validateLabRecorderRunnerProcessDeployment(configuration.LabRecorderRunner); err != nil {
		return err
	}
	if configuration.TelemetryCollector != nil {
		if err := validateGuestTelemetryCollectorDeployment(*configuration.TelemetryCollector); err != nil {
			return err
		}
		if configuration.GuestRuntime.TelemetryPipeline.Kind != "otlp-http" {
			return fmt.Errorf("Guest telemetry Collector requires the otlp-http telemetry pipeline")
		}
		if !guestRuntimeTelemetryCollectorEndpointTargetsCollector(configuration.GuestRuntime.TelemetryPipeline.CollectorBaseEndpoint, configuration.TelemetryCollector.OTLPHTTPListener) {
			return fmt.Errorf("Guest Runtime telemetry collectorBaseEndpoint must target the declared Guest telemetry Collector OTLP listener")
		}
	}
	listeners := []GuestProductProcessListener{
		configuration.GuestRuntime.Listener,
		configuration.RecorderGateway.Listener,
		configuration.LabRecorderRunner.Listener,
	}
	if configuration.TelemetryCollector != nil {
		listeners = append(listeners, configuration.TelemetryCollector.OTLPHTTPListener)
	}
	if anyGuestProductListenersConflict(listeners) {
		return fmt.Errorf("Guest Runtime, Recorder Gateway, Lab recorder Runner, and telemetry Collector listeners cannot bind the same Guest socket")
	}
	if err := validateGuestPublicServiceBridgeProcessOwnership(configuration.GuestRuntime.PublicServiceVirtioSocketBridges, configuration.GuestRuntime.Listener, configuration.RecorderGateway.Listener); err != nil {
		return err
	}
	if !guestRuntimeColdPathSourceEndpointTargetsRecorderGateway(configuration.GuestRuntime.RecorderGatewayColdPathSourceEndpoint, configuration.RecorderGateway.Listener) {
		return fmt.Errorf("Guest Runtime recorderGatewayColdPathSourceEndpoint must target the declared Recorder Gateway Guest-loopback listener")
	}
	if !guestRuntimeLabRecorderRunnerEndpointTargetsRunner(configuration.GuestRuntime.LabRecorderRunnerEndpoint, configuration.LabRecorderRunner.Listener) {
		return fmt.Errorf("Guest Runtime labRecorderRunnerEndpoint must target the declared Lab recorder Runner Guest-loopback listener")
	}
	if !labRecorderRunnerGatewayEndpointTargetsRecorderGateway(configuration.LabRecorderRunner.RecorderGatewayEndpoint, configuration.RecorderGateway.Listener) {
		return fmt.Errorf("Lab recorder Runner recorderGatewayEndpoint must target the declared Recorder Gateway Guest-loopback listener")
	}
	if !labRecorderRunnerObservationCatalogEndpointTargetsGuestRuntime(configuration.LabRecorderRunner.GuestRuntimeObservationCatalogEndpoint, configuration.GuestRuntime.Listener) {
		return fmt.Errorf("Lab recorder Runner guestRuntimeObservationCatalogEndpoint must target the declared Guest Runtime Guest-loopback listener")
	}
	if configuration.GuestRuntime.StateDatabasePath == configuration.RecorderGateway.DurableIngressStateDirectory {
		return fmt.Errorf("Guest Runtime stateDatabasePath and Recorder Gateway durableIngressStateDirectory must remain separate owned stores")
	}
	return nil
}

// PlanGuestProductProcessInvocations derives only explicit required child
// invocations. It has no process side effect and supplies every supported
// service option; no child is allowed to choose a hidden product value.
func PlanGuestProductProcessInvocations(configuration GuestProductProcessDeploymentConfiguration, resolution RecorderGatewayVitalServerDeliveryResolution, externalConfiguration *ExternalVitalServerDeliveryConfiguration) ([]GuestProductProcessInvocation, error) {
	if err := ValidateGuestProductProcessDeploymentConfiguration(configuration); err != nil {
		return nil, err
	}
	if err := validateRecorderGatewayVitalServerDeliveryResolution(resolution); err != nil {
		return nil, err
	}
	runtime := configuration.GuestRuntime
	gateway := configuration.RecorderGateway
	runtimeArguments := []string{
		"--listen=" + listenerAddress(runtime.Listener),
		"--control-virtio-socket-port=" + strconv.Itoa(runtime.ControlVirtioSocketListener.Port),
		"--state-db=" + runtime.StateDatabasePath,
		"--service-version=" + runtime.ServiceVersion,
		"--instance-id=" + runtime.InstanceID,
		"--archive-provider-kind=" + runtime.ArchiveExportProvider.Kind,
		"--archive-provider-id=" + runtime.ArchiveExportProvider.ID,
		"--archive-provider-capability-revision=" + strconv.Itoa(runtime.ArchiveExportProvider.CapabilityRevision),
		"--recorder-gateway-cold-path-source-endpoint=" + runtime.RecorderGatewayColdPathSourceEndpoint,
		"--lab-recorder-runner-endpoint=" + runtime.LabRecorderRunnerEndpoint,
		"--external-upstream-observation-provider-kind=" + runtime.ExternalUpstreamObservationProvider.Kind,
		"--external-upstream-observation-provider-id=" + runtime.ExternalUpstreamObservationProvider.ID,
		"--external-upstream-observation-provider-capability-revision=" + strconv.Itoa(runtime.ExternalUpstreamObservationProvider.CapabilityRevision),
		"--external-upstream-observation-provider-mode=" + runtime.ExternalUpstreamObservationProvider.OutcomeMode,
		"--external-upstream-observation-external-vitalserver-delivery-configuration=" + runtime.ExternalUpstreamObservationProvider.ExternalVitalServerDeliveryConfigurationPath,
		"--external-upstream-observation-request-timeout-milliseconds=" + strconv.Itoa(runtime.ExternalUpstreamObservationProvider.RequestTimeoutMilliseconds),
		"--outbound-relay-observation-provider-kind=" + runtime.OutboundRelayObservationProvider.Kind,
		"--outbound-relay-observation-provider-id=" + runtime.OutboundRelayObservationProvider.ID,
		"--outbound-relay-observation-provider-capability-revision=" + strconv.Itoa(runtime.OutboundRelayObservationProvider.CapabilityRevision),
		"--outbound-relay-observation-provider-mode=" + runtime.OutboundRelayObservationProvider.OutcomeMode,
		"--guest-node-id=" + runtime.TimeAuthority.GuestNodeID,
		"--time-authority-id=" + runtime.TimeAuthority.TimeAuthorityID,
		"--time-adapter-kind=" + runtime.TimeAuthority.Kind,
		"--time-chrony-executable-path=" + runtime.TimeAuthority.ChronyExecutablePath,
		"--time-request-timeout-milliseconds=" + strconv.Itoa(runtime.TimeAuthority.RequestTimeoutMilliseconds),
		"--time-provider-mode=" + runtime.TimeAuthority.ProbeOutcomeMode,
		"--telemetry-adapter-kind=" + runtime.TelemetryPipeline.Kind,
		"--telemetry-collector-base-endpoint=" + runtime.TelemetryPipeline.CollectorBaseEndpoint,
		"--telemetry-request-timeout-milliseconds=" + strconv.Itoa(runtime.TelemetryPipeline.RequestTimeoutMilliseconds),
		"--telemetry-pipeline-mode=" + runtime.TelemetryPipeline.CollectorProbeOutcomeMode,
		"--telemetry-export-mode=" + runtime.TelemetryPipeline.ExportOutcomeMode,
	}
	archiveProviderArguments, err := planGuestRuntimeArchiveProviderArguments(runtime.ArchiveExportProvider, configuration.RecorderGateway, externalConfiguration)
	if err != nil {
		return nil, err
	}
	runtimeArguments = append(runtimeArguments, archiveProviderArguments...)
	for _, publicServiceBridge := range runtime.PublicServiceVirtioSocketBridges {
		runtimeArguments = append(runtimeArguments,
			"--guest-public-service-virtio-socket-bridge="+guestPublicServiceVirtioSocketBridgeArgument(publicServiceBridge),
		)
	}
	gatewayArguments := []string{
		gateway.ProgramPath,
		"--listen=" + listenerAddress(gateway.Listener),
		"--state-dir=" + gateway.DurableIngressStateDirectory,
		"--vitalserver-delivery-url=" + resolution.RecorderGatewayVitalServerDeliveryURL(),
		"--provider-kind=" + resolution.VitalServerDeliveryProvider.Kind,
		"--provider-id=" + resolution.VitalServerDeliveryProvider.ID,
		"--capability-revision=" + strconv.Itoa(resolution.VitalServerDeliveryProvider.CapabilityRevision),
		"--vitalserver-delivery-acknowledgement-timeout-ms=" + strconv.Itoa(resolution.VitalServerDeliveryAcknowledgementTimeoutMilliseconds),
		"--delivery-replay-max-items=" + strconv.Itoa(gateway.DeliveryReplayAdmissionPolicy.MaximumPendingItems),
		"--delivery-replay-max-bytes=" + strconv.Itoa(gateway.DeliveryReplayAdmissionPolicy.MaximumPendingBytes),
		"--cold-path-capture-max-retained-packets=" + strconv.Itoa(gateway.ColdPathCapturePolicy.MaximumRetainedPackets),
		"--cold-path-capture-max-retained-payload-bytes=" + strconv.Itoa(gateway.ColdPathCapturePolicy.MaximumRetainedPayloadBytes),
		"--replay-interval-ms=" + strconv.Itoa(gateway.ReplayPolicy.IntervalMilliseconds),
		"--replay-max-attempts=" + strconv.Itoa(gateway.ReplayPolicy.MaximumAttempts),
		"--replay-retry-delay-ms=" + strconv.Itoa(gateway.ReplayPolicy.RetryDelayMilliseconds),
		"--replay-lease-duration-ms=" + strconv.Itoa(gateway.ReplayPolicy.LeaseDurationMilliseconds),
	}
	runner := configuration.LabRecorderRunner
	runnerArguments := []string{
		runner.ProgramPath,
		"--listen=" + listenerAddress(runner.Listener),
		"--recorder-gateway-endpoint=" + runner.RecorderGatewayEndpoint,
		"--guest-runtime-observation-catalog-endpoint=" + runner.GuestRuntimeObservationCatalogEndpoint,
		"--scenario-catalog=" + runner.ScenarioCatalogPath,
	}
	invocations := make([]GuestProductProcessInvocation, 0, 4)
	if collector := configuration.TelemetryCollector; collector != nil {
		invocations = append(invocations, GuestProductProcessInvocation{
			ProcessName:    GuestTelemetryCollectorProcessName,
			ExecutablePath: collector.ExecutablePath,
			Arguments:      []string{"--config=" + collector.ConfigurationPath},
		})
	}
	invocations = append(invocations,
		GuestProductProcessInvocation{ProcessName: GuestRuntimeProcessName, ExecutablePath: runtime.ExecutablePath, Arguments: runtimeArguments},
		GuestProductProcessInvocation{ProcessName: RecorderGatewayProcessName, ExecutablePath: gateway.NodeExecutablePath, Arguments: gatewayArguments},
		GuestProductProcessInvocation{ProcessName: LabRecorderRunnerProcessName, ExecutablePath: runner.NodeExecutablePath, Arguments: runnerArguments},
	)
	return invocations, nil
}

// planGuestRuntimeArchiveProviderArguments performs only C37/C44/C46 equality
// checks and emits the complete adapter invocation. It never reads a secret,
// opens an upstream connection, or turns a missing desired document into an
// outcome-profile success.
func planGuestRuntimeArchiveProviderArguments(provider ArchiveExportProvider, gateway RecorderGatewayProcessDeployment, externalConfiguration *ExternalVitalServerDeliveryConfiguration) ([]string, error) {
	switch provider.Kind {
	case "archive-export-outcome-profile":
		return []string{"--archive-provider-mode=" + provider.OutcomeMode}, nil
	case "vitalserver-indexed-library":
		if provider.VitalServerConfiguration == nil {
			return nil, fmt.Errorf("VitalServer indexed-library Archive provider requires an explicit C44 or C46 configuration")
		}
		configuration := *provider.VitalServerConfiguration
		switch configuration.Kind {
		case "external-vitalserver-delivery-configuration":
			if gateway.ExternalVitalServerDeliveryConfigurationPath == "" || gateway.ExternalVitalServerDeliveryConfigurationPath != configuration.ConfigurationPath || externalConfiguration == nil {
				return nil, fmt.Errorf("C37 external VitalServer archive provider configuration must match Recorder Gateway C46 path")
			}
			if err := ValidateExternalVitalServerDeliveryConfiguration(*externalConfiguration); err != nil {
				return nil, err
			}
			if !sameGuestProductProviderCapabilityReference(provider.GuestProductProviderCapabilityReference, externalConfiguration.VitalServerArchiveProvider) || isGuestLoopbackHost(externalConfiguration.VitalServerIndexedLibraryEndpoint.Host) {
				return nil, fmt.Errorf("C37 Archive Export provider and C46 VitalServer archive provider do not describe the same external capability")
			}
		case "bundled-vitalserver-topology-deployment":
			if configuration.ConfigurationPath != gateway.VitalServerTopologyDeploymentPath || gateway.ExternalVitalServerDeliveryConfigurationPath != "" || externalConfiguration != nil {
				return nil, fmt.Errorf("C37 bundled VitalServer archive provider must use exactly the C44 topology path without C46")
			}
		default:
			return nil, fmt.Errorf("C37 VitalServer indexed-library configuration kind is unsupported")
		}
		return []string{
			"--archive-provider-vitalserver-configuration-kind=" + configuration.Kind,
			"--archive-provider-vitalserver-configuration=" + configuration.ConfigurationPath,
			"--archive-provider-credential-material-path=" + provider.CredentialMaterialPath,
		}, nil
	default:
		return nil, fmt.Errorf("Guest Runtime Archive provider kind is invalid")
	}
}

func (resolution RecorderGatewayVitalServerDeliveryResolution) RecorderGatewayVitalServerDeliveryURL() string {
	endpoint := resolution.VitalServerPacketDeliveryEndpoint
	return (&url.URL{Scheme: endpoint.Scheme, Host: net.JoinHostPort(endpoint.Host, strconv.Itoa(endpoint.Port))}).String()
}

// ResolveRecorderGatewayVitalServerDelivery derives the one complete VitalServer
// packet-delivery input that the Supervisor may pass to Recorder Gateway. It
// compares complete C37, C44, and C46 inputs and never probes a network target,
// guesses a bundled endpoint, or substitutes a previous successful provider.
func ResolveRecorderGatewayVitalServerDelivery(
	deployment RecorderGatewayProcessDeployment,
	topology GuestProductVitalServerTopologyDeployment,
	externalConfiguration *ExternalVitalServerDeliveryConfiguration,
) (RecorderGatewayVitalServerDeliveryResolution, error) {
	if err := validateRecorderGatewayProcessDeployment(deployment); err != nil {
		return RecorderGatewayVitalServerDeliveryResolution{}, err
	}
	if err := ValidateGuestProductVitalServerTopologyDeployment(topology); err != nil {
		return RecorderGatewayVitalServerDeliveryResolution{}, err
	}
	switch topology.TopologyKind {
	case "external-vitalserver":
		if deployment.ExternalVitalServerDeliveryConfigurationPath == "" {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("external VitalServer topology requires C46 externalVitalServerDeliveryConfigurationPath before Recorder Gateway activation")
		}
		if externalConfiguration == nil {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("external VitalServer topology requires C46 external delivery configuration before Recorder Gateway activation")
		}
		if err := ValidateExternalVitalServerDeliveryConfiguration(*externalConfiguration); err != nil {
			return RecorderGatewayVitalServerDeliveryResolution{}, err
		}
		external := topology.ExternalVitalServerDeploymentConfiguration
		if external == nil || !sameGuestProductResourceReference(external.ExternalUpstreamIntegrationReference, externalConfiguration.ExternalUpstreamIntegrationReference) || external.ExternalVitalServerDeliveryConfigurationReference.ResourceID != externalConfiguration.ConfigurationID || !sameGuestProductProviderCapabilityReference(topology.VitalServerDeliveryProvider, externalConfiguration.VitalServerDeliveryProvider) {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("C44 external VitalServer topology and C46 external delivery configuration do not describe the same integration, configuration, and provider")
		}
		if isGuestLoopbackHost(externalConfiguration.VitalServerPacketDeliveryEndpoint.Host) {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("C46 external VitalServer packet-delivery endpoint must not use a Guest-loopback host")
		}
		return RecorderGatewayVitalServerDeliveryResolution{
			VitalServerPacketDeliveryEndpoint:                     externalConfiguration.VitalServerPacketDeliveryEndpoint,
			VitalServerDeliveryProvider:                           externalConfiguration.VitalServerDeliveryProvider,
			VitalServerDeliveryAcknowledgementTimeoutMilliseconds: externalConfiguration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds,
		}, nil
	case "bundled-vitalserver":
		if deployment.ExternalVitalServerDeliveryConfigurationPath != "" || externalConfiguration != nil {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("C44 bundled VitalServer topology must not use C46 external delivery configuration")
		}
		bundled := topology.BundledUpstreamImageSetDeployment
		if bundled == nil || !isGuestProductResourceReference(bundled.ImageSetManagerConfigurationReference, "guest-bundled-upstream-image-set-manager-configuration") || !validVitalServerPacketDeliveryEndpoint(bundled.VitalServerPacketDeliveryEndpoint) || !isGuestLoopbackHost(bundled.VitalServerPacketDeliveryEndpoint.Host) || !inRange(bundled.VitalServerDeliveryAcknowledgementTimeoutMilliseconds, 1, 3600000) {
			return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("C44 bundled Upstream image-set deployment is invalid")
		}
		return RecorderGatewayVitalServerDeliveryResolution{
			VitalServerPacketDeliveryEndpoint:                     bundled.VitalServerPacketDeliveryEndpoint,
			VitalServerDeliveryProvider:                           topology.VitalServerDeliveryProvider,
			VitalServerDeliveryAcknowledgementTimeoutMilliseconds: bundled.VitalServerDeliveryAcknowledgementTimeoutMilliseconds,
		}, nil
	default:
		return RecorderGatewayVitalServerDeliveryResolution{}, fmt.Errorf("Guest Product VitalServer topology kind is invalid")
	}
}

// ValidateGuestProductVitalServerTopologyDeployment checks C44 desired
// topology facts only. It does not claim that an artifact exists, a process
// started, or a referenced external integration is reachable.
func ValidateGuestProductVitalServerTopologyDeployment(topology GuestProductVitalServerTopologyDeployment) error {
	if topology.SchemaVersion != GuestProductProcessDeploymentConfigurationSchemaVersion || !validIdentifier(topology.TopologyDeploymentID) || !validGuestProductProviderCapabilityReference(topology.VitalServerDeliveryProvider) {
		return fmt.Errorf("C44 Guest Product VitalServer topology identity or provider is invalid")
	}
	switch topology.TopologyKind {
	case "bundled-vitalserver":
		bundled := topology.BundledUpstreamImageSetDeployment
		if bundled == nil || topology.ExternalVitalServerDeploymentConfiguration != nil || !oneOf(topology.PublicBrowserExposure, "not-exposed", "guest-virtio-route") || !isGuestProductResourceReference(bundled.ImageSetManagerConfigurationReference, "guest-bundled-upstream-image-set-manager-configuration") || !validVitalServerPacketDeliveryEndpoint(bundled.VitalServerPacketDeliveryEndpoint) || !isGuestLoopbackHost(bundled.VitalServerPacketDeliveryEndpoint.Host) || !inRange(bundled.VitalServerDeliveryAcknowledgementTimeoutMilliseconds, 1, 3600000) || !validVitalServerHTTPObservationEndpoint(bundled.VitalServerObservationEndpoint) || !isGuestLoopbackHost(bundled.VitalServerObservationEndpoint.Host) || bundled.VitalServerArchiveProvider.Kind != "vitalserver-indexed-library" || !validGuestProductProviderCapabilityReference(bundled.VitalServerArchiveProvider) || !validVitalServerPacketDeliveryEndpoint(bundled.VitalServerIndexedLibraryEndpoint) || !isGuestLoopbackHost(bundled.VitalServerIndexedLibraryEndpoint.Host) || !validGuestProductSecretReference(bundled.VitalServerArchiveCredentialReference) || !inRange(bundled.VitalServerArchiveRequestTimeoutMilliseconds, 1, 3600000) {
			return fmt.Errorf("C44 bundled Upstream image-set deployment is invalid")
		}
	case "external-vitalserver":
		external := topology.ExternalVitalServerDeploymentConfiguration
		if external == nil || topology.BundledUpstreamImageSetDeployment != nil || !oneOf(topology.PublicBrowserExposure, "not-exposed", "host-external-route") || !isGuestProductResourceReference(external.ExternalUpstreamIntegrationReference, "external-upstream-integration") || !isGuestProductResourceReference(external.ExternalVitalServerDeliveryConfigurationReference, "external-vitalserver-delivery-configuration") {
			return fmt.Errorf("C44 external VitalServer deployment configuration is invalid")
		}
	default:
		return fmt.Errorf("C44 Guest Product VitalServer topology kind is invalid")
	}
	return nil
}

// ValidateExternalVitalServerDeliveryConfiguration checks C46 input without
// opening a connection or reading a secret. The archive credential reference
// is distinct from its secret material and from Socket.IO packet delivery.
func ValidateExternalVitalServerDeliveryConfiguration(configuration ExternalVitalServerDeliveryConfiguration) error {
	if configuration.SchemaVersion != GuestProductProcessDeploymentConfigurationSchemaVersion || !validIdentifier(configuration.ConfigurationID) || !isGuestProductResourceReference(configuration.ExternalUpstreamIntegrationReference, "external-upstream-integration") || !validGuestProductProviderCapabilityReference(configuration.VitalServerDeliveryProvider) || !validVitalServerPacketDeliveryEndpoint(configuration.VitalServerPacketDeliveryEndpoint) || !inRange(configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds, 1, 3600000) || !validVitalServerHTTPObservationEndpoint(configuration.VitalServerObservationEndpoint) || isGuestLoopbackHost(configuration.VitalServerObservationEndpoint.Host) || configuration.VitalServerArchiveProvider.Kind != "vitalserver-indexed-library" || !validGuestProductProviderCapabilityReference(configuration.VitalServerArchiveProvider) || !validVitalServerPacketDeliveryEndpoint(configuration.VitalServerIndexedLibraryEndpoint) || !validGuestProductSecretReference(configuration.VitalServerArchiveCredentialReference) || !inRange(configuration.VitalServerArchiveRequestTimeoutMilliseconds, 1, 3600000) {
		return fmt.Errorf("C46 external VitalServer delivery configuration is invalid")
	}
	return nil
}

func validateRecorderGatewayVitalServerDeliveryResolution(resolution RecorderGatewayVitalServerDeliveryResolution) error {
	if !validVitalServerPacketDeliveryEndpoint(resolution.VitalServerPacketDeliveryEndpoint) || !validGuestProductProviderCapabilityReference(resolution.VitalServerDeliveryProvider) || !inRange(resolution.VitalServerDeliveryAcknowledgementTimeoutMilliseconds, 1, 3600000) {
		return fmt.Errorf("resolved Recorder Gateway VitalServer delivery configuration is invalid")
	}
	return nil
}

func validateGuestRuntimeProcessDeployment(deployment GuestRuntimeProcessDeployment) error {
	if !validAbsoluteGuestPath(deployment.ExecutablePath) || !validAbsoluteGuestPath(deployment.StateDatabasePath) {
		return fmt.Errorf("Guest Runtime executablePath and stateDatabasePath must be absolute Guest paths without traversal")
	}
	if !validListener(deployment.Listener) || !validPort(deployment.ControlVirtioSocketListener.Port) || !validIdentifier(deployment.ServiceVersion) || !validIdentifier(deployment.InstanceID) {
		return fmt.Errorf("Guest Runtime listener, controlVirtioSocketListener, serviceVersion, or instanceId is invalid")
	}
	if err := validateGuestPublicServiceVirtioSocketBridges(deployment.PublicServiceVirtioSocketBridges, deployment.ControlVirtioSocketListener.Port); err != nil {
		return err
	}
	if !validArchiveExportProvider(deployment.ArchiveExportProvider) || !validGuestLoopbackHTTPURL(deployment.RecorderGatewayColdPathSourceEndpoint) || !validGuestLoopbackHTTPURL(deployment.LabRecorderRunnerEndpoint) || !validExternalUpstreamObservationProvider(deployment.ExternalUpstreamObservationProvider) || !validOutboundRelayObservationProvider(deployment.OutboundRelayObservationProvider) {
		return fmt.Errorf("Guest Runtime selected provider is invalid")
	}
	if !validGuestTimeAuthority(deployment.TimeAuthority) {
		return fmt.Errorf("Guest Runtime timeAuthority is invalid")
	}
	if !validGuestTelemetryPipeline(deployment.TelemetryPipeline) {
		return fmt.Errorf("Guest Runtime telemetryPipeline is invalid")
	}
	return nil
}

func validateGuestPublicServiceVirtioSocketBridges(bridges []GuestPublicServiceVirtioSocketBridge, controlVirtioSocketPort int) error {
	if len(bridges) == 0 {
		return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridges must declare every public service route explicitly")
	}
	routeIDs := make(map[string]struct{}, len(bridges))
	virtioSocketPorts := make(map[int]struct{}, len(bridges))
	for _, bridge := range bridges {
		if !validIdentifier(bridge.RouteID) || !validIdentifier(bridge.GuestProductProcessName) || !validPort(bridge.VirtioSocketPort) || bridge.TargetHost != "127.0.0.1" || !validPort(bridge.TargetPort) {
			return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridge is invalid")
		}
		if bridge.VirtioSocketPort == controlVirtioSocketPort {
			return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridge cannot reuse the control virtio-socket port")
		}
		if _, duplicate := routeIDs[bridge.RouteID]; duplicate {
			return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridge routeId must be unique")
		}
		if _, duplicate := virtioSocketPorts[bridge.VirtioSocketPort]; duplicate {
			return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridge virtioSocketPort must be unique")
		}
		routeIDs[bridge.RouteID] = struct{}{}
		virtioSocketPorts[bridge.VirtioSocketPort] = struct{}{}
	}
	return nil
}

// validateGuestPublicServiceBridgeProcessOwnership ensures that C37 exposes
// only a listener owned by one of the exact child processes it plans. It is a
// desired-configuration equality check, not a process probe or readiness
// observation.
func validateGuestPublicServiceBridgeProcessOwnership(bridges []GuestPublicServiceVirtioSocketBridge, guestRuntimeListener GuestProductProcessListener, recorderGatewayListener GuestProductProcessListener) error {
	plannedProcessListeners := map[string]GuestProductProcessListener{
		GuestRuntimeProcessName:    guestRuntimeListener,
		RecorderGatewayProcessName: recorderGatewayListener,
	}
	for _, bridge := range bridges {
		listener, planned := plannedProcessListeners[bridge.GuestProductProcessName]
		if !planned || listener.Port != bridge.TargetPort || !guestLoopbackTargetIsAcceptedByListener(listener) {
			return fmt.Errorf("Guest Runtime publicServiceVirtioSocketBridge must name an invoked Guest Product process that listens on its target Guest-loopback socket")
		}
	}
	return nil
}

func guestLoopbackTargetIsAcceptedByListener(listener GuestProductProcessListener) bool {
	return listener.BindHost == "127.0.0.1" || listener.BindHost == "0.0.0.0"
}

func guestPublicServiceVirtioSocketBridgeArgument(bridge GuestPublicServiceVirtioSocketBridge) string {
	return bridge.RouteID + "," + strconv.Itoa(bridge.VirtioSocketPort) + "," + net.JoinHostPort(bridge.TargetHost, strconv.Itoa(bridge.TargetPort))
}

func validateRecorderGatewayProcessDeployment(deployment RecorderGatewayProcessDeployment) error {
	if !validAbsoluteGuestPath(deployment.NodeExecutablePath) || !validAbsoluteGuestPath(deployment.ProgramPath) || !validAbsoluteGuestPath(deployment.DurableIngressStateDirectory) {
		return fmt.Errorf("Recorder Gateway executable and durable ingress-state paths must be absolute Guest paths without traversal")
	}
	if !validListener(deployment.Listener) || !validAbsoluteGuestPath(deployment.VitalServerTopologyDeploymentPath) || (deployment.ExternalVitalServerDeliveryConfigurationPath != "" && !validAbsoluteGuestPath(deployment.ExternalVitalServerDeliveryConfigurationPath)) {
		return fmt.Errorf("Recorder Gateway listener, C44 topology path, or C46 external delivery configuration path is invalid")
	}
	if !inRange(deployment.DeliveryReplayAdmissionPolicy.MaximumPendingItems, 1, 10000000) || !inRange(deployment.DeliveryReplayAdmissionPolicy.MaximumPendingBytes, 1, 2147483648) || !inRange(deployment.ColdPathCapturePolicy.MaximumRetainedPackets, 1, 10000000) || !inRange(deployment.ColdPathCapturePolicy.MaximumRetainedPayloadBytes, 1, 2147483648) {
		return fmt.Errorf("Recorder Gateway deliveryReplayAdmissionPolicy or coldPathCapturePolicy is invalid")
	}
	if !inRange(deployment.ReplayPolicy.IntervalMilliseconds, 1, 3600000) || !inRange(deployment.ReplayPolicy.MaximumAttempts, 1, 1000) || !inRange(deployment.ReplayPolicy.RetryDelayMilliseconds, 1, 3600000) || !inRange(deployment.ReplayPolicy.LeaseDurationMilliseconds, 1, 3600000) {
		return fmt.Errorf("Recorder Gateway replayPolicy is invalid")
	}
	return nil
}

func validateLabRecorderRunnerProcessDeployment(deployment LabRecorderRunnerProcessDeployment) error {
	if !validAbsoluteGuestPath(deployment.NodeExecutablePath) || !validAbsoluteGuestPath(deployment.ProgramPath) || !validAbsoluteGuestPath(deployment.ScenarioCatalogPath) {
		return fmt.Errorf("Lab recorder Runner executable, program, and scenario catalog paths must be absolute Guest paths without traversal")
	}
	if deployment.Listener.BindHost != "127.0.0.1" || !validPort(deployment.Listener.Port) || !validGuestLoopbackHTTPURL(deployment.RecorderGatewayEndpoint) || !validGuestLoopbackHTTPURL(deployment.GuestRuntimeObservationCatalogEndpoint) {
		return fmt.Errorf("Lab recorder Runner listener, Recorder Gateway endpoint, and Guest Runtime observation catalog endpoint must be valid Guest-loopback values")
	}
	return nil
}

func validArchiveExportProvider(provider ArchiveExportProvider) bool {
	if !validGuestProductProviderCapabilityReference(provider.GuestProductProviderCapabilityReference) {
		return false
	}
	switch provider.Kind {
	case "archive-export-outcome-profile":
		return provider.CredentialMaterialPath == "" && provider.VitalServerConfiguration == nil && oneOf(provider.OutcomeMode, "succeed", "upload-failed", "index-failed", "upload-outcome-unknown", "index-outcome-unknown")
	case "vitalserver-indexed-library":
		return provider.OutcomeMode == "" && validAbsoluteGuestPath(provider.CredentialMaterialPath) && provider.VitalServerConfiguration != nil && validVitalServerArchiveProviderConfiguration(*provider.VitalServerConfiguration)
	default:
		return false
	}
}

func validVitalServerArchiveProviderConfiguration(configuration VitalServerArchiveProviderConfiguration) bool {
	return oneOf(configuration.Kind, "external-vitalserver-delivery-configuration", "bundled-vitalserver-topology-deployment") && validAbsoluteGuestPath(configuration.ConfigurationPath)
}

func validGuestProductSecretReference(reference GuestProductSecretReference) bool {
	return validIdentifier(reference.Kind) && validIdentifier(reference.ID)
}

func validExternalUpstreamObservationProvider(provider ExternalUpstreamObservationProvider) bool {
	if !validGuestProductProviderCapabilityReference(provider.GuestProductProviderCapabilityReference) {
		return false
	}
	switch provider.Kind {
	case "external-capability-profile":
		return provider.ExternalVitalServerDeliveryConfigurationPath == "" && provider.RequestTimeoutMilliseconds == 0 && oneOf(provider.OutcomeMode, "available", "unavailable", "failed", "unsupported", "outcome-unknown")
	case "external-vitalserver-http":
		return provider.OutcomeMode == "" && validAbsoluteGuestPath(provider.ExternalVitalServerDeliveryConfigurationPath) && inRange(provider.RequestTimeoutMilliseconds, 1, 60000)
	default:
		return false
	}
}

func validOutboundRelayObservationProvider(provider OutboundRelayObservationProvider) bool {
	return validGuestProductProviderCapabilityReference(provider.GuestProductProviderCapabilityReference) && oneOf(provider.OutcomeMode, "available", "unavailable", "failed", "unsupported", "outcome-unknown")
}

func validGuestTelemetryPipeline(pipeline GuestTelemetryPipeline) bool {
	switch pipeline.Kind {
	case "telemetry-export-outcome-profile":
		return pipeline.CollectorBaseEndpoint == "" && pipeline.RequestTimeoutMilliseconds == 0 && oneOf(pipeline.CollectorProbeOutcomeMode, "ready", "unavailable", "failed", "unsupported", "outcome-unknown") && oneOf(pipeline.ExportOutcomeMode, "exported", "dropped", "unavailable", "failed", "outcome-unknown")
	case "otlp-http":
		return pipeline.CollectorProbeOutcomeMode == "" && pipeline.ExportOutcomeMode == "" && inRange(pipeline.RequestTimeoutMilliseconds, 1, 60000) && validOTLPHTTPCollectorBaseURL(pipeline.CollectorBaseEndpoint)
	default:
		return false
	}
}

func validateGuestTelemetryCollectorDeployment(deployment GuestTelemetryCollectorDeployment) error {
	if !validAbsoluteGuestPath(deployment.ExecutablePath) || !validAbsoluteGuestPath(deployment.ConfigurationPath) {
		return fmt.Errorf("Guest telemetry Collector executable and configuration paths must be absolute Guest paths without traversal")
	}
	if deployment.OTLPHTTPListener.BindHost != "127.0.0.1" || !validPort(deployment.OTLPHTTPListener.Port) {
		return fmt.Errorf("Guest telemetry Collector OTLP listener must use one valid Guest-loopback socket")
	}
	return nil
}

func validGuestTimeAuthority(authority GuestTimeAuthority) bool {
	if !validIdentifier(authority.GuestNodeID) || !validIdentifier(authority.TimeAuthorityID) {
		return false
	}
	switch authority.Kind {
	case "time-authority-outcome-profile":
		return authority.ChronyExecutablePath == "" && authority.NTPServerHost == "" && authority.NTPServerPort == 0 && authority.RequestTimeoutMilliseconds == 0 && oneOf(authority.ProbeOutcomeMode, "synchronized", "synchronizing", "unsynchronized", "stale", "failed", "unsupported", "outcome-unknown")
	case "chrony-tracking":
		return authority.ProbeOutcomeMode == "" && validAbsoluteGuestPath(authority.ChronyExecutablePath) && inRange(authority.RequestTimeoutMilliseconds, 1, 60000) && (authority.NTPServerHost == "" || validNTPServerHost(authority.NTPServerHost)) && (authority.NTPServerPort == 0 || validPort(authority.NTPServerPort))
	default:
		return false
	}
}

func validNTPServerHost(value string) bool {
	if value == "" || len(value) > 253 || strings.HasPrefix(value, ".") || strings.HasSuffix(value, ".") || strings.Contains(value, "..") {
		return false
	}
	for _, character := range value {
		if (character < 'a' || character > 'z') && (character < 'A' || character > 'Z') && (character < '0' || character > '9') && character != '.' && character != '-' {
			return false
		}
	}
	return true
}

func validOTLPHTTPCollectorBaseURL(value string) bool {
	parsed, err := url.Parse(value)
	return err == nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Host != "" && parsed.User == nil && parsed.RawQuery == "" && parsed.Fragment == "" && (parsed.Path == "" || parsed.Path == "/")
}

func guestRuntimeTelemetryCollectorEndpointTargetsCollector(endpoint string, collectorListener GuestProductProcessListener) bool {
	return guestLoopbackEndpointTargetsListener(endpoint, collectorListener)
}

func validGuestProductProviderCapabilityReference(provider GuestProductProviderCapabilityReference) bool {
	return validIdentifier(provider.Kind) && validIdentifier(provider.ID) && provider.CapabilityRevision >= 1
}

func validVitalServerPacketDeliveryEndpoint(endpoint VitalServerPacketDeliveryEndpoint) bool {
	return oneOf(endpoint.Scheme, "http", "https") && validHost(endpoint.Host) && validPort(endpoint.Port)
}

func validVitalServerHTTPObservationEndpoint(endpoint VitalServerHTTPObservationEndpoint) bool {
	if !validVitalServerPacketDeliveryEndpoint(VitalServerPacketDeliveryEndpoint{Scheme: endpoint.Scheme, Host: endpoint.Host, Port: endpoint.Port}) || len(endpoint.Path) == 0 || len(endpoint.Path) > 2048 || endpoint.Path[0] != '/' || strings.ContainsAny(endpoint.Path, "?#") || len(endpoint.AcceptedStatusCodes) == 0 {
		return false
	}
	seen := make(map[int]struct{}, len(endpoint.AcceptedStatusCodes))
	for _, statusCode := range endpoint.AcceptedStatusCodes {
		if statusCode < 100 || statusCode > 599 {
			return false
		}
		if _, duplicate := seen[statusCode]; duplicate {
			return false
		}
		seen[statusCode] = struct{}{}
	}
	return true
}

func validGuestLoopbackHTTPURL(value string) bool {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "http" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || (parsed.Path != "" && parsed.Path != "/") {
		return false
	}
	if parsed.Hostname() != "127.0.0.1" && parsed.Hostname() != "::1" {
		return false
	}
	port, err := strconv.Atoi(parsed.Port())
	return parsed.Port() != "" && err == nil && validPort(port)
}

func guestRuntimeColdPathSourceEndpointTargetsRecorderGateway(endpoint string, recorderGatewayListener GuestProductProcessListener) bool {
	return guestLoopbackEndpointTargetsListener(endpoint, recorderGatewayListener)
}

func labRecorderRunnerGatewayEndpointTargetsRecorderGateway(endpoint string, recorderGatewayListener GuestProductProcessListener) bool {
	return guestRuntimeColdPathSourceEndpointTargetsRecorderGateway(endpoint, recorderGatewayListener)
}

func labRecorderRunnerObservationCatalogEndpointTargetsGuestRuntime(endpoint string, guestRuntimeListener GuestProductProcessListener) bool {
	return guestLoopbackEndpointTargetsListener(endpoint, guestRuntimeListener)
}

// guestLoopbackEndpointTargetsListener proves a declaration points to one
// local process listener. Callers keep their bounded-context names instead of
// borrowing another feature's endpoint semantics.
func guestLoopbackEndpointTargetsListener(endpoint string, listener GuestProductProcessListener) bool {
	if !guestLoopbackTargetIsAcceptedByListener(listener) || !validGuestLoopbackHTTPURL(endpoint) {
		return false
	}
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return false
	}
	port, err := strconv.Atoi(parsed.Port())
	return err == nil && port == listener.Port
}

func guestRuntimeLabRecorderRunnerEndpointTargetsRunner(endpoint string, runnerListener GuestProductProcessListener) bool {
	if runnerListener.BindHost != "127.0.0.1" || !validGuestLoopbackHTTPURL(endpoint) {
		return false
	}
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return false
	}
	port, err := strconv.Atoi(parsed.Port())
	return err == nil && port == runnerListener.Port
}

func isGuestProductResourceReference(reference GuestProductResourceReference, expectedResourceType string) bool {
	return reference.ResourceType == expectedResourceType && validIdentifier(reference.ResourceID)
}

func sameGuestProductResourceReference(left GuestProductResourceReference, right GuestProductResourceReference) bool {
	return left.ResourceType == right.ResourceType && left.ResourceID == right.ResourceID
}

func sameGuestProductProviderCapabilityReference(left GuestProductProviderCapabilityReference, right GuestProductProviderCapabilityReference) bool {
	return left.Kind == right.Kind && left.ID == right.ID && left.CapabilityRevision == right.CapabilityRevision
}

func isGuestLoopbackHost(value string) bool {
	return value == "127.0.0.1" || value == "::1" || value == "localhost"
}

func validListener(listener GuestProductProcessListener) bool {
	return validHost(listener.BindHost) && validPort(listener.Port)
}

func listenersConflict(left GuestProductProcessListener, right GuestProductProcessListener) bool {
	if left.Port != right.Port {
		return false
	}
	return left.BindHost == right.BindHost || left.BindHost == "0.0.0.0" || left.BindHost == "::" || right.BindHost == "0.0.0.0" || right.BindHost == "::"
}

func anyGuestProductListenersConflict(listeners []GuestProductProcessListener) bool {
	for left := 0; left < len(listeners); left++ {
		for right := left + 1; right < len(listeners); right++ {
			if listenersConflict(listeners[left], listeners[right]) {
				return true
			}
		}
	}
	return false
}

func listenerAddress(listener GuestProductProcessListener) string {
	return net.JoinHostPort(listener.BindHost, strconv.Itoa(listener.Port))
}

func validAbsoluteGuestPath(value string) bool {
	if !path.IsAbs(value) || strings.Contains(value, "\\") || len(value) > 1024 {
		return false
	}
	for _, component := range strings.Split(path.Clean(value), "/") {
		if component == ".." {
			return false
		}
	}
	return path.Clean(value) != "/"
}

func validIdentifier(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == '-' {
			if index == 0 && (character == '.' || character == '_' || character == '-') {
				return false
			}
			continue
		}
		return false
	}
	return true
}

func validHost(value string) bool {
	if value == "" || len(value) > 255 {
		return false
	}
	for index, character := range value {
		if index == 0 && !((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == ':') {
			return false
		}
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == ':' || character == '-' {
			continue
		}
		return false
	}
	return true
}

func validPort(value int) bool                         { return value >= 1 && value <= 65535 }
func inRange(value int, minimum int, maximum int) bool { return value >= minimum && value <= maximum }

func oneOf(value string, allowed ...string) bool {
	for _, candidate := range allowed {
		if value == candidate {
			return true
		}
	}
	return false
}
