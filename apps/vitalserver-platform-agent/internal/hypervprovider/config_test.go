package hypervprovider

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigPreservesWindowsAbsolutePaths(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hyperv-provider.json")
	data := `{
  "schemaVersion": 1,
  "powerShellExecutable": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
  "vmName": "VitalServer Runtime",
  "runtimeReadyURL": "http://172.24.0.2:18330/ready",
  "runtimeEndpointAddress": "172.24.0.2",
  "runtimeEndpointDocument": "C:\\ProgramData\\VitalServer\\run\\runtime-endpoint.json",
  "runtimeProviderDocument": "C:\\ProgramData\\VitalServer\\run\\runtime-provider.json",
  "startupTimeoutSeconds": 180,
  "shutdownTimeoutSeconds": 120
}`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	config, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.PowerShellExecutable != `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` {
		t.Fatalf("PowerShell path=%s", config.PowerShellExecutable)
	}
}

func TestLoadConfigRejectsUnknownFieldAndHostnameEndpoint(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hyperv-provider.json")
	base := `{
  "schemaVersion": 1,
  "powerShellExecutable": "powershell.exe",
  "vmName": "VitalServer Runtime",
  "runtimeReadyURL": "http://runtime.local:18330/health",
  "runtimeEndpointAddress": "runtime.local",
  "runtimeEndpointDocument": "endpoint.json",
  "runtimeProviderDocument": "provider.json",
  "startupTimeoutSeconds": 180,
  "shutdownTimeoutSeconds": 120
}`
	if err := os.WriteFile(path, []byte(base), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil || !strings.Contains(err.Error(), "must be an IP address") {
		t.Fatalf("endpoint error=%v", err)
	}
	unknown := strings.Replace(base, `"schemaVersion": 1`, `"schemaVersion": 1, "discoverVM": true`, 1)
	if err := os.WriteFile(path, []byte(unknown), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path); err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("unknown field error=%v", err)
	}
}
