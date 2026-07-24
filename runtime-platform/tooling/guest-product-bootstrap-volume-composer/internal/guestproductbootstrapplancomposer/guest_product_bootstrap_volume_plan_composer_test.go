package guestproductbootstrapplancomposer_test

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapplancomposer"
)

func TestComposeGuestProductBootstrapVolumePlanPreservesExplicitOwnershipAndPayloadIdentity(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 plan: %v", err)
	}
	if plan.ServiceUnitName != "vitalserver-guest-product.service" {
		t.Fatalf("service unit=%q", plan.ServiceUnitName)
	}
	if plan.StorageImageFormat != "raw" || plan.GuestVolumeFileSystem != "iso9660" {
		t.Fatalf("C40 storage delivery contract is not explicit: %#v", plan)
	}
	if plan.Sources[0].ID != "guest-node-services-linux-arm64" {
		t.Fatalf("sources are not canonicalized: %#v", plan.Sources)
	}
	if plan.Sources[len(plan.Sources)-1].ID != "guest-runtime-linux-arm64" {
		t.Fatalf("sources are not canonicalized: %#v", plan.Sources)
	}
	if plan.FileInstallations[0].DestinationPath != composition.BootstrapConfiguration.GuestRuntime.DestinationPath {
		t.Fatalf("Guest Runtime destination was not preserved")
	}
	topologyInstalled := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == "guest-product-vitalserver-topology-deployment" && installation.DestinationPath == "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-vitalserver-topology-deployment.json" {
			topologyInstalled = true
		}
	}
	if !topologyInstalled {
		t.Fatalf("C44 VitalServer topology deployment was not installed: %#v", plan.FileInstallations)
	}
	if plan.ArchiveInstallations[0].DestinationDirectory != "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev" {
		t.Fatalf("Guest Node Services archive destination was not preserved")
	}
	if plan.ArchiveInstallations[0].SymbolicLinkPolicy != "allow-relative-links-to-declared-regular-files" {
		t.Fatalf("Guest Node Services archive symbolic-link policy was not preserved: %#v", plan.ArchiveInstallations[0])
	}
	if plan.GuestRuntimeStateDirectory.DirectoryPath != "/var/lib/vitalserver/guest-runtime" || plan.GuestRuntimeStateDirectory.DirectoryMode != "0700" {
		t.Fatalf("Guest Runtime state directory was not preserved: %#v", plan.GuestRuntimeStateDirectory)
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsStateDirectoryMismatch(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.ProcessDeployment.GuestRuntimeStateDatabasePath = "/var/lib/vitalserver/other/guest-runtime.sqlite"
	_, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err == nil || !strings.Contains(err.Error(), "state database parent") {
		t.Fatalf("expected explicit C37/C39 state directory agreement failure, got %v", err)
	}
}

func TestComposeGuestProductBootstrapVolumePlanDeclaresChronyBootstrapFromExplicitC37Source(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.ProcessDeployment.GuestTimeAuthorityKind = "chrony-tracking"
	composition.ProcessDeployment.GuestTimeAuthorityNTPServerHost = "ntp.example.test"
	composition.ProcessDeployment.GuestTimeAuthorityNTPServerPort = 123
	composition.BootstrapConfiguration.GuestTimeSynchronization = &guestproductbootstrapplancomposer.GuestProductBootstrapTimeSynchronization{
		PackageManager: "apt", PackageName: "chrony", ServiceName: "chrony.service", ConfigurationDestinationPath: "/etc/chrony/chrony.conf",
	}

	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 plan with Guest time synchronization: %v", err)
	}
	if plan.GuestTimeSynchronization == nil || plan.GuestTimeSynchronization.PackageName != "chrony" {
		t.Fatalf("C40 time synchronization was not preserved: %#v", plan.GuestTimeSynchronization)
	}
	installed := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == "guest-time-synchronization-configuration" && installation.DestinationPath == "/etc/chrony/chrony.conf" && installation.FileMode == "0644" {
			installed = true
		}
	}
	if !installed {
		t.Fatalf("C40 does not install generated Chrony configuration: %#v", plan.FileInstallations)
	}
	if configuration := guestproductbootstrapplancomposer.RenderGuestTimeSynchronizationConfiguration(composition.ProcessDeployment); configuration != "# Managed by VitalServer Guest Product bootstrap.\nserver ntp.example.test port 123 iburst\nmakestep 1.0 3\nrtcsync\n" {
		t.Fatalf("generated Chrony configuration=%q", configuration)
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsGuestTimeSynchronizationWithoutExactNTPSource(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.ProcessDeployment.GuestTimeAuthorityKind = "chrony-tracking"
	composition.BootstrapConfiguration.GuestTimeSynchronization = &guestproductbootstrapplancomposer.GuestProductBootstrapTimeSynchronization{
		PackageManager: "apt", PackageName: "chrony", ServiceName: "chrony.service", ConfigurationDestinationPath: "/etc/chrony/chrony.conf",
	}
	if _, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition); err == nil || !strings.Contains(err.Error(), "explicit C37 chrony-tracking") {
		t.Fatalf("expected C37 NTP source requirement, got %v", err)
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsLabRecorderRunnerOutsideGuestNodeServicesBundle(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.ProcessDeployment.LabScenarioCatalogPath = "/etc/vitalserver/lab-scenario-catalog.json"

	_, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err == nil || !strings.Contains(err.Error(), "C37 process paths") {
		t.Fatalf("expected explicit Runner/C39 bundle agreement failure, got %v", err)
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsC38ServiceUnitMismatch(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.ServiceManagerDeployment.ServiceUnitName = "different.service"
	_, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err == nil || !strings.Contains(err.Error(), "C38 service manager paths") {
		t.Fatalf("expected explicit C38/C39 agreement failure, got %v", err)
	}
}

func TestComposeGuestProductBootstrapVolumePlanInstallsDeclaredExternalVitalServerDeliveryConfiguration(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	configurationIdentifier := "external-vitalserver-delivery-configuration"
	composition.BootstrapConfiguration.ExternalVitalServerDeliveryConfiguration = &guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{
		ArtifactID: configurationIdentifier, DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json", FileMode: "0644",
	}
	digest := sha256.Sum256([]byte(configurationIdentifier))
	composition.Payloads[configurationIdentifier] = guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{
		ID: configurationIdentifier, SourceRelativePath: "sources/" + configurationIdentifier, SizeBytes: int64(len(configurationIdentifier)), SHA256: hex.EncodeToString(digest[:]),
	}

	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 plan with C46 = %v", err)
	}
	externalDeliveryConfigurationInstalled := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == configurationIdentifier && installation.DestinationPath == "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json" && installation.FileMode == "0644" {
			externalDeliveryConfigurationInstalled = true
		}
	}
	if !externalDeliveryConfigurationInstalled {
		t.Fatalf("C46 external delivery configuration was not installed: %#v", plan.FileInstallations)
	}

	delete(composition.Payloads, configurationIdentifier)
	if _, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition); err == nil || !strings.Contains(err.Error(), "bootstrap payload is missing") {
		t.Fatalf("missing C46 payload error = %v", err)
	}
}

func TestComposeGuestProductBootstrapVolumePlanInstallsExplicitExternalVitalServerDeliveryConfiguration(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	identifier := "external-vitalserver-delivery-configuration"
	digest := sha256.Sum256([]byte(identifier))
	composition.Payloads[identifier] = guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{
		ID: identifier, SourceRelativePath: "sources/" + identifier, SizeBytes: int64(len(identifier)), SHA256: hex.EncodeToString(digest[:]),
	}
	composition.BootstrapConfiguration.ExternalVitalServerDeliveryConfiguration = &guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{
		ArtifactID: identifier, DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json", FileMode: "0644",
	}

	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 external delivery configuration: %v", err)
	}
	installed := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == identifier && installation.DestinationPath == "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json" && installation.FileMode == "0644" {
			installed = true
		}
	}
	if !installed {
		t.Fatalf("C46 external VitalServer delivery configuration was not installed: %#v", plan.FileInstallations)
	}
}

