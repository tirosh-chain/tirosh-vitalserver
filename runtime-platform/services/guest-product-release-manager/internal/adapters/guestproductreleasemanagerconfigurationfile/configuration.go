// Package guestproductreleasemanagerconfigurationfile reads the C59 desired
// deployment document. It converts no missing value into a default: a
// manager cannot expose a release mutation endpoint without every declared
// ownership and health-check value.
package guestproductreleasemanagerconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

const releaseManagerConfigurationPathDescription = "path to the C59 Guest Product Release Manager configuration JSON document"

// DeploymentConfiguration contains the explicit network binding plus the
// pure manager configuration. The listener is deliberately not folded into
// the domain policy because opening a socket is an adapter responsibility.
type DeploymentConfiguration struct {
	Listener                        guestproductreleasemanagerdomain.LoopbackListener
	ControlVirtioSocketListenerPort uint32
	Manager                         guestproductreleasemanagerdomain.ManagerConfiguration
}

type configurationDocument struct {
	SchemaVersion               string                       `json:"schemaVersion"`
	ManagerID                   string                       `json:"managerId"`
	Listener                    listenerDocument             `json:"listener"`
	ControlVirtioSocketListener virtioSocketListenerDocument `json:"controlVirtioSocketListener"`
	ReleaseDirectoryRoot        string                       `json:"releaseDirectoryRoot"`
	CurrentReleaseLinkPath      string                       `json:"currentReleaseLinkPath"`
	StagingDirectory            string                       `json:"stagingDirectory"`
	StateDirectory              string                       `json:"stateDirectory"`
	StateDirectoryMode          string                       `json:"stateDirectoryMode"`
	MaximumReleaseArtifactBytes int64                        `json:"maximumReleaseArtifactBytes"`
	ServiceManagement           serviceManagementDocument    `json:"serviceManagement"`
	HealthCheck                 healthCheckDocument          `json:"healthCheck"`
}

type listenerDocument struct {
	BindHost string `json:"bindHost"`
	Port     int    `json:"port"`
}

// virtioSocketListenerDocument deliberately contains only a port. The Guest
// does not own a Host address for this boundary: macOS C32 owns the matching
// Host-loopback listener and connects it to this Guest AF_VSOCK port.
type virtioSocketListenerDocument struct {
	Port int `json:"port"`
}

type serviceManagementDocument struct {
	SystemctlExecutablePath    string `json:"systemctlExecutablePath"`
	ManagedServiceUnitName     string `json:"managedServiceUnitName"`
	RestartTimeoutMilliseconds int    `json:"restartTimeoutMilliseconds"`
}

type healthCheckDocument struct {
	Scheme              string `json:"scheme"`
	Host                string `json:"host"`
	Port                int    `json:"port"`
	Path                string `json:"path"`
	AcceptedStatusCodes []int  `json:"acceptedStatusCodes"`
	TimeoutMilliseconds int    `json:"timeoutMilliseconds"`
}

func GuestProductReleaseManagerConfigurationPathDescription() string {
	return releaseManagerConfigurationPathDescription
}

func LoadGuestProductReleaseManagerConfiguration(configurationPath string) (DeploymentConfiguration, error) {
	if configurationPath == "" {
		return DeploymentConfiguration{}, fmt.Errorf("C59 Guest Product Release Manager configuration path is required")
	}
	file, err := os.Open(configurationPath)
	if err != nil {
		return DeploymentConfiguration{}, fmt.Errorf("open C59 Guest Product Release Manager configuration: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var document configurationDocument
	if err := decoder.Decode(&document); err != nil {
		return DeploymentConfiguration{}, fmt.Errorf("decode C59 Guest Product Release Manager configuration: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return DeploymentConfiguration{}, fmt.Errorf("C59 Guest Product Release Manager configuration contains multiple documents")
	}
	if document.SchemaVersion != guestproductreleasemanagerdomain.SchemaVersion {
		return DeploymentConfiguration{}, fmt.Errorf("C59 Guest Product Release Manager configuration schema version is unsupported")
	}
	listener := guestproductreleasemanagerdomain.LoopbackListener{BindHost: document.Listener.BindHost, Port: document.Listener.Port}
	if document.ControlVirtioSocketListener.Port < 1 || document.ControlVirtioSocketListener.Port > 65535 {
		return DeploymentConfiguration{}, fmt.Errorf("C59 Guest Product Release Manager control virtio-socket listener port must be between 1 and 65535")
	}
	manager := guestproductreleasemanagerdomain.ManagerConfiguration{
		ManagerID:                      document.ManagerID,
		ReleaseDirectoryRoot:           document.ReleaseDirectoryRoot,
		CurrentReleaseLinkPath:         document.CurrentReleaseLinkPath,
		StagingDirectory:               document.StagingDirectory,
		StateDirectory:                 document.StateDirectory,
		StateDirectoryMode:             document.StateDirectoryMode,
		MaximumReleaseArtifactBytes:    document.MaximumReleaseArtifactBytes,
		SystemctlExecutablePath:        document.ServiceManagement.SystemctlExecutablePath,
		ManagedServiceUnitName:         document.ServiceManagement.ManagedServiceUnitName,
		RestartTimeoutMilliseconds:     document.ServiceManagement.RestartTimeoutMilliseconds,
		HealthCheckURL:                 document.HealthCheck.Scheme + "://" + document.HealthCheck.Host + ":" + fmt.Sprint(document.HealthCheck.Port) + document.HealthCheck.Path,
		HealthCheckTimeoutMilliseconds: document.HealthCheck.TimeoutMilliseconds,
		HealthCheckAcceptedStatusCodes: document.HealthCheck.AcceptedStatusCodes,
	}
	if err := guestproductreleasemanagerdomain.ValidateLoopbackListener(listener); err != nil {
		return DeploymentConfiguration{}, err
	}
	if document.HealthCheck.Scheme != "http" || document.HealthCheck.Host != "127.0.0.1" || document.HealthCheck.Port < 1 || document.HealthCheck.Port > 65535 || document.HealthCheck.Path != "/v1/runtime/readiness" {
		return DeploymentConfiguration{}, fmt.Errorf("C59 Guest Product Release Manager health check endpoint is invalid")
	}
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(manager); err != nil {
		return DeploymentConfiguration{}, err
	}
	return DeploymentConfiguration{
		Listener:                        listener,
		ControlVirtioSocketListenerPort: uint32(document.ControlVirtioSocketListener.Port),
		Manager:                         manager,
	}, nil
}

// ParseReleaseUpdateCommand decodes just the multipart command part. It is
// exported for the HTTP adapter and keeps duplicate/unknown JSON rejection in
// one explicit transport boundary.
func ParseReleaseUpdateCommand(source io.Reader) (guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, error) {
	decoder := json.NewDecoder(source)
	decoder.DisallowUnknownFields()
	var command guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand
	if err := decoder.Decode(&command); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, fmt.Errorf("decode C59 release update command: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{}, fmt.Errorf("C59 release update command contains multiple documents")
	}
	return command, nil
}

func IsReleaseUpdateCommandPartName(value string) bool { return strings.TrimSpace(value) == "command" }
