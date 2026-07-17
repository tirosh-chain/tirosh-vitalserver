// Package guestproductbootstrapartifactcompositionapplication owns the C35
// release-build workflow. It copies declared boot/root artifacts and composes
// the declared NoCloud bootstrap volume; it never writes a Guest root.
package guestproductbootstrapartifactcompositionapplication

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapplancomposer"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/nocloudguestproductbootstrapvolumeadapter"
)

const (
	maximumCompilationCommandBytes = 1 << 20
	generatedSystemdUnitSourceID   = "guest-product-systemd-unit"
)

// GuestProductBootstrapArtifactCompositionExecution declares every Host-side
// effect path. The caller chooses these paths; no release directory, cache, or
// mounted Guest filesystem is discovered.
type GuestProductBootstrapArtifactCompositionExecution struct {
	GuestArtifactCompilationCommandPath string
	InputRoot                           string
	OutputDirectory                     string
}

// GuestProductBootstrapArtifactCompositionError retains C35 identity and the
// failed workflow stage so a build failure cannot masquerade as a Guest image.
type GuestProductBootstrapArtifactCompositionError struct {
	CompilationID string
	Stage         string
	Reason        string
}

func (err GuestProductBootstrapArtifactCompositionError) Error() string {
	compilationID := err.CompilationID
	if compilationID == "" {
		compilationID = "unknown"
	}
	return "Guest Product bootstrap artifact composition failed compilationId=" + compilationID + " stage=" + err.Stage + " reason=" + err.Reason
}

type declaredInputArtifact struct {
	ID                string `json:"id"`
	InputRelativePath string `json:"inputRelativePath"`
	SizeBytes         int64  `json:"sizeBytes"`
	SHA256            string `json:"sha256"`
}

type declaredBootArtifactOutput struct {
	Source             declaredInputArtifact `json:"source"`
	OutputRelativePath string                `json:"outputRelativePath"`
}

type declaredStorageArtifactOutput struct {
	ID                    string                 `json:"id"`
	Role                  string                 `json:"role"`
	StorageImageFormat    string                 `json:"storageImageFormat"`
	GuestVolumeFileSystem string                 `json:"guestVolumeFileSystem,omitempty"`
	ReadOnly              bool                   `json:"readOnly"`
	BaseImage             *declaredInputArtifact `json:"baseImage,omitempty"`
	OutputRelativePath    string                 `json:"outputRelativePath"`
}

// guestArtifactCompilationCommand is the exact C35 view consumed by this
// selected C35 composer. Its desired state is fully supplied by the command.
type guestArtifactCompilationCommand struct {
	SchemaVersion    string `json:"schemaVersion"`
	CompilationID    string `json:"compilationId"`
	ArtifactSetID    string `json:"artifactSetId"`
	Architecture     string `json:"architecture"`
	BuildEnvironment struct {
		ID                         string `json:"id"`
		BuilderExecutableSizeBytes int64  `json:"builderExecutableSizeBytes"`
		BuilderExecutableSHA256    string `json:"builderExecutableSHA256"`
	} `json:"buildEnvironment"`
	Boot struct {
		Kernel         declaredBootArtifactOutput  `json:"kernel"`
		InitialRamdisk *declaredBootArtifactOutput `json:"initialRamdisk,omitempty"`
	} `json:"boot"`
	GuestRuntimeArtifact                                      declaredInputArtifact           `json:"guestRuntimeArtifact"`
	RecorderGatewayArtifact                                   declaredInputArtifact           `json:"recorderGatewayArtifact"`
	GuestProductProcessSupervisorArtifact                     declaredInputArtifact           `json:"guestProductProcessSupervisorArtifact"`
	GuestProductProcessDeploymentConfigurationArtifact        declaredInputArtifact           `json:"guestProductProcessDeploymentConfigurationArtifact"`
	GuestProductServiceManagerDeploymentConfigurationArtifact declaredInputArtifact           `json:"guestProductServiceManagerDeploymentConfigurationArtifact"`
	GuestProductBootstrapConfigurationArtifact                declaredInputArtifact           `json:"guestProductBootstrapConfigurationArtifact"`
	GuestProductVitalServerTopologyDeploymentArtifact         declaredInputArtifact           `json:"guestProductVitalServerTopologyDeploymentArtifact"`
	ExternalVitalServerDeliveryConfigurationArtifact          *declaredInputArtifact          `json:"externalVitalServerDeliveryConfigurationArtifact,omitempty"`
	StorageDevices                                            []declaredStorageArtifactOutput `json:"storageDevices"`
}

type guestProductProcessDeploymentConfiguration struct {
	SchemaVersion             string `json:"schemaVersion"`
	DeploymentID              string `json:"deploymentId"`
	RequiredProcessExitPolicy string `json:"requiredProcessExitPolicy"`
	GuestRuntime              struct {
		ExecutablePath    string `json:"executablePath"`
		StateDatabasePath string `json:"stateDatabasePath"`
	} `json:"guestRuntime"`
	RecorderGateway struct {
		NodeExecutablePath                           string `json:"nodeExecutablePath"`
		ProgramPath                                  string `json:"programPath"`
		VitalServerTopologyDeploymentPath            string `json:"vitalServerTopologyDeploymentPath"`
		ExternalVitalServerDeliveryConfigurationPath string `json:"externalVitalServerDeliveryConfigurationPath"`
	} `json:"recorderGateway"`
}

type guestProductServiceManagerDeploymentConfiguration struct {
	SchemaVersion      string `json:"schemaVersion"`
	ServiceManagerKind string `json:"serviceManagerKind"`
	ServiceUnitName    string `json:"serviceUnitName"`
	Supervisor         struct {
		ExecutablePath              string `json:"executablePath"`
		DeploymentConfigurationPath string `json:"deploymentConfigurationPath"`
	} `json:"supervisor"`
	Restart struct {
		Mode              string `json:"mode"`
		DelayMilliseconds int64  `json:"delayMilliseconds"`
	} `json:"restart"`
	Logging struct {
		StandardOutput string `json:"standardOutput"`
		StandardError  string `json:"standardError"`
	} `json:"logging"`
	Install struct {
		WantedByTarget string `json:"wantedByTarget"`
	} `json:"install"`
}

