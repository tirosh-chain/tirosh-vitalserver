// Package hostedgeproxydomain contains pure Host Edge Proxy route and C36 policy.
package hostedgeproxydomain

import (
	"fmt"
	"net"
	"net/url"
	"strings"
)

// HostEdgeProxyDeploymentConfigurationSchemaVersion is the only C36 desired
// deployment document version accepted by this bounded context.
const HostEdgeProxyDeploymentConfigurationSchemaVersion = "v1"

// HostEdgeProxyLocalAdministrationCredentialMaterialPath is C60's exact
// Host Agent local-administration route. It is never eligible for C36 public
// routing, including from an otherwise valid catch-all browser route. C52 OS
// transport authorization owns access instead.
const HostEdgeProxyLocalAdministrationCredentialMaterialPath = "/v1/runtime/archive/credential-material"

// HostEdgeProxyDeploymentConfiguration is C36 after its Host deployment input
// has been decoded. It is desired configuration, not a claim about listener
// reachability, Guest readiness, or upstream health.
type HostEdgeProxyDeploymentConfiguration struct {
	SchemaVersion              string                `json:"schemaVersion"`
	ProxyID                    string                `json:"proxyId"`
	Listener                   HostEdgeProxyListener `json:"listener"`
	ReadinessPath              string                `json:"readinessPath"`
	ClientIdentityHeaderPolicy string                `json:"clientIdentityHeaderPolicy"`
	Routes                     []HostEdgeProxyRoute  `json:"routes"`
}

type HostEdgeProxyListener struct {
	Protocol string `json:"protocol"`
	BindHost string `json:"bindHost"`
	Port     int    `json:"port"`
}

type HostEdgeProxyRoute struct {
	ID                                        string                    `json:"id"`
	RequestPathPrefix                         string                    `json:"requestPathPrefix"`
	Target                                    HostEdgeProxyHTTPUpstream `json:"target"`
	ForwardingProtocol                        string                    `json:"forwardingProtocol"`
	RequestHostHeaderPolicy                   string                    `json:"requestHostHeaderPolicy"`
	MaximumRequestBodyBytes                   int64                     `json:"maximumRequestBodyBytes"`
	UpstreamResponseHeaderTimeoutMilliseconds int                       `json:"upstreamResponseHeaderTimeoutMilliseconds"`
}

