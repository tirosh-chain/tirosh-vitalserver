package agent

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

type controllableServices struct {
	available bool
	failure   error
	actions   []provider.Action
}

func (services *controllableServices) ReadPlatformServices() ([]contract.PlatformServiceStatus, []contract.ReadIssue) {
	return stubServices{}.ReadPlatformServices()
}

func (services *controllableServices) RuntimeProviderControlAvailable() bool {
	return services.available
}

func (services *controllableServices) ControlRuntimeProvider(_ context.Context, action provider.Action) error {
	services.actions = append(services.actions, action)
	return services.failure
}

func TestRuntimeProviderControlExecutesEffectWithoutInventingProviderState(t *testing.T) {
	root := t.TempDir()
	services := &controllableServices{available: true}
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeProviderDocument: filepath.Join(root, "runtime-provider.json"),
	}, services, time.Now())

	request := httptest.NewRequest(http.MethodPost, "/platform/runtime-provider/start", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	if len(services.actions) != 1 || services.actions[0] != provider.ActionStart {
		t.Fatalf("actions=%v", services.actions)
	}
	var result contract.RuntimeProviderCommandResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.State != "completed" || result.Failure != nil || result.Provider.State != "missing" {
		t.Fatalf("result=%+v", result)
	}
	if string(result.Provider.Document) != "null" {
		t.Fatalf("Agent invented Runtime Provider state: %s", result.Provider.Document)
	}
}

func TestRuntimeProviderControlPreservesEffectFailure(t *testing.T) {
	root := t.TempDir()
	services := &controllableServices{
		available: true,
		failure:   provider.EffectError{Kind: "permission-denied", Message: "systemd access denied"},
	}
	handler := NewHandler(Config{
		APIToken: "test-token", RuntimeProviderDocument: filepath.Join(root, "runtime-provider.json"),
	}, services, time.Now())

	request := httptest.NewRequest(http.MethodPost, "/platform/runtime-provider/stop", nil)
	request.Header.Set("Authorization", "Bearer test-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var result contract.RuntimeProviderCommandResponse
	if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.State != "failed" || result.Failure == nil || result.Failure.Kind != "permission-denied" {
		t.Fatalf("result=%+v", result)
	}
	if result.Provider.State != "missing" || string(result.Provider.Document) != "null" {
		t.Fatalf("effect failure must not overwrite Provider-owned state: %+v", result.Provider)
	}
}

func TestRuntimeProviderControlCapabilityMatchesAdapterAvailability(t *testing.T) {
	for _, test := range []struct {
		name, expected string
		services       *controllableServices
	}{
		{name: "available", expected: "true", services: &controllableServices{available: true}},
		{name: "unavailable", expected: "false", services: &controllableServices{available: false}},
	} {
		t.Run(test.name, func(t *testing.T) {
			handler := NewHandler(Config{APIToken: "test-token"}, test.services, time.Now())
			request := httptest.NewRequest(http.MethodGet, "/platform/capabilities", nil)
			request.Header.Set("X-Runtime-Control-Token", "test-token")
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			var capabilities map[string]any
			if err := json.Unmarshal(response.Body.Bytes(), &capabilities); err != nil {
				t.Fatal(err)
			}
			if got := capabilities["canControlRuntimeServices"]; got != (test.expected == "true") {
				t.Fatalf("canControlRuntimeServices=%v expected=%s", got, test.expected)
			}
		})
	}
}

func TestRuntimeProviderControlUnavailableDoesNotExecuteEffect(t *testing.T) {
	services := &controllableServices{available: false, failure: errors.New("must not execute")}
	handler := NewHandler(Config{APIToken: "test-token"}, services, time.Now())
	request := httptest.NewRequest(http.MethodPost, "/platform/runtime-provider/restart", nil)
	request.Header.Set("X-Runtime-Control-Token", "test-token")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNotImplemented || len(services.actions) != 0 {
		t.Fatalf("status=%d actions=%v body=%s", response.Code, services.actions, response.Body.String())
	}
}
