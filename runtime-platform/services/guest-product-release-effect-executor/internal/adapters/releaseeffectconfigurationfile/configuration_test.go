package releaseeffectconfigurationfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadRejectsTrailingJSONDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "configuration.json")
	if err := os.WriteFile(path, append(validConfigurationJSON(), []byte("\n{}\n")...), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Fatal("expected C61 configuration with a trailing JSON document to be rejected")
	}
}

func TestLoadRejectsRelativePath(t *testing.T) {
	if _, err := Load("configuration.json"); err == nil {
		t.Fatal("expected relative C61 configuration path to be rejected")
	}
}

func validConfigurationJSON() []byte {
	return []byte(`{
  "schemaVersion": "v1",
  "effectExecutorId": "guest-product-release-effect-executor-020",
  "guestProductReleaseManagerEndpoint": {
    "scheme": "http",
    "host": "127.0.0.1",
    "port": 18444,
    "path": "/v1/guest-product-release-updates",
    "requestTimeoutMilliseconds": 60000
  },
  "apply": {
    "expectedActiveReleaseId": "vitalserver-guest-product-0.2.0",
    "targetReleaseId": "vitalserver-guest-product-0.3.0",
    "targetReleaseDirectory": "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0"
  }
}`)
}
