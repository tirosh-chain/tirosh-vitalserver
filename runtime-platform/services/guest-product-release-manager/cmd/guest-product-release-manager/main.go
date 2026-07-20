// guest-product-release-manager owns immutable Guest Product release staging,
// current-link activation, health-gated rollback, and durable C59 operation
// evidence. It exposes the same explicit C59 HTTP contract on Guest loopback
// and a Guest AF_VSOCK listener; C32 owns the matching Host-loopback bridge.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleasecontrolvirtiotransport"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleasefilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleasemanagerconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/adapters/guestproductreleaseprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerhttpapi"
)

func main() {
	configurationPath, exitCode := loadConfigurationPath(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	deployment, err := guestproductreleasemanagerconfigurationfile.LoadGuestProductReleaseManagerConfiguration(configurationPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager configuration failed: %v\n", err)
		os.Exit(1)
	}
	repository, err := guestproductreleasefilesystem.NewReleaseOperationFileRepository(deployment.Manager)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager operation repository failed: %v\n", err)
		os.Exit(1)
	}
	stager, err := guestproductreleasefilesystem.NewReleaseArchiveFilesystemStager(deployment.Manager)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager archive stager failed: %v\n", err)
		os.Exit(1)
	}
	current, err := guestproductreleasefilesystem.NewCurrentReleaseFilesystemLinkManager(deployment.Manager)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager current-link manager failed: %v\n", err)
		os.Exit(1)
	}
	managedService, err := guestproductreleaseprocess.NewSystemctlManagedGuestProductService(deployment.Manager)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager service controller failed: %v\n", err)
		os.Exit(1)
	}
	health, err := guestproductreleaseprocess.NewHTTPGuestProductHealthProbe(deployment.Manager)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager health probe failed: %v\n", err)
		os.Exit(1)
	}
	application, err := guestproductreleasemanagerapplication.NewGuestProductReleaseManagerApplicationService(deployment.Manager, repository, stager, current, managedService, health, releaseManagementSystemClock{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager application failed: %v\n", err)
		os.Exit(1)
	}
	handler, err := guestproductreleasemanagerhttpapi.NewGuestProductReleaseManagerHTTPHandler(deployment.Manager.MaximumReleaseArtifactBytes, application)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager HTTP handler failed: %v\n", err)
		os.Exit(1)
	}
	loopbackListener, err := net.Listen("tcp", net.JoinHostPort(deployment.Listener.BindHost, fmt.Sprint(deployment.Listener.Port)))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager loopback listener failed: %v\n", err)
		os.Exit(1)
	}
	controlVirtioSocketListener, err := guestproductreleasecontrolvirtiotransport.ListenGuestProductReleaseManagerControlVirtioSocket(deployment.ControlVirtioSocketListenerPort)
	if err != nil {
		_ = loopbackListener.Close()
		fmt.Fprintf(os.Stderr, "Guest Product Release Manager control virtio-socket listener failed: %v\n", err)
		os.Exit(1)
	}
	loopbackServer := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	controlVirtioSocketServer := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	shutdownContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	serverErrors := make(chan error, 2)
	go serveGuestProductReleaseManagerHTTPServer(loopbackServer, loopbackListener, serverErrors)
	go serveGuestProductReleaseManagerHTTPServer(controlVirtioSocketServer, controlVirtioSocketListener, serverErrors)
	fmt.Printf("guest-product-release-manager listening loopbackAddress=%s controlVirtioSocketAddress=%s managerId=%s\n", loopbackListener.Addr(), controlVirtioSocketListener.Addr(), deployment.Manager.ManagerID)
	select {
	case <-shutdownContext.Done():
		shutdownGuestProductReleaseManagerHTTPServers(loopbackServer, controlVirtioSocketServer)
		<-serverErrors
		<-serverErrors
	case err := <-serverErrors:
		shutdownGuestProductReleaseManagerHTTPServers(loopbackServer, controlVirtioSocketServer)
		<-serverErrors
		if err != nil {
			fmt.Fprintf(os.Stderr, "Guest Product Release Manager server failed: %v\n", err)
			os.Exit(1)
		}
	}
}

func serveGuestProductReleaseManagerHTTPServer(server *http.Server, listener net.Listener, serverErrors chan<- error) {
	err := server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		serverErrors <- nil
		return
	}
	serverErrors <- err
}

func shutdownGuestProductReleaseManagerHTTPServers(servers ...*http.Server) {
	shutdownContext, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	for _, server := range servers {
		_ = server.Shutdown(shutdownContext)
	}
}

func loadConfigurationPath(arguments []string) (string, int) {
	flags := flag.NewFlagSet("guest-product-release-manager", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var configurationPath string
	flags.StringVar(&configurationPath, "configuration", "", guestproductreleasemanagerconfigurationfile.GuestProductReleaseManagerConfigurationPathDescription())
	if err := flags.Parse(arguments); err != nil {
		return "", 2
	}
	if configurationPath == "" {
		fmt.Fprintln(os.Stderr, "Guest Product Release Manager configuration path is required")
		return "", 2
	}
	return configurationPath, 0
}

type releaseManagementSystemClock struct{}

func (releaseManagementSystemClock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
