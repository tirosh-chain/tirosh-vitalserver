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
	if plan.Sources[0].ID != "guest-product-process-deployment-configuration" {
		t.Fatalf("sources are not canonicalized: %#v", plan.Sources)
	}
	if plan.Sources[len(plan.Sources)-1].ID != "recorder-gateway-linux-arm64" {
		t.Fatalf("sources are not canonicalized: %#v", plan.Sources)
	}
	if plan.FileInstallations[0].DestinationPath != composition.BootstrapConfiguration.GuestRuntime.DestinationPath {
		t.Fatalf("Guest Runtime destination was not preserved")
	}
	topologyInstalled := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == "guest-product-vitalserver-topology-deployment" && installation.DestinationPath == "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json" {
			topologyInstalled = true
		}
	}
	if !topologyInstalled {
		t.Fatalf("C44 VitalServer topology deployment was not installed: %#v", plan.FileInstallations)
	}
	if plan.ArchiveInstallations[0].DestinationDirectory != "/opt/vitalserver" {
		t.Fatalf("Recorder Gateway archive destination was not preserved")
	}
	if plan.ArchiveInstallations[0].SymbolicLinkPolicy != "allow-relative-links-to-declared-regular-files" {
		t.Fatalf("Recorder Gateway archive symbolic-link policy was not preserved: %#v", plan.ArchiveInstallations[0])
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
		ArtifactID: configurationIdentifier, DestinationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json", FileMode: "0644",
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
		if installation.SourceID == configurationIdentifier && installation.DestinationPath == "/etc/vitalserver/external-vitalserver-delivery-configuration.json" && installation.FileMode == "0644" {
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
		ArtifactID: identifier, DestinationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json", FileMode: "0644",
	}

	plan, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err != nil {
		t.Fatalf("compose C40 external delivery configuration: %v", err)
	}
	installed := false
	for _, installation := range plan.FileInstallations {
		if installation.SourceID == identifier && installation.DestinationPath == "/etc/vitalserver/external-vitalserver-delivery-configuration.json" && installation.FileMode == "0644" {
			installed = true
		}
	}
	if !installed {
		t.Fatalf("C46 external VitalServer delivery configuration was not installed: %#v", plan.FileInstallations)
	}
}

func TestComposeGuestProductBootstrapVolumePlanRejectsDeclaredExternalDeliveryConfigurationWithoutItsPayload(t *testing.T) {
	composition := completeGuestProductBootstrapVolumePlanComposition()
	composition.BootstrapConfiguration.ExternalVitalServerDeliveryConfiguration = &guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{
		ArtifactID: "external-vitalserver-delivery-configuration", DestinationPath: "/etc/vitalserver/external-vitalserver-delivery-configuration.json", FileMode: "0644",
	}

	_, err := guestproductbootstrapplancomposer.ComposeGuestProductBootstrapVolumePlan(composition)
	if err == nil || !strings.Contains(err.Error(), "external-vitalserver-delivery-configuration") {
		t.Fatalf("expected missing C46 payload rejection, got %v", err)
	}
}

func completeGuestProductBootstrapVolumePlanComposition() guestproductbootstrapplancomposer.GuestProductBootstrapVolumePlanComposition {
	payloads := guestproductbootstrapplancomposer.GuestProductBootstrapPayloads{}
	for _, identifier := range []string{
		"guest-runtime-linux-arm64", "recorder-gateway-linux-arm64",
		"guest-product-process-supervisor-linux-arm64", "guest-product-process-deployment-configuration",
		"guest-product-vitalserver-topology-deployment", "guest-product-service-manager-deployment-configuration",
	} {
		digest := sha256.Sum256([]byte(identifier))
		payloads[identifier] = guestproductbootstrapplancomposer.GuestProductBootstrapPayloadIdentity{
			ID: identifier, SourceRelativePath: "sources/" + identifier, SizeBytes: int64(len(identifier)), SHA256: hex.EncodeToString(digest[:]),
		}
	}
	return guestproductbootstrapplancomposer.GuestProductBootstrapVolumePlanComposition{
		ProcessDeployment: guestproductbootstrapplancomposer.GuestProductProcessDeploymentPaths{
			GuestRuntimeExecutablePath: "/opt/vitalserver/bin/guest-runtime", GuestRuntimeStateDatabasePath: "/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite", RecorderGatewayNodePath: "/opt/vitalserver/node/bin/node", RecorderGatewayProgramPath: "/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js",
		},
		ServiceManagerDeployment: guestproductbootstrapplancomposer.GuestProductServiceManagerDeployment{
			ServiceUnitName: "vitalserver-guest-product.service", SupervisorExecutablePath: "/opt/vitalserver/bin/guest-product-process-supervisor", SupervisorDeploymentConfigurationPath: "/etc/vitalserver/guest-product-process-deployment.json",
		},
		BootstrapConfiguration: guestproductbootstrapplancomposer.GuestProductBootstrapConfiguration{
			BootstrapID: "vitalserver-guest-product-bootstrap", VolumeLabel: "CIDATA", GuestVolumeFileSystem: "iso9660", InstanceID: "vitalserver-guest-bootstrap-instance", LocalHostName: "vitalserver-guest",
			GuestRuntime:                              guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: "guest-runtime-linux-arm64", DestinationPath: "/opt/vitalserver/bin/guest-runtime", FileMode: "0755"},
			GuestRuntimeStateDirectory:                guestproductbootstrapplancomposer.GuestProductBootstrapStateDirectory{DirectoryPath: "/var/lib/vitalserver/guest-runtime", DirectoryMode: "0700"},
			RecorderGatewayBundle:                     guestproductbootstrapplancomposer.GuestProductBootstrapRecorderGatewayArchive{ArtifactID: "recorder-gateway-linux-arm64", ArchiveFormat: "tar-gzip", EntryModePolicy: "preserve-archive-mode", SymbolicLinkPolicy: "allow-relative-links-to-declared-regular-files", DestinationDirectory: "/opt/vitalserver", RequiredArchivePaths: []string{"node/bin/node", "recorder-gateway/dist/cmd/recorder-gateway.js"}},
			GuestProductProcessSupervisor:             guestproductbootstrapplancomposer.GuestProductBootstrapExecutablePayload{ArtifactID: "guest-product-process-supervisor-linux-arm64", DestinationPath: "/opt/vitalserver/bin/guest-product-process-supervisor", FileMode: "0755"},
			GuestProductProcessDeployment:             guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: "guest-product-process-deployment-configuration", DestinationPath: "/etc/vitalserver/guest-product-process-deployment.json", FileMode: "0644"},
			GuestProductVitalServerTopologyDeployment: guestproductbootstrapplancomposer.GuestProductBootstrapConfigurationPayload{ArtifactID: "guest-product-vitalserver-topology-deployment", DestinationPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json", FileMode: "0644"},
			GuestProductServiceManagerDeployment:      guestproductbootstrapplancomposer.GuestProductBootstrapServiceManagerPayload{ArtifactID: "guest-product-service-manager-deployment-configuration", ConfigurationDestinationPath: "/etc/vitalserver/guest-product-service-manager-deployment.json", UnitDestinationPath: "/etc/systemd/system/vitalserver-guest-product.service", EnabledUnitLinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service", EnabledUnitLinkTargetPath: "/etc/systemd/system/vitalserver-guest-product.service"},
		},
		Payloads:                     payloads,
		GeneratedSystemdUnitContents: []byte("[Service]\\nExecStart=/opt/vitalserver/bin/guest-product-process-supervisor\\n"),
	}
}
