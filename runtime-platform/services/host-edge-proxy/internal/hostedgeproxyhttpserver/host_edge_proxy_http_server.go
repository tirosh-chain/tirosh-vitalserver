// Package hostedgeproxyhttpserver adapts C36 routes to Host-owned HTTP/WebSocket proxy I/O.
package hostedgeproxyhttpserver

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-edge-proxy/internal/hostedgeproxydomain"
)

// NewHostEdgeProxyHTTPHandler creates the Host public edge handler from a
// complete C36. It validates before exposing any route and never derives a
// backend from a request Host header or a Guest runtime state read.
func NewHostEdgeProxyHTTPHandler(configuration hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration) (http.Handler, error) {
	if err := hostedgeproxydomain.ValidateHostEdgeProxyDeploymentConfiguration(configuration); err != nil {
		return nil, err
	}
	proxies := make(map[string]*httputil.ReverseProxy, len(configuration.Routes))
	for _, route := range configuration.Routes {
		proxies[route.ID] = reverseProxyForConfiguredRoute(route)
	}
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == configuration.ReadinessPath {
			if request.Method != http.MethodGet && request.Method != http.MethodHead {
				http.Error(response, "Host Edge Proxy readiness accepts only GET or HEAD", http.StatusMethodNotAllowed)
				return
			}
			response.WriteHeader(http.StatusNoContent)
			return
		}
		route, found := hostedgeproxydomain.ResolveHostEdgeProxyRoute(configuration.Routes, request.URL.Path)
		if !found {
			http.Error(response, "Host Edge Proxy has no configured route for this request path", http.StatusNotFound)
			return
		}
		if request.ContentLength > route.MaximumRequestBodyBytes {
			http.Error(response, "Host Edge Proxy request body exceeds the configured route limit", http.StatusRequestEntityTooLarge)
			return
		}
		if issue := replaceInboundClientIdentity(request); issue != nil {
			http.Error(response, "Host Edge Proxy could not establish client identity", http.StatusBadRequest)
			return
		}
		if request.Body != nil {
			request.Body = http.MaxBytesReader(response, request.Body, route.MaximumRequestBodyBytes)
		}
		proxies[route.ID].ServeHTTP(response, request)
	}), nil
}

func reverseProxyForConfiguredRoute(route hostedgeproxydomain.HostEdgeProxyRoute) *httputil.ReverseProxy {
	target := route.ConfiguredHTTPUpstreamURL()
	return &httputil.ReverseProxy{
		Director: func(request *http.Request) {
			request.URL.Scheme = target.Scheme
			request.URL.Host = target.Host
			request.RequestURI = ""
			if route.RequestHostHeaderPolicy == "target-host" {
				request.Host = target.Host
			}
		},
		Transport: &http.Transport{
			Proxy:                 nil,
			ForceAttemptHTTP2:     true,
			ResponseHeaderTimeout: time.Duration(route.UpstreamResponseHeaderTimeoutMilliseconds) * time.Millisecond,
		},
		ErrorHandler: func(response http.ResponseWriter, _ *http.Request, _ error) {
			http.Error(response, "Host Edge Proxy configured upstream is unavailable", http.StatusBadGateway)
		},
	}
}

func replaceInboundClientIdentity(request *http.Request) error {
	remoteHost, _, err := net.SplitHostPort(request.RemoteAddr)
	if err != nil || remoteHost == "" {
		return fmt.Errorf("remote address is not a host and port")
	}
	for _, header := range []string{"Forwarded", "X-Forwarded-For", "X-Real-IP", "X-Client-IP"} {
		request.Header.Del(header)
	}
	// httputil.ReverseProxy appends exactly one X-Forwarded-For hop from
	// request.RemoteAddr when that header is absent. Leaving it absent here
	// replaces any client-supplied chain instead of duplicating this Host hop.
	request.Header.Set("X-Real-IP", remoteHost)
	request.Header.Set("X-Client-IP", remoteHost)
	request.Header.Set("Forwarded", forwardedHeader(remoteHost))
	return nil
}

func forwardedHeader(remoteHost string) string {
	if strings.Contains(remoteHost, ":") {
		return `for="[` + remoteHost + `]";proto=http`
	}
	return "for=" + remoteHost + ";proto=http"
}
