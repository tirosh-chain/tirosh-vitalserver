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
const generatedGuestProductReleaseManagerSystemdUnitSourceID = "guest-product-release-manager-systemd-unit"
const generatedGuestBundledUpstreamImageSetManagerSystemdUnitSourceID = "guest-bundled-upstream-image-set-manager-systemd-unit"
const generatedGuestTimeSynchronizationConfigurationSourceID = "guest-time-synchronization-configuration"

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
	GuestRuntimeExecutablePath                                   string
	GuestRuntimeStateDatabasePath                                string
	RecorderCatalogDatabaseURLMaterialPath                       string
	RecorderCatalogMigrationReceiptPath                          string
	RecorderCatalogAdmissionBearerTokenMaterialPath              string
	ArchiveSourceAdmissionBearerTokenMaterialPath                string
	ArchiveArtifactObjectRootDirectory                           string
	RecorderGatewayNodePath                                      string
	RecorderGatewayProgramPath                                   string
	RecorderGatewayObservationCatalogBearerTokenMaterialPath     string
	RecorderGatewayArchiveSourceAdmissionBearerTokenMaterialPath string
	LabRecorderRunnerNodePath                                    string
	LabRecorderRunnerProgramPath                                 string
	LabScenarioCatalogPath                                       string
	GuestTelemetryCollectorExecutablePath                        string
	GuestTelemetryCollectorConfigurationPath                     string
	GuestTimeAuthorityKind                                       string
	GuestTimeAuthorityNTPServerHost                              string
	GuestTimeAuthorityNTPServerPort                              int
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

