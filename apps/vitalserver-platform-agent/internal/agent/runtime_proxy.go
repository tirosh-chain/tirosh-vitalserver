package agent

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

func (h *Handler) proxyRuntime(response http.ResponseWriter, request *http.Request) {
	targetPath, exists := runtimeControllerPath(request.Method, request.URL.Path)
	if !exists {
		writeJSON(response, http.StatusNotFound, contract.ErrorResponse{
			Code: "notFound", Message: "Runtime Controller route is not mapped by the Platform Agent.",
		})
		return
	}
	endpoint := owner.ReadEndpoint(h.config.RuntimeEndpointDocument)
	if endpoint.State != "loaded" || endpoint.Read == nil || endpoint.Read.Address == nil {
		message := "Runtime Controller endpoint is unavailable."
		if endpoint.ReadError != nil {
			message = *endpoint.ReadError
		}
		writeJSON(response, http.StatusServiceUnavailable, contract.ErrorResponse{
			Code: "runtimeControllerUnavailable", Message: message,
		})
		return
	}
	address := *endpoint.Read.Address
	if net.ParseIP(address) == nil {
		writeJSON(response, http.StatusServiceUnavailable, contract.ErrorResponse{
			Code: "runtimeControllerUnavailable", Message: "Runtime Controller endpoint address is not an IP address.",
		})
		return
	}
	target := &url.URL{
		Scheme: "http",
		Host:   net.JoinHostPort(address, fmt.Sprintf("%d", h.config.RuntimeControllerPort)),
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director
	proxy.Director = func(outbound *http.Request) {
		originalDirector(outbound)
		outbound.URL.Path = targetPath
		outbound.URL.RawPath = ""
		outbound.Header.Del("X-Runtime-Control-Token")
		outbound.Header.Del("Authorization")
	}
	proxy.ErrorHandler = func(response http.ResponseWriter, _ *http.Request, err error) {
		writeJSON(response, http.StatusBadGateway, contract.ErrorResponse{
			Code:    "runtimeControllerTransportFailed",
			Message: fmt.Sprintf("Runtime Controller transport failed: %v", err),
		})
	}
	proxy.ServeHTTP(response, request)
}

func runtimeControllerPath(method, path string) (string, bool) {
	parts := splitRuntimePath(path)
	if parts == nil {
		return "", false
	}
	for _, route := range runtimeControllerRoutes {
		if route.matches(method, parts) {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
	}
	return "", false
}

func splitRuntimePath(path string) []string {
	if !strings.HasPrefix(path, "/runtime/") || strings.HasSuffix(path, "/") {
		return nil
	}
	parts := strings.Split(strings.TrimPrefix(path, "/runtime/"), "/")
	for _, part := range parts {
		if part == "" || part == "." || part == ".." {
			return nil
		}
	}
	return parts
}
