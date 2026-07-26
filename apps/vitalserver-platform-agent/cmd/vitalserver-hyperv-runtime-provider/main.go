package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/tirosh/vitalserver-platform-agent/internal/hypervprovider"
	"github.com/tirosh/vitalserver-platform-agent/internal/servicehost"
)

const serviceName = "VitalServerHyperVRuntime"

func main() {
	configPath := flag.String("config", "", "path to the explicit Windows Hyper-V Runtime Provider configuration")
	flag.Parse()
	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "Hyper-V provider config path is required: --config <path>")
		os.Exit(2)
	}
	config, err := hypervprovider.LoadConfig(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	runner := hypervprovider.NewRunner(config)
	if err := servicehost.Run(serviceName, func(ctx context.Context) error {
		return runner.Run(ctx)
	}); err != nil {
		log.Fatal(err)
	}
}
