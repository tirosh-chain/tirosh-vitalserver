//go:build !windows

package hostservicerunner

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

// ErrDeclaredServiceStopped distinguishes an operator stop from a child
// process failure. The service manager, rather than this adapter, owns the
// interpretation of the process result.
var ErrDeclaredServiceStopped = errors.New("declared Host service stopped")

// RunDeclaredHostService runs the exact child command for non-Windows service
// managers. A signal is forwarded by canceling the child context; this module
// neither retries nor selects another command.
func RunDeclaredHostService(definition ExecutionDefinition) error {
	context, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	command := exec.CommandContext(context, definition.Command.ExecutablePath, definition.Command.Arguments...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		if context.Err() != nil {
			return ErrDeclaredServiceStopped
		}
		return fmt.Errorf("run declared command: %w", err)
	}
	return nil
}
