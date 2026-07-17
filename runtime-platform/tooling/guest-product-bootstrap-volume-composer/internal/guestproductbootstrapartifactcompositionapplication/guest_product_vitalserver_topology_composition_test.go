package guestproductbootstrapartifactcompositionapplication

import (
	"strings"
	"testing"
)

func TestValidateGuestProductProcessTopologyBootstrapCompositionRejectsBundledTopologyWithoutC37LaunchPlan(t *testing.T) {
	var processDeployment guestProductProcessDeploymentConfiguration
	processDeployment.RecorderGateway.VitalServerTopologyDeploymentPath = "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json"

	var topologyDeployment guestProductVitalServerTopologyDeployment
	topologyDeployment.TopologyDeploymentID = "bundled-vitalserver-primary-topology"
	topologyDeployment.TopologyKind = "bundled-vitalserver"

	var bootstrapConfiguration guestProductBootstrapConfiguration
	bootstrapConfiguration.GuestProductVitalServerTopologyDeployment.DestinationPath = "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json"

	err := validateGuestProductProcessTopologyBootstrapComposition(
		processDeployment,
		topologyDeployment,
		bootstrapConfiguration,
		nil,
		nil,
	)
	if err == nil || !strings.Contains(err.Error(), "explicit C37 bundled VitalServer process launch plan") {
		t.Fatalf("bundled topology composition error = %v", err)
	}
}