type guestProductBootstrapConfiguration struct {
	SchemaVersion                  string `json:"schemaVersion"`
	BootstrapID                    string `json:"bootstrapId"`
	VolumeLabel                    string `json:"volumeLabel"`
	GuestBootstrapVolumeFileSystem string `json:"guestBootstrapVolumeFileSystem"`
	InstanceID                     string `json:"instanceId"`
	LocalHostName                  string `json:"localHostName"`
	GuestRuntime                   struct {
		ArtifactID      string `json:"artifactId"`
		DestinationPath string `json:"destinationPath"`
		FileMode        string `json:"fileMode"`
	} `json:"guestRuntime"`
	GuestRuntimeStateDirectory struct {
		DirectoryPath string `json:"directoryPath"`
		DirectoryMode string `json:"directoryMode"`
	} `json:"guestRuntimeStateDirectory"`
	RecorderGatewayBundle struct {
		ArtifactID           string   `json:"artifactId"`
		ArchiveFormat        string   `json:"archiveFormat"`
		EntryModePolicy      string   `json:"entryModePolicy"`
		SymbolicLinkPolicy   string   `json:"symbolicLinkPolicy"`
		DestinationDirectory string   `json:"destinationDirectory"`
		RequiredArchivePaths []string `json:"requiredArchivePaths"`
	} `json:"recorderGatewayBundle"`
	GuestProductProcessSupervisor struct {
		ArtifactID      string `json:"artifactId"`
		DestinationPath string `json:"destinationPath"`
		FileMode        string `json:"fileMode"`
	} `json:"guestProductProcessSupervisor"`
	GuestProductProcessDeployment struct {
		ArtifactID      string `json:"artifactId"`
		DestinationPath string `json:"destinationPath"`
		FileMode        string `json:"fileMode"`
	} `json:"guestProductProcessDeployment"`
	GuestProductVitalServerTopologyDeployment struct {
		ArtifactID      string `json:"artifactId"`
		DestinationPath string `json:"destinationPath"`
		FileMode        string `json:"fileMode"`
	} `json:"guestProductVitalServerTopologyDeployment"`
	ExternalVitalServerDeliveryConfiguration *guestProductExternalVitalServerDeliveryConfigurationPayload `json:"externalVitalServerDeliveryConfiguration"`
	GuestProductServiceManagerDeployment     struct {
		ArtifactID                   string `json:"artifactId"`
		ConfigurationDestinationPath string `json:"configurationDestinationPath"`
		UnitDestinationPath          string `json:"unitDestinationPath"`
		EnabledUnitLinkPath          string `json:"enabledUnitLinkPath"`
		EnabledUnitLinkTargetPath    string `json:"enabledUnitLinkTargetPath"`
	} `json:"guestProductServiceManagerDeployment"`
}

// guestProductExternalVitalServerDeliveryConfigurationPayload is C39's
// install-time reference to the C46 document. It is optional in C39 because
// only a C44 external topology may require it.
type guestProductExternalVitalServerDeliveryConfigurationPayload struct {
	ArtifactID      string `json:"artifactId"`
	DestinationPath string `json:"destinationPath"`
	FileMode        string `json:"fileMode"`
}

// guestProductVitalServerTopologyDeployment is the exact C44 topology view
// validated before C40 installs it. It declares desired placement only; no
// endpoint, credential, connection, or process observation appears here.
type guestProductVitalServerTopologyDeployment struct {
	SchemaVersion               string `json:"schemaVersion"`
	TopologyDeploymentID        string `json:"topologyDeploymentId"`
	TopologyKind                string `json:"topologyKind"`
	VitalServerDeliveryProvider struct {
		Kind               string `json:"kind"`
		ID                 string `json:"id"`
		CapabilityRevision int64  `json:"capabilityRevision"`
	} `json:"vitalServerDeliveryProvider"`
	PublicBrowserExposure               string `json:"publicBrowserExposure"`
	BundledVitalServerServiceDeployment *struct {
		GuestProductProcessName string `json:"guestProductProcessName"`
		ServiceArtifactID       string `json:"serviceArtifactId"`
		ExecutablePath          string `json:"executablePath"`
		DeliveryListener        struct {
			BindHost string `json:"bindHost"`
			Port     int64  `json:"port"`
		} `json:"deliveryListener"`
		StateDirectory string `json:"stateDirectory"`
	} `json:"bundledVitalServerServiceDeployment"`
	ExternalVitalServerDeploymentConfiguration *struct {
		ExternalUpstreamIntegrationReference struct {
			ResourceType string `json:"resourceType"`
			ResourceID   string `json:"resourceId"`
		} `json:"externalUpstreamIntegrationReference"`
		ExternalVitalServerDeliveryConfigurationReference struct {
			ResourceType string `json:"resourceType"`
			ResourceID   string `json:"resourceId"`
		} `json:"externalVitalServerDeliveryConfigurationReference"`
	} `json:"externalVitalServerDeploymentConfiguration"`
}

// externalVitalServerDeliveryConfiguration is the C46 view required only for
// a C44 external topology. It contains desired endpoint identity, never a
// connection or packet-delivery observation.
type externalVitalServerDeliveryConfiguration struct {
	SchemaVersion                        string `json:"schemaVersion"`
	ConfigurationID                      string `json:"configurationId"`
	ExternalUpstreamIntegrationReference struct {
		ResourceType string `json:"resourceType"`
		ResourceID   string `json:"resourceId"`
	} `json:"externalUpstreamIntegrationReference"`
	VitalServerDeliveryProvider struct {
		Kind               string `json:"kind"`
		ID                 string `json:"id"`
		CapabilityRevision int64  `json:"capabilityRevision"`
	} `json:"vitalServerDeliveryProvider"`
	VitalServerPacketDeliveryEndpoint struct {
		Scheme string `json:"scheme"`
		Host   string `json:"host"`
		Port   int64  `json:"port"`
	} `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int64 `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
}