// GuestProductBootstrapNodeServicesArchive declares the sole archive payload
// that cloud-init can extract during the Guest-owned bootstrap. It contains
// the exact Node runtime and both Guest-local Node services, not a proxy for a
// single service's process state.
type GuestProductBootstrapNodeServicesArchive struct {
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

// GuestProductBootstrapReleaseManager keeps the release mutator as a distinct
// systemd unit. It must not be a child of the product supervisor: it is the
// component that restarts that supervisor after an atomic current-link change.
type GuestProductBootstrapReleaseManager struct {
	Executable    GuestProductBootstrapExecutablePayload
	Configuration GuestProductBootstrapConfigurationPayload
	ServiceUnit   GuestProductBootstrapReleaseManagerServiceUnit
}

type GuestProductBootstrapReleaseManagerServiceUnit struct {
	ServiceUnitName           string
	UnitDestinationPath       string
	EnabledUnitLinkPath       string
	EnabledUnitLinkTargetPath string
	RestartMode               string
	RestartDelayMilliseconds  int64
	StandardOutput            string
	StandardError             string
	WantedByTarget            string
}

// GuestProductBootstrapBundledUpstreamImageSetManager is the C39 declaration
// for the independently supervised C64 service. Its state stays outside the
// immutable Guest Product release while its executable and configuration move
// atomically with that release through the current-release link.
type GuestProductBootstrapBundledUpstreamImageSetManager struct {
	ManagerID                  string
	Executable                 GuestProductBootstrapExecutablePayload
	Configuration              GuestProductBootstrapConfigurationPayload
	StateDirectory             GuestProductBootstrapStateDirectory
	ContainerEngineBootstrap   GuestProductBootstrapContainerEngineBootstrap
	ServiceUnit                GuestProductBootstrapReleaseManagerServiceUnit
	InitialActiveImageSetState string
}

// GuestProductBootstrapContainerEngineBootstrap declares the one Guest OS
// package/service C40 installs before it starts C64. It is desired input, not
// a discovery of whatever container engine happens to be in the base image.
type GuestProductBootstrapContainerEngineBootstrap struct {
	PackageManager string
	PackageName    string
	ServiceName    string
}

// GuestProductBootstrapTimeSynchronization declares the selected first-boot
// package/service/configuration boundary. C37 owns the actual Chrony source;
// C39 only chooses the Guest installation location and service manager.
type GuestProductBootstrapTimeSynchronization struct {
	PackageManager               string
	PackageName                  string
	ServiceName                  string
	ConfigurationDestinationPath string
}

// GuestProductBootstrapRecorderCatalogPostgreSQL declares the only supported
// first-boot database and migration effect. Every private path must agree with
// C37; generated values never appear in C39.
type GuestProductBootstrapRecorderCatalogPostgreSQL struct {
	PackageManager                                string
	PackageNames                                  []string
	ServiceName                                   string
	DatabaseHost                                  string
	DatabasePort                                  int
	DatabaseName                                  string
	DatabaseRoleName                              string
	DatabaseURLMaterialPath                       string
	CatalogAdmissionBearerTokenMaterialPath       string
	ArchiveSourceAdmissionBearerTokenMaterialPath string
	GeneratedSecretByteCount                      int
	MigrationExecutablePath                       string
	MigrationPythonExecutablePath                 string
	ExpectedRevision                              string
	MigrationReceiptPath                          string
}

// GuestProductBootstrapConfiguration is C39's domain view. It describes a
// first-Guest-boot payload installation, not a Host filesystem operation.
type GuestProductBootstrapConfiguration struct {
	BootstrapID                               string
	VolumeLabel                               string
	GuestVolumeFileSystem                     string
	InstanceID                                string
	LocalHostName                             string
	GuestArchitecture                         string
	GuestProductRelease                       GuestProductBootstrapRelease
	GuestRuntime                              GuestProductBootstrapExecutablePayload
	GuestRuntimeStateDirectory                GuestProductBootstrapStateDirectory
	GuestPrivateStateDirectory                GuestProductBootstrapStateDirectory
	GuestArchiveArtifactObjectDirectory       GuestProductBootstrapStateDirectory
	GuestRecorderCatalogPostgreSQL            GuestProductBootstrapRecorderCatalogPostgreSQL
	GuestTelemetryCollector                   *GuestProductBootstrapExecutablePayload
	GuestTelemetryCollectorConfiguration      *GuestProductBootstrapConfigurationPayload
	GuestTelemetryStateDirectory              *GuestProductBootstrapStateDirectory
	GuestTimeSynchronization                  *GuestProductBootstrapTimeSynchronization
	GuestNodeServicesBundle                   GuestProductBootstrapNodeServicesArchive
	GuestProductProcessSupervisor             GuestProductBootstrapExecutablePayload
	GuestProductProcessDeployment             GuestProductBootstrapConfigurationPayload
	GuestProductReleaseManager                GuestProductBootstrapReleaseManager
	GuestProductVitalServerTopologyDeployment GuestProductBootstrapConfigurationPayload
	ExternalVitalServerDeliveryConfiguration  *GuestProductBootstrapConfigurationPayload
	GuestBundledUpstreamImageSetManager       *GuestProductBootstrapBundledUpstreamImageSetManager
	GuestProductServiceManagerDeployment      GuestProductBootstrapServiceManagerPayload
}

// GuestProductBootstrapRelease names the immutable Guest Product code and
// configuration directory selected at first boot. The mutable current link is
// a Guest Product Release Manager boundary; C40 can initialize it but never
// retarget an already activated release.
type GuestProductBootstrapRelease struct {
	ReleaseID                 string
	ReleaseDirectory          string
	CurrentReleaseLinkPath    string
	ReleaseStateDirectory     string
	ReleaseStateDirectoryMode string
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
	ProcessDeployment                                          GuestProductProcessDeploymentPaths
	ServiceManagerDeployment                                   GuestProductServiceManagerDeployment
	BootstrapConfiguration                                     GuestProductBootstrapConfiguration
	Payloads                                                   GuestProductBootstrapPayloads
	GeneratedSystemdUnitContents                               []byte
	GeneratedReleaseManagerSystemdUnitContents                 []byte
	GeneratedBundledUpstreamImageSetManagerSystemdUnitContents []byte
}

// ComposeGuestProductBootstrapVolumePlan validates cross-contract agreements
// and returns one C40 plan. It creates no directories, reads no payload bytes,
// and performs no Guest or Host effect.
func ComposeGuestProductBootstrapVolumePlan(
	composition GuestProductBootstrapVolumePlanComposition,
) (guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan, error) {
	configuration := composition.BootstrapConfiguration
	if len(composition.GeneratedSystemdUnitContents) == 0 || len(composition.GeneratedReleaseManagerSystemdUnitContents) == 0 {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C38 generated systemd unit is empty")
	}
	if configuration.VolumeLabel != guestproductbootstrapvolumeplan.RequiredNoCloudVolumeLabel {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 volumeLabel must be %q", guestproductbootstrapvolumeplan.RequiredNoCloudVolumeLabel)
	}
	if configuration.GuestVolumeFileSystem != guestproductbootstrapvolumeplan.RequiredBootstrapVolumeFileSystem {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 guestBootstrapVolumeFileSystem must be %q", guestproductbootstrapvolumeplan.RequiredBootstrapVolumeFileSystem)
	}
	if configuration.GuestArchitecture != "arm64" && configuration.GuestArchitecture != "amd64" {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 guestArchitecture must be arm64 or amd64")
	}
	if !validGuestProductBootstrapRelease(configuration.GuestProductRelease) {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 Guest Product release declaration is invalid")
	}
	if !pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestRuntime.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductProcessSupervisor.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductProcessDeployment.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductReleaseManager.Executable.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductReleaseManager.Configuration.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductVitalServerTopologyDeployment.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestProductServiceManagerDeployment.ConfigurationDestinationPath) ||
		!pathAtOrBelowGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestNodeServicesBundle.DestinationDirectory) {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 Guest Product release payload destinations must stay below its immutable release directory")
	}
	if configuration.GuestTelemetryCollector != nil && (!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestTelemetryCollector.DestinationPath) || !pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.GuestTelemetryCollectorConfiguration.DestinationPath)) {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 Guest telemetry Collector payload destinations must stay below the immutable Guest Product release directory")
	}
	if configuration.ExternalVitalServerDeliveryConfiguration != nil && !pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, configuration.ExternalVitalServerDeliveryConfiguration.DestinationPath) {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 external VitalServer delivery configuration must stay below the immutable Guest Product release directory")
	}
	if bundledManager := configuration.GuestBundledUpstreamImageSetManager; bundledManager != nil {
		if len(composition.GeneratedBundledUpstreamImageSetManagerSystemdUnitContents) == 0 || !validGuestProductBootstrapBundledUpstreamImageSetManager(configuration.GuestProductRelease, *bundledManager) {
			return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 Guest Bundled Upstream Image-set Manager payload or service unit is invalid")
		}
	}
	if composition.ProcessDeployment.GuestRuntimeExecutablePath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestRuntime.DestinationPath) ||
		composition.ProcessDeployment.RecorderGatewayNodePath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestNodeServicesBundle.DestinationDirectory+"/node/bin/node") ||
		composition.ProcessDeployment.RecorderGatewayProgramPath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestNodeServicesBundle.DestinationDirectory+"/recorder-gateway/dist/cmd/recorder-gateway.js") ||
		composition.ProcessDeployment.LabRecorderRunnerNodePath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestNodeServicesBundle.DestinationDirectory+"/node/bin/node") ||
		composition.ProcessDeployment.LabRecorderRunnerProgramPath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestNodeServicesBundle.DestinationDirectory+"/lab-recorder-runner/dist/cmd/lab-recorder-runner.js") ||
		composition.ProcessDeployment.LabScenarioCatalogPath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestNodeServicesBundle.DestinationDirectory+"/lab-recorder-runner/lab-scenario-catalog.json") {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C37 process paths do not match the activated C39 Guest Product release")
	}
	if path.Dir(composition.ProcessDeployment.GuestRuntimeStateDatabasePath) != configuration.GuestRuntimeStateDirectory.DirectoryPath {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C37 Guest Runtime state database parent does not match C39 Guest Runtime state directory")
	}
	recorderCatalog := configuration.GuestRecorderCatalogPostgreSQL
	if composition.ProcessDeployment.RecorderCatalogDatabaseURLMaterialPath != recorderCatalog.DatabaseURLMaterialPath ||
		composition.ProcessDeployment.RecorderCatalogMigrationReceiptPath != recorderCatalog.MigrationReceiptPath ||
		composition.ProcessDeployment.RecorderCatalogAdmissionBearerTokenMaterialPath != recorderCatalog.CatalogAdmissionBearerTokenMaterialPath ||
		composition.ProcessDeployment.ArchiveSourceAdmissionBearerTokenMaterialPath != recorderCatalog.ArchiveSourceAdmissionBearerTokenMaterialPath ||
		composition.ProcessDeployment.RecorderGatewayObservationCatalogBearerTokenMaterialPath != recorderCatalog.CatalogAdmissionBearerTokenMaterialPath ||
		composition.ProcessDeployment.RecorderGatewayArchiveSourceAdmissionBearerTokenMaterialPath != recorderCatalog.ArchiveSourceAdmissionBearerTokenMaterialPath ||
		composition.ProcessDeployment.ArchiveArtifactObjectRootDirectory != configuration.GuestArchiveArtifactObjectDirectory.DirectoryPath {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C37 private material or Archive object paths do not match C39 PostgreSQL bootstrap ownership")
	}
	if err := validateTelemetryCollectorBootstrapAgreement(composition.ProcessDeployment, configuration); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, err
	}
	if err := validateGuestTimeSynchronizationBootstrapAgreement(composition.ProcessDeployment, configuration); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, err
	}
	serviceManager := configuration.GuestProductServiceManagerDeployment
	if composition.ServiceManagerDeployment.SupervisorExecutablePath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestProductProcessSupervisor.DestinationPath) ||
		composition.ServiceManagerDeployment.SupervisorDeploymentConfigurationPath != activatedGuestProductReleasePath(configuration.GuestProductRelease, configuration.GuestProductProcessDeployment.DestinationPath) ||
		path.Base(serviceManager.UnitDestinationPath) != composition.ServiceManagerDeployment.ServiceUnitName ||
		serviceManager.EnabledUnitLinkTargetPath != serviceManager.UnitDestinationPath {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C38 service manager paths do not match C39 Guest Product bootstrap destinations")
	}
	releaseManager := configuration.GuestProductReleaseManager
	if releaseManager.ServiceUnit.ServiceUnitName != "vitalserver-guest-product-release-manager.service" ||
		releaseManager.ServiceUnit.EnabledUnitLinkTargetPath != releaseManager.ServiceUnit.UnitDestinationPath ||
		path.Base(releaseManager.ServiceUnit.UnitDestinationPath) != releaseManager.ServiceUnit.ServiceUnitName ||
		releaseManager.ServiceUnit.RestartMode != "on-failure" || releaseManager.ServiceUnit.RestartDelayMilliseconds < 0 ||
		releaseManager.ServiceUnit.StandardOutput != "journal+console" || releaseManager.ServiceUnit.StandardError != "journal+console" || releaseManager.ServiceUnit.WantedByTarget != "multi-user.target" ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, releaseManager.Executable.DestinationPath) ||
		!pathWithinGuestRelease(configuration.GuestProductRelease.ReleaseDirectory, releaseManager.Configuration.DestinationPath) {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C39 Guest Product Release Manager payload or service unit is invalid")
	}

	plan := guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		SchemaVersion:                 guestproductbootstrapvolumeplan.ExpectedSchemaVersion,
		BootstrapID:                   configuration.BootstrapID,
		VolumeLabel:                   configuration.VolumeLabel,
		StorageImageFormat:            guestproductbootstrapvolumeplan.RequiredBootstrapStorageImageFormat,
		GuestVolumeFileSystem:         configuration.GuestVolumeFileSystem,
		InstanceID:                    configuration.InstanceID,
		LocalHostName:                 configuration.LocalHostName,
		ServiceUnitName:               composition.ServiceManagerDeployment.ServiceUnitName,
		ReleaseManagerServiceUnitName: releaseManager.ServiceUnit.ServiceUnitName,
		GuestProductRelease: guestproductbootstrapvolumeplan.DeclaredGuestProductRelease{
			ReleaseID:                 configuration.GuestProductRelease.ReleaseID,
			ReleaseDirectory:          configuration.GuestProductRelease.ReleaseDirectory,
			CurrentReleaseLinkPath:    configuration.GuestProductRelease.CurrentReleaseLinkPath,
			ReleaseStateDirectory:     configuration.GuestProductRelease.ReleaseStateDirectory,
			ReleaseStateDirectoryMode: configuration.GuestProductRelease.ReleaseStateDirectoryMode,
		},
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: configuration.GuestRuntimeStateDirectory.DirectoryPath,
			DirectoryMode: configuration.GuestRuntimeStateDirectory.DirectoryMode,
		},
		GuestPrivateStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: configuration.GuestPrivateStateDirectory.DirectoryPath,
			DirectoryMode: configuration.GuestPrivateStateDirectory.DirectoryMode,
		},
		GuestArchiveArtifactObjectDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: configuration.GuestArchiveArtifactObjectDirectory.DirectoryPath,
			DirectoryMode: configuration.GuestArchiveArtifactObjectDirectory.DirectoryMode,
		},
		GuestRecorderCatalogPostgreSQL: guestproductbootstrapvolumeplan.DeclaredGuestRecorderCatalogPostgreSQL{
			PackageManager:                          recorderCatalog.PackageManager,
			PackageNames:                            append([]string(nil), recorderCatalog.PackageNames...),
			ServiceName:                             recorderCatalog.ServiceName,
			DatabaseHost:                            recorderCatalog.DatabaseHost,
			DatabasePort:                            recorderCatalog.DatabasePort,
			DatabaseName:                            recorderCatalog.DatabaseName,
			DatabaseRoleName:                        recorderCatalog.DatabaseRoleName,
			DatabaseURLMaterialPath:                 recorderCatalog.DatabaseURLMaterialPath,
			CatalogAdmissionBearerTokenMaterialPath: recorderCatalog.CatalogAdmissionBearerTokenMaterialPath,
			ArchiveSourceAdmissionBearerTokenMaterialPath: recorderCatalog.ArchiveSourceAdmissionBearerTokenMaterialPath,
			GeneratedSecretByteCount:                      recorderCatalog.GeneratedSecretByteCount,
			MigrationExecutablePath:                       recorderCatalog.MigrationExecutablePath,
			MigrationPythonExecutablePath:                 recorderCatalog.MigrationPythonExecutablePath,
			ExpectedRevision:                              recorderCatalog.ExpectedRevision,
			MigrationReceiptPath:                          recorderCatalog.MigrationReceiptPath,
		},
	}
	if configuration.GuestTelemetryStateDirectory != nil {
		plan.GuestTelemetryStateDirectory = &guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: configuration.GuestTelemetryStateDirectory.DirectoryPath,
			DirectoryMode: configuration.GuestTelemetryStateDirectory.DirectoryMode,
		}
	}
	if configuration.GuestTimeSynchronization != nil {
		plan.GuestTimeSynchronization = &guestproductbootstrapvolumeplan.DeclaredGuestTimeSynchronization{
			PackageManager: configuration.GuestTimeSynchronization.PackageManager,
			PackageName:    configuration.GuestTimeSynchronization.PackageName,
			ServiceName:    configuration.GuestTimeSynchronization.ServiceName,
		}
		timeSynchronizationConfiguration := RenderGuestTimeSynchronizationConfiguration(composition.ProcessDeployment)
		timeSynchronizationDigest := sha256.Sum256([]byte(timeSynchronizationConfiguration))
		plan.Sources = append(plan.Sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
			ID: generatedGuestTimeSynchronizationConfigurationSourceID, SourceRelativePath: "generated/chrony.conf",
			SizeBytes: int64(len(timeSynchronizationConfiguration)), SHA256: hex.EncodeToString(timeSynchronizationDigest[:]),
		})
	}
	bootstrapPayloadArtifactIDs := []string{
		configuration.GuestRuntime.ArtifactID,
		configuration.GuestNodeServicesBundle.ArtifactID,
		configuration.GuestProductProcessSupervisor.ArtifactID,
		configuration.GuestProductProcessDeployment.ArtifactID,
		configuration.GuestProductReleaseManager.Executable.ArtifactID,
		configuration.GuestProductReleaseManager.Configuration.ArtifactID,
		configuration.GuestProductVitalServerTopologyDeployment.ArtifactID,
		serviceManager.ArtifactID,
	}
	if configuration.GuestTelemetryCollector != nil {
		bootstrapPayloadArtifactIDs = append(bootstrapPayloadArtifactIDs,
			configuration.GuestTelemetryCollector.ArtifactID,
			configuration.GuestTelemetryCollectorConfiguration.ArtifactID,
		)
	}
	if configuration.ExternalVitalServerDeliveryConfiguration != nil {
		bootstrapPayloadArtifactIDs = append(
			bootstrapPayloadArtifactIDs,
			configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID,
		)
	}
	if bundledManager := configuration.GuestBundledUpstreamImageSetManager; bundledManager != nil {
		bootstrapPayloadArtifactIDs = append(bootstrapPayloadArtifactIDs, bundledManager.Executable.ArtifactID, bundledManager.Configuration.ArtifactID)
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
	if bundledManager := configuration.GuestBundledUpstreamImageSetManager; bundledManager != nil {
		bundledManagerUnitDigest := sha256.Sum256(composition.GeneratedBundledUpstreamImageSetManagerSystemdUnitContents)
		plan.Sources = append(plan.Sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
			ID: generatedGuestBundledUpstreamImageSetManagerSystemdUnitSourceID, SourceRelativePath: "generated/" + bundledManager.ServiceUnit.ServiceUnitName,
			SizeBytes: int64(len(composition.GeneratedBundledUpstreamImageSetManagerSystemdUnitContents)), SHA256: hex.EncodeToString(bundledManagerUnitDigest[:]),
		})
	}
	releaseManagerUnitDigest := sha256.Sum256(composition.GeneratedReleaseManagerSystemdUnitContents)
	plan.Sources = append(plan.Sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
		ID: generatedGuestProductReleaseManagerSystemdUnitSourceID, SourceRelativePath: "generated/" + releaseManager.ServiceUnit.ServiceUnitName,
		SizeBytes: int64(len(composition.GeneratedReleaseManagerSystemdUnitContents)), SHA256: hex.EncodeToString(releaseManagerUnitDigest[:]),
	})
	sort.Slice(plan.Sources, func(left, right int) bool { return plan.Sources[left].ID < plan.Sources[right].ID })

	plan.FileInstallations = []guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
		{SourceID: configuration.GuestRuntime.ArtifactID, DestinationPath: configuration.GuestRuntime.DestinationPath, FileMode: configuration.GuestRuntime.FileMode},
		{SourceID: configuration.GuestProductProcessSupervisor.ArtifactID, DestinationPath: configuration.GuestProductProcessSupervisor.DestinationPath, FileMode: configuration.GuestProductProcessSupervisor.FileMode},
		{SourceID: configuration.GuestProductProcessDeployment.ArtifactID, DestinationPath: configuration.GuestProductProcessDeployment.DestinationPath, FileMode: configuration.GuestProductProcessDeployment.FileMode},
		{SourceID: releaseManager.Executable.ArtifactID, DestinationPath: releaseManager.Executable.DestinationPath, FileMode: releaseManager.Executable.FileMode},
		{SourceID: releaseManager.Configuration.ArtifactID, DestinationPath: releaseManager.Configuration.DestinationPath, FileMode: releaseManager.Configuration.FileMode},
		{SourceID: configuration.GuestProductVitalServerTopologyDeployment.ArtifactID, DestinationPath: configuration.GuestProductVitalServerTopologyDeployment.DestinationPath, FileMode: configuration.GuestProductVitalServerTopologyDeployment.FileMode},
		{SourceID: serviceManager.ArtifactID, DestinationPath: serviceManager.ConfigurationDestinationPath, FileMode: "0644"},
		{SourceID: generatedGuestProductSystemdUnitSourceID, DestinationPath: serviceManager.UnitDestinationPath, FileMode: "0644"},
		{SourceID: generatedGuestProductReleaseManagerSystemdUnitSourceID, DestinationPath: releaseManager.ServiceUnit.UnitDestinationPath, FileMode: "0644"},
	}
	if configuration.GuestTelemetryCollector != nil {
		plan.FileInstallations = append(plan.FileInstallations,
			guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{SourceID: configuration.GuestTelemetryCollector.ArtifactID, DestinationPath: configuration.GuestTelemetryCollector.DestinationPath, FileMode: configuration.GuestTelemetryCollector.FileMode},
			guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{SourceID: configuration.GuestTelemetryCollectorConfiguration.ArtifactID, DestinationPath: configuration.GuestTelemetryCollectorConfiguration.DestinationPath, FileMode: configuration.GuestTelemetryCollectorConfiguration.FileMode},
		)
	}
	if configuration.ExternalVitalServerDeliveryConfiguration != nil {
		plan.FileInstallations = append(plan.FileInstallations, guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
			SourceID:        configuration.ExternalVitalServerDeliveryConfiguration.ArtifactID,
			DestinationPath: configuration.ExternalVitalServerDeliveryConfiguration.DestinationPath,
			FileMode:        configuration.ExternalVitalServerDeliveryConfiguration.FileMode,
		})
	}
	if bundledManager := configuration.GuestBundledUpstreamImageSetManager; bundledManager != nil {
		plan.FileInstallations = append(plan.FileInstallations,
			guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{SourceID: bundledManager.Executable.ArtifactID, DestinationPath: bundledManager.Executable.DestinationPath, FileMode: bundledManager.Executable.FileMode},
			guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{SourceID: bundledManager.Configuration.ArtifactID, DestinationPath: bundledManager.Configuration.DestinationPath, FileMode: bundledManager.Configuration.FileMode},
			guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{SourceID: generatedGuestBundledUpstreamImageSetManagerSystemdUnitSourceID, DestinationPath: bundledManager.ServiceUnit.UnitDestinationPath, FileMode: "0644"},
		)
		plan.GuestBundledUpstreamImageSetManager = &guestproductbootstrapvolumeplan.DeclaredGuestBundledUpstreamImageSetManager{
			ManagerID:                  bundledManager.ManagerID,
			ExecutablePath:             activatedGuestProductReleasePath(configuration.GuestProductRelease, bundledManager.Executable.DestinationPath),
			ConfigurationPath:          activatedGuestProductReleasePath(configuration.GuestProductRelease, bundledManager.Configuration.DestinationPath),
			StateDirectory:             guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: bundledManager.StateDirectory.DirectoryPath, DirectoryMode: bundledManager.StateDirectory.DirectoryMode},
			ContainerEngineBootstrap:   guestproductbootstrapvolumeplan.DeclaredGuestContainerEngineBootstrap{PackageManager: bundledManager.ContainerEngineBootstrap.PackageManager, PackageName: bundledManager.ContainerEngineBootstrap.PackageName, ServiceName: bundledManager.ContainerEngineBootstrap.ServiceName},
			ServiceUnitName:            bundledManager.ServiceUnit.ServiceUnitName,
			InitialActiveImageSetState: bundledManager.InitialActiveImageSetState,
		}
	}
	if configuration.GuestTimeSynchronization != nil {
		plan.FileInstallations = append(plan.FileInstallations, guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
			SourceID: generatedGuestTimeSynchronizationConfigurationSourceID, DestinationPath: configuration.GuestTimeSynchronization.ConfigurationDestinationPath, FileMode: "0644",
		})
	}
	plan.ArchiveInstallations = []guestproductbootstrapvolumeplan.DeclaredGuestArchiveInstallation{{
		SourceID: configuration.GuestNodeServicesBundle.ArtifactID, ArchiveFormat: configuration.GuestNodeServicesBundle.ArchiveFormat,
		EntryModePolicy: configuration.GuestNodeServicesBundle.EntryModePolicy, SymbolicLinkPolicy: configuration.GuestNodeServicesBundle.SymbolicLinkPolicy, DestinationDirectory: configuration.GuestNodeServicesBundle.DestinationDirectory,
		RequiredArchivePaths: append([]string(nil), configuration.GuestNodeServicesBundle.RequiredArchivePaths...),
	}}
	plan.SymbolicLinks = []guestproductbootstrapvolumeplan.DeclaredGuestSymbolicLink{
		{LinkPath: serviceManager.EnabledUnitLinkPath, TargetPath: serviceManager.EnabledUnitLinkTargetPath},
		{LinkPath: releaseManager.ServiceUnit.EnabledUnitLinkPath, TargetPath: releaseManager.ServiceUnit.EnabledUnitLinkTargetPath},
	}
	if bundledManager := configuration.GuestBundledUpstreamImageSetManager; bundledManager != nil {
		plan.SymbolicLinks = append(plan.SymbolicLinks, guestproductbootstrapvolumeplan.DeclaredGuestSymbolicLink{LinkPath: bundledManager.ServiceUnit.EnabledUnitLinkPath, TargetPath: bundledManager.ServiceUnit.EnabledUnitLinkTargetPath})
	}
	if err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("derived C40 Guest Product bootstrap volume plan is invalid: %w", err)
	}
	return plan, nil
}

