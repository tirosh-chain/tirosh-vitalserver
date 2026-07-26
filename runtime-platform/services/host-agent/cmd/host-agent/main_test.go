package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestHostAgentStartupRequiresOneC33ConfigurationPath(t *testing.T) {
	var diagnostics bytes.Buffer
	_, exitCode := loadHostAgentDeploymentConfiguration(nil, &diagnostics)
	if exitCode != 2 {
		t.Fatalf("exit code = %d, want 2", exitCode)
	}
	if !strings.Contains(diagnostics.String(), "deployment configuration path is required") {
		t.Fatalf("diagnostics = %q", diagnostics.String())
	}
}

func TestHostAgentStartupReportsUnavailableC33InsteadOfCreatingConfiguration(t *testing.T) {
	var diagnostics bytes.Buffer
	_, exitCode := loadHostAgentDeploymentConfiguration([]string{"--deployment-configuration", "/var/lib/vitalserver/missing-host-agent-deployment.json"}, &diagnostics)
	if exitCode != 1 {
		t.Fatalf("exit code = %d, want 1", exitCode)
	}
	if !strings.Contains(diagnostics.String(), "deployment configuration is unavailable") {
		t.Fatalf("diagnostics = %q", diagnostics.String())
	}
}