// ExecuteGuestProductBootstrapArtifactComposition performs the C35 effect:
// copied boot/root outputs plus a freshly composed read-only bootstrap volume.
// Guest root mutation remains a later cloud-init responsibility inside Linux.
func ExecuteGuestProductBootstrapArtifactComposition(
	execution GuestProductBootstrapArtifactCompositionExecution,
) (map[string]string, error) {
	if err := requireAbsoluteRegularNonSymlinkFile(execution.GuestArtifactCompilationCommandPath, "C35 command"); err != nil {
		return nil, compositionFailure("", "execution-validate", err)
	}
	if err := requireAbsoluteDirectoryNonSymlink(execution.InputRoot, "C35 input root"); err != nil {
		return nil, compositionFailure("", "execution-validate", err)
	}
	if err := requireAbsoluteDirectoryNonSymlink(execution.OutputDirectory, "C35 compiler output directory"); err != nil {
		return nil, compositionFailure("", "execution-validate", err)
	}
	if err := requireEmptyDirectory(execution.OutputDirectory); err != nil {
		return nil, compositionFailure("", "execution-validate", err)
	}
	command, err := readGuestArtifactCompilationCommand(execution.GuestArtifactCompilationCommandPath)
	if err != nil {
		return nil, compositionFailure("", "C35-decode", err)
	}
	inputPaths, err := verifyDeclaredC35InputArtifacts(command, execution.InputRoot)
	if err != nil {
		return nil, compositionFailure(command.CompilationID, "C35-input-identity", err)
	}
	processDeployment, err := readGuestProductProcessDeployment(inputPaths[command.GuestProductProcessDeploymentConfigurationArtifact.ID])
	if err != nil {
		return nil, compositionFailure(command.CompilationID, "C37-decode", err)
	}
	serviceManagerDeployment, err := readGuestProductServiceManagerDeployment(inputPaths[command.GuestProductServiceManagerDeploymentConfigurationArtifact.ID])
	if err != nil {
		return nil, compositionFailure(command.CompilationID, "C38-decode", err)
	}
	bootstrapConfiguration, err := readGuestProductBootstrapConfiguration(inputPaths[command.GuestProductBootstrapConfigurationArtifact.ID])
	if err != nil {
		return nil, compositionFailure(command.CompilationID, "C39-decode", err)
	}
	topologyDeployment, err := readGuestProductVitalServerTopologyDeployment(inputPaths[command.GuestProductVitalServerTopologyDeploymentArtifact.ID])
	if err != nil {
		return nil, compositionFailure(command.CompilationID, "C44-decode", err)
	}
	var externalDeliveryConfiguration *externalVitalServerDeliveryConfiguration
	if command.ExternalVitalServerDeliveryConfigurationArtifact != nil {
		loadedExternalDeliveryConfiguration, readErr := readExternalVitalServerDeliveryConfiguration(inputPaths[command.ExternalVitalServerDeliveryConfigurationArtifact.ID])
		if readErr != nil {
			return nil, compositionFailure(command.CompilationID, "C46-decode", readErr)
		}
		externalDeliveryConfiguration = &loadedExternalDeliveryConfiguration
	}
	if err := validateGuestProductProcessTopologyBootstrapComposition(
		processDeployment,
		topologyDeployment,
		bootstrapConfiguration,
		command.ExternalVitalServerDeliveryConfigurationArtifact,
		externalDeliveryConfiguration,
	); err != nil {
		return nil, compositionFailure(command.CompilationID, "C37-C39-C44-C46-topology-delivery-configuration", err)
	}
	if err := copyDeclaredBootAndRootArtifacts(command, inputPaths, execution.OutputDirectory); err != nil {
		return nil, compositionFailure(command.CompilationID, "declared-output-copy", err)
	}
	if err := composeDeclaredGuestProductBootstrapVolume(
		command,
		inputPaths,
		processDeployment,
		serviceManagerDeployment,
		bootstrapConfiguration,
		execution.OutputDirectory,
	); err != nil {
		return nil, compositionFailure(command.CompilationID, "guest-product-bootstrap-volume-compose", err)
	}
	return map[string]string{
		"compilationId":               command.CompilationID,
		"guestRootStorageOutput":      "storage/guest-root.raw",
		"guestProductBootstrapVolume": "storage/guest-product-bootstrap.raw",
	}, nil
}

func compositionFailure(compilationID string, stage string, err error) GuestProductBootstrapArtifactCompositionError {
	return GuestProductBootstrapArtifactCompositionError{CompilationID: compilationID, Stage: stage, Reason: err.Error()}
}

func readGuestArtifactCompilationCommand(path string) (guestArtifactCompilationCommand, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestArtifactCompilationCommand{}, fmt.Errorf("C35 command cannot be read: %w", err)
	}
	if len(contents) > maximumCompilationCommandBytes {
		return guestArtifactCompilationCommand{}, fmt.Errorf("C35 command exceeds %d bytes", maximumCompilationCommandBytes)
	}
	var command guestArtifactCompilationCommand
	if err := decodeOneStrictJSONDocument(contents, &command); err != nil {
		return guestArtifactCompilationCommand{}, fmt.Errorf("C35 command cannot be decoded: %w", err)
	}
	if err := validateGuestArtifactCompilationCommand(command); err != nil {
		return guestArtifactCompilationCommand{}, err
	}
	return command, nil
}

func validateGuestArtifactCompilationCommand(command guestArtifactCompilationCommand) error {
	if command.SchemaVersion != "v1" || command.Architecture != "arm64" || command.CompilationID == "" || command.ArtifactSetID == "" || !isSelectedGuestProductBootstrapArtifactComposerIdentityValid(command.BuildEnvironment.ID, command.BuildEnvironment.BuilderExecutableSizeBytes, command.BuildEnvironment.BuilderExecutableSHA256) {
		return fmt.Errorf("C35 bootstrap artifact composer identity is invalid")
	}
	if command.Boot.Kernel.OutputRelativePath != "boot/Image" || (command.Boot.InitialRamdisk != nil && command.Boot.InitialRamdisk.OutputRelativePath != "boot/initrd.img") {
		return fmt.Errorf("C35 boot output paths are invalid")
	}
	artifacts := commandInputArtifacts(command)
	seenIDs := map[string]struct{}{}
	seenPaths := map[string]struct{}{}
	for _, artifact := range artifacts {
		if !isDeclaredInputArtifactValid(artifact) {
			return fmt.Errorf("C35 declared input artifact is invalid")
		}
		if _, exists := seenIDs[artifact.ID]; exists {
			return fmt.Errorf("C35 input artifact ID is repeated: %s", artifact.ID)
		}
		if _, exists := seenPaths[artifact.InputRelativePath]; exists {
			return fmt.Errorf("C35 input artifact path is repeated: %s", artifact.InputRelativePath)
		}
		seenIDs[artifact.ID] = struct{}{}
		seenPaths[artifact.InputRelativePath] = struct{}{}
	}
	if command.ExternalVitalServerDeliveryConfigurationArtifact != nil && command.ExternalVitalServerDeliveryConfigurationArtifact.ID != "external-vitalserver-delivery-configuration" {
		return fmt.Errorf("C35 external VitalServer delivery configuration artifact identity is invalid")
	}
	root, bootstrap, err := selectedStorageOutputs(command.StorageDevices)
	if err != nil {
		return err
	}
	if root.BaseImage == nil || root.Role != "guest-root-storage" || root.StorageImageFormat != "raw" || root.GuestVolumeFileSystem != "" || root.ReadOnly || root.OutputRelativePath != "storage/guest-root.raw" {
		return fmt.Errorf("C35 guest-root output must be one writable raw base copy")
	}
	if bootstrap.BaseImage != nil || bootstrap.Role != "guest-product-bootstrap-volume" || bootstrap.StorageImageFormat != "raw" || bootstrap.GuestVolumeFileSystem != "iso9660" || !bootstrap.ReadOnly || bootstrap.OutputRelativePath != "storage/guest-product-bootstrap.raw" {
		return fmt.Errorf("C35 Guest Product bootstrap output must be one read-only RAW storage image containing an ISO9660 Guest volume")
	}
	return nil
}