func validGuestProductBootstrapBundledUpstreamImageSetManager(release GuestProductBootstrapRelease, manager GuestProductBootstrapBundledUpstreamImageSetManager) bool {
	unit := manager.ServiceUnit
	return manager.ManagerID != "" && manager.InitialActiveImageSetState == "unprovisioned" &&
		manager.Executable.ArtifactID != "" && manager.Executable.FileMode == "0755" && pathWithinGuestRelease(release.ReleaseDirectory, manager.Executable.DestinationPath) &&
		manager.Configuration.ArtifactID == "guest-bundled-upstream-image-set-manager-configuration" && manager.Configuration.FileMode == "0644" && pathWithinGuestRelease(release.ReleaseDirectory, manager.Configuration.DestinationPath) &&
		guestproductbootstrapvolumeplan.IsSafeAbsoluteGuestPath(manager.StateDirectory.DirectoryPath) && manager.StateDirectory.DirectoryMode == "0700" && manager.ContainerEngineBootstrap.PackageManager == "apt" && manager.ContainerEngineBootstrap.PackageName == "docker.io" && manager.ContainerEngineBootstrap.ServiceName == "docker.service" &&
		unit.ServiceUnitName == "vitalserver-guest-bundled-upstream-image-set-manager.service" && unit.EnabledUnitLinkTargetPath == unit.UnitDestinationPath && path.Base(unit.UnitDestinationPath) == unit.ServiceUnitName &&
		unit.RestartMode == "on-failure" && unit.RestartDelayMilliseconds >= 0 && unit.StandardOutput == "journal+console" && unit.StandardError == "journal+console" && unit.WantedByTarget == "multi-user.target"
}

