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
	if method == http.MethodGet {
		switch strings.Join(parts, "/") {
		case "capabilities":
			return "/runtime/capabilities", true
		case "services":
			return "/runtime/services", true
		case "stack":
			return "/runtime/stack", true
		case "events":
			return "/runtime/events", true
		case "settings":
			return "/runtime/settings", true
		case "recorder-ingress/status":
			return "/runtime/recorder-ingress/status", true
		case "redis-relay/status":
			return "/runtime/redis-relay/status", true
		case "redis-relay/settings":
			return "/runtime/redis-relay/settings", true
		case "lab/scenarios", "lab/vital-files", "lab/beds", "lab/recorders":
			return "/runtime/" + strings.Join(parts, "/"), true
		case "vitaldb/observations/latest", "vitaldb/recorders", "vitaldb/beds", "vitaldb/relationships":
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if len(parts) == 3 && parts[0] == "services" && (parts[2] == "status" || parts[2] == "resource") {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if len(parts) == 3 && parts[0] == "lab" && parts[1] == "sessions" {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if len(parts) == 4 && parts[0] == "vitaldb" && parts[1] == "recorders" && parts[3] == "activity" {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if len(parts) == 3 && parts[0] == "vitaldb" && (parts[1] == "recorders" || parts[1] == "beds") {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if len(parts) == 2 && parts[0] == "operations" {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
	}
	if method == http.MethodPut && strings.Join(parts, "/") == "settings" {
		return "/runtime/settings", true
	}
	if method == http.MethodPut && strings.Join(parts, "/") == "redis-relay/settings" {
		return "/runtime/redis-relay/settings", true
	}
	if method == http.MethodPost {
		if strings.Join(parts, "/") == "admin-password" {
			return "/runtime/admin-password", true
		}
		if len(parts) == 3 && parts[0] == "services" && (parts[2] == "start" || parts[2] == "stop" || parts[2] == "restart") {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
		if strings.Join(parts, "/") == "maintenance/datastore/repair" {
			return "/runtime/maintenance/datastore/repair", true
		}
		if isRuntimeControllerPostPath(parts) {
			return "/runtime/" + strings.Join(parts, "/"), true
		}
	}
	return "", false
}

func isRuntimeControllerPostPath(parts []string) bool {
	path := strings.Join(parts, "/")
	switch path {
	case "lab/beds/create", "lab/beds/delete", "lab/beds/reset",
		"lab/recorders/create", "lab/recorders/delete", "lab/recorders/reset",
		"lab/sessions", "lab/vital-files/replay", "lab/vital-files/upload",
		"vitaldb/recorders/hide", "vitaldb/recorders/unhide", "vitaldb/recorders/delete",
		"vitaldb/beds/hide", "vitaldb/beds/unhide", "vitaldb/beds/delete":
		return true
	}
	return len(parts) == 4 && parts[0] == "lab" && parts[1] == "sessions" &&
		(parts[3] == "start" || parts[3] == "stop")
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