// isSelectedGuestProductBootstrapArtifactComposerIdentityValid verifies the
// C35 declaration of the selected builder. The outer GuestArtifactCompiler
// compares this declared identity with the executable it invokes.
func isSelectedGuestProductBootstrapArtifactComposerIdentityValid(identifier string, sizeBytes int64, sha256 string) bool {
	return identifier == "guest-product-bootstrap-artifact-composer" && sizeBytes > 0 && len(sha256) == 64 && strings.Trim(sha256, "0123456789abcdef") == ""
}

func commandInputArtifacts(command guestArtifactCompilationCommand) []declaredInputArtifact {
	artifacts := []declaredInputArtifact{
		command.Boot.Kernel.Source,
		command.GuestRuntimeArtifact,
		command.RecorderGatewayArtifact,
		command.GuestProductProcessSupervisorArtifact,
		command.GuestProductProcessDeploymentConfigurationArtifact,
		command.GuestProductServiceManagerDeploymentConfigurationArtifact,
		command.GuestProductBootstrapConfigurationArtifact,
		command.GuestProductVitalServerTopologyDeploymentArtifact,
	}
	if command.ExternalVitalServerDeliveryConfigurationArtifact != nil {
		artifacts = append(artifacts, *command.ExternalVitalServerDeliveryConfigurationArtifact)
	}
	if command.Boot.InitialRamdisk != nil {
		artifacts = append(artifacts, command.Boot.InitialRamdisk.Source)
	}
	for _, storage := range command.StorageDevices {
		if storage.BaseImage != nil {
			artifacts = append(artifacts, *storage.BaseImage)
		}
	}
	return artifacts
}

func selectedStorageOutputs(storageDevices []declaredStorageArtifactOutput) (declaredStorageArtifactOutput, declaredStorageArtifactOutput, error) {
	if len(storageDevices) != 2 {
		return declaredStorageArtifactOutput{}, declaredStorageArtifactOutput{}, fmt.Errorf("C35 requires exactly two storage outputs")
	}
	var root, bootstrap *declaredStorageArtifactOutput
	for index := range storageDevices {
		storage := &storageDevices[index]
		switch storage.ID {
		case "guest-root":
			root = storage
		case "guest-product-bootstrap":
			bootstrap = storage
		default:
			return declaredStorageArtifactOutput{}, declaredStorageArtifactOutput{}, fmt.Errorf("C35 has unknown storage output %s", storage.ID)
		}
	}
	if root == nil || bootstrap == nil {
		return declaredStorageArtifactOutput{}, declaredStorageArtifactOutput{}, fmt.Errorf("C35 requires guest-root and guest-product-bootstrap storage outputs")
	}
	return *root, *bootstrap, nil
}

func isDeclaredInputArtifactValid(artifact declaredInputArtifact) bool {
	return artifact.ID != "" && isSafeInputRelativePath(artifact.InputRelativePath) && artifact.SizeBytes > 0 && len(artifact.SHA256) == 64 && strings.Trim(artifact.SHA256, "0123456789abcdef") == ""
}

func verifyDeclaredC35InputArtifacts(command guestArtifactCompilationCommand, inputRoot string) (map[string]string, error) {
	paths := make(map[string]string)
	for _, artifact := range commandInputArtifacts(command) {
		path, err := resolveDeclaredInputArtifactPath(inputRoot, artifact)
		if err != nil {
			return nil, err
		}
		identity, err := calculateRegularFileIdentity(path)
		if err != nil {
			return nil, fmt.Errorf("C35 input artifact %s cannot be read: %w", artifact.ID, err)
		}
		if identity.sizeBytes != artifact.SizeBytes || identity.sha256 != artifact.SHA256 {
			return nil, fmt.Errorf("C35 input artifact identity differs: %s", artifact.ID)
		}
		paths[artifact.ID] = path
	}
	return paths, nil
}

func readGuestProductProcessDeployment(path string) (guestProductProcessDeploymentConfiguration, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestProductProcessDeploymentConfiguration{}, err
	}
	var deployment guestProductProcessDeploymentConfiguration
	if err := json.Unmarshal(contents, &deployment); err != nil {
		return guestProductProcessDeploymentConfiguration{}, err
	}
	if deployment.SchemaVersion != "v1" || deployment.RequiredProcessExitPolicy != "terminate-guest-product" || !isAbsoluteGuestPath(deployment.GuestRuntime.ExecutablePath) || !isAbsoluteGuestPath(deployment.GuestRuntime.StateDatabasePath) || !isAbsoluteGuestPath(deployment.RecorderGateway.NodeExecutablePath) || !isAbsoluteGuestPath(deployment.RecorderGateway.ProgramPath) || !isAbsoluteGuestPath(deployment.RecorderGateway.VitalServerTopologyDeploymentPath) || (deployment.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath != "" && !isAbsoluteGuestPath(deployment.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath)) {
		return guestProductProcessDeploymentConfiguration{}, fmt.Errorf("C37 bootstrap-relevant process deployment is invalid")
	}
	return deployment, nil
}

