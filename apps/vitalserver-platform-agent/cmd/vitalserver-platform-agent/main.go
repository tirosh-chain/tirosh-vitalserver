package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/agent"
	"github.com/tirosh/vitalserver-platform-agent/internal/platform"
	"github.com/tirosh/vitalserver-platform-agent/internal/servicehost"
)

const serviceName = "VitalServerPlatformAgent"

func main() {
	configPath := flag.String("config", "", "path to the explicit Platform Agent configuration")
	flag.Parse()
	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "platform agent config path is required: --config <path>")
		os.Exit(2)
	}
	config, err := agent.LoadConfig(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	if err := agent.ValidatePWA(config.PWA); err != nil {
		log.Fatalf("platform agent PWA unavailable path=%s reason=%v", config.PWA, err)
	}
	if err := agent.ValidateDelivery(config.Delivery); err != nil {
		log.Fatal(err)
	}
	if err := servicehost.Run(serviceName, func(ctx context.Context) error {
		return serve(ctx, config)
	}); err != nil {
		log.Fatal(err)
	}
}

func serve(ctx context.Context, config agent.Config) error {
	handler := agent.NewHandler(config, platform.NewServiceObserver(config.PlatformServices), time.Now())
	server := &http.Server{
		Addr: config.ListenAddress, Handler: handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("VitalServer Platform Agent listening address=%s", config.ListenAddress)
	serverResult := make(chan error, 1)
	go func() {
		serverResult <- server.ListenAndServe()
	}()
	select {
	case err := <-serverResult:
		if err == http.ErrServerClosed {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownContext); err != nil {
			return fmt.Errorf("Platform Agent HTTP shutdown failed: %w", err)
		}
		err := <-serverResult
		if err != nil && err != http.ErrServerClosed {
			return err
		}
		return nil
	}
}