func validGuestProductBootstrapRelease(release GuestProductBootstrapRelease) bool {
	if !guestproductbootstrapvolumeplan.IsSafeAbsoluteGuestPath(release.ReleaseDirectory) ||
		!guestproductbootstrapvolumeplan.IsSafeAbsoluteGuestPath(release.CurrentReleaseLinkPath) ||
		!guestproductbootstrapvolumeplan.IsSafeAbsoluteGuestPath(release.ReleaseStateDirectory) ||
		release.ReleaseStateDirectoryMode != "0700" || release.ReleaseID == "" {
		return false
	}
	if release.ReleaseDirectory == release.CurrentReleaseLinkPath ||
		release.ReleaseDirectory == release.ReleaseStateDirectory ||
		release.CurrentReleaseLinkPath == release.ReleaseStateDirectory {
		return false
	}
	return path.Base(release.ReleaseDirectory) == release.ReleaseID &&
		path.Dir(release.CurrentReleaseLinkPath) == path.Dir(path.Dir(release.ReleaseDirectory))
}

func pathWithinGuestRelease(releaseDirectory string, candidate string) bool {
	return candidate != releaseDirectory && strings.HasPrefix(candidate, releaseDirectory+"/")
}

func pathAtOrBelowGuestRelease(releaseDirectory string, candidate string) bool {
	return candidate == releaseDirectory || pathWithinGuestRelease(releaseDirectory, candidate)
}

