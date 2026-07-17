// Package guestprocessoslauncher adapts planned Guest Product processes to OS process I/O.
package guestprocessoslauncher

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

// OperatingSystemGuestProductProcessLauncher performs the only OS process
// effect used by Guest Product supervision. It forwards child diagnostics but
// does not inspect them to construct product state.
type OperatingSystemGuestProductProcessLauncher struct {
	StandardOutput *os.File
	StandardError  *os.File
}

func (launcher OperatingSystemGuestProductProcessLauncher) StartGuestProductProcess(invocation guestproductprocesssupervisordomain.GuestProductProcessInvocation) (guestproductprocesssupervisorapplication.GuestProductProcessLifecycleHandle, error) {
	if invocation.ProcessName == "" || invocation.ExecutablePath == "" {
		return nil, fmt.Errorf("Guest Product process invocation is incomplete")
	}
	command := exec.Command(invocation.ExecutablePath, invocation.Arguments...)
	command.Stdout = launcher.StandardOutput
	command.Stderr = launcher.StandardError
	if err := command.Start(); err != nil {
		return nil, err
	}
	managed := &OperatingSystemGuestProductProcessLifecycleHandle{command: command, exits: make(chan error, 1)}
	go func() { managed.exits <- command.Wait() }()
	return managed, nil
}

var _ guestproductprocesssupervisorapplication.GuestProductProcessLauncher = OperatingSystemGuestProductProcessLauncher{}

// OperatingSystemGuestProductProcessLifecycleHandle presents one os/exec
// child as the application port. SIGTERM is the explicit Guest service-manager
// stop effect.
type OperatingSystemGuestProductProcessLifecycleHandle struct {
	command *exec.Cmd
	exits   chan error
}

func (process *OperatingSystemGuestProductProcessLifecycleHandle) WaitForGuestProductProcessExit() <-chan error {
	return process.exits
}

func (process *OperatingSystemGuestProductProcessLifecycleHandle) TerminateGuestProductProcess() error {
	if process.command == nil || process.command.Process == nil {
		return fmt.Errorf("Guest Product process was not started")
	}
	if err := process.command.Process.Signal(syscall.SIGTERM); err != nil && !errors.Is(err, os.ErrProcessDone) {
		return err
	}
	// os.ErrProcessDone is not a successful stop assertion. The application
	// still drains WaitForGuestProductProcessExit and records the observed child exit. It only
	// means an explicit sibling-stop signal raced an already-observed exit.
	return nil
}
