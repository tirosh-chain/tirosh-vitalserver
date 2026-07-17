package hostdeployment

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
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
	ListenAddress            string `json:"listenAddress"`
	StateDatabasePath        string `json:"stateDatabasePath"`
	GuestTimeoutMilliseconds int    `json:"guestTimeoutMilliseconds"`
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
	Kind                                        string `json:"kind"`
	ID                                          string `json:"id"`
	NativeProviderBridgeExecutablePath          string `json:"nativeProviderBridgeExecutablePath"`
	MacOSVirtualMachineSupervisorExecutablePath string `json:"macOSVirtualMachineSupervisorExecutablePath"`
	MacOSVirtualMachineConfigurationPath        string `json:"macOSVirtualMachineConfigurationPath"`
	NativeVirtualMachineName                    string `json:"nativeVirtualMachineName"`
	HostServiceName                             string `json:"hostServiceName"`
}

type HostTimeConfiguration struct {
	HostNodeID      string `json:"hostNodeId"`
	TimeAuthorityID string `json:"timeAuthorityId"`
	ProviderMode    string `json:"providerMode"`
}

type HostTelemetryConfiguration struct {
	PipelineMode string `json:"pipelineMode"`
	ExportMode   string `json:"exportMode"`
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
	if !isExplicitText(configuration.Control.ListenAddress) || !isSafeHostAbsolutePath(configuration.Control.StateDatabasePath) || configuration.Control.GuestTimeoutMilliseconds < 1 || configuration.Control.GuestTimeoutMilliseconds > 120000 {
		return fmt.Errorf("control listenAddress, stateDatabasePath, and guestTimeoutMilliseconds must be explicit and valid")
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
		if !isSafeHostAbsolutePath(configuration.Provider.MacOSVirtualMachineConfigurationPath) || !isSafeHostAbsolutePath(configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath) || isExplicitText(configuration.Provider.NativeProviderBridgeExecutablePath) || isExplicitText(configuration.Provider.NativeVirtualMachineName) || isExplicitText(configuration.Provider.HostServiceName) {
			return fmt.Errorf("macOS provider requires C32 and supervisor paths without native provider bridge resource names")
		}
	} else if !isSafeHostAbsolutePath(configuration.Provider.NativeProviderBridgeExecutablePath) || !isDeploymentIdentifier(configuration.Provider.NativeVirtualMachineName) || !isDeploymentIdentifier(configuration.Provider.HostServiceName) || isExplicitText(configuration.Provider.MacOSVirtualMachineConfigurationPath) || isExplicitText(configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath) {
		return fmt.Errorf("native provider requires its bridge, virtual machine, and Host service names without macOS deployment inputs")
	}
	if !isDeploymentIdentifier(configuration.Time.HostNodeID) || !isDeploymentIdentifier(configuration.Time.TimeAuthorityID) || !contains(hostTimeProviderModes, configuration.Time.ProviderMode) {
		return fmt.Errorf("Host time node, authority, and provider mode must be explicit and valid")
	}
	if !contains(hostTelemetryPipelineModes, configuration.Telemetry.PipelineMode) || !contains(hostTelemetryExportModes, configuration.Telemetry.ExportMode) {
		return fmt.Errorf("Host telemetry pipeline and export modes must be explicit and valid")
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
		MacOSVirtualMachineSupervisorExecutablePath: configuration.Provider.MacOSVirtualMachineSupervisorExecutablePath,
		MacOSVirtualMachineConfigurationPath:        configuration.Provider.MacOSVirtualMachineConfigurationPath,
		NativeVirtualMachineName:                    configuration.Provider.NativeVirtualMachineName,
		HostServiceName:                             configuration.Provider.HostServiceName,
	}
}

var deploymentIdentifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

var hostTimeProviderModes = []string{"synchronized", "synchronizing", "unsynchronized", "stale", "failed", "unsupported", "outcome-unknown"}
var hostTelemetryPipelineModes = []string{"ready", "unavailable", "failed", "unsupported", "outcome-unknown"}
var hostTelemetryExportModes = []string{"exported", "dropped", "unavailable", "failed", "outcome-unknown"}

func isDeploymentIdentifier(value string) bool {
	return deploymentIdentifierPattern.MatchString(value)
}

func isSafeHostAbsolutePath(value string) bool {
	if !filepath.IsAbs(value) || strings.Contains(value, `\`) {
		return false
	}
	for _, component := range strings.Split(value, "/") {
		if component == ".." {
			return false
		}
	}
	return true
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