func TestComposeGuestProductBootstrapVolumePlanInstallsAndExplicitlyInitializesBundledImageSetManager(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	managerExecutableID := "guest-bundled-upstream-image-set-manager-linux-arm64"
	managerConfigurationID := "guest-bundled-upstream-image-set-manager-configuration"
	for _, identifier := range []string{managerExecutableID, managerConfigurationID} {
		digest := sha256.Sum256([]byte(identifier))
		composition.Payloads[identifier] = guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{ID: identifier, SourceRelativePath: "sources/" + identifier, SizeBytes: int64(len(identifier)), SHA256: hex.EncodeToString(digest[:])}
	}
	composition.BootstrapConfiguration.GuestBundledUpstreamImageSetManager = &guestproductbootstrapplancomposer.GuestProductBootstrapBundledUpstreamImageSetManager{
		ManagerID:                  "bundled-upstream-image-set-manager",
		Executable:                 guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: managerExecutableID, DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-bundled-upstream-image-set-manager", FileMode: "0755"},
		Configuration:              guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: managerConfigurationID, DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-bundled-upstream-image-set-manager.json", FileMode: "0644"},
		StateDirectory:             guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: "/var/lib/vitalserver/bundled-upstream-image-sets", DirectoryMode: "0700"},
		ContainerEngineBootstrap:   guestproductbootstrapplancomposer.GuestProductBootstrapContainerEngineBootstrap{PackageManager: "apt", PackageName: "docker.io", ServiceName: "docker.service"},
		ServiceUnit:                guestproductbootstrapplancomposer.GuestProductBootstrapReleaseManagerServiceUnit{ServiceUnitName: "vitalserver-guest-bundled-upstream-image-set-manager.service", UnitDestinationPath: "/etc/systemd/system/vitalserver-guest-bundled-upstream-image-set-manager.service", EnabledUnitLinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-bundled-upstream-image-set-manager.service", EnabledUnitLinkTargetPath: "/etc/systemd/system/vitalserver-guest-bundled-upstream-image-set-manager.service", RestartMode: "on-failure", RestartDelayMilliseconds: 1000, StandardOutput: "journal+console", StandardError: "journal+console", WantedByTarget: "multi-user.target"},
		InitialActiveImageSetState: "unprovisioned",
	}
	composition.GeneratedBundledUpstreamImageSetManagerSystemdUnitContents = []byte("[Service]\nExecStart=/opt/vitalserver/current/bin/guest-bundled-upstream-image-set-manager --configuration /opt/vitalserver/current/config/guest-bundled-upstream-image-set-manager.json --mode serve\n")

	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 plan with bundled manager: %v", err)
	}
	manager := plan.GuestBundledUpstreamImageSetManager
	if manager == nil || manager.ManagerID != "bundled-upstream-image-set-manager" || manager.ExecutablePath != "/opt/vitalserver/current/bin/guest-bundled-upstream-image-set-manager" || manager.InitialActiveImageSetState != "unprovisioned" {
		t.Fatalf("bundled manager plan=%#v", manager)
	}
	if len(plan.SymbolicLinks) != 3 {
		t.Fatalf("bundled manager must add exactly one explicit service enable link: %#v", plan.SymbolicLinks)
	}
	installed := map[string]bool{}
	for _, installation := range plan.FileInstallations {
		installed[installation.SourceID] = true
	}
	for _, identifier := range []string{managerExecutableID, managerConfigurationID, "guest-bundled-upstream-image-set-manager-systemd-unit"} {
		if !installed[identifier] {
			t.Fatalf("C40 does not install %s: %#v", identifier, plan.FileInstallations)
		}
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsDeclaredExternalDeliveryConfigurationWithoutItsPayload(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.BootstrapConfiguration.ExternalVitalServerDeliveryConfiguration = &guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{
		ArtifactID: "external-vitalserver-delivery-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json", FileMode: "0644",
	}

	_, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err == nil || !strings.Contains(err.Error(), "external-vitalserver-delivery-configuration") {
		t.Fatalf("expected missing C46 payload rejection, got %v", err)
	}
}

func completeGuestProductBootstrapVolumePlanComposition() guestproductbootstrapplancomposer.GuestProductBootstrapVolumePlanComposition {
	payloads := guestproductbootstrapplancomposer.GuestProductBootstrapPayloads{}
	for _, identifier := range []string{
		"guest-runtime-linux-arm64", "guest-node-services-linux-arm64",
		"guest-product-process-supervisor-linux-arm64", "guest-product-process-deployment-configuration",
		"guest-product-release-manager-linux-arm64", "guest-product-release-manager-configuration",
		"guest-product-vitalserver-topology-deployment", "guest-product-service-manager-deployment-configuration",
	} {
		digest := sha256.Sum256([]byte(identifier))
		payloads[identifier] = guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{
			ID: identifier, SourceRelativePath: "sources/" + identifier, SizeBytes: int64(len(identifier)), SHA256: hex.EncodeToString(digest[:]),
		}
	}
	return guestproductbootstrapplancomposer.GuestProductBootstrapVolumePlanComposition{
		ProcessDeployment: guestproductbootstrapplancomposer.GuestProductProcessDeploymentPaths{
			GuestRuntimeExecutablePath: "/opt/vitalserver/current/bin/guest-runtime", GuestRuntimeStateDatabasePath: "/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite", RecorderGatewayNodePath: "/opt/vitalserver/current/node/bin/node", RecorderGatewayProgramPath: "/opt/vitalserver/current/recorder-gateway/dist/cmd/recorder-gateway.js", LabRecorderRunnerNodePath: "/opt/vitalserver/current/node/bin/node", LabRecorderRunnerProgramPath: "/opt/vitalserver/current/lab-recorder-runner/dist/cmd/lab-recorder-runner.js", LabScenarioCatalogPath: "/opt/vitalserver/current/lab-recorder-runner/lab-scenario-catalog.json",
			RecorderCatalogDatabaseURLMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-database-url", RecorderCatalogMigrationReceiptPath: "/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json", RecorderCatalogAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-admission-token", ArchiveSourceAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/archive-source-admission-token", ArchiveArtifactObjectRootDirectory: "/var/lib/vitalserver/archive-artifacts",
			RecorderGatewayObservationCatalogBearerTokenMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-admission-token", RecorderGatewayArchiveSourceAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/archive-source-admission-token",
		},
		ServiceManagerDeployment: guestproductbootstrapplancomposer.GuestProductServiceManagerDeployment{
			ServiceUnitName: "vitalserver-guest-product.service", SupervisorExecutablePath: "/opt/vitalserver/current/bin/guest-product-process-supervisor", SupervisorDeploymentConfigurationPath: "/opt/vitalserver/current/config/guest-product-process-deployment.json",
		},
		BootstrapConfiguration: guestproductbootstrapplancomposer.GuestProductBootstrapConfiguration{
			GuestArchitecture: "arm64",
			BootstrapID:       "vitalserver-guest-product-bootstrap", VolumeLabel: "CIDATA", GuestVolumeFileSystem: "iso9660", InstanceID: "vitalserver-guest-bootstrap-instance", LocalHostName: "vitalserver-guest",
			GuestProductRelease:                 guestproductbootstrapplancomposer.GuestProductBootstrapRelease{ReleaseID: "vitalserver-guest-product-0.2.0-dev", ReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev", CurrentReleaseLinkPath: "/opt/vitalserver/current", ReleaseStateDirectory: "/var/lib/vitalserver/guest-product-releases", ReleaseStateDirectoryMode: "0700"},
			GuestRuntime:                        guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: "guest-runtime-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-runtime", FileMode: "0755"},
			GuestRuntimeStateDirectory:          guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: "/var/lib/vitalserver/guest-runtime", DirectoryMode: "0700"},
			GuestPrivateStateDirectory:          guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: "/var/lib/vitalserver/private", DirectoryMode: "0700"},
			GuestArchiveArtifactObjectDirectory: guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: "/var/lib/vitalserver/archive-artifacts", DirectoryMode: "0700"},
			GuestRecorderCatalogPostgreSQL: guestproductbootstrapplancomposer.GuestProductBootstrapRecorderCatalogPostgreSQL{
				PackageManager: "apt", PackageNames: []string{"postgresql", "python3-alembic", "python3-psycopg"}, ServiceName: "postgresql.service",
				DatabaseHost: "127.0.0.1", DatabasePort: 5432, DatabaseName: "vitalserver", DatabaseRoleName: "vitalserver",
				DatabaseURLMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-database-url", CatalogAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-admission-token", ArchiveSourceAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/archive-source-admission-token",
				GeneratedSecretByteCount: 32, MigrationExecutablePath: "/opt/vitalserver/current/bin/guest-runtime", MigrationPythonExecutablePath: "/usr/bin/python3", ExpectedRevision: "0006_backup_owner", MigrationReceiptPath: "/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json",
			},
			GuestNodeServicesBundle:       guestproductbootstrapplancomposer.GuestProductBootstrapNodeServicesArchive{ArtifactID: "guest-node-services-linux-arm64", ArchiveFormat: "tar-gzip", EntryModePolicy: "preserve-archive-mode", SymbolicLinkPolicy: "allow-relative-links-to-declared-regular-files", DestinationDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev", RequiredArchivePaths: []string{"node/bin/node", "recorder-gateway/dist/cmd/recorder-gateway.js", "lab-recorder-runner/dist/cmd/lab-recorder-runner.js", "lab-recorder-runner/lab-scenario-catalog.json"}},
			GuestProductProcessSupervisor: guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: "guest-product-process-supervisor-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-product-process-supervisor", FileMode: "0755"},
			GuestProductProcessDeployment: guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: "guest-product-process-deployment-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-process-deployment.json", FileMode: "0644"},
			GuestProductReleaseManager: guestproductbootstrapplancomposer.GuestProductBootstrapReleaseManager{
				Executable:    guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: "guest-product-release-manager-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-product-release-manager", FileMode: "0755"},
				Configuration: guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: "guest-product-release-manager-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-release-manager.json", FileMode: "0644"},
				ServiceUnit:   guestproductbootstrapplancomposer.GuestProductBootstrapReleaseManagerServiceUnit{ServiceUnitName: "vitalserver-guest-product-release-manager.service", UnitDestinationPath: "/etc/systemd/system/vitalserver-guest-product-release-manager.service", EnabledUnitLinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product-release-manager.service", EnabledUnitLinkTargetPath: "/etc/systemd/system/vitalserver-guest-product-release-manager.service", RestartMode: "on-failure", RestartDelayMilliseconds: 1000, StandardOutput: "journal+console", StandardError: "journal+console", WantedByTarget: "multi-user.target"},
			},
			GuestProductVitalServerTopologyDeployment: guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: "guest-product-vitalserver-topology-deployment", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-vitalserver-topology-deployment.json", FileMode: "0644"},
			GuestProductServiceManagerDeployment:      guestproductbootstrapplancomposer.GuestProductBootstrapServiceManagerPayload{ArtifactID: "guest-product-service-manager-deployment-configuration", ConfigurationDestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-service-manager-deployment.json", UnitDestinationPath: "/etc/systemd/system/vitalserver-guest-product.service", EnabledUnitLinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service", EnabledUnitLinkTargetPath: "/etc/systemd/system/vitalserver-guest-product.service"},
		},
		Payloads:                     payloads,
		GeneratedSystemdUnitContents: []byte("[Service]\\nExecStart=/opt/vitalserver/current/bin/guest-product-process-supervisor\\n"),
		GeneratedReleaseManagerSystemdUnitContents: []byte("[Service]\\nExecStart=/opt/vitalserver/current/bin/guest-product-release-manager\\n"),
	}
}
