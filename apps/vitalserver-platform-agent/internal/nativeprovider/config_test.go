package nativeprovider

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigRequiresExplicitFieldsAndRejectsUnknownFields(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "native-provider.json")
	valid := `{
  "schemaVersion": 1,
  "composeExecutable": "/usr/bin/docker",
  "composeFile": "bundle/compose.yaml",
  "composeEnvironmentFile": "runtime.env",
  "composeProjectName": "vitalserver",
  "projectDirectory": "bundle",
  "runtimeReadyURL": "http://127.0.0.1:18330/ready",
  "runtimeEndpointAddress": "127.0.0.1",
  "runtimeEndpointDocument": "run/endpoint.json",
  "runtimeProviderDocument": "run/provider.json",
  "readinessProbeTimeoutSeconds": 20,
  "startupTimeoutSeconds": 120,
  "shutdownTimeoutSeconds": 60
}`
	if err := os.WriteFile(path, []byte(valid), 0o600); err != nil {
		t.Fatal(err)
	}
	config, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.ComposeFile != filepath.Join(root, "bundle/compose.yaml") {
		t.Fatalf("compose file=%s", config.ComposeFile)
	}

	unknown := strings.Replace(valid, `"schemaVersion": 1`, `"schemaVersion": 1, "implicitFallback": true`, 1)
	if err := os.WriteFile(path, []byte(unknown), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("unknown field error=%v", err)
	}
}

func TestLoadConfigRejectsNonIPRuntimeEndpoint(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native-provider.json")
	data := `{
  "schemaVersion": 1,
  "composeExecutable": "/usr/bin/docker",
  "composeFile": "/opt/vitalserver/compose.yaml",
  "composeEnvironmentFile": "/etc/vitalserver/runtime.env",
  "composeProjectName": "vitalserver",
  "projectDirectory": "/opt/vitalserver",
  "runtimeReadyURL": "http://localhost:18330/health",
  "runtimeEndpointAddress": "localhost",
  "runtimeEndpointDocument": "/run/vitalserver/endpoint.json",
  "runtimeProviderDocument": "/run/vitalserver/provider.json",
  "readinessProbeTimeoutSeconds": 20,
  "startupTimeoutSeconds": 120,
  "shutdownTimeoutSeconds": 60
}`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil || !strings.Contains(err.Error(), "must be an IP address") {
		t.Fatalf("endpoint error=%v", err)
	}
}

func TestLoadConfigRejectsLivenessURLAsProviderReadiness(t *testing.T) {
	path := filepath.Join(t.TempDir(), "native-provider.json")
	data := `{
  "schemaVersion": 1,
  "composeExecutable": "/usr/bin/docker",
  "composeFile": "/opt/vitalserver/compose.yaml",
  "composeEnvironmentFile": "/etc/vitalserver/runtime.env",
  "composeProjectName": "vitalserver",
  "projectDirectory": "/opt/vitalserver",
  "runtimeReadyURL": "http://127.0.0.1:18330/health",
  "runtimeEndpointAddress": "127.0.0.1",
  "runtimeEndpointDocument": "/run/vitalserver/endpoint.json",
  "runtimeProviderDocument": "/run/vitalserver/provider.json",
  "readinessProbeTimeoutSeconds": 20,
  "startupTimeoutSeconds": 120,
  "shutdownTimeoutSeconds": 60
}`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil || !strings.Contains(err.Error(), "/ready") {
		t.Fatalf("readiness error=%v", err)
	}
}
