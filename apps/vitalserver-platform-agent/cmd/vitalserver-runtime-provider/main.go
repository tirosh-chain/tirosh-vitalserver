package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/tirosh/vitalserver-platform-agent/internal/nativeprovider"
	"github.com/tirosh/vitalserver-platform-agent/internal/servicehost"
)

const serviceName = "VitalServerNativeRuntime"

func main() {
	configPath := flag.String("config", "", "path to the explicit Linux Native Runtime Provider configuration")
	flag.Parse()
	if *configPath == "" {
		fmt.Fprintln(os.Stderr, "native provider config path is required: --config <path>")
		os.Exit(2)
	}
	config, err := nativeprovider.LoadConfig(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	runner := nativeprovider.NewRunner(config)
	if err := servicehost.Run(serviceName, func(ctx context.Context) error {
		return runner.Run(ctx)
	}); err != nil {
		log.Fatal(err)
	}
}
