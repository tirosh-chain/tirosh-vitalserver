// Package guestbundledupstreamimagesetmanagerconfigurationfile reads C64
// deployment input. No missing field becomes a Docker default.
package guestbundledupstreamimagesetmanagerconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

const configurationPathDescription = "path to the C64 Guest Bundled Upstream Image-set Manager configuration JSON document"

type DeploymentConfiguration struct {
	Listener                        guestbundledupstreamimagesetmanagerdomain.LoopbackListener
	ControlVirtioSocketListenerPort uint32
	Manager                         guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration
}

type document struct {
	SchemaVersion                   string `json:"schemaVersion"`
	ManagerID                       string `json:"managerId"`
	Listener                        struct { BindHost string `json:"bindHost"`; Port int `json:"port"` } `json:"listener"`
	ControlVirtioSocketListener     struct { Port int `json:"port"` } `json:"controlVirtioSocketListener"`
	StateDirectory                  string `json:"stateDirectory"`
	StagingDirectory                string `json:"stagingDirectory"`
	StateDirectoryMode              string `json:"stateDirectoryMode"`
	MaximumImageSetArtifactBytes    int64 `json:"maximumImageSetArtifactBytes"`
	ContainerEngine                 struct { Kind string `json:"kind"`; ExecutablePath string `json:"executablePath"`; ComposeProjectName string `json:"composeProjectName"` } `json:"containerEngine"`
}

func ConfigurationPathDescription() string { return configurationPathDescription }

func LoadImageSetManagerConfiguration(configurationPath string) (DeploymentConfiguration, error) {
	if configurationPath == "" { return DeploymentConfiguration{}, fmt.Errorf("C64 Guest Bundled Upstream Image-set Manager configuration path is required") }
	file, err := os.Open(configurationPath)
	if err != nil { return DeploymentConfiguration{}, fmt.Errorf("open C64 configuration: %w", err) }
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var value document
	if err := decoder.Decode(&value); err != nil { return DeploymentConfiguration{}, fmt.Errorf("decode C64 configuration: %w", err) }
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) { return DeploymentConfiguration{}, fmt.Errorf("C64 configuration contains multiple documents") }
	if value.SchemaVersion != guestbundledupstreamimagesetmanagerdomain.SchemaVersion || value.ContainerEngine.Kind != "docker-cli" { return DeploymentConfiguration{}, fmt.Errorf("C64 configuration schema version or container engine kind is unsupported") }
	listener := guestbundledupstreamimagesetmanagerdomain.LoopbackListener{BindHost: value.Listener.BindHost, Port: value.Listener.Port}
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateLoopbackListener(listener); err != nil { return DeploymentConfiguration{}, err }
	// TCP loopback and AF_VSOCK are distinct Guest transports, so using the
	// same declared port is intentional and matches the C32 bridge contract.
	if value.ControlVirtioSocketListener.Port < 1 || value.ControlVirtioSocketListener.Port > 65535 { return DeploymentConfiguration{}, fmt.Errorf("C64 control virtio-socket listener port must be between 1 and 65535") }
	manager := guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration{ManagerID: value.ManagerID, StateDirectory: value.StateDirectory, StagingDirectory: value.StagingDirectory, StateDirectoryMode: value.StateDirectoryMode, MaximumImageSetArtifactBytes: value.MaximumImageSetArtifactBytes, ContainerEngineExecutablePath: value.ContainerEngine.ExecutablePath, ContainerEngineComposeProjectID: value.ContainerEngine.ComposeProjectName}
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateManagerConfiguration(manager); err != nil { return DeploymentConfiguration{}, err }
	return DeploymentConfiguration{Listener: listener, ControlVirtioSocketListenerPort: uint32(value.ControlVirtioSocketListener.Port), Manager: manager}, nil
}

func ParseImageSetUpdateCommand(source io.Reader) (guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, error) {
	decoder := json.NewDecoder(source)
	decoder.DisallowUnknownFields()
	var command guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand
	if err := decoder.Decode(&command); err != nil { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, fmt.Errorf("decode C64 image-set update command: %w", err) }
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{}, fmt.Errorf("C64 image-set update command contains multiple documents") }
	return command, nil
}
