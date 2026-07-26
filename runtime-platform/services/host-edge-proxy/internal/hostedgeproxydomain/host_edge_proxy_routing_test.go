package hostedgeproxydomain

import (
	"strings"
	"testing"
)

func TestHostEdgeProxyConfigurationRequiresExplicitTrustBoundaryAndOrderedRoutes(t *testing.T) {
	configuration := validHostEdgeProxyDeploymentConfiguration()
	if err := ValidateHostEdgeProxyDeploymentConfiguration(configuration); err != nil {
		t.Fatalf("valid configuration rejected: %v", err)
	}

	configuration.ClientIdentityHeaderPolicy = ""
	if err := ValidateHostEdgeProxyDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "clientIdentityHeaderPolicy") {
		t.Fatalf("implicit identity policy error = %v", err)
	}

	configuration = validHostEdgeProxyDeploymentConfiguration()
	configuration.Routes[0], configuration.Routes[1] = configuration.Routes[1], configuration.Routes[0]
	if err := ValidateHostEdgeProxyDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "most-specific") {
		t.Fatalf("unordered routes error = %v", err)
	}

	configuration = validHostEdgeProxyDeploymentConfiguration()
	configuration.Routes[0].Target.Host = "target/derived-from-request"
	if err := ValidateHostEdgeProxyDeploymentConfiguration(configuration); err == nil || !strings.Contains(err.Error(), "target") {
		t.Fatalf("implicit target host error = %v", err)
	}
}

func TestResolveHostEdgeProxyRouteReturnsOnlyExplicitConfiguredRoute(t *testing.T) {
	configuration := validHostEdgeProxyDeploymentConfiguration()
	route, found := ResolveHostEdgeProxyRoute(configuration.Routes, "/socket.io/?EIO=3")
	if !found || route.ID != "recorder-gateway" {
		t.Fatalf("recorder route = %#v found=%t", route, found)
	}
	if _, found := ResolveHostEdgeProxyRoute(configuration.Routes[:1], "/browser"); found {
		t.Fatal("unmatched path selected an implicit route")
	}
	if _, found := ResolveHostEdgeProxyRoute(configuration.Routes, HostEdgeProxyLocalAdministrationCredentialMaterialPath); found {
		t.Fatal("C60 local credential-material route crossed the Host public edge")
	}
}

func validHostEdgeProxyDeploymentConfiguration() HostEdgeProxyDeploymentConfiguration {
	return HostEdgeProxyDeploymentConfiguration{
		SchemaVersion:              HostEdgeProxyDeploymentConfigurationSchemaVersion,
		ProxyID:                    "public-edge",
		Listener:                   HostEdgeProxyListener{Protocol: "http", BindHost: "0.0.0.0", Port: 8088},
		ReadinessPath:              "/ready",
		ClientIdentityHeaderPolicy: "replace-with-remote-address",
		Routes: []HostEdgeProxyRoute{
			{
				ID: "recorder-gateway", RequestPathPrefix: "/socket.io/", Target: HostEdgeProxyHTTPUpstream{Scheme: "http", Host: "127.0.0.1", Port: 18090},
				ForwardingProtocol: "http-and-websocket", RequestHostHeaderPolicy: "preserve-client-host", MaximumRequestBodyBytes: 1024, UpstreamResponseHeaderTimeoutMilliseconds: 1000,
			},
			{
				ID: "browser", RequestPathPrefix: "/", Target: HostEdgeProxyHTTPUpstream{Scheme: "http", Host: "127.0.0.1", Port: 18091},
				ForwardingProtocol: "http-and-websocket", RequestHostHeaderPolicy: "target-host", MaximumRequestBodyBytes: 1024, UpstreamResponseHeaderTimeoutMilliseconds: 1000,
			},
		},
	}
}
