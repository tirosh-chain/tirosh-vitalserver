package provider

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestRunnerPublishesExplicitLifecycleAndStopsProvider(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	stateOwner := &recordingOwner{running: make(chan struct{})}
	effect := &recordingEffect{}
	runner := testRunner(stateOwner, effect, readinessProbe{result: nil})
	result := make(chan error, 1)
	go func() { result <- runner.Run(ctx) }()
	<-stateOwner.running
	cancel()
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	states := stateOwner.states()
	expected := []State{StateStarting, StateBootstrapping, StateRunning, StateStopping, StateStopped}
	if len(states) != len(expected) {
		t.Fatalf("states=%v", states)
	}
	for index := range expected {
		if states[index] != expected[index] {
			t.Fatalf("states=%v expected=%v", states, expected)
		}
	}
	if stateOwner.published != "127.0.0.1" || stateOwner.removeCount != 1 {
		t.Fatalf("endpoint published=%q removed=%d", stateOwner.published, stateOwner.removeCount)
	}
	if effect.startCount != 1 || effect.stopCount != 1 {
		t.Fatalf("effects start=%d stop=%d", effect.startCount, effect.stopCount)
	}
}

func TestRunnerRecordsReadinessTimeoutWithoutInventingRunningState(t *testing.T) {
	stateOwner := &recordingOwner{running: make(chan struct{})}
	effect := &recordingEffect{}
	runner := testRunner(stateOwner, effect, readinessProbe{result: errors.New("connection refused")})
	runner.StartupTimeout = 20 * time.Millisecond
	runner.PollInterval = 2 * time.Millisecond
	if err := runner.Run(context.Background()); err == nil {
		t.Fatal("readiness timeout returned success")
	}
	states := stateOwner.states()
	if states[len(states)-1] != StateFailed {
		t.Fatalf("states=%v", states)
	}
	for _, state := range states {
		if state == StateRunning {
			t.Fatalf("timeout invented running state states=%v", states)
		}
	}
	if effect.stopCount != 1 {
		t.Fatalf("cleanup stop count=%d", effect.stopCount)
	}
	last := stateOwner.lastDocument()
	if last.Message == nil || !strings.Contains(*last.Message, "lastProbeError=connection refused") {
		t.Fatalf("readiness failure omitted last probe evidence: %+v", last)
	}
}

func TestRunnerRecordsStartFailureAndDoesNotPublishEndpoint(t *testing.T) {
	stateOwner := &recordingOwner{running: make(chan struct{})}
	effect := &recordingEffect{startErr: errors.New("exit status 1")}
	runner := testRunner(stateOwner, effect, readinessProbe{})
	if err := runner.Run(context.Background()); err == nil {
		t.Fatal("start failure returned success")
	}
	states := stateOwner.states()
	if len(states) != 2 || states[1] != StateFailed {
		t.Fatalf("states=%v", states)
	}
	if stateOwner.published != "" {
		t.Fatalf("failed start published endpoint=%s", stateOwner.published)
	}
}

func testRunner(owner StateOwner, effect Effect, probe ReadinessProbe) Runner {
	now := time.Date(2026, 7, 11, 0, 0, 0, 0, time.UTC)
	id := 0
	return Runner{
		Name: "Test Runtime Provider", ReadyURL: "http://127.0.0.1:18330/ready",
		EndpointAddress: "127.0.0.1", StartupTimeout: 2 * time.Second, ShutdownTimeout: 2 * time.Second,
		Effect: effect, Probe: probe, Owner: owner,
		Now:          func() time.Time { now = now.Add(time.Second); return now },
		PollInterval: time.Millisecond,
		NewID:        func() (string, error) { id++; return string(rune('0' + id)), nil },
	}
}

type readinessProbe struct{ result error }

func (probe readinessProbe) Read(context.Context, string) error { return probe.result }

type recordingEffect struct {
	startCount int
	stopCount  int
	startErr   error
}

func (effect *recordingEffect) Start(context.Context) error {
	effect.startCount++
	return effect.startErr
}

func (effect *recordingEffect) Stop(context.Context) error {
	effect.stopCount++
	return nil
}

type recordingOwner struct {
	mu          sync.Mutex
	documents   []Document
	published   string
	removeCount int
	running     chan struct{}
	once        sync.Once
}

func (owner *recordingOwner) WriteLifecycle(document Document) error {
	owner.mu.Lock()
	owner.documents = append(owner.documents, document)
	owner.mu.Unlock()
	if document.State == StateRunning {
		owner.once.Do(func() { close(owner.running) })
	}
	return nil
}

func (owner *recordingOwner) PublishEndpoint(address string) error {
	owner.published = address
	return nil
}

func (owner *recordingOwner) RemoveEndpoint() error {
	owner.removeCount++
	return nil
}

func (owner *recordingOwner) states() []State {
	owner.mu.Lock()
	defer owner.mu.Unlock()
	states := make([]State, len(owner.documents))
	for index, document := range owner.documents {
		states[index] = document.State
	}
	return states
}

func (owner *recordingOwner) lastDocument() Document {
	owner.mu.Lock()
	defer owner.mu.Unlock()
	return owner.documents[len(owner.documents)-1]
}
