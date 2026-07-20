package hostdeployment

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// HostAgentDeploymentConfiguration is C33 as consumed by the Host Agent
// process. It is a deployment input, not Host runtime state. Host SQLite keeps
// C7/C8/C2 runtime resources after this configuration has been validated.
type HostAgentDeploymentConfiguration struct {
	SchemaVersion               string                                   `json:"schemaVersion"`
	Control                     HostAgentControlConfiguration            `json:"control"`
	Installation                HostInstallationConfiguration            `json:"installation"`
	GuestRuntimeControlEndpoint GuestRuntimeControlEndpointConfiguration `json:"guestRuntimeControlEndpoint"`
	Provider                    SelectedProviderConfiguration            `json:"provider"`
	Time                        HostTimeConfiguration                    `json:"time"`
	Telemetry                   HostTelemetryConfiguration               `json:"telemetry"`
	UpdateBootstrap             HostUpdateBootstrapConfiguration         `json:"updateBootstrap"`
}

type HostAgentControlConfiguration struct {
	LocalAdministration      HostLocalAdministrationConfiguration `json:"localAdministration"`
	LoopbackHTTP             HostAgentLoopbackHTTPConfiguration   `json:"loopbackHTTP"`
	StateDatabasePath        string                               `json:"stateDatabasePath"`
	GuestTimeoutMilliseconds int                                  `json:"guestTimeoutMilliseconds"`
}

// HostLocalAdministrationConfiguration is the C33 desired local-control
// transport. The Host Agent owns its listener and C52 descriptor. Interfaces
// consume C52 and do not read this deployment input.
type HostLocalAdministrationConfiguration struct {
	Transport          string `json:"transport"`
	EndpointAddress    string `json:"endpointAddress"`
	DescriptorPath     string `json:"descriptorPath"`
	AuthorizedUserID   *int   `json:"authorizedUserId"`
	SecurityDescriptor string `json:"securityDescriptor"`
}

// HostAgentLoopbackHTTPConfiguration is an explicitly opt-in development
// facade. A released product must use localAdministration; an unprotected
// loopback port is never the administrator authorization boundary.
type HostAgentLoopbackHTTPConfiguration struct {
	Mode          string `json:"mode"`
	ListenAddress string `json:"listenAddress"`
}

type HostInstallationConfiguration struct {
	InstallationID string `json:"installationId"`
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
	DataDirectory  string `json:"dataDirectory"`
}

