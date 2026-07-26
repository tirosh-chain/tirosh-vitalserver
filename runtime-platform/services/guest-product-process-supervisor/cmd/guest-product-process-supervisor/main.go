// guest-product-process-supervisor owns Guest Runtime and Recorder Gateway process lifetime.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/adapters/guestprocessoslauncher"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/adapters/guestproductdeploymentconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

func main() {
	configurationPath, exitCode := loadGuestProductProcessDeploymentConfigurationPath(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	configuration, err := guestproductdeploymentconfigurationfile.LoadGuestProductProcessDeploymentConfiguration(configurationPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product process deployment configuration failed: %v\n", err)
		os.Exit(1)
	}
	topology, err := guestproductdeploymentconfigurationfile.LoadGuestProductVitalServerTopologyDeployment(configuration.RecorderGateway.VitalServerTopologyDeploymentPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product VitalServer topology deployment failed: %v\n", err)
		os.Exit(1)
	}
	var externalDeliveryConfiguration *guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration
	if configuration.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath != "" {
		loaded, loadErr := guestproductdeploymentconfigurationfile.LoadExternalVitalServerDeliveryConfiguration(configuration.RecorderGateway.ExternalVitalServerDeliveryConfigurationPath)
		if loadErr != nil {
			fmt.Fprintf(os.Stderr, "External VitalServer delivery configuration failed: %v\n", loadErr)
			os.Exit(1)
		}
		externalDeliveryConfiguration = &loaded
	}
	supervisionContext, stopSupervision := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSupervision()
	guestProductProcessLauncher := guestprocessoslauncher.OperatingSystemGuestProductProcessLauncher{StandardOutput: os.Stdout, StandardError: os.Stderr}
	fmt.Printf("guest-product-process-supervisor starting deploymentId=%s\n", configuration.DeploymentID)
	if err := guestproductprocesssupervisorapplication.RunGuestProductProcessDeployment(supervisionContext, configuration, topology, externalDeliveryConfiguration, guestProductProcessLauncher); err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product process supervision failed: %v\n", err)
		os.Exit(1)
	}
}

func loadGuestProductProcessDeploymentConfigurationPath(arguments []string) (string, int) {
	flags := flag.NewFlagSet("guest-product-process-supervisor", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var configurationPath string
	flags.StringVar(&configurationPath, "deployment-configuration", "", guestproductdeploymentconfigurationfile.GuestProductProcessDeploymentConfigurationPathDescription())
	if err := flags.Parse(arguments); err != nil {
		return "", 2
	}
	if configurationPath == "" {
		fmt.Fprintln(os.Stderr, "Guest Product process deployment configuration path is required")
		return "", 2
	}
	return configurationPath, 0
}
