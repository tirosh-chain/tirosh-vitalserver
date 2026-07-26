package guestproductbootstrapartifactcompositionapplication

import "testing"

func TestValidateGuestProductProcessTopologyBootstrapCompositionAcceptsBundledC64TopologyWithoutC37Process(t *testing.T) {
	var processDeployment guestProductProcessDeploymentConfiguration
	processDeployment.RecorderGateway.VitalServerTopologyDeploymentPath = "/opt/vitalserver/current/config/guest-product-vitalserver-topology-deployment.json"

	var topologyDeployment guestProductVitalServerTopologyDeployment
	topologyDeployment.TopologyDeploymentID = "bundled-vitalserver-primary-topology"
	topologyDeployment.TopologyKind = "bundled-vitalserver"
	topologyDeployment.BundledUpstreamImageSetDeployment = &guestProductBundledUpstreamImageSetDeployment{}
	topologyDeployment.VitalServerDeliveryProvider.Kind = "bundled-vitalserver"
	topologyDeployment.VitalServerDeliveryProvider.ID = "bundled-vitalserver-primary"
	topologyDeployment.VitalServerDeliveryProvider.CapabilityRevision = 1
	topologyDeployment.BundledUpstreamImageSetDeployment.ImageSetManagerConfigurationReference.ResourceType = "guest-bundled-upstream-image-set-manager-configuration"
	topologyDeployment.BundledUpstreamImageSetDeployment.ImageSetManagerConfigurationReference.ResourceID = "bundled-upstream-image-set-manager"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerPacketDeliveryEndpoint.Scheme = "http"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerPacketDeliveryEndpoint.Host = "127.0.0.1"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerPacketDeliveryEndpoint.Port = 18300
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerDeliveryAcknowledgementTimeoutMilliseconds = 5000
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerObservationEndpoint.Scheme = "http"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerObservationEndpoint.Host = "127.0.0.1"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerObservationEndpoint.Port = 18300
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerObservationEndpoint.Path = "/healthz"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerObservationEndpoint.AcceptedStatusCodes = []int64{200}
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveProvider.Kind = "vitalserver-indexed-library"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveProvider.ID = "bundled-vitalserver-library"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveProvider.CapabilityRevision = 1
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerIndexedLibraryEndpoint.Scheme = "http"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerIndexedLibraryEndpoint.Host = "127.0.0.1"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerIndexedLibraryEndpoint.Port = 18300
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveCredentialReference.Kind = "vitalserver-library-credential"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveCredentialReference.ID = "bundled-vitalserver-library"
	topologyDeployment.BundledUpstreamImageSetDeployment.VitalServerArchiveRequestTimeoutMilliseconds = 5000

	var bootstrapConfiguration guestProductBootstrapConfiguration
	bootstrapConfiguration.GuestProductRelease.ReleaseID = "vitalserver-guest-product-0.2.0-dev"
	bootstrapConfiguration.GuestProductRelease.ReleaseDirectory = "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev"
	bootstrapConfiguration.GuestProductRelease.CurrentReleaseLinkPath = "/opt/vitalserver/current"
	bootstrapConfiguration.GuestProductRelease.ReleaseStateDirectory = "/var/lib/vitalserver/guest-product-releases"
	bootstrapConfiguration.GuestProductRelease.ReleaseStateDirectoryMode = "0700"
	bootstrapConfiguration.GuestProductVitalServerTopologyDeployment.DestinationPath = "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-product-vitalserver-topology-deployment.json"
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager = &guestProductBundledUpstreamImageSetManagerPayload{}
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager.ManagerID = "bundled-upstream-image-set-manager"
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager.Executable.ArtifactID = "guest-bundled-upstream-image-set-manager-linux-arm64"
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager.Configuration.ArtifactID = "guest-bundled-upstream-image-set-manager-configuration"
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager.StateDirectory.DirectoryPath = "/var/lib/vitalserver/bundled-upstream-image-sets"
	bootstrapConfiguration.GuestBundledUpstreamImageSetManager.StateDirectory.DirectoryMode = "0700"
	managerArtifact := &declaredInputArtifact{ID: "guest-bundled-upstream-image-set-manager-linux-arm64"}
	managerConfigurationArtifact := &declaredInputArtifact{ID: "guest-bundled-upstream-image-set-manager-configuration"}
	managerConfiguration := &guestBundledUpstreamImageSetManagerConfiguration{SchemaVersion: "v1", ManagerID: "bundled-upstream-image-set-manager", StateDirectory: "/var/lib/vitalserver/bundled-upstream-image-sets", StateDirectoryMode: "0700"}

	err := validateGuestProductProcessTopologyBootstrapComposition(
		processDeployment,
		topologyDeployment,
		bootstrapConfiguration,
		nil,
		nil,
		managerArtifact,
		managerConfigurationArtifact,
		managerConfiguration,
	)
	if err != nil {
		t.Fatalf("bundled C64 topology composition error = %v", err)
	}
}
