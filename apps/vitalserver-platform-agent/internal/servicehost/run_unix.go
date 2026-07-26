//go:build !windows

package servicehost

import (
	"context"
	"os"
	"os/signal"
	"syscall"
)

func Run(_ string, serve func(context.Context) error) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return serve(ctx)
}
