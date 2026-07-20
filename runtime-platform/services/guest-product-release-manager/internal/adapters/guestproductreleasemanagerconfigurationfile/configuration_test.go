package guestproductreleasemanagerconfigurationfile

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadGuestProductReleaseManagerConfigurationRejectsMissingMaximumArtifactLimit(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "release-manager.json")
	if err := os.WriteFile(path, []byte(`{
  "schemaVersion":"v1","managerId":"manager-primary","listener":{"bindHost":"127.0.0.1","port":18444},"controlVirtioSocketListener":{"port":18444},
  "releaseDirectoryRoot":"/opt/vitalserver/releases","currentReleaseLinkPath":"/opt/vitalserver/current",
  "stagingDirectory":"/var/lib/vitalserver/release-staging","stateDirectory":"/var/lib/vitalserver/release-state","stateDirectoryMode":"0700",
  "serviceManagement":{"systemctlExecutablePath":"/usr/bin/systemctl","managedServiceUnitName":"vitalserver-guest-product.service","restartTimeoutMilliseconds":60000},
  "healthCheck":{"scheme":"http","host":"127.0.0.1","port":18443,"path":"/v1/runtime/readiness","acceptedStatusCodes":[200],"timeoutMilliseconds":30000}
}`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := LoadGuestProductReleaseManagerConfiguration(path)
	if err == nil || !strings.Contains(err.Error(), "configuration is invalid") {
		t.Fatalf("expected explicit missing artifact-limit failure, got %v", err)
	}
}

func TestLoadGuestProductReleaseManagerConfigurationProvidesOnlyDeclaredValues(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "release-manager.json")
	if err := os.WriteFile(path, []byte(validConfiguration), 0o600); err != nil {
		t.Fatal(err)
	}
	configuration, err := LoadGuestProductReleaseManagerConfiguration(path)
	if err != nil {
		t.Fatal(err)
	}
	if configuration.Listener.Port != 18444 || configuration.ControlVirtioSocketListenerPort != 18444 || configuration.Manager.MaximumReleaseArtifactBytes != 1073741824 || configuration.Manager.HealthCheckURL != "http://127.0.0.1:18443/v1/runtime/readiness" {
		t.Fatalf("unexpected configuration %#v", configuration)
	}
}

func TestLoadGuestProductReleaseManagerConfigurationRejectsMissingControlVirtioSocketListener(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "release-manager.json")
	configuration := strings.Replace(validConfiguration, `,"controlVirtioSocketListener":{"port":18444}`, "", 1)
	if err := os.WriteFile(path, []byte(configuration), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := LoadGuestProductReleaseManagerConfiguration(path)
	if err == nil || !strings.Contains(err.Error(), "control virtio-socket listener port") {
		t.Fatalf("expected explicit missing C59 control listener failure, got %v", err)
	}
}

func TestParseReleaseUpdateCommandRejectsUnknownField(t *testing.T) {
	t.Parallel()
	_, err := ParseReleaseUpdateCommand(strings.NewReader(`{"schemaVersion":"v1","updateId":"update-01","expectedActiveReleaseId":"release-01","targetRelease":{"releaseId":"release-02","releaseDirectory":"/opt/vitalserver/releases/release-02","artifact":{"sha256":"0123456789012345678901234567890123456789012345678901234567890123","sizeBytes":1,"mediaType":"application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"}},"requestedAt":"2026-07-20T00:00:00Z","unknown":true}`))
	if err == nil {
		t.Fatal("expected unknown field rejection")
	}
}

const validConfiguration = `{
  "schemaVersion":"v1","managerId":"manager-primary","listener":{"bindHost":"127.0.0.1","port":18444},"controlVirtioSocketListener":{"port":18444},
  "releaseDirectoryRoot":"/opt/vitalserver/releases","currentReleaseLinkPath":"/opt/vitalserver/current",
  "stagingDirectory":"/var/lib/vitalserver/release-staging","stateDirectory":"/var/lib/vitalserver/release-state","stateDirectoryMode":"0700","maximumReleaseArtifactBytes":1073741824,
  "serviceManagement":{"systemctlExecutablePath":"/usr/bin/systemctl","managedServiceUnitName":"vitalserver-guest-product.service","restartTimeoutMilliseconds":60000},
  "healthCheck":{"scheme":"http","host":"127.0.0.1","port":18443,"path":"/v1/runtime/readiness","acceptedStatusCodes":[200],"timeoutMilliseconds":30000}
}`
