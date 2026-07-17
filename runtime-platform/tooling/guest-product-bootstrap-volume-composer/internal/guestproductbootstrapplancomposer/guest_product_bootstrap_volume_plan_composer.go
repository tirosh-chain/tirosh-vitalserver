// Package guestproductbootstrapplancomposer derives C40 from complete,
// explicit Guest Product deployment and bootstrap inputs. It is pure: the
// NoCloud adapter owns byte reads and ISO9660 writes.
package guestproductbootstrapplancomposer

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"path"
	"sort"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

const generatedGuestProductSystemdUnitSourceID = "guest-product-systemd-unit"

// GuestProductBootstrapPayloadIdentity identifies one pre-staged product
// payload. Its source-relative path is preserved into C40 so a later adapter
// has no authority to discover release directories.
type GuestProductBootstrapPayloadIdentity struct {
	ID                 string
	SourceRelativePath string
	SizeBytes          int64
	SHA256             string
}

// GuestProductBootstrapPayloads maps a declared release role to its immutable
// source identity. The caller owns staging and source-file effects.
type GuestProductBootstrapPayloads map[string]GuestProductBootstrapPayloadIdentity

// GuestProductProcessDeploymentPaths is the C37 subset which must agree with
// the Guest-owned paths declared by C39.
type GuestProductProcessDeploymentPaths struct {
	GuestRuntimeExecutablePath    string
	GuestRuntimeStateDatabasePath string
	RecorderGatewayNodePath       string
	RecorderGatewayProgramPath    string
}

// GuestProductServiceManagerDeployment is the C38 subset that controls the
// declared service-unit vocabulary and Supervisor invocation.
type GuestProductServiceManagerDeployment struct {
	ServiceUnitName                       string
	SupervisorExecutablePath              string
	SupervisorDeploymentConfigurationPath string
}

// GuestProductBootstrapExecutablePayload declares one executable source and
// final Guest destination from C39.
type GuestProductBootstrapExecutablePayload struct {
	ArtifactID      string
	DestinationPath string
	FileMode        string
}

// GuestProductBootstrapConfigurationPayload declares one configuration source
// and final Guest destination from C39.
type GuestProductBootstrapConfigurationPayload struct {
	ArtifactID      string
	DestinationPath string
	FileMode        string
}

// GuestProductBootstrapRecorderGatewayArchive declares the sole archive
// payload that cloud-init can extract during the Guest-owned bootstrap.
type GuestProductBootstrapRecorderGatewayArchive struct {
	ArtifactID           string
	ArchiveFormat        string
	EntryModePolicy      string
	SymbolicLinkPolicy   string
	DestinationDirectory string
	RequiredArchivePaths []string
}

// GuestProductBootstrapServiceManagerPayload contains both C39 installation
// destinations and the enable-link intent. It intentionally does not contain
// an observed systemd state.
type GuestProductBootstrapServiceManagerPayload struct {
	ArtifactID                   string
	ConfigurationDestinationPath string
	UnitDestinationPath          string
	EnabledUnitLinkPath          string
	EnabledUnitLinkTargetPath    string
}

// GuestProductBootstrapConfiguration is C39's domain view. It describes a
// first-Guest-boot payload installation, not a Host filesystem operation.
type GuestProductBootstrapConfiguration struct {
	BootstrapID                               string
	VolumeLabel                               string
	GuestVolumeFileSystem                     string
	InstanceID                                string
	LocalHostName                             string
	GuestRuntime                              GuestProductBootstrapExecutablePayload
	GuestRuntimeStateDirectory                GuestProductBootstrapStateDirectory
	RecorderGatewayBundle                     GuestProductBootstrapRecorderGatewayArchive
	GuestProductProcessSupervisor             GuestProductBootstrapExecutablePayload
	GuestProductProcessDeployment             GuestProductBootstrapConfigurationPayload
	GuestProductVitalServerTopologyDeployment GuestProductBootstrapConfigurationPayload
	ExternalVitalServerDeliveryConfiguration  *GuestProductBootstrapConfigurationPayload
	GuestProductServiceManagerDeployment      GuestProductBootstrapServiceManagerPayload
}

// GuestProductBootstrapStateDirectory declares the Guest Runtime-owned
// mutable storage root that C40 must create before C38 starts C37.
type GuestProductBootstrapStateDirectory struct {
	DirectoryPath string
	DirectoryMode string
}

