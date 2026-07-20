// guest-bundled-upstream-image-set-manager owns the Guest-local C64
// container image-set lifecycle. It serves the same narrow API on Guest
// loopback and AF_VSOCK; C32 owns any matching Host-loopback bridge.
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

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamcontrolvirtiotransport"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetmanagerconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerhttpapi"
)

func main() {
	invocation, exitCode := loadInvocation(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	deployment, err := guestbundledupstreamimagesetmanagerconfigurationfile.LoadImageSetManagerConfiguration(invocation.configurationPath)
	if err != nil {
		fail("C64 configuration", err)
	}
	operations, err := guestbundledupstreamimagesetfilesystem.NewImageSetOperationFileRepository(deployment.Manager)
	if err != nil {
		fail("C64 operation repository", err)
	}
	active, err := guestbundledupstreamimagesetfilesystem.NewActiveImageSetFileRepository(deployment.Manager)
	if err != nil {
		fail("C64 active image-set repository", err)
	}
	if invocation.mode == "initialize-active-image-set" {
		if failure := active.InitializeActiveImageSet(context.Background(), guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned}); failure != nil {
			fail("C64 explicit active image-set initialization", fmt.Errorf("state=%s issue=%s: %s", failure.State, failure.Issue.Code, failure.Issue.Message))
		}
		fmt.Printf("guest-bundled-upstream-image-set-manager initialized activeImageSetState=%s managerId=%s\n", guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned, deployment.Manager.ManagerID)
		return
	}
	stager, err := guestbundledupstreamimagesetfilesystem.NewImageSetArchiveFilesystemStager(deployment.Manager)
	if err != nil {
		fail("C64 archive stager", err)
	}
	engine, err := guestbundledupstreamimagesetprocess.NewDockerCLIContainerEngine(deployment.Manager)
	if err != nil {
		fail("C64 container engine", err)
	}
	application, err := guestbundledupstreamimagesetmanagerapplication.NewImageSetManagerApplicationService(deployment.Manager, operations, stager, active, engine, clock{})
	if err != nil {
		fail("C64 application", err)
	}
	handler, err := guestbundledupstreamimagesetmanagerhttpapi.NewImageSetManagerHTTPHandler(deployment.Manager.MaximumImageSetArtifactBytes, application)
	if err != nil {
		fail("C64 HTTP handler", err)
	}
	loopbackListener, err := net.Listen("tcp", net.JoinHostPort(deployment.Listener.BindHost, fmt.Sprint(deployment.Listener.Port)))
	if err != nil {
		fail("C64 loopback listener", err)
	}
	vsockListener, err := guestbundledupstreamcontrolvirtiotransport.ListenImageSetManagerControlVirtioSocket(deployment.ControlVirtioSocketListenerPort)
	if err != nil {
		_ = loopbackListener.Close()
		fail("C64 control virtio-socket listener", err)
	}
	loopbackServer, vsockServer := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second}, &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second}
	shutdownContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	serverErrors := make(chan error, 2)
	go serve(loopbackServer, loopbackListener, serverErrors)
	go serve(vsockServer, vsockListener, serverErrors)
	fmt.Printf("guest-bundled-upstream-image-set-manager listening loopbackAddress=%s controlVirtioSocketAddress=%s managerId=%s\n", loopbackListener.Addr(), vsockListener.Addr(), deployment.Manager.ManagerID)
	select {
	case <-shutdownContext.Done():
		shutdown(loopbackServer, vsockServer)
		<-serverErrors
		<-serverErrors
	case err := <-serverErrors:
		shutdown(loopbackServer, vsockServer)
		<-serverErrors
		if err != nil {
			fail("C64 HTTP server", err)
		}
	}
}

type invocation struct {
	configurationPath string
	mode              string
}

func loadInvocation(arguments []string) (invocation, int) {
	flags := flag.NewFlagSet("guest-bundled-upstream-image-set-manager", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var value invocation
	flags.StringVar(&value.configurationPath, "configuration", "", guestbundledupstreamimagesetmanagerconfigurationfile.ConfigurationPathDescription())
	flags.StringVar(&value.mode, "mode", "serve", "C64 operation mode: serve or initialize-active-image-set")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 {
		return invocation{}, 2
	}
	if value.configurationPath == "" {
		fmt.Fprintln(os.Stderr, "C64 configuration path is required")
		return invocation{}, 2
	}
	if value.mode != "serve" && value.mode != "initialize-active-image-set" {
		fmt.Fprintln(os.Stderr, "C64 mode is unsupported")
		return invocation{}, 2
	}
	return value, 0
}
func serve(server *http.Server, listener net.Listener, errorsChannel chan<- error) {
	err := server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		errorsChannel <- nil
		return
	}
	errorsChannel <- err
}
func shutdown(servers ...*http.Server) {
	context, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	for _, server := range servers {
		_ = server.Shutdown(context)
	}
}
func fail(component string, err error) {
	fmt.Fprintf(os.Stderr, "%s failed: %v\n", component, err)
	os.Exit(1)
}

type clock struct{}

func (clock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
