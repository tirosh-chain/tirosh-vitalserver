package guestproductbootstrapartifactcompositionapplication

import (
	"strings"
	"testing"
)

func TestRenderGuestProductSystemdServiceUnitKeepsC38LogSinksExplicit(t *testing.T) {
	deployment := guestProductServiceManagerDeploymentConfiguration{
		SchemaVersion:      "v1",
		ServiceManagerKind: "systemd",
		ServiceUnitName:    "vitalserver-guest-product.service",
	}
	deployment.Supervisor.ExecutablePath = "/opt/vitalserver/bin/guest-product-process-supervisor"
	deployment.Supervisor.DeploymentConfigurationPath = "/etc/vitalserver/guest-product-process-deployment.json"
	deployment.Restart.Mode = "on-failure"
	deployment.Restart.DelayMilliseconds = 1000
	deployment.Logging.StandardOutput = "journal+console"
	deployment.Logging.StandardError = "journal+console"
	deployment.Install.WantedByTarget = "multi-user.target"

	unit, err := renderGuestProductSystemdServiceUnit(deployment)
	if err != nil {
		t.Fatalf("render C38 unit: %v", err)
	}
	for _, requiredLine := range []string{
		"StandardOutput=journal+console",
		"StandardError=journal+console",
	} {
		if !strings.Contains(unit, requiredLine) {
			t.Fatalf("C38 rendered unit is missing %q:\n%s", requiredLine, unit)
		}
	}
}

func TestRenderGuestProductSystemdServiceUnitRejectsImplicitLogSink(t *testing.T) {
	deployment := guestProductServiceManagerDeploymentConfiguration{}
	deployment.Restart.DelayMilliseconds = 1000

	_, err := renderGuestProductSystemdServiceUnit(deployment)
	if err == nil || !strings.Contains(err.Error(), "logging policy") {
		t.Fatalf("implicit C38 logging policy error=%v", err)
	}
}
