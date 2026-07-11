package provider

import (
	"testing"
	"time"
)

func TestLinuxNativeLifecycleHappyPath(t *testing.T) {
	now := time.Date(2026, 7, 11, 1, 2, 3, 0, time.UTC)
	document := Starting("operation-1", "boot-1", now, now.Add(time.Minute))
	assertState(t, document, StateStarting)

	var err error
	document, err = Transition(document, EventRuntimeStarted, now.Add(time.Second), "Compose accepted")
	if err != nil {
		t.Fatal(err)
	}
	assertState(t, document, StateBootstrapping)
	document, err = Transition(document, EventEndpointReady, now.Add(2*time.Second), "Runtime Controller ready")
	if err != nil {
		t.Fatal(err)
	}
	assertState(t, document, StateRunning)
	if document.DeadlineAt != nil {
		t.Fatal("running lifecycle retained deadline")
	}
	document, err = Transition(document, EventStopRequested, now.Add(3*time.Second), "stop requested")
	if err != nil {
		t.Fatal(err)
	}
	assertState(t, document, StateStopping)
	if document.Operation == nil || *document.Operation != "stop-services" {
		t.Fatalf("stop operation=%v", document.Operation)
	}
	document, err = Transition(document, EventRuntimeStopped, now.Add(4*time.Second), "stopped")
	if err != nil {
		t.Fatal(err)
	}
	assertState(t, document, StateStopped)
}

func TestLifecycleRejectsImplicitTransition(t *testing.T) {
	now := time.Now()
	document := Starting("operation-1", "boot-1", now, now.Add(time.Minute))
	if _, err := Transition(document, EventEndpointReady, now, ""); err == nil {
		t.Fatal("starting lifecycle advanced directly to running")
	}
}

func TestLifecycleFailurePreservesExplicitEvidence(t *testing.T) {
	now := time.Now()
	document := Fail(
		Starting("operation-1", "boot-1", now, now.Add(time.Minute)),
		now.Add(time.Second),
		"launch-failed",
		"compose process exitCode=1",
	)
	assertState(t, document, StateFailed)
	if document.TerminalReason == nil || *document.TerminalReason != "launch-failed" {
		t.Fatalf("terminal reason=%v", document.TerminalReason)
	}
	if document.Message == nil || *document.Message == "" {
		t.Fatal("failure message is missing")
	}
}

func assertState(t *testing.T, document Document, expected State) {
	t.Helper()
	if document.State != expected {
		t.Fatalf("state=%s expected=%s", document.State, expected)
	}
}