func activatedGuestProductReleasePath(release GuestProductBootstrapRelease, releasePath string) string {
	if !pathWithinGuestRelease(release.ReleaseDirectory, releasePath) {
		return ""
	}
	relative := strings.TrimPrefix(releasePath, release.ReleaseDirectory+"/")
	return path.Join(release.CurrentReleaseLinkPath, relative)
}

func validateGuestTimeSynchronizationBootstrapAgreement(process GuestProductProcessDeploymentPaths, configuration GuestProductBootstrapConfiguration) error {
	timeSynchronization := configuration.GuestTimeSynchronization
	if timeSynchronization == nil {
		return nil
	}
	if process.GuestTimeAuthorityKind != "chrony-tracking" || !validNTPServerHost(process.GuestTimeAuthorityNTPServerHost) || process.GuestTimeAuthorityNTPServerPort < 1 || process.GuestTimeAuthorityNTPServerPort > 65535 {
		return fmt.Errorf("C39 Guest time synchronization requires explicit C37 chrony-tracking NTP server host and port")
	}
	if timeSynchronization.PackageManager != "apt" || timeSynchronization.PackageName != "chrony" || timeSynchronization.ServiceName != "chrony.service" || !guestproductbootstrapvolumeplan.IsSafeAbsoluteGuestPath(timeSynchronization.ConfigurationDestinationPath) {
		return fmt.Errorf("C39 Guest time synchronization declaration is invalid")
	}
	return nil
}

