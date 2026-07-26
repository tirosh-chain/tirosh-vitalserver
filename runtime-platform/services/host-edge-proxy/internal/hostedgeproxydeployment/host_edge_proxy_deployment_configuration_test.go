package hostedgeproxydeployment

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadHostEdgeProxyDeploymentConfigurationDoesNotCreateMissingInput(t *testing.T) {
	_, err := LoadHostEdgeProxyDeploymentConfiguration(filepath.Join(t.TempDir(), "missing.json"))
	var unavailable HostEdgeProxyDeploymentConfigurationUnavailableError
	if !errors.As(err, &unavailable) {
		t.Fatalf("missing configuration error = %T %v", err, err)
	}
}

func TestLoadHostEdgeProxyDeploymentConfigurationRejectsUnknownFieldsAndMultipleValues(t *testing.T) {
	path := filepath.Join(t.TempDir(), "edge-proxy.json")
	if err := os.WriteFile(path, []byte(`{"schemaVersion":"v1","proxyId":"edge","listener":{"protocol":"http","bindHost":"0.0.0.0","port":8088},"readinessPath":"/ready","clientIdentityHeaderPolicy":"replace-with-remote-address","routes":[{"id":"gateway","requestPathPrefix":"/socket.io/","target":{"scheme":"http","host":"127.0.0.1","port":8090},"forwardingProtocol":"http-and-websocket","requestHostHeaderPolicy":"target-host","maximumRequestBodyBytes":1024,"upstreamResponseHeaderTimeoutMilliseconds":1000}],"unexpected":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := LoadHostEdgeProxyDeploymentConfiguration(path)
	var invalid HostEdgeProxyDeploymentConfigurationInvalidError
	if !errors.As(err, &invalid) {
		t.Fatalf("unknown field error = %T %v", err, err)
	}

	if err := os.WriteFile(path, []byte(`{"schemaVersion":"v1","proxyId":"edge","listener":{"protocol":"http","bindHost":"0.0.0.0","port":8088},"readinessPath":"/ready","clientIdentityHeaderPolicy":"replace-with-remote-address","routes":[{"id":"gateway","requestPathPrefix":"/socket.io/","target":{"scheme":"http","host":"127.0.0.1","port":8090},"forwardingProtocol":"http-and-websocket","requestHostHeaderPolicy":"target-host","maximumRequestBodyBytes":1024,"upstreamResponseHeaderTimeoutMilliseconds":1000}]} {}`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err = LoadHostEdgeProxyDeploymentConfiguration(path)
	if !errors.As(err, &invalid) {
		t.Fatalf("multiple JSON values error = %T %v", err, err)
	}
}
