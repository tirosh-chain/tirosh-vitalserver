package guestprocessoslauncher

import (
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

func TestOperatingSystemGuestProductProcessLauncherWaitsForExplicitTermination(t *testing.T) {
	launcher := OperatingSystemGuestProductProcessLauncher{}
	process, err := launcher.StartGuestProductProcess(guestproductprocesssupervisordomain.GuestProductProcessInvocation{
		ProcessName:    "termination-test-child",
		ExecutablePath: "/bin/sh",
		Arguments:      []string{"-c", "trap 'exit 0' TERM; while :; do sleep 1; done"},
	})
	if err != nil {
		t.Fatalf("start child process: %v", err)
	}
	if err := process.TerminateGuestProductProcess(); err != nil {
		t.Fatalf("terminate child process: %v", err)
	}
	select {
	case <-process.WaitForGuestProductProcessExit():
	case <-time.After(5 * time.Second):
		t.Fatal("terminated Guest Product child did not exit")
	}
}

func TestOperatingSystemGuestProductProcessLauncherTreatsAlreadyExitedChildAsAnObservedExit(t *testing.T) {
	launcher := OperatingSystemGuestProductProcessLauncher{}
	process, err := launcher.StartGuestProductProcess(guestproductprocesssupervisordomain.GuestProductProcessInvocation{
		ProcessName:    "already-exited-child",
		ExecutablePath: "/bin/sh",
		Arguments:      []string{"-c", "exit 0"},
	})
	if err != nil {
		t.Fatalf("start child: %v", err)
	}
	select {
	case <-process.WaitForGuestProductProcessExit():
	case <-time.After(5 * time.Second):
		t.Fatal("short-lived Guest Product child did not exit")
	}
	if err := process.TerminateGuestProductProcess(); err != nil {
		t.Fatalf("terminate already exited child: %v", err)
	}
}
