package platformproviderprocess_test

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/adapters/platformproviderprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type fixedClock struct{ now time.Time }

func (clock fixedClock) Now() time.Time { return clock.now }

type runner func(context.Context, []byte) ([]byte, error)

func (run runner) Run(ctx context.Context, input []byte) ([]byte, error) { return run(ctx, input) }

func invocation() hostagentdomain.PlatformProviderLifecycleInvocation {
	return hostagentdomain.PlatformProviderLifecycleInvocation{
		SchemaVersion: "v1", ProviderKind: hostagentdomain.WindowsHyperVSCMProviderKind, RequestID: "request-1", ExpectedGuestRuntimeControlEndpointRevision: 1,
		Lifecycle: hostagentdomain.ProviderLifecycleRequest{SchemaVersion: "v1", RequestID: "request-1", ProviderID: "guest-vm", Action: "start"},
	}
}

func TestProviderReturnsBridgeContractWithoutHostPolicy(t *testing.T) {
	var received hostagentdomain.PlatformProviderLifecycleInvocation
	provider, err := platformproviderprocess.NewSelectedPlatformProviderProcessClientWithRunner(hostagentdomain.WindowsHyperVSCMProviderKind, runner(func(_ context.Context, input []byte) ([]byte, error) {
		if err := json.Unmarshal(input, &received); err != nil {
			t.Fatalf("decode C21 input: %v", err)
		}
		return []byte(`{"schemaVersion":"v1","requestId":"request-1","providerId":"guest-vm","observedState":"running","observedAt":"2026-07-17T00:00:00Z"}`), nil
	}), fixedClock{now: time.Date(2026, 7, 17, 0, 0, 1, 0, time.UTC)})
	if err != nil {
		t.Fatal(err)
	}
	result := provider.Execute(context.Background(), invocation())
	if result.ObservedState != "running" || result.Issue != nil {
		t.Fatalf("provider result = %+v", result)
	}
	if received.ProviderKind != hostagentdomain.WindowsHyperVSCMProviderKind || received.RequestID != "request-1" || received.ExpectedGuestRuntimeControlEndpointRevision != 1 || received.Lifecycle.RequestID != received.RequestID {
		t.Fatalf("C21 invocation = %+v", received)
	}
}

func TestProviderReportsBridgeFailureAsTypedProviderResult(t *testing.T) {
	provider, err := platformproviderprocess.NewSelectedPlatformProviderProcessClientWithRunner(hostagentdomain.LinuxKVMlibvirtSystemdProviderKind, runner(func(_ context.Context, _ []byte) ([]byte, error) {
		return nil, errors.New("bridge is unavailable")
	}), hostagentapplication.SystemHostAgentClock{})
	if err != nil {
		t.Fatal(err)
	}
	invocation := invocation()
	invocation.ProviderKind = hostagentdomain.LinuxKVMlibvirtSystemdProviderKind
	result := provider.Execute(context.Background(), invocation)
	if result.ObservedState != "failed" || result.Issue == nil || result.Issue.Code != "platform-provider-process-execution-failed" {
		t.Fatalf("provider result = %+v", result)
	}
}

func TestPersistentPlatformProviderProcessRunnerRetainsOneLifecycleTransport(t *testing.T) {
	if os.Getenv("HOST_AGENT_PERSISTENT_PROVIDER_HELPER") == "1" {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			fmt.Fprintln(os.Stdout, `{"schemaVersion":"v1","requestId":"request-1","providerId":"guest-vm","observedState":"running","observedAt":"2026-07-17T00:00:00Z"}`)
		}
		return
	}
	t.Setenv("HOST_AGENT_PERSISTENT_PROVIDER_HELPER", "1")
	runner, err := platformproviderprocess.StartPersistentPlatformProviderProcessRunner(context.Background(), platformproviderprocess.SelectedPlatformProviderProcessCommand{
		ExecutablePath: os.Args[0],
		Arguments:      []string{"-test.run=TestPersistentPlatformProviderProcessRunnerRetainsOneLifecycleTransport"},
	})
	if err != nil {
		t.Fatal(err)
	}
	defer runner.Close()
	output, err := runner.Run(context.Background(), []byte(`{"schemaVersion":"v1"}`))
	if err != nil {
		t.Fatal(err)
	}
	var result hostagentdomain.ProviderLifecycleResult
	if err := json.Unmarshal(output, &result); err != nil {
		t.Fatal(err)
	}
	if result.ObservedState != "running" || result.RequestID != "request-1" {
		t.Fatalf("persistent provider result = %+v", result)
	}
}

func TestPersistentPlatformProviderProcessRunnerPreservesTerminationForLaterInvocation(t *testing.T) {
	if os.Getenv("HOST_AGENT_TERMINATING_PROVIDER_HELPER") == "1" {
		scanner := bufio.NewScanner(os.Stdin)
		if scanner.Scan() {
			fmt.Fprintln(os.Stdout, `{"schemaVersion":"v1","requestId":"request-1","providerId":"guest-vm","observedState":"running","observedAt":"2026-07-17T00:00:00Z"}`)
		}
		return
	}
	t.Setenv("HOST_AGENT_TERMINATING_PROVIDER_HELPER", "1")
	runner, err := platformproviderprocess.StartPersistentPlatformProviderProcessRunner(context.Background(), platformproviderprocess.SelectedPlatformProviderProcessCommand{
		ExecutablePath: os.Args[0],
		Arguments:      []string{"-test.run=TestPersistentPlatformProviderProcessRunnerPreservesTerminationForLaterInvocation"},
	})
	if err != nil {
		t.Fatal(err)
	}
	defer runner.Close()
	if _, err := runner.Run(context.Background(), []byte(`{"schemaVersion":"v1"}`)); err != nil {
		t.Fatalf("first lifecycle result: %v", err)
	}
	contextWithDeadline, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := runner.WaitForTermination(contextWithDeadline); err == nil {
		t.Fatal("expected the one-shot helper to terminate after its first result")
	}
	if _, err := runner.Run(contextWithDeadline, []byte(`{"schemaVersion":"v1"}`)); err == nil {
		t.Fatal("expected the terminated Platform Provider process to remain unavailable")
	}
}