// validateGuestProductProcessTopologyBootstrapComposition checks only desired
// document identity and installation-path agreement. It never opens the C46
// endpoint or treats a valid declaration as an available VitalServer.
func validateGuestProductProcessTopologyBootstrapComposition(
	processDeployment guestProductProcessDeploymentConfiguration,
	topologyDeployment guestProductVitalServerTopologyDeployment,
	bootstrapConfiguration guestProductBootstrapConfiguration,
	externalDeliveryArtifact *declaredInputArtifact,
	externalDeliveryConfiguration *externalVitalServerDeliveryConfiguration,
) error {
	if processDeployment.RecorderGateway.VitalServerTopologyDeploymentPath != bootstrapConfiguration.GuestProductVitalServerTopologyDeployment.DestinationPath {
		return fmt.Errorf("C37 Recorder Gateway topology path must equal the C39 installed C44 destination")
	}
	if topologyDeployment.TopologyDeploymentID == "" {
		return fmt.Errorf("C44 topology deployment identity is missing")
	}
	switch topologyDeployment.TopologyKind {
	case "external-vitalserver":
		installedExternalDeliveryConfiguration := bootstrapConfiguration.ExternalVitalServerDeliveryConfiguration
		if externalDeliveryArtifact == nil || installedExternalDeliveryConfiguration == nil || externalDeliveryConfiguration == nil {
			return fmt.Errorf("C44 external VitalServer topology requires C46 artifact, C39 installation payload, and decoded C46 configuration")
		}
		if installedExternalDeliveryConfiguration.ArtifactID != "external-vitalserver-delivery-configuration" || installedExternalDeliveryConfiguration.FileMode != "0644" || !isAbsoluteGuestPath(installedExternalDeliveryConfiguration.DestinationPath) {
			return fmt.Errorf("C39 external VitalServer delivery configuration payload is invalid")
		}
		if processDeployment.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath != installedExternalDeliveryConfiguration.DestinationPath {
			return fmt.Errorf("C37 Recorder Gateway external delivery configuration path must equal the C39 installed C46 destination")
		}
		external := topologyDeployment.ExternalVitalServerDeploymentConfiguration
		if external == nil || external.ExternalUpstreamIntegrationReference.ResourceType != externalDeliveryConfiguration.ExternalUpstreamIntegrationReference.ResourceType || external.ExternalUpstreamIntegrationReference.ResourceID != externalDeliveryConfiguration.ExternalUpstreamIntegrationReference.ResourceID || external.ExternalVitalServerDeliveryConfigurationReference.ResourceID != externalDeliveryConfiguration.ConfigurationID || topologyDeployment.VitalServerDeliveryProvider.Kind != externalDeliveryConfiguration.VitalServerDeliveryProvider.Kind || topologyDeployment.VitalServerDeliveryProvider.ID != externalDeliveryConfiguration.VitalServerDeliveryProvider.ID || topologyDeployment.VitalServerDeliveryProvider.CapabilityRevision != externalDeliveryConfiguration.VitalServerDeliveryProvider.CapabilityRevision {
			return fmt.Errorf("C44 external VitalServer topology and C46 delivery configuration do not describe the same integration, configuration, and provider")
		}
	case "bundled-vitalserver":
		if externalDeliveryArtifact != nil || bootstrapConfiguration.ExternalVitalServerDeliveryConfiguration != nil || processDeployment.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath != "" || externalDeliveryConfiguration != nil {
			return fmt.Errorf("C44 bundled VitalServer topology must not install or reference an unused C46 external delivery configuration")
		}
		return fmt.Errorf("C44 bundled VitalServer topology requires an explicit C37 bundled VitalServer process launch plan; current C37 plans only Guest Runtime and Recorder Gateway")
	default:
		return fmt.Errorf("C44 topology kind is invalid")
	}
	return nil
}

func readGuestProductServiceManagerDeployment(path string) (guestProductServiceManagerDeploymentConfiguration, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestProductServiceManagerDeploymentConfiguration{}, err
	}
	var deployment guestProductServiceManagerDeploymentConfiguration
	if err := decodeOneStrictJSONDocument(contents, &deployment); err != nil {
		return guestProductServiceManagerDeploymentConfiguration{}, err
	}
	if deployment.SchemaVersion != "v1" || deployment.ServiceManagerKind != "systemd" || !strings.HasSuffix(deployment.ServiceUnitName, ".service") || !isAbsoluteGuestPath(deployment.Supervisor.ExecutablePath) || !isAbsoluteGuestPath(deployment.Supervisor.DeploymentConfigurationPath) || deployment.Restart.Mode != "on-failure" || deployment.Restart.DelayMilliseconds < 0 || deployment.Logging.StandardOutput != "journal+console" || deployment.Logging.StandardError != "journal+console" || deployment.Install.WantedByTarget != "multi-user.target" {
		return guestProductServiceManagerDeploymentConfiguration{}, fmt.Errorf("C38 service manager deployment is invalid")
	}
	return deployment, nil
}

func readGuestProductBootstrapConfiguration(path string) (guestProductBootstrapConfiguration, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestProductBootstrapConfiguration{}, err
	}
	var configuration guestProductBootstrapConfiguration
	if err := decodeOneStrictJSONDocument(contents, &configuration); err != nil {
		return guestProductBootstrapConfiguration{}, err
	}
	if configuration.SchemaVersion != "v1" || configuration.BootstrapID == "" || configuration.InstanceID == "" || configuration.LocalHostName == "" || configuration.VolumeLabel != "CIDATA" || configuration.GuestBootstrapVolumeFileSystem != "iso9660" || !isBootstrapConfigurationValid(configuration) {
		return guestProductBootstrapConfiguration{}, fmt.Errorf("C39 Guest Product bootstrap configuration is invalid")
	}
	return configuration, nil
}

func isBootstrapConfigurationValid(configuration guestProductBootstrapConfiguration) bool {
	externalDeliveryConfigurationIsValid := configuration.ExternalVitalServerDeliveryConfiguration == nil || (configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID == "external-vitalserver-delivery-configuration" && isAbsoluteGuestPath(configuration.ExternalVitalServerDeliveryConfiguration.DestinationPath) && configuration.ExternalVitalServerDeliveryConfiguration.FileMode == "0644")
	return configuration.GuestRuntime.ArtifactID == "guest-runtime-linux-arm64" && isAbsoluteGuestPath(configuration.GuestRuntime.DestinationPath) && configuration.GuestRuntime.FileMode == "0755" &&
		isAbsoluteGuestPath(configuration.GuestRuntimeStateDirectory.DirectoryPath) && configuration.GuestRuntimeStateDirectory.DirectoryMode == "0700" &&
		configuration.RecorderGatewayBundle.ArtifactID == "recorder-gateway-linux-arm64" && configuration.RecorderGatewayBundle.ArchiveFormat == "tar-gzip" && configuration.RecorderGatewayBundle.EntryModePolicy == guestproductbootstrapvolumeplan.PreserveArchiveEntryModePolicy && configuration.RecorderGatewayBundle.SymbolicLinkPolicy == guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy && isAbsoluteGuestPath(configuration.RecorderGatewayBundle.DestinationDirectory) && len(configuration.RecorderGatewayBundle.RequiredArchivePaths) >= 2 &&
		configuration.GuestProductProcessSupervisor.ArtifactID == "guest-product-process-supervisor-linux-arm64" && isAbsoluteGuestPath(configuration.GuestProductProcessSupervisor.DestinationPath) && configuration.GuestProductProcessSupervisor.FileMode == "0755" &&
		configuration.GuestProductProcessDeployment.ArtifactID == "guest-product-process-deployment-configuration" && isAbsoluteGuestPath(configuration.GuestProductProcessDeployment.DestinationPath) && configuration.GuestProductProcessDeployment.FileMode == "0644" &&
		configuration.GuestProductVitalServerTopologyDeployment.ArtifactID == "guest-product-vitalserver-topology-deployment" && isAbsoluteGuestPath(configuration.GuestProductVitalServerTopologyDeployment.DestinationPath) && configuration.GuestProductVitalServerTopologyDeployment.FileMode == "0644" &&
		externalDeliveryConfigurationIsValid &&
		configuration.GuestProductServiceManagerDeployment.ArtifactID == "guest-product-service-manager-deployment-configuration" && isAbsoluteGuestPath(configuration.GuestProductServiceManagerDeployment.ConfigurationDestinationPath) && isAbsoluteGuestPath(configuration.GuestProductServiceManagerDeployment.UnitDestinationPath) && isAbsoluteGuestPath(configuration.GuestProductServiceManagerDeployment.EnabledUnitLinkPath) && isAbsoluteGuestPath(configuration.GuestProductServiceManagerDeployment.EnabledUnitLinkTargetPath)
}

