//go:build windows

package hostservicerunner

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"

	"golang.org/x/sys/windows/svc"
)

// ErrDeclaredServiceStopped distinguishes a Windows SCM stop request from a
// child-process failure. It is intentionally shared with the non-Windows
// adapter so the executable main keeps one explicit outcome vocabulary.
var ErrDeclaredServiceStopped = errors.New("declared Host service stopped")

// RunDeclaredHostService attaches one C48-hash-bound command to the exact SCM
// service name. It does not register, reconfigure, or discover a Windows
// service; C50 remains owner of those effects.
func RunDeclaredHostService(definition ExecutionDefinition) error {
	return svc.Run(definition.ServiceName, declaredHostServiceHandler{definition: definition})
}

type declaredHostServiceHandler struct {
	definition ExecutionDefinition
}

func (handler declaredHostServiceHandler) Execute(_ []string, requests <-chan svc.ChangeRequest, changes chan<- svc.Status) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}
	context, cancel := context.WithCancel(context.Background())
	defer cancel()
	command := exec.CommandContext(context, handler.definition.Command.ExecutablePath, handler.definition.Command.Arguments...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return false, 1
	}
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	changes <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case request := <-requests:
			switch request.Cmd {
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending}
				cancel()
				<-done
				return false, 0
			}
		case err := <-done:
			if err != nil {
				return false, 1
			}
			return false, 0
		}
	}
}

func (handler declaredHostServiceHandler) String() string {
	return fmt.Sprintf("declared Host service %s", handler.definition.ServiceName)
}
