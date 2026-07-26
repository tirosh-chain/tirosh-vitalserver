//go:build windows

package servicehost

import (
	"context"
	"os"
	"os/signal"

	"golang.org/x/sys/windows/svc"
)

func Run(name string, serve func(context.Context) error) error {
	isService, err := svc.IsWindowsService()
	if err != nil {
		return err
	}
	if !isService {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		return serve(ctx)
	}
	return svc.Run(name, &handler{serve: serve})
}

type handler struct {
	serve func(context.Context) error
}

func (handler *handler) Execute(
	_ []string,
	requests <-chan svc.ChangeRequest,
	status chan<- svc.Status,
) (bool, uint32) {
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	status <- svc.Status{State: svc.StartPending}
	go func() { result <- handler.serve(ctx) }()
	status <- svc.Status{
		State:   svc.Running,
		Accepts: svc.AcceptStop | svc.AcceptShutdown,
	}

	for {
		select {
		case err := <-result:
			if err != nil {
				return true, 1
			}
			return false, 0
		case request := <-requests:
			switch request.Cmd {
			case svc.Interrogate:
				status <- request.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending}
				cancel()
				if err := <-result; err != nil {
					return true, 1
				}
				return false, 0
			}
		}
	}
}