func readGuestProductVitalServerTopologyDeployment(path string) (guestProductVitalServerTopologyDeployment, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return guestProductVitalServerTopologyDeployment{}, err
	}
	var deployment guestProductVitalServerTopologyDeployment
	if err := decodeOneStrictJSONDocument(contents, &deployment); err != nil {
		return guestProductVitalServerTopologyDeployment{}, err
	}
	if !isGuestProductVitalServerTopologyDeploymentValid(deployment) {
		return guestProductVitalServerTopologyDeployment{}, fmt.Errorf("C44 Guest Product VitalServer topology deployment is invalid")
	}
	return deployment, nil
}

func isGuestProductVitalServerTopologyDeploymentValid(deployment guestProductVitalServerTopologyDeployment) bool {
	if deployment.SchemaVersion != "v1" || deployment.TopologyDeploymentID == "" || deployment.VitalServerDeliveryProvider.Kind == "" || deployment.VitalServerDeliveryProvider.ID == "" || deployment.VitalServerDeliveryProvider.CapabilityRevision < 1 {
		return false
	}
	switch deployment.TopologyKind {
	case "bundled-vitalserver":
		bundled := deployment.BundledVitalServerServiceDeployment
		return bundled != nil && deployment.ExternalVitalServerDeploymentConfiguration == nil && (deployment.PublicBrowserExposure == "not-exposed" || deployment.PublicBrowserExposure == "guest-virtio-route") && bundled.GuestProductProcessName == "bundled-vitalserver" && bundled.ServiceArtifactID != "" && isAbsoluteGuestPath(bundled.ExecutablePath) && bundled.DeliveryListener.BindHost == "127.0.0.1" && bundled.DeliveryListener.Port >= 1 && bundled.DeliveryListener.Port <= 65535 && isAbsoluteGuestPath(bundled.StateDirectory)
	case "external-vitalserver":
		external := deployment.ExternalVitalServerDeploymentConfiguration
		return external != nil && deployment.BundledVitalServerServiceDeployment == nil && (deployment.PublicBrowserExposure == "not-exposed" || deployment.PublicBrowserExposure == "host-external-route") && external.ExternalUpstreamIntegrationReference.ResourceType == "external-upstream-integration" && external.ExternalUpstreamIntegrationReference.ResourceID != "" && external.ExternalVitalServerDeliveryConfigurationReference.ResourceType == "external-vitalserver-delivery-configuration" && external.ExternalVitalServerDeliveryConfigurationReference.ResourceID != ""
	default:
		return false
	}
}

func readExternalVitalServerDeliveryConfiguration(path string) (externalVitalServerDeliveryConfiguration, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return externalVitalServerDeliveryConfiguration{}, err
	}
	var configuration externalVitalServerDeliveryConfiguration
	if err := decodeOneStrictJSONDocument(contents, &configuration); err != nil {
		return externalVitalServerDeliveryConfiguration{}, err
	}
	if !isExternalVitalServerDeliveryConfigurationValid(configuration) {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 external VitalServer delivery configuration is invalid")
	}
	return configuration, nil
}

func isExternalVitalServerDeliveryConfigurationValid(configuration externalVitalServerDeliveryConfiguration) bool {
	return configuration.SchemaVersion == "v1" && configuration.ConfigurationID != "" &&
		configuration.ExternalUpstreamIntegrationReference.ResourceType == "external-upstream-integration" && configuration.ExternalUpstreamIntegrationReference.ResourceID != "" &&
		configuration.VitalServerDeliveryProvider.Kind != "" && configuration.VitalServerDeliveryProvider.ID != "" && configuration.VitalServerDeliveryProvider.CapabilityRevision >= 1 &&
		(configuration.VitalServerPacketDeliveryEndpoint.Scheme == "http" || configuration.VitalServerPacketDeliveryEndpoint.Scheme == "https") && configuration.VitalServerPacketDeliveryEndpoint.Host != "" && configuration.VitalServerPacketDeliveryEndpoint.Host != "127.0.0.1" && configuration.VitalServerPacketDeliveryEndpoint.Host != "::1" && configuration.VitalServerPacketDeliveryEndpoint.Host != "localhost" && configuration.VitalServerPacketDeliveryEndpoint.Port >= 1 && configuration.VitalServerPacketDeliveryEndpoint.Port <= 65535 &&
		configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds >= 1 && configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds <= 3600000
}

func copyDeclaredBootAndRootArtifacts(command guestArtifactCompilationCommand, inputPaths map[string]string, outputDirectory string) error {
	if err := copyNewRegularFile(inputPaths[command.Boot.Kernel.Source.ID], outputPath(outputDirectory, command.Boot.Kernel.OutputRelativePath)); err != nil {
		return fmt.Errorf("C35 kernel output: %w", err)
	}
	if command.Boot.InitialRamdisk != nil {
		if err := copyNewRegularFile(inputPaths[command.Boot.InitialRamdisk.Source.ID], outputPath(outputDirectory, command.Boot.InitialRamdisk.OutputRelativePath)); err != nil {
			return fmt.Errorf("C35 initial RAM disk output: %w", err)
		}
	}
	root, _, err := selectedStorageOutputs(command.StorageDevices)
	if err != nil {
		return err
	}
	if err := copyNewRegularFile(inputPaths[root.BaseImage.ID], outputPath(outputDirectory, root.OutputRelativePath)); err != nil {
		return fmt.Errorf("C35 Guest root storage output: %w", err)
	}
	return nil
}