type GuestRuntimeControlEndpointConfiguration struct {
	ID     string `json:"id"`
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

type SelectedProviderConfiguration struct {
	Kind                                            string `json:"kind"`
	ID                                              string `json:"id"`
	NativeProviderBridgeExecutablePath              string `json:"nativeProviderBridgeExecutablePath"`
	MacOSVirtualMachineSupervisorExecutablePath     string `json:"macOSVirtualMachineSupervisorExecutablePath"`
	MacOSVirtualMachineConfigurationPath            string `json:"macOSVirtualMachineConfigurationPath"`
	NativeVirtualMachineName                        string `json:"nativeVirtualMachineName"`
	HostServiceName                                 string `json:"hostServiceName"`
	NativeGuestMachineOwnership                     string `json:"nativeGuestMachineOwnership"`
	NativeGuestMachineProvisioningConfigurationPath string `json:"nativeGuestMachineProvisioningConfigurationPath"`
}

type HostTimeConfiguration struct {
	HostNodeID                     string  `json:"hostNodeId"`
	TimeAuthorityID                string  `json:"timeAuthorityId"`
	Kind                           string  `json:"kind"`
	NTPServerAddress               string  `json:"ntpServerAddress"`
	SourceProfile                  string  `json:"sourceProfile"`
	SourceID                       string  `json:"sourceId"`
	RequestTimeoutMilliseconds     int     `json:"requestTimeoutMilliseconds"`
	MaximumOffsetMilliseconds      float64 `json:"maximumOffsetMilliseconds"`
	MaximumUncertaintyMilliseconds float64 `json:"maximumUncertaintyMilliseconds"`
	ProviderMode                   string  `json:"providerMode"`
}

type HostTelemetryConfiguration struct {
	Kind                       string `json:"kind"`
	CollectorBaseEndpoint      string `json:"collectorBaseEndpoint"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
	PipelineMode               string `json:"pipelineMode"`
	ExportMode                 string `json:"exportMode"`
}

type HostUpdateBootstrapConfiguration struct {
	Mode                 string `json:"mode"`
	BundleStoreDirectory string `json:"bundleStoreDirectory"`
	StagingDirectory     string `json:"stagingDirectory"`
	TrustStorePath       string `json:"trustStorePath"`
}

// DeploymentConfigurationUnavailableError preserves a filesystem read failure
// as unavailable startup input. It must never be converted to an empty service
// configuration.
type DeploymentConfigurationUnavailableError struct{ reason string }

func (failure DeploymentConfigurationUnavailableError) Error() string {
	return "Host Agent deployment configuration is unavailable: " + failure.reason
}

// DeploymentConfigurationInvalidError preserves malformed or semantically
// incomplete C33 as invalid startup input.
type DeploymentConfigurationInvalidError struct{ reason string }

func (failure DeploymentConfigurationInvalidError) Error() string {
	return "Host Agent deployment configuration is invalid: " + failure.reason
}

// LoadHostAgentDeploymentConfiguration loads one explicit C33 document. It
// does not create configuration, directories, or state when the document is
// absent or invalid.
func LoadHostAgentDeploymentConfiguration(path string) (HostAgentDeploymentConfiguration, error) {
	if !isSafeHostAbsolutePath(path) {
		return HostAgentDeploymentConfiguration{}, DeploymentConfigurationInvalidError{reason: "configuration path must be an absolute path without traversal"}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			return HostAgentDeploymentConfiguration{}, DeploymentConfigurationUnavailableError{reason: "configuration file cannot be read"}
		}
		return HostAgentDeploymentConfiguration{}, DeploymentConfigurationUnavailableError{reason: "configuration file read failed"}
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	var configuration HostAgentDeploymentConfiguration
	if err := decoder.Decode(&configuration); err != nil {
		return HostAgentDeploymentConfiguration{}, DeploymentConfigurationInvalidError{reason: "configuration JSON is invalid"}
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return HostAgentDeploymentConfiguration{}, DeploymentConfigurationInvalidError{reason: "configuration must contain exactly one JSON document"}
	}
	if err := configuration.Validate(); err != nil {
		return HostAgentDeploymentConfiguration{}, DeploymentConfigurationInvalidError{reason: err.Error()}
	}
	return configuration, nil
}

// Validate checks C33 rules that must remain explicit at the Host process
// boundary. JSON Schema validates release documents; this check protects a
// running service from an independently edited deployment file.
func (configuration HostAgentDeploymentConfiguration) Validate() error {
	if configuration.SchemaVersion != "v1" {
		return fmt.Errorf("schemaVersion must be v1")
	}
	if !isSafeHostAbsolutePath(configuration.Control.StateDatabasePath) || configuration.Control.GuestTimeoutMilliseconds < 1 || configuration.Control.GuestTimeoutMilliseconds > 120000 {
		return fmt.Errorf("control stateDatabasePath and guestTimeoutMilliseconds must be explicit and valid")
	}
	if err := configuration.Control.LocalAdministration.Validate(); err != nil {
		return fmt.Errorf("local administration configuration is invalid: %w", err)
	}
	if err := configuration.Control.LoopbackHTTP.Validate(); err != nil {
		return fmt.Errorf("loopback HTTP configuration is invalid: %w", err)
	}
	if !isDeploymentIdentifier(configuration.Installation.InstallationID) || !isExplicitText(configuration.Installation.ProductVersion) || !isExplicitText(configuration.Installation.RuntimeVersion) || !isSafeHostAbsolutePath(configuration.Installation.DataDirectory) {
		return fmt.Errorf("installation identity, versions, and dataDirectory must be explicit and valid")
	}
	if !isDeploymentIdentifier(configuration.GuestRuntimeControlEndpoint.ID) || (configuration.GuestRuntimeControlEndpoint.Scheme != "http" && configuration.GuestRuntimeControlEndpoint.Scheme != "https") || !isExplicitText(configuration.GuestRuntimeControlEndpoint.Host) || configuration.GuestRuntimeControlEndpoint.Port < 1 || configuration.GuestRuntimeControlEndpoint.Port > 65535 {
		return fmt.Errorf("Guest Runtime Control endpoint identity, scheme, host, and port must be explicit and valid")
	}
	if !hostagentdomain.ValidPlatformProviderKind(configuration.Provider.Kind) || !isDeploymentIdentifier(configuration.Provider.ID) {
		return fmt.Errorf("selected provider kind and identity must be explicit and valid")
	}
	if configuration.Provider.Kind == hostagentdomain.MacOSVirtualizationProviderKind {
		if !isSafeHostAbsolutePath(configuration.Provider.MacOSVirtualMachineConfigurationPath) || !isSafeHostAbsolutePath(configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath) || isExplicitText(configuration.Provider.NativeProviderBridgeExecutablePath) || isExplicitText(configuration.Provider.NativeVirtualMachineName) || isExplicitText(configuration.Provider.HostServiceName) || isExplicitText(configuration.Provider.NativeGuestMachineOwnership) || isExplicitText(configuration.Provider.NativeGuestMachineProvisioningConfigurationPath) {
			return fmt.Errorf("macOS provider requires C32 and supervisor paths without native provider bridge resource names")
		}
	} else if !isSafeHostAbsolutePath(configuration.Provider.NativeProviderBridgeExecutablePath) || !isDeploymentIdentifier(configuration.Provider.NativeVirtualMachineName) || !isDeploymentIdentifier(configuration.Provider.HostServiceName) || isExplicitText(configuration.Provider.MacOSVirtualMachineConfigurationPath) || isExplicitText(configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath) {
		return fmt.Errorf("native provider requires its bridge, virtual machine, and Host service names without macOS deployment inputs")
	} else if configuration.Provider.NativeGuestMachineOwnership == "runtime-platform-provisioned" {
		if !isSafeHostAbsolutePath(configuration.Provider.NativeGuestMachineProvisioningConfigurationPath) {
			return fmt.Errorf("runtime-platform-provisioned native Guest requires an explicit C62 provisioning configuration path")
		}
	} else if configuration.Provider.NativeGuestMachineOwnership == "externally-provisioned" {
		if isExplicitText(configuration.Provider.NativeGuestMachineProvisioningConfigurationPath) {
			return fmt.Errorf("externally-provisioned native Guest must not include a C62 provisioning configuration path")
		}
	} else {
		return fmt.Errorf("native provider Guest ownership must be runtime-platform-provisioned or externally-provisioned")
	}
	if !isDeploymentIdentifier(configuration.Time.HostNodeID) || !isDeploymentIdentifier(configuration.Time.TimeAuthorityID) {
		return fmt.Errorf("Host time node and authority must be explicit and valid")
	}
	switch configuration.Time.Kind {
	case "time-authority-outcome-profile":
		if !contains(hostTimeProviderModes, configuration.Time.ProviderMode) || isExplicitText(configuration.Time.NTPServerAddress) || isExplicitText(configuration.Time.SourceProfile) || isExplicitText(configuration.Time.SourceID) || configuration.Time.RequestTimeoutMilliseconds != 0 || configuration.Time.MaximumOffsetMilliseconds != 0 || configuration.Time.MaximumUncertaintyMilliseconds != 0 {
			return fmt.Errorf("Host time outcome profile requires providerMode without NTP probe inputs")
		}
	case "ntp-udp-quality-probe":
		if !isExplicitHostPort(configuration.Time.NTPServerAddress) || (configuration.Time.SourceProfile != "enterprise-ntp" && configuration.Time.SourceProfile != "helper-ntp") || !isDeploymentIdentifier(configuration.Time.SourceID) || configuration.Time.RequestTimeoutMilliseconds < 1 || configuration.Time.RequestTimeoutMilliseconds > 60000 || configuration.Time.MaximumOffsetMilliseconds < 0 || configuration.Time.MaximumUncertaintyMilliseconds < 0 || isExplicitText(configuration.Time.ProviderMode) {
			return fmt.Errorf("Host NTP UDP probe requires endpoint, source identity, timeout, and quality thresholds without providerMode")
		}
	default:
		return fmt.Errorf("Host time kind must be time-authority-outcome-profile or ntp-udp-quality-probe")
	}
	switch configuration.Telemetry.Kind {
	case "telemetry-export-outcome-profile":
		if !contains(hostTelemetryPipelineModes, configuration.Telemetry.PipelineMode) || !contains(hostTelemetryExportModes, configuration.Telemetry.ExportMode) || isExplicitText(configuration.Telemetry.CollectorBaseEndpoint) || configuration.Telemetry.RequestTimeoutMilliseconds != 0 {
			return fmt.Errorf("Host telemetry outcome profile requires pipeline/export modes without a Collector endpoint")
		}
	case "otlp-http":
		if !isExplicitHTTPBaseURL(configuration.Telemetry.CollectorBaseEndpoint) || configuration.Telemetry.RequestTimeoutMilliseconds < 1 || configuration.Telemetry.RequestTimeoutMilliseconds > 60000 || isExplicitText(configuration.Telemetry.PipelineMode) || isExplicitText(configuration.Telemetry.ExportMode) {
			return fmt.Errorf("Host OTLP telemetry requires an explicit Collector base endpoint and timeout without outcome profile modes")
		}
	default:
		return fmt.Errorf("Host telemetry kind must be telemetry-export-outcome-profile or otlp-http")
	}
	switch configuration.UpdateBootstrap.Mode {
	case "unavailable":
		if isExplicitText(configuration.UpdateBootstrap.BundleStoreDirectory) || isExplicitText(configuration.UpdateBootstrap.StagingDirectory) || isExplicitText(configuration.UpdateBootstrap.TrustStorePath) {
			return fmt.Errorf("unavailable update bootstrap must not include staged update paths")
		}
	case "staged":
		if !isSafeHostAbsolutePath(configuration.UpdateBootstrap.BundleStoreDirectory) || !isSafeHostAbsolutePath(configuration.UpdateBootstrap.StagingDirectory) || !isSafeHostAbsolutePath(configuration.UpdateBootstrap.TrustStorePath) {
			return fmt.Errorf("staged update bootstrap requires explicit safe bundle, staging, and trust-store paths")
		}
	default:
		return fmt.Errorf("update bootstrap mode must be unavailable or staged")
	}
	return nil
}

func (configuration HostAgentDeploymentConfiguration) GuestTimeout() time.Duration {
	return time.Duration(configuration.Control.GuestTimeoutMilliseconds) * time.Millisecond
}

func (configuration HostAgentDeploymentConfiguration) SelectedPlatformProviderProcessDeployment() SelectedPlatformProviderProcessDeployment {
	return SelectedPlatformProviderProcessDeployment{
		ProviderKind:                       configuration.Provider.Kind,
		ProviderID:                         configuration.Provider.ID,
		NativeProviderBridgeExecutablePath: configuration.Provider.NativeProviderBridgeExecutablePath,
		MacOSVirtualMachineSupervisorExecutablePath:     configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath,
		MacOSVirtualMachineConfigurationPath:            configuration.Provider.MacOSVirtualMachineConfigurationPath,
		NativeVirtualMachineName:                        configuration.Provider.NativeVirtualMachineName,
		HostServiceName:                                 configuration.Provider.HostServiceName,
		NativeGuestMachineProvisioningConfigurationPath: configuration.Provider.NativeGuestMachineProvisioningConfigurationPath,
	}
}

var deploymentIdentifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
var windowsAbsolutePathPattern = regexp.MustCompile(`^[A-Za-z]:[\\/].*$`)

var hostTimeProviderModes = []string{"synchronized", "synchronizing", "unsynchronized", "stale", "failed", "unsupported", "outcome-unknown"}
var hostTelemetryPipelineModes = []string{"ready", "unavailable", "failed", "unsupported", "outcome-unknown"}
var hostTelemetryExportModes = []string{"exported", "dropped", "unavailable", "failed", "outcome-unknown"}

func isDeploymentIdentifier(value string) bool {
	return deploymentIdentifierPattern.MatchString(value)
}

func isSafeHostAbsolutePath(value string) bool {
	if strings.ContainsRune(value, '\x00') || strings.TrimSpace(value) != value {
		return false
	}
	isPOSIXAbsolute := filepath.IsAbs(value) && strings.HasPrefix(value, "/") && !strings.Contains(value, `\`)
	isWindowsAbsolute := windowsAbsolutePathPattern.MatchString(value)
	if !isPOSIXAbsolute && !isWindowsAbsolute {
		return false
	}
	for _, component := range strings.FieldsFunc(value, func(character rune) bool { return character == '/' || character == '\\' }) {
		if component == ".." {
			return false
		}
	}
	return true
}

func isExplicitHTTPBaseURL(value string) bool {
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return false
	}
	return parsed.User == nil && parsed.RawQuery == "" && parsed.Fragment == "" && (parsed.Path == "" || parsed.Path == "/")
}

func isExplicitHostPort(value string) bool {
	if strings.TrimSpace(value) != value {
		return false
	}
	host, port, err := net.SplitHostPort(value)
	if err != nil || host == "" || port == "" {
		return false
	}
	parsedPort, err := net.LookupPort("udp", port)
	return err == nil && parsedPort >= 1 && parsedPort <= 65535
}

// Validate keeps OS-local administration transport selection explicit. It is
// a deployment boundary check, not an authorization decision: the selected
// adapter enforces peer identity or Windows ACLs while accepting connections.
func (configuration HostLocalAdministrationConfiguration) Validate() error {
	if !isSafeHostAbsolutePath(configuration.DescriptorPath) {
		return errors.New("descriptorPath must be a safe absolute Host path")
	}
	switch configuration.Transport {
	case "unix-domain-socket":
		if !isSafeUnixDomainSocketAddress(configuration.EndpointAddress) || configuration.AuthorizedUserID == nil || *configuration.AuthorizedUserID < 0 || *configuration.AuthorizedUserID > 2147483647 || isExplicitText(configuration.SecurityDescriptor) {
			return errors.New("unix-domain-socket requires endpointAddress and authorizedUserId without a Windows securityDescriptor")
		}
	case "windows-named-pipe":
		if !isWindowsNamedPipeAddress(configuration.EndpointAddress) || !isExplicitText(configuration.SecurityDescriptor) || !strings.HasPrefix(configuration.SecurityDescriptor, "D:") || configuration.AuthorizedUserID != nil {
			return errors.New("windows-named-pipe requires endpointAddress and DACL securityDescriptor without authorizedUserId")
		}
	default:
		return errors.New("transport must be unix-domain-socket or windows-named-pipe")
	}
	return nil
}

// Validate permits only disabled loopback HTTP or a numeric loopback address
// for deliberately opted-in development diagnostics. It never accepts a
// hostname or non-loopback network listener.
func (configuration HostAgentLoopbackHTTPConfiguration) Validate() error {
	switch configuration.Mode {
	case "disabled":
		if isExplicitText(configuration.ListenAddress) {
			return errors.New("disabled loopbackHTTP must not contain listenAddress")
		}
		return nil
	case "development-loopback":
		host, port, err := net.SplitHostPort(configuration.ListenAddress)
		if err != nil || port == "" || (host != "127.0.0.1" && host != "::1") {
			return errors.New("development-loopback requires explicit numeric 127.0.0.1 or ::1 listenAddress")
		}
		return nil
	default:
		return errors.New("mode must be disabled or development-loopback")
	}
}

func isSafeUnixDomainSocketAddress(value string) bool {
	return strings.HasPrefix(value, "/") && !strings.Contains(value, `\`) && !strings.ContainsRune(value, '\x00') && len(value) <= 104 && isSafeHostAbsolutePath(value)
}

func isWindowsNamedPipeAddress(value string) bool {
	const namedPipePrefix = `\\.\pipe\`
	if !strings.HasPrefix(value, namedPipePrefix) {
		return false
	}
	return deploymentIdentifierPattern.MatchString(strings.TrimPrefix(value, namedPipePrefix))
}

func isExplicitText(value string) bool {
	return strings.TrimSpace(value) != ""
}

func contains(values []string, candidate string) bool {
	for _, value := range values {
		if value == candidate {
			return true
		}
	}
	return false
}