// GuestProductBootstrapVolumePlanComposition supplies every fact required to
// derive C40. GeneratedSystemdUnitContents are passed directly because C38's
// unit renderer owns their creation; this pure composer neither executes nor
// discovers it.
type GuestProductBootstrapVolumePlanComposition struct {
	ProcessDeployment            GuestProductProcessDeploymentPaths
	ServiceManagerDeployment     GuestProductServiceManagerDeployment
	BootstrapConfiguration       GuestProductBootstrapConfiguration
	Payloads                     GuestProductBootstrapPayloads
	GeneratedSystemdUnitContents []byte
}

// ComposeGuestProductBootstrapVolumePlan validates cross-contract agreements
// and returns one C40 plan. It creates no directories, reads no payload bytes,
// and performs no Guest or Host effect.
func ComposeGuestProductBootstrapVolumePlan(
	composition GuestProductBootstrapVolumePlanComposition,
) (guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan, error) {
	configuration := composition.BootstrapConfiguration
	if len(composition.GeneratedSystemdUnitContents) == 0 {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C38 generated systemd unit is empty")
	}
	if configuration.VolumeLabel != guestproductbootstrapvolumeplan.RequiredNoCloudVolumeLabel {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 volumeLabel must be %q", guestproductbootstrapvolumeplan.RequiredNoCloudVolumeLabel)
	}
	if configuration.GuestVolumeFileSystem != guestproductbootstrapvolumeplan.RequiredBootstrapVolumeFileSystem {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 guestBootstrapVolumeFileSystem must be %q", guestproductbootstrapvolumeplan.RequiredBootstrapVolumeFileSystem)
	}
	if composition.ProcessDeployment.GuestRuntimeExecutablePath != configuration.GuestRuntime.DestinationPath ||
		composition.ProcessDeployment.RecorderGatewayNodePath != configuration.RecorderGatewayBundle.DestinationDirectory+"/node/bin/node" ||
		composition.ProcessDeployment.RecorderGatewayProgramPath != configuration.RecorderGatewayBundle.DestinationDirectory+"/recorder-gateway/dist/cmd/recorder-gateway.js" {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C37 process paths do not match C39 Guest Product bootstrap destinations")
	}
	if path.Dir(composition.ProcessDeployment.GuestRuntimeStateDatabasePath) != configuration.GuestRuntimeStateDirectory.DirectoryPath {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C37 Guest Runtime state database parent does not match C39 Guest Runtime state directory")
	}
	serviceManager := configuration.GuestProductServiceManagerDeployment
	if composition.ServiceManagerDeployment.SupervisorExecutablePath != configuration.GuestProductProcessSupervisor.DestinationPath ||
		composition.ServiceManagerDeployment.SupervisorDeploymentConfigurationPath != configuration.GuestProductProcessDeployment.DestinationPath ||
		path.Base(serviceManager.UnitDestinationPath) != composition.ServiceManagerDeployment.ServiceUnitName ||
		serviceManager.EnabledUnitLinkTargetPath != serviceManager.UnitDestinationPath {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C38 service manager paths do not match C39 Guest Product bootstrap destinations")
	}

	plan := guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		SchemaVersion:         guestproductbootstrapvolumeplan.ExpectedSchemaVersion,
		BootstrapID:           configuration.BootstrapID,
		VolumeLabel:           configuration.VolumeLabel,
		StorageImageFormat:    guestproductbootstrapvolumeplan.RequiredBootstrapStorageImageFormat,
		GuestVolumeFileSystem: configuration.GuestVolumeFileSystem,
		InstanceID:            configuration.InstanceID,
		LocalHostName:         configuration.LocalHostName,
		ServiceUnitName:       composition.ServiceManagerDeployment.ServiceUnitName,
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: configuration.GuestRuntimeStateDirectory.DirectoryPath,
			DirectoryMode: configuration.GuestRuntimeStateDirectory.DirectoryMode,
		},
	}
	bootstrapPayloadArtifactIDs := []string{
		configuration.GuestRuntime.ArtifactID,
		configuration.RecorderGatewayBundle.ArtifactID,
		configuration.GuestProductProcessSupervisor.ArtifactID,
		configuration.GuestProductProcessDeployment.ArtifactID,
		configuration.GuestProductVitalServerTopologyDeployment.ArtifactID,
		serviceManager.ArtifactID,
	}
	if configuration.ExternalVitalServerDeliveryConfiguration != nil {
		bootstrapPayloadArtifactIDs = append(
			bootstrapPayloadArtifactIDs,
			configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID,
		)
	}
	for _, artifactID := range bootstrapPayloadArtifactIDs {
		payload, found := composition.Payloads[artifactID]
		if !found || payload.ID != artifactID {
			return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 bootstrap payload is missing or mismatched: %s", artifactID)
		}
		plan.Sources = append(plan.Sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
			ID: payload.ID, SourceRelativePath: payload.SourceRelativePath, SizeBytes: payload.SizeBytes, SHA256: payload.SHA256,
		})
	}
	unitDigest := sha256.Sum256(composition.GeneratedSystemdUnitContents)
	plan.Sources = append(plan.Sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
		ID: generatedGuestProductSystemdUnitSourceID, SourceRelativePath: "generated/" + composition.ServiceManagerDeployment.ServiceUnitName,
		SizeBytes: int64(len(composition.GeneratedSystemdUnitContents)), SHA256: hex.EncodeToString(unitDigest[:]),
	})
	sort.Slice(plan.Sources, func(left, right int) bool { return plan.Sources[left].ID < plan.Sources[right].ID })

	plan.FileInstallations = []guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
		{SourceID: configuration.GuestRuntime.ArtifactID, DestinationPath: configuration.GuestRuntime.DestinationPath, FileMode: configuration.GuestRuntime.FileMode},
		{SourceID: configuration.GuestProductProcessSupervisor.ArtifactID, DestinationPath: configuration.GuestProductProcessSupervisor.DestinationPath, FileMode: configuration.GuestProductProcessSupervisor.FileMode},
		{SourceID: configuration.GuestProductProcessDeployment.ArtifactID, DestinationPath: configuration.GuestProductProcessDeployment.DestinationPath, FileMode: configuration.GuestProductProcessDeployment.FileMode},
		{SourceID: configuration.GuestProductVitalServerTopologyDeployment.ArtifactID, DestinationPath: configuration.GuestProductVitalServerTopologyDeployment.DestinationPath, FileMode: configuration.GuestProductVitalServerTopologyDeployment.FileMode},
		{SourceID: serviceManager.ArtifactID, DestinationPath: serviceManager.ConfigurationDestinationPath, FileMode: "0644"},
		{SourceID: generatedGuestProductSystemdUnitSourceID, DestinationPath: serviceManager.UnitDestinationPath, FileMode: "0644"},
	}
	if configuration.ExternalVitalServerDeliveryConfiguration != nil {
		plan.FileInstallations = append(plan.FileInstallations, guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
			SourceID:        configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID,
			DestinationPath: configuration.ExternalVitalServerDeliveryConfiguration.DestinationPath,
			FileMode:        configuration.ExternalVitalServerDeliveryConfiguration.FileMode,
		})
	}
	plan.ArchiveInstallations = []guestproductbootstrapvolumeplan.DeclaredGuestArchiveInstallation{{
		SourceID: configuration.RecorderGatewayBundle.ArtifactID, ArchiveFormat: configuration.RecorderGatewayBundle.ArchiveFormat,
		EntryModePolicy: configuration.RecorderGatewayBundle.EntryModePolicy, SymbolicLinkPolicy: configuration.RecorderGatewayBundle.SymbolicLinkPolicy, DestinationDirectory: configuration.RecorderGatewayBundle.DestinationDirectory,
		RequiredArchivePaths: append([]string(nil), configuration.RecorderGatewayBundle.RequiredArchivePaths...),
	}}
	plan.SymbolicLinks = []guestproductbootstrapvolumeplan.DeclaredGuestSymbolicLink{{
		LinkPath: serviceManager.EnabledUnitLinkPath, TargetPath: serviceManager.EnabledUnitLinkTargetPath,
	}}
	if err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("derived C40 Guest Product bootstrap volume plan is invalid: %w", err)
	}
	return plan, nil
}

// SortedPayloadIdentities returns a stable copy for release-build adapters
// that need to stage every already-declared payload without discovering one.
func SortedPayloadIdentities(payloads GuestProductBootstrapPayloads) []GuestProductBootstrapPayloadIdentity {
	identities := make([]GuestProductBootstrapPayloadIdentity, 0, len(payloads))
	for _, payload := range payloads {
		identities = append(identities, payload)
	}
	sort.Slice(identities, func(left, right int) bool { return identities[left].ID < identities[right].ID })
	return identities
}

// ValidateSourceIdentityFormat checks the identifiers a C35 decode adapter
// supplies before it calls the pure plan composer. The C40 plan validator then
// remains the single semantic rule for the derived source declarations.
func ValidateSourceIdentityFormat(payload GuestProductBootstrapPayloadIdentity) error {
	if strings.TrimSpace(payload.ID) == "" || payload.SizeBytes < 1 || strings.TrimSpace(payload.SourceRelativePath) == "" || len(payload.SHA256) != 64 {
		return fmt.Errorf("Guest Product bootstrap payload identity is incomplete")
	}
	return nil
}