type HostEdgeProxyHTTPUpstream struct {
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

// ValidateHostEdgeProxyDeploymentConfiguration validates semantic C36 rules
// that JSON shape alone cannot express. It has no network or filesystem read.
func ValidateHostEdgeProxyDeploymentConfiguration(configuration HostEdgeProxyDeploymentConfiguration) error {
	if configuration.SchemaVersion != HostEdgeProxyDeploymentConfigurationSchemaVersion {
		return fmt.Errorf("Host Edge Proxy deployment schemaVersion must be %q", HostEdgeProxyDeploymentConfigurationSchemaVersion)
	}
	if !validIdentifier(configuration.ProxyID) {
		return fmt.Errorf("Host Edge Proxy proxyId is invalid")
	}
	if configuration.Listener.Protocol != "http" || !validHost(configuration.Listener.BindHost) || !validPort(configuration.Listener.Port) {
		return fmt.Errorf("Host Edge Proxy listener is invalid")
	}
	if !validRequestPathPrefix(configuration.ReadinessPath) {
		return fmt.Errorf("Host Edge Proxy readinessPath is invalid")
	}
	if configuration.ClientIdentityHeaderPolicy != "replace-with-remote-address" {
		return fmt.Errorf("Host Edge Proxy clientIdentityHeaderPolicy must explicitly replace forwarded client identity")
	}
	if len(configuration.Routes) == 0 || len(configuration.Routes) > 32 {
		return fmt.Errorf("Host Edge Proxy requires between one and 32 configured routes")
	}
	routeIDs := map[string]struct{}{}
	routePrefixes := map[string]struct{}{}
	previousPrefixLength := int(^uint(0) >> 1)
	for _, route := range configuration.Routes {
		if !validIdentifier(route.ID) {
			return fmt.Errorf("Host Edge Proxy route id is invalid")
		}
		if _, exists := routeIDs[route.ID]; exists {
			return fmt.Errorf("Host Edge Proxy route ids must be unique")
		}
		routeIDs[route.ID] = struct{}{}
		if !validRequestPathPrefix(route.RequestPathPrefix) {
			return fmt.Errorf("Host Edge Proxy route %s requestPathPrefix is invalid", route.ID)
		}
		if _, exists := routePrefixes[route.RequestPathPrefix]; exists {
			return fmt.Errorf("Host Edge Proxy requestPathPrefix values must be unique")
		}
		routePrefixes[route.RequestPathPrefix] = struct{}{}
		if len(route.RequestPathPrefix) > previousPrefixLength {
			return fmt.Errorf("Host Edge Proxy routes must be ordered from most-specific to least-specific requestPathPrefix")
		}
		previousPrefixLength = len(route.RequestPathPrefix)
		if route.ForwardingProtocol != "http-and-websocket" {
			return fmt.Errorf("Host Edge Proxy route %s forwardingProtocol is unsupported", route.ID)
		}
		if route.RequestHostHeaderPolicy != "preserve-client-host" && route.RequestHostHeaderPolicy != "target-host" {
			return fmt.Errorf("Host Edge Proxy route %s requestHostHeaderPolicy is invalid", route.ID)
		}
		if route.MaximumRequestBodyBytes < 1 || route.MaximumRequestBodyBytes > 2147483648 {
			return fmt.Errorf("Host Edge Proxy route %s maximumRequestBodyBytes must be between one and 2147483648", route.ID)
		}
		if route.UpstreamResponseHeaderTimeoutMilliseconds < 1 || route.UpstreamResponseHeaderTimeoutMilliseconds > 3600000 {
			return fmt.Errorf("Host Edge Proxy route %s upstreamResponseHeaderTimeoutMilliseconds must be between one and 3600000", route.ID)
		}
		if route.Target.Scheme != "http" && route.Target.Scheme != "https" || !validHost(route.Target.Host) || !validPort(route.Target.Port) {
			return fmt.Errorf("Host Edge Proxy route %s target is invalid", route.ID)
		}
	}
	return nil
}

// ResolveHostEdgeProxyRoute returns only a configured route. An unmatched
// request has no implicit default backend.
func ResolveHostEdgeProxyRoute(routes []HostEdgeProxyRoute, requestPath string) (HostEdgeProxyRoute, bool) {
	if requestPath == HostEdgeProxyLocalAdministrationCredentialMaterialPath {
		return HostEdgeProxyRoute{}, false
	}
	for _, route := range routes {
		if strings.HasPrefix(requestPath, route.RequestPathPrefix) {
			return route, true
		}
	}
	return HostEdgeProxyRoute{}, false
}

// ConfiguredHTTPUpstreamURL resolves this route's already-configured HTTP
// upstream. It does not derive an upstream from a request or runtime state.
func (route HostEdgeProxyRoute) ConfiguredHTTPUpstreamURL() *url.URL {
	return &url.URL{Scheme: route.Target.Scheme, Host: net.JoinHostPort(route.Target.Host, fmt.Sprintf("%d", route.Target.Port))}
}

func validIdentifier(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == '-' {
			if index == 0 && (character == '.' || character == '_' || character == '-') {
				return false
			}
			continue
		}
		return false
	}
	return true
}

func validHost(value string) bool {
	if value == "" || len(value) > 255 {
		return false
	}
	for index, character := range value {
		if index == 0 && !((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == ':') {
			return false
		}
		if (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '_' || character == ':' || character == '-' {
			continue
		}
		return false
	}
	return true
}

func validPort(value int) bool { return value >= 1 && value <= 65535 }

func validRequestPathPrefix(value string) bool {
	return strings.HasPrefix(value, "/") && len(value) <= 512 && !strings.ContainsAny(value, "?#") && !containsTraversalSegment(value)
}

func containsTraversalSegment(value string) bool {
	for _, segment := range strings.Split(value, "/") {
		if segment == ".." {
			return true
		}
	}
	return false
}
