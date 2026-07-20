package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRunServiceDrainLoopStopsOnlyAtAnExplicitContextBoundary(t *testing.T) {
	runContext, cancel := context.WithCancel(context.Background())
	calls := 0
	err := runServiceDrainLoop(runContext, time.Hour, func(context.Context) error {
		calls++
		cancel()
		return nil
	})
	if err != nil || calls != 1 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}

func TestRunServiceDrainLoopReturnsTheExplicitDrainFailure(t *testing.T) {
	expected := errors.New("C31 queue unavailable")
	err := runServiceDrainLoop(context.Background(), time.Millisecond, func(context.Context) error {
		return expected
	})
	if !errors.Is(err, expected) {
		t.Fatalf("err=%v", err)
	}
}

func TestAutomaticAttemptIDIsStableAndBoundToHandoffBytes(t *testing.T) {
	first := automaticAttemptID([]byte(`{"schemaVersion":"v1","updateId":"update-1"}`))
	if first != automaticAttemptID([]byte(`{"schemaVersion":"v1","updateId":"update-1"}`)) {
		t.Fatal("the same immutable C31 bytes must select the same automatic attempt")
	}
	if first == automaticAttemptID([]byte(`{"schemaVersion":"v1","updateId":"update-2"}`)) {
		t.Fatal("different C31 bytes must not share an automatic attempt")
	}
}

func TestDirectRegularJSONFilesRejectsSymbolicLinkQueueEntry(t *testing.T) {
	directory, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "handoff.json"), []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(directory, "handoff.json"), filepath.Join(directory, "linked.json")); err != nil {
		t.Fatal(err)
	}
	if _, err := directRegularJSONFiles(directory); err == nil {
		t.Fatal("a symbolic-link C31 queue entry must be rejected")
	}
}