func composeDeclaredGuestProductBootstrapVolume(
	command guestArtifactCompilationCommand,
	inputPaths map[string]string,
	processDeployment guestProductProcessDeploymentConfiguration,
	serviceManagerDeployment guestProductServiceManagerDeploymentConfiguration,
	bootstrapConfiguration guestProductBootstrapConfiguration,
	outputDirectory string,
) error {
	payloads := guestproductbootstrapplancomposer.GuestProductBootstrapPayloads{}
	for _, artifact := range []declaredInputArtifact{
		command.GuestRuntimeArtifact,
		command.RecorderGatewayArtifact,
		command.GuestProductProcessSupervisorArtifact,
		command.GuestProductProcessDeploymentConfigurationArtifact,
		command.GuestProductServiceManagerDeploymentConfigurationArtifact,
		command.GuestProductVitalServerTopologyDeploymentArtifact,
	} {
		payload := guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{ID: artifact.ID, SourceRelativePath: "sources/" + artifact.ID, SizeBytes: artifact.SizeBytes, SHA256: artifact.SHA256}
		if err := guestproductbootstrapplancomposer.ValidateSourceIdentityFormat(payload); err != nil {
			return err
		}
		payloads[artifact.ID] = payload
	}
	if command.ExternalVitalServerDeliveryConfigurationArtifact != nil {
		artifact := *command.ExternalVitalServerDeliveryConfigurationArtifact
		payload := guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{ID: artifact.ID, SourceRelativePath: "sources/" + artifact.ID, SizeBytes: artifact.SizeBytes, SHA256: artifact.SHA256}
		if err := guestproductbootstrapplancomposer.ValidateSourceIdentityFormat(payload); err != nil {
			return err
		}
		payloads[artifact.ID] = payload
	}
	unitContents, err := renderGuestProductSystemdServiceUnit(serviceManagerDeployment)
	if err != nil {
		return err
	}
	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(
		guestproductbootstrapplancomposer.GuestProductBootstrapVolumePlanComposition{
			ProcessDeployment: guestproductbootstrapplancomposer.GuestProductProcessDeploymentPaths{
				GuestRuntimeExecutablePath:    processDeployment.GuestRuntime.ExecutablePath,
				GuestRuntimeStateDatabasePath: processDeployment.GuestRuntime.StateDatabasePath,
				RecorderGatewayNodePath:       processDeployment.RecorderGateway.NodeExecutablePath,
				RecorderGatewayProgramPath:    processDeployment.RecorderGateway.ProgramPath,
			},
			ServiceManagerDeployment: guestproductbootstrapplancomposer.GuestProductServiceManagerDeployment{
				ServiceUnitName:                       serviceManagerDeployment.ServiceUnitName,
				SupervisorExecutablePath:              serviceManagerDeployment.Supervisor.ExecutablePath,
				SupervisorDeploymentConfigurationPath: serviceManagerDeployment.Supervisor.DeploymentConfigurationPath,
			},
			BootstrapConfiguration:       mapGuestProductBootstrapConfiguration(bootstrapConfiguration),
			Payloads:                     payloads,
			GeneratedSystemdUnitContents: []byte(unitContents),
		},
	)
	if err != nil {
		return err
	}
	stagingRoot, err := os.MkdirTemp(outputDirectory, ".guest-product-bootstrap-sources.")
	if err != nil {
		return fmt.Errorf("C40 source staging directory cannot be created: %w", err)
	}
	defer os.RemoveAll(stagingRoot)
	for _, source := range plan.Sources {
		destination := filepath.Join(stagingRoot, filepath.FromSlash(source.SourceRelativePath))
		if source.ID == generatedSystemdUnitSourceID {
			if err := writeNewFile(destination, []byte(unitContents), 0o600); err != nil {
				return fmt.Errorf("C40 generated systemd unit cannot be staged: %w", err)
			}
			continue
		}
		sourcePath, found := inputPaths[source.ID]
		if !found {
			return fmt.Errorf("C40 source has no verified C35 input: %s", source.ID)
		}
		if err := copyNewRegularFile(sourcePath, destination); err != nil {
			return fmt.Errorf("C40 source %s cannot be staged: %w", source.ID, err)
		}
	}
	planPath := filepath.Join(stagingRoot, "guest-product-bootstrap-volume-composition-plan.json")
	planBytes, err := json.Marshal(plan)
	if err != nil {
		return fmt.Errorf("C40 plan cannot be encoded: %w", err)
	}
	if err := writeNewFile(planPath, append(planBytes, '\n'), 0o600); err != nil {
		return fmt.Errorf("C40 plan cannot be written: %w", err)
	}
	_, bootstrap, err := selectedStorageOutputs(command.StorageDevices)
	if err != nil {
		return err
	}
	outputVolumePath := outputPath(outputDirectory, bootstrap.OutputRelativePath)
	if err := os.MkdirAll(filepath.Dir(outputVolumePath), 0o700); err != nil {
		return fmt.Errorf("C40 output parent cannot be created: %w", err)
	}
	_, err = guestproductbootstrapvolumeapplication.ExecuteGuestProductBootstrapVolumeComposition(
		guestproductbootstrapvolumeapplication.GuestProductBootstrapVolumeCompositionExecution{
			CompositionPlanPath: planPath,
			SourceRoot:          stagingRoot,
			OutputVolumePath:    outputVolumePath,
		},
		nocloudguestproductbootstrapvolumeadapter.NewNoCloudGuestProductBootstrapVolumeAdapter(),
	)
	return err
}

func mapGuestProductBootstrapConfiguration(configuration guestProductBootstrapConfiguration) guestproductbootstrapplancomposer.GuestProductBootstrapConfiguration {
	var externalVitalServerDeliveryConfiguration *guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload
	if configuration.ExternalVitalServerDeliveryConfiguration != nil {
		externalVitalServerDeliveryConfiguration = &guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{
			ArtifactID:      configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID,
			DestinationPath: configuration.ExternalVitalServerDeliveryConfiguration.DestinationPath,
			FileMode:        configuration.ExternalVitalServerDeliveryConfiguration.FileMode,
		}
	}
	return guestproductbootstrapplancomposer.GuestProductBootstrapConfiguration{
		BootstrapID: configuration.BootstrapID, VolumeLabel: configuration.VolumeLabel, GuestVolumeFileSystem: configuration.GuestBootstrapVolumeFileSystem, InstanceID: configuration.InstanceID, LocalHostName: configuration.LocalHostName,
		GuestRuntime:                              guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: configuration.GuestRuntime.ArtifactID, DestinationPath: configuration.GuestRuntime.DestinationPath, FileMode: configuration.GuestRuntime.FileMode},
		GuestRuntimeStateDirectory:                guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: configuration.GuestRuntimeStateDirectory.DirectoryPath, DirectoryMode: configuration.GuestRuntimeStateDirectory.DirectoryMode},
		RecorderGatewayBundle:                     guestproductbootstrapplancomposer.GuestProductBootstrapRecorderGatewayArchive{ArtifactID: configuration.RecorderGatewayBundle.ArtifactID, ArchiveFormat: configuration.RecorderGatewayBundle.ArchiveFormat, EntryModePolicy: configuration.RecorderGatewayBundle.EntryModePolicy, SymbolicLinkPolicy: configuration.RecorderGatewayBundle.SymbolicLinkPolicy, DestinationDirectory: configuration.RecorderGatewayBundle.DestinationDirectory, RequiredArchivePaths: configuration.RecorderGatewayBundle.RequiredArchivePaths},
		GuestProductProcessSupervisor:             guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: configuration.GuestProductProcessSupervisor.ArtifactID, DestinationPath: configuration.GuestProductProcessSupervisor.DestinationPath, FileMode: configuration.GuestProductProcessSupervisor.FileMode},
		GuestProductProcessDeployment:             guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: configuration.GuestProductProcessDeployment.ArtifactID, DestinationPath: configuration.GuestProductProcessDeployment.DestinationPath, FileMode: configuration.GuestProductProcessDeployment.FileMode},
		GuestProductVitalServerTopologyDeployment: guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: configuration.GuestProductVitalServerTopologyDeployment.ArtifactID, DestinationPath: configuration.GuestProductVitalServerTopologyDeployment.DestinationPath, FileMode: configuration.GuestProductVitalServerTopologyDeployment.FileMode},
		ExternalVitalServerDeliveryConfiguration:  externalVitalServerDeliveryConfiguration,
		GuestProductServiceManagerDeployment:      guestproductbootstrapplancomposer.GuestProductBootstrapServiceManagerPayload{ArtifactID: configuration.GuestProductServiceManagerDeployment.ArtifactID, ConfigurationDestinationPath: configuration.GuestProductServiceManagerDeployment.ConfigurationDestinationPath, UnitDestinationPath: configuration.GuestProductServiceManagerDeployment.UnitDestinationPath, EnabledUnitLinkPath: configuration.GuestProductServiceManagerDeployment.EnabledUnitLinkPath, EnabledUnitLinkTargetPath: configuration.GuestProductServiceManagerDeployment.EnabledUnitLinkTargetPath},
	}
}

