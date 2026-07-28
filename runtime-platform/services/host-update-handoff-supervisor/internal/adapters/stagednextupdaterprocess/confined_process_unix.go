//go:build darwin || linux

package stagednextupdaterprocess

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"syscall"
)

// runConfinedProcess owns one OS process group. Cancellation terminates the
// whole group so a staged updater cannot leave layer-effect executors running.
func runConfinedProcess(ctx context.Context, executable string, arguments []string, standardOutput io.Writer, standardError io.Writer) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	command := exec.Command(executable, arguments...)
	command.Stdout = standardOutput
	command.Stderr = standardError
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		return err
	}

	waitResult := make(chan error, 1)
	go func() {
		waitResult <- command.Wait()
	}()

	select {
	case err := <-waitResult:
		return err
	case <-ctx.Done():
		killError := syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
		<-waitResult
		if killError != nil && !errors.Is(killError, syscall.ESRCH) {
			return fmt.Errorf("terminate staged updater process group: %w", killError)
		}
		return ctx.Err()
	}
}
