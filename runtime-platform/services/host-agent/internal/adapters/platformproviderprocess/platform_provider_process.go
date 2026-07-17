// Package platformproviderprocess adapts one explicitly selected Platform
// Provider process to the Host lifecycle port. It never selects another
// provider after a process execution, decode, or provider outcome failure.
package platformproviderprocess

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"sync"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

// LifecycleInvocationRunner exchanges one C21 invocation for one C10 result.
// The interface hides transport mechanics, not provider state or policy.
type LifecycleInvocationRunner interface {
	Run(context.Context, []byte) ([]byte, error)
}

// SelectedPlatformProviderProcessCommand names the exact executable process
// selected by C33. Arguments are explicit deployment input passed only to
// that process; this adapter never derives another command, provider, or
// configuration.
type SelectedPlatformProviderProcessCommand struct {
	ExecutablePath string
	Arguments      []string
}

type OneShotPlatformProviderProcessRunner struct {
	command SelectedPlatformProviderProcessCommand
}

// PersistentPlatformProviderProcessRunner owns one selected provider child process. It is
// used only where that process owns a live native resource for its entire
// lifetime, such as macOS VZVirtualMachine. Each Run exchanges one newline
// delimited invocation/result pair; calls are serialized by the Host Agent.
type PersistentPlatformProviderProcessRunner struct {
	stdin                 io.WriteCloser
	responses             chan []byte
	processTerminated     chan struct{}
	processTerminationMu  sync.RWMutex
	processTerminationErr error
	invocationMu          sync.Mutex
	closeOnce             sync.Once
	closeErr              error
	process               *exec.Cmd
}

func StartPersistentPlatformProviderProcessRunner(ctx context.Context, command SelectedPlatformProviderProcessCommand) (*PersistentPlatformProviderProcessRunner, error) {
	if command.ExecutablePath == "" {
		return nil, fmt.Errorf("persistent platform provider executable is required")
	}
	process := exec.CommandContext(ctx, command.ExecutablePath, command.Arguments...)
	stdin, err := process.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("open persistent platform provider input: %w", err)
	}
	stdout, err := process.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("open persistent platform provider output: %w", err)
	}
	if err := process.Start(); err != nil {
		return nil, fmt.Errorf("start persistent platform provider: %w", err)
	}
	runner := &PersistentPlatformProviderProcessRunner{
		stdin:             stdin,
		responses:         make(chan []byte, 1),
		processTerminated: make(chan struct{}),
		process:           process,
	}
	go runner.readResponses(stdout)
	go func() {
		runner.processTerminationMu.Lock()
		runner.processTerminationErr = process.Wait()
		runner.processTerminationMu.Unlock()
		close(runner.processTerminated)
	}()
	return runner, nil
}

func (runner *PersistentPlatformProviderProcessRunner) readResponses(output io.Reader) {
	scanner := bufio.NewScanner(output)
	scanner.Buffer(make([]byte, 1024), 1<<20)
	for scanner.Scan() {
		runner.responses <- append([]byte(nil), scanner.Bytes()...)
	}
}

