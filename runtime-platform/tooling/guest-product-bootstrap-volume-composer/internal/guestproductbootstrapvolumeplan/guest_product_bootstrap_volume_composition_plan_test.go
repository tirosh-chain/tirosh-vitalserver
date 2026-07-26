package guestproductbootstrapvolumeplan_test

import (
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

func TestValidateGuestProductBootstrapVolumeCompositionPlanRejectsUnconsumedPayload(t *testing.T) {
	plan := completeDeclaredGuestProductBootstrapVolumePlan()
	plan.Sources = append(plan.Sources, declaredBootstrapSource("unconsumed-diagnostic-payload", "sources/unconsumed-diagnostic-payload"))

	err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan)
	if err == nil || !strings.Contains(err.Error(), "does not declare an installation") {
		t.Fatalf("expected an unconsumed bootstrap payload rejection, got %v", err)
	}
}

func TestValidateGuestProductBootstrapVolumeCompositionPlanRejectsServiceEnableLinkWithoutInstalledServiceUnit(t *testing.T) {
	plan := completeDeclaredGuestProductBootstrapVolumePlan()
	plan.SymbolicLinks[0].TargetPath = "/etc/systemd/system/not-installed.service"

	err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan)
	if err == nil || !strings.Contains(err.Error(), "does not target an installed Guest file") {
		t.Fatalf("expected a service enable-link target rejection, got %v", err)
	}
}

func TestValidateGuestProductBootstrapVolumeCompositionPlanRejectsUnspecifiedArchiveSymbolicLinkPolicy(t *testing.T) {
	plan := completeDeclaredGuestProductBootstrapVolumePlan()
	plan.ArchiveInstallations[0].SymbolicLinkPolicy = ""

	err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan)
	if err == nil || !strings.Contains(err.Error(), "archive installation is invalid") {
		t.Fatalf("expected an explicit archive symbolic-link policy rejection, got %v", err)
	}
}

func completeDeclaredGuestProductBootstrapVolumePlan() guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan {
	return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		SchemaVersion:                 "v1",
		BootstrapID:                   "vitalserver-guest-product-bootstrap",
		VolumeLabel:                   "CIDATA",
		StorageImageFormat:            "raw",
		GuestVolumeFileSystem:         "iso9660",
		InstanceID:                    "vitalserver-guest-bootstrap-instance",
		LocalHostName:                 "vitalserver-guest",
		ServiceUnitName:               "vitalserver-guest-product.service",
		ReleaseManagerServiceUnitName: "vitalserver-guest-product-release-manager.service",
		GuestProductRelease: guestproductbootstrapvolumeplan.DeclaredGuestProductRelease{
			ReleaseID: "vitalserver-guest-product-0.2.0-dev", ReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev", CurrentReleaseLinkPath: "/opt/vitalserver/current", ReleaseStateDirectory: "/var/lib/vitalserver/guest-product-releases", ReleaseStateDirectoryMode: "0700",
		},
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: "/var/lib/vitalserver/guest-runtime",
			DirectoryMode: "0700",
		},
		GuestPrivateStateDirectory:          guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/private", DirectoryMode: "0700"},
		GuestArchiveArtifactObjectDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/archive-artifacts", DirectoryMode: "0700"},
		GuestRecorderCatalogPostgreSQL: guestproductbootstrapvolumeplan.DeclaredGuestRecorderCatalogPostgreSQL{
			PackageManager: "apt", PackageNames: []string{"postgresql", "python3-alembic", "python3-psycopg"}, ServiceName: "postgresql.service",
			DatabaseHost: "127.0.0.1", DatabasePort: 5432, DatabaseName: "vitalserver", DatabaseRoleName: "vitalserver",
			DatabaseURLMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-database-url", CatalogAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/recorder-catalog-admission-token", ArchiveSourceAdmissionBearerTokenMaterialPath: "/var/lib/vitalserver/private/archive-source-admission-token",
			GeneratedSecretByteCount: 32, MigrationExecutablePath: "/opt/vitalserver/current/bin/guest-runtime", MigrationPythonExecutablePath: "/usr/bin/python3", ExpectedRevision: "0006_backup_owner", MigrationReceiptPath: "/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json",
		},
		Sources: []guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
			declaredBootstrapSource("guest-runtime-linux-arm64", "sources/guest-runtime-linux-arm64"),
			declaredBootstrapSource("guest-node-services-linux-arm64", "sources/guest-node-services-linux-arm64"),
			declaredBootstrapSource("guest-product-process-supervisor-linux-arm64", "sources/guest-product-process-supervisor-linux-arm64"),
			declaredBootstrapSource("guest-product-process-deployment-configuration", "sources/guest-product-process-deployment-configuration"),
			declaredBootstrapSource("guest-product-release-manager-linux-arm64", "sources/guest-product-release-manager-linux-arm64"),
			declaredBootstrapSource("guest-product-release-manager-configuration", "sources/guest-product-release-manager-configuration"),
			declaredBootstrapSource("guest-product-vitalserver-topology-deployment", "sources/guest-product-vitalserver-topology-deployment"),
			declaredBootstrapSource("guest-product-service-manager-deployment-configuration", "sources/guest-product-service-manager-deployment-configuration"),
			declaredBootstrapSource("guest-product-systemd-unit", "generated/vitalserver-guest-product.service"),
			declaredBootstrapSource("guest-product-release-manager-systemd-unit", "generated/vitalserver-guest-product-release-manager.service"),
		},
		FileInstallations: []guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
			{SourceID: "guest-runtime-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-runtime", FileMode: "0755"},
			{SourceID: "guest-product-process-supervisor-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-product-process-supervisor", FileMode: "0755"},
			{SourceID: "guest-product-process-deployment-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-process-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-release-manager-linux-arm64", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-product-release-manager", FileMode: "0755"},
			{SourceID: "guest-product-release-manager-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-release-manager.json", FileMode: "0644"},
			{SourceID: "guest-product-vitalserver-topology-deployment", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-vitalserver-topology-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-service-manager-deployment-configuration", DestinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-service-manager-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-systemd-unit", DestinationPath: "/etc/systemd/system/vitalserver-guest-product.service", FileMode: "0644"},
			{SourceID: "guest-product-release-manager-systemd-unit", DestinationPath: "/etc/systemd/system/vitalserver-guest-product-release-manager.service", FileMode: "0644"},
		},
		ArchiveInstallations: []guestproductbootstrapvolumeplan.DeclaredGuestArchiveInstallation{{
			SourceID: "guest-node-services-linux-arm64", ArchiveFormat: "tar-gzip", EntryModePolicy: "preserve-archive-mode", SymbolicLinkPolicy: guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy, DestinationDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev",
			RequiredArchivePaths: []string{"node/bin/node", "recorder-gateway/dist/cmd/recorder-gateway.js", "lab-recorder-runner/dist/cmd/lab-recorder-runner.js", "lab-recorder-runner/lab-scenario-catalog.json"},
		}},
		SymbolicLinks: []guestproductbootstrapvolumeplan.DeclaredGuestSymbolicLink{
			{LinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service", TargetPath: "/etc/systemd/system/vitalserver-guest-product.service"},
			{LinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product-release-manager.service", TargetPath: "/etc/systemd/system/vitalserver-guest-product-release-manager.service"},
		},
	}
}

func declaredBootstrapSource(identifier string, sourceRelativePath string) guestproductbootstrapvolumeplan.DeclaredBootstrapSource {
	return guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
		ID: identifier, SourceRelativePath: sourceRelativePath, SizeBytes: 1, SHA256: strings.Repeat("a", 64),
	}
}