func renderGuestProductSystemdServiceUnit(deployment guestProductServiceManagerDeploymentConfiguration) (string, error) {
	if deployment.Restart.DelayMilliseconds < 0 || deployment.Logging.StandardOutput != "journal+console" || deployment.Logging.StandardError != "journal+console" {
		return "", fmt.Errorf("C38 restart or logging policy is invalid")
	}
	seconds := fmt.Sprintf("%.3f", float64(deployment.Restart.DelayMilliseconds)/1000)
	seconds = strings.TrimRight(strings.TrimRight(seconds, "0"), ".") + "s"
	return "[Unit]\nDescription=VitalServer Guest Product Process Supervisor\n\n[Service]\nType=simple\nExecStart=" + deployment.Supervisor.ExecutablePath + " --deployment-configuration " + deployment.Supervisor.DeploymentConfigurationPath + "\nRestart=" + deployment.Restart.Mode + "\nRestartSec=" + seconds + "\nStandardOutput=" + deployment.Logging.StandardOutput + "\nStandardError=" + deployment.Logging.StandardError + "\nKillMode=control-group\n\n[Install]\nWantedBy=" + deployment.Install.WantedByTarget + "\n", nil
}

type regularFileIdentity struct {
	sizeBytes int64
	sha256    string
}

func calculateRegularFileIdentity(path string) (regularFileIdentity, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return regularFileIdentity{}, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return regularFileIdentity{}, fmt.Errorf("must be a regular non-symlink file")
	}
	file, err := os.Open(path)
	if err != nil {
		return regularFileIdentity{}, err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return regularFileIdentity{}, err
	}
	return regularFileIdentity{sizeBytes: info.Size(), sha256: hex.EncodeToString(digest.Sum(nil))}, nil
}

func resolveDeclaredInputArtifactPath(inputRoot string, artifact declaredInputArtifact) (string, error) {
	if !isSafeInputRelativePath(artifact.InputRelativePath) {
		return "", fmt.Errorf("C35 input path is unsafe: %s", artifact.ID)
	}
	path := filepath.Join(inputRoot, filepath.FromSlash(artifact.InputRelativePath))
	relative, err := filepath.Rel(inputRoot, path)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("C35 input path escapes root: %s", artifact.ID)
	}
	if err := requireDeclaredInputPathParentsWithinInputRoot(inputRoot, path, artifact.ID); err != nil {
		return "", err
	}
	return path, nil
}

// requireDeclaredInputPathParentsWithinInputRoot prevents a declared C35
// relative path from traversing a symbolic-link directory after the input root
// has been accepted. The input root is an explicit immutable evidence set;
// C35 must not read a file which is only lexically below it.
func requireDeclaredInputPathParentsWithinInputRoot(inputRoot string, artifactPath string, artifactID string) error {
	relativePath, err := filepath.Rel(inputRoot, artifactPath)
	if err != nil || relativePath == "." || strings.HasPrefix(relativePath, ".."+string(filepath.Separator)) {
		return fmt.Errorf("C35 input parent path escapes root: %s", artifactID)
	}
	components := strings.Split(relativePath, string(filepath.Separator))
	parentPath := inputRoot
	for _, component := range components[:len(components)-1] {
		parentPath = filepath.Join(parentPath, component)
		info, err := os.Lstat(parentPath)
		if err != nil {
			return fmt.Errorf("C35 input parent cannot be stated: %s: %w", artifactID, err)
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C35 input parent must be a directory non-symlink: %s", artifactID)
		}
	}
	return nil
}

func isSafeInputRelativePath(value string) bool {
	return strings.HasPrefix(value, "inputs/") && value != "inputs/" && !strings.Contains(value, "\\") && !strings.Contains(value, "//") && !strings.Contains(value, "/./") && !strings.HasSuffix(value, "/.") && !strings.Contains(value, "/../") && !strings.HasSuffix(value, "/..") && !strings.HasPrefix(value, "/")
}

func isAbsoluteGuestPath(value string) bool {
	return strings.HasPrefix(value, "/") && value != "/" && !strings.Contains(value, "//") && !strings.Contains(value, "/../") && !strings.HasSuffix(value, "/..")
}

func outputPath(outputDirectory string, outputRelativePath string) string {
	return filepath.Join(outputDirectory, filepath.FromSlash(outputRelativePath))
}

func copyNewRegularFile(source string, destination string) error {
	if _, err := calculateRegularFileIdentity(source); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
		return err
	}
	target, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	defer target.Close()
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	_, err = io.Copy(target, input)
	return err
}

func writeNewFile(destination string, contents []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
		return err
	}
	file, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = file.Write(contents)
	return err
}

func requireAbsoluteRegularNonSymlinkFile(path string, role string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("%s path must be absolute", role)
	}
	_, err := calculateRegularFileIdentity(path)
	return err
}

func requireAbsoluteDirectoryNonSymlink(path string, role string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("%s path must be absolute", role)
	}
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("%s cannot be stated: %w", role, err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%s must be a directory non-symlink", role)
	}
	return nil
}

func requireEmptyDirectory(path string) error {
	entries, err := os.ReadDir(path)
	if err != nil {
		return err
	}
	if len(entries) != 0 {
		return fmt.Errorf("C35 compiler output directory must be empty")
	}
	return nil
}

func decodeOneStrictJSONDocument(contents []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return fmt.Errorf("JSON document must contain one object")
	}
	return nil
}