func (runner *PersistentPlatformProviderProcessRunner) Run(ctx context.Context, input []byte) ([]byte, error) {
	runner.invocationMu.Lock()
	defer runner.invocationMu.Unlock()
	select {
	case <-runner.processTerminated:
		return nil, fmt.Errorf("persistent Platform Provider process is not running: %w", runner.terminationError())
	default:
	}
	if _, err := runner.stdin.Write(append(append([]byte(nil), input...), '\n')); err != nil {
		return nil, fmt.Errorf("write persistent Platform Provider lifecycle invocation: %w", err)
	}
	select {
	case output := <-runner.responses:
		return output, nil
	case <-runner.processTerminated:
		select {
		case output := <-runner.responses:
			return output, nil
		default:
			return nil, fmt.Errorf("persistent Platform Provider process exited before a lifecycle result: %w", runner.terminationError())
		}
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func (runner *PersistentPlatformProviderProcessRunner) terminationError() error {
	runner.processTerminationMu.RLock()
	defer runner.processTerminationMu.RUnlock()
	if runner.processTerminationErr == nil {
		return errors.New("process exited without an error")
	}
	return runner.processTerminationErr
}

// WaitForTermination reports the explicit child-process termination fact. It
// never infers process liveness from a prior lifecycle result or a failed
// write. Callers that need to act on supervisor exit must wait for this fact.
func (runner *PersistentPlatformProviderProcessRunner) WaitForTermination(ctx context.Context) error {
	select {
	case <-runner.processTerminated:
		return runner.terminationError()
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (runner *PersistentPlatformProviderProcessRunner) Close() error {
	runner.closeOnce.Do(func() {
		_ = runner.stdin.Close()
		select {
		case <-runner.processTerminated:
			return
		default:
		}
		if runner.process.Process != nil {
			runner.closeErr = runner.process.Process.Kill()
		}
	})
	return runner.closeErr
}

func (runner OneShotPlatformProviderProcessRunner) Run(ctx context.Context, input []byte) ([]byte, error) {
	if runner.command.ExecutablePath == "" {
		return nil, fmt.Errorf("Platform Provider process executable is required")
	}
	command := exec.CommandContext(ctx, runner.command.ExecutablePath, runner.command.Arguments...)
	command.Stdin = bytes.NewReader(input)
	output, err := command.Output()
	if err != nil {
		return nil, fmt.Errorf("run Platform Provider process: %w", err)
	}
	return output, nil
}

// SelectedPlatformProviderProcessClient is the Host-facing adapter for C21/C10
// transport to exactly one C33-selected provider process.
type SelectedPlatformProviderProcessClient struct {
	providerKind string
	runner       LifecycleInvocationRunner
	clock        hostagentapplication.HostAgentClock
}

func NewSelectedPlatformProviderProcessClient(providerKind string, command SelectedPlatformProviderProcessCommand, clock hostagentapplication.HostAgentClock) (*SelectedPlatformProviderProcessClient, error) {
	return NewSelectedPlatformProviderProcessClientWithRunner(providerKind, OneShotPlatformProviderProcessRunner{command: command}, clock)
}

func NewSelectedPlatformProviderProcessClientWithRunner(providerKind string, runner LifecycleInvocationRunner, clock hostagentapplication.HostAgentClock) (*SelectedPlatformProviderProcessClient, error) {
	if !hostagentdomain.ValidPlatformProviderKind(providerKind) || runner == nil || clock == nil {
		return nil, fmt.Errorf("supported Platform Provider kind, lifecycle invocation runner, and clock are required")
	}
	return &SelectedPlatformProviderProcessClient{providerKind: providerKind, runner: runner, clock: clock}, nil
}

func (provider *SelectedPlatformProviderProcessClient) Execute(ctx context.Context, invocation hostagentdomain.PlatformProviderLifecycleInvocation) hostagentdomain.ProviderLifecycleResult {
	request := invocation.Lifecycle
	if issue := hostagentdomain.ValidatePlatformProviderLifecycleInvocation(invocation); issue != nil {
		return provider.failure(request, issue.Code, issue.Message)
	}
	if invocation.ProviderKind != provider.providerKind {
		return provider.failure(request, "platform-provider-process-kind-mismatch", "configured Host provider kind does not match the selected Platform Provider process")
	}
	encoded, err := json.Marshal(invocation)
	if err != nil {
		return provider.failure(request, "provider-request-encode-failed", "Host could not encode the platform provider invocation")
	}
	output, err := provider.runner.Run(ctx, encoded)
	if err != nil {
		return provider.failure(request, "platform-provider-process-execution-failed", "selected Platform Provider process did not return a lifecycle result")
	}
	decoder := json.NewDecoder(strings.NewReader(string(output)))
	decoder.DisallowUnknownFields()
	var result hostagentdomain.ProviderLifecycleResult
	if err := decoder.Decode(&result); err != nil {
		return provider.failure(request, "platform-provider-process-decode-failed", "selected Platform Provider process returned an invalid lifecycle result")
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return provider.failure(request, "platform-provider-process-decode-failed", "selected Platform Provider process returned more than one JSON document")
	}
	return result
}

func (provider *SelectedPlatformProviderProcessClient) failure(request hostagentdomain.ProviderLifecycleRequest, code string, message string) hostagentdomain.ProviderLifecycleResult {
	return hostagentdomain.FailedProviderResult(request, hostagentdomain.Timestamp(provider.clock.Now()), hostagentdomain.Issue{
		Code:       code,
		Message:    message,
		Retryable:  hostagentdomain.Bool(true),
		Dependency: provider.providerKind + "-process",
	})
}
