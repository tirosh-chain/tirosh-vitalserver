package hypervprovider

import (
	"strings"
	"testing"
)

func TestHyperVScriptsUseStructuredCmdletsWithoutVMNameInterpolation(t *testing.T) {
	for name, script := range map[string]string{"start": startScript, "stop": stopScript} {
		t.Run(name, func(t *testing.T) {
			if !strings.Contains(script, "Get-VM") || !strings.Contains(script, "-ErrorAction Stop") {
				t.Fatalf("script does not use explicit Hyper-V cmdlet failure: %s", script)
			}
			if strings.Contains(script, "VitalServer Runtime") {
				t.Fatal("script interpolates a configured VM name")
			}
			if !strings.Contains(script, vmNameEnvironment) {
				t.Fatal("script does not read the exact process environment binding")
			}
		})
	}
}

func TestHyperVStopIsGracefulAndDoesNotForcePowerOff(t *testing.T) {
	if !strings.Contains(stopScript, "-Shutdown") {
		t.Fatal("Hyper-V stop does not request guest shutdown")
	}
	if strings.Contains(stopScript, "-TurnOff") || strings.Contains(stopScript, "-Force") {
		t.Fatal("Hyper-V stop can force power off and risk Runtime data")
	}
}
