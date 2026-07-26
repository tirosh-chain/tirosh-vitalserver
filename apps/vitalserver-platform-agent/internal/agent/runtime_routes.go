package agent

import (
	"net/http"
	"strings"
)

// runtimeControllerRoutes is the closed Platform Agent forwarding boundary.
// Templates accept one decoded path segment for each braced placeholder only
// after splitRuntimePath has rejected empty and traversal segments.
var runtimeControllerRoutes = []runtimeControllerRoute{
	{method: http.MethodGet, template: "/runtime/capabilities"},
	{method: http.MethodGet, template: "/runtime/services"},
	{method: http.MethodGet, template: "/runtime/stack"},
	{method: http.MethodGet, template: "/runtime/events"},
	{method: http.MethodGet, template: "/runtime/settings"},
	{method: http.MethodGet, template: "/runtime/recorder-ingress/status"},
	{method: http.MethodGet, template: "/runtime/redis-relay/status"},
	{method: http.MethodGet, template: "/runtime/redis-relay/settings"},
	{method: http.MethodGet, template: "/runtime/services/{service}/status"},
	{method: http.MethodGet, template: "/runtime/services/{service}/resource"},
	{method: http.MethodGet, template: "/runtime/lab/scenarios"},
	{method: http.MethodGet, template: "/runtime/lab/vital-files"},
	{method: http.MethodGet, template: "/runtime/lab/beds"},
	{method: http.MethodGet, template: "/runtime/lab/recorders"},
	{method: http.MethodGet, template: "/runtime/lab/sessions"},
	{method: http.MethodGet, template: "/runtime/lab/sessions/{sessionID}"},
	{method: http.MethodGet, template: "/runtime/vitaldb/observations/latest"},
	{method: http.MethodGet, template: "/runtime/vitaldb/recorders"},
	{method: http.MethodGet, template: "/runtime/vitaldb/recorders/{vrcode}"},
	{method: http.MethodGet, template: "/runtime/vitaldb/recorders/{vrcode}/activity"},
	{method: http.MethodGet, template: "/runtime/vitaldb/beds"},
	{method: http.MethodGet, template: "/runtime/vitaldb/beds/{bedID}"},
	{method: http.MethodGet, template: "/runtime/vitaldb/relationships"},
	{method: http.MethodGet, template: "/runtime/operations/{operationID}"},
	{method: http.MethodPut, template: "/runtime/settings"},
	{method: http.MethodPut, template: "/runtime/redis-relay/settings"},
	{method: http.MethodPost, template: "/runtime/admin-password"},
	{method: http.MethodPost, template: "/runtime/services/{service}/start"},
	{method: http.MethodPost, template: "/runtime/services/{service}/stop"},
	{method: http.MethodPost, template: "/runtime/services/{service}/restart"},
	{method: http.MethodPost, template: "/runtime/maintenance/datastore/repair"},
	{method: http.MethodPost, template: "/runtime/lab/beds/create"},
	{method: http.MethodPost, template: "/runtime/lab/beds/delete"},
	{method: http.MethodPost, template: "/runtime/lab/beds/reset"},
	{method: http.MethodPost, template: "/runtime/lab/recorders/create"},
	{method: http.MethodPost, template: "/runtime/lab/recorders/delete"},
	{method: http.MethodPost, template: "/runtime/lab/recorders/reset"},
	{method: http.MethodPost, template: "/runtime/lab/sessions"},
	{method: http.MethodPost, template: "/runtime/lab/sessions/{sessionID}/start"},
	{method: http.MethodPost, template: "/runtime/lab/sessions/{sessionID}/stop"},
	{method: http.MethodPost, template: "/runtime/lab/sessions/{sessionID}/recorders/{recorderID}/start"},
	{method: http.MethodPost, template: "/runtime/lab/sessions/{sessionID}/recorders/{recorderID}/stop"},
	{method: http.MethodPost, template: "/runtime/lab/vital-files/replay"},
	{method: http.MethodPost, template: "/runtime/lab/vital-files/upload"},
	{method: http.MethodPost, template: "/runtime/vitaldb/recorders/hide"},
	{method: http.MethodPost, template: "/runtime/vitaldb/recorders/unhide"},
	{method: http.MethodPost, template: "/runtime/vitaldb/recorders/delete"},
	{method: http.MethodPost, template: "/runtime/vitaldb/beds/hide"},
	{method: http.MethodPost, template: "/runtime/vitaldb/beds/unhide"},
	{method: http.MethodPost, template: "/runtime/vitaldb/beds/delete"},
}

type runtimeControllerRoute struct {
	method   string
	template string
}

func (route runtimeControllerRoute) matches(method string, pathParts []string) bool {
	if route.method != method {
		return false
	}
	templateParts := strings.Split(strings.TrimPrefix(route.template, "/runtime/"), "/")
	if len(templateParts) != len(pathParts) {
		return false
	}
	for index, templatePart := range templateParts {
		if isRuntimeRouteParameter(templatePart) {
			continue
		}
		if templatePart != pathParts[index] {
			return false
		}
	}
	return true
}

func isRuntimeRouteParameter(part string) bool {
	return strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") && len(part) > 2
}