// RenderGuestTimeSynchronizationConfiguration produces the only generated
// Guest clock-service configuration. Its inputs were validated by the pure
// C37/C39 agreement check before this value is used by a release adapter.
func RenderGuestTimeSynchronizationConfiguration(process GuestProductProcessDeploymentPaths) string {
	return "# Managed by VitalServer Guest Product bootstrap.\n" +
		"server " + process.GuestTimeAuthorityNTPServerHost + " port " + fmt.Sprintf("%d", process.GuestTimeAuthorityNTPServerPort) + " iburst\n" +
		"makestep 1.0 3\nrtcsync\n"
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

func validateTelemetryCollectorBootstrapAgreement(process GuestProductProcessDeploymentPaths, configuration GuestProductBootstrapConfiguration) error {
	collector := configuration.GuestTelemetryCollector
	collectorConfiguration := configuration.GuestTelemetryCollectorConfiguration
	stateDirectory := configuration.GuestTelemetryStateDirectory
	if collector == nil && collectorConfiguration == nil && stateDirectory == nil {
		if process.GuestTelemetryCollectorExecutablePath != "" || process.GuestTelemetryCollectorConfigurationPath != "" {
			return fmt.Errorf("C37 telemetry Collector paths require C39 telemetry Collector payloads and state directory")
		}
		return nil
	}
	if collector == nil || collectorConfiguration == nil || stateDirectory == nil {
		return fmt.Errorf("C39 telemetry Collector executable, configuration, and state directory must be declared together")
	}
	if process.GuestTelemetryCollectorExecutablePath != activatedGuestProductReleasePath(configuration.GuestProductRelease, collector.DestinationPath) || process.GuestTelemetryCollectorConfigurationPath != activatedGuestProductReleasePath(configuration.GuestProductRelease, collectorConfiguration.DestinationPath) {
		return fmt.Errorf("C37 telemetry Collector paths do not match the activated C39 Guest Product release")
	}
	if collector.ArtifactID != "guest-telemetry-collector-linux-"+configuration.GuestArchitecture || collector.FileMode != "0755" || collectorConfiguration.ArtifactID != "guest-telemetry-collector-configuration" || collectorConfiguration.FileMode != "0644" || stateDirectory.DirectoryMode != "0700" {
		return fmt.Errorf("C39 telemetry Collector bootstrap payloads or state directory are invalid")
	}
	return nil
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
