//go:build darwin || linux

package stagednextupdaterprocess

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestCancellationTerminatesEntireStagedUpdaterProcessGroup(t *testing.T) {
	directory := t.TempDir()
	scriptPath := filepath.Join(directory, "staged-updater")
	childPIDPath := filepath.Join(directory, "layer-effect-executor.pid")
	script := "#!/bin/sh\nsleep 30 &\necho $! > '" + childPIDPath + "'\nwait\n"
	if err := os.WriteFile(scriptPath, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	go func() {
		result <- runConfinedProcess(ctx, scriptPath, nil, io.Discard, io.Discard)
	}()

	childPID := waitForPIDFile(t, childPIDPath)
	cancel()
	if err := <-result; !errors.Is(err, context.Canceled) {
		t.Fatalf("run result=%v, want context cancellation", err)
	}
	waitForProcessExit(t, childPID)
}

func waitForPIDFile(t *testing.T, path string) int {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		contents, err := os.ReadFile(path)
		if err == nil {
			pid, conversionError := strconv.Atoi(strings.TrimSpace(string(contents)))
			if conversionError != nil {
				t.Fatalf("invalid child pid %q: %v", contents, conversionError)
			}
			return pid
		}
		if !errors.Is(err, os.ErrNotExist) {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("staged updater did not report its child pid at %s", path)
	return 0
}

func waitForProcessExit(t *testing.T, pid int) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		err := syscall.Kill(pid, 0)
		if errors.Is(err, syscall.ESRCH) {
			return
		}
		if err != nil {
			t.Fatalf("inspect layer-effect executor pid %d: %v", pid, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("layer-effect executor pid %d survived staged updater cancellation", pid)
}
