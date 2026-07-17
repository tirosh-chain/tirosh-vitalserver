// host-edge-proxy is the Host-owned C36 HTTP/WebSocket trust boundary.
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

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-edge-proxy/internal/hostedgeproxydeployment"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-edge-proxy/internal/hostedgeproxyhttpserver"
)

func main() {
	configurationPath, exitCode := loadHostEdgeProxyDeploymentConfigurationPath(os.Args[1:])
	if exitCode != 0 {
		os.Exit(exitCode)
	}
	configuration, err := hostedgeproxydeployment.LoadHostEdgeProxyDeploymentConfiguration(configurationPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Edge Proxy deployment configuration failed: %v\n", err)
		os.Exit(1)
	}
	handler, err := hostedgeproxyhttpserver.NewHostEdgeProxyHTTPHandler(configuration)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Edge Proxy route initialization failed: %v\n", err)
		os.Exit(1)
	}
	listener, err := net.Listen("tcp", net.JoinHostPort(configuration.Listener.BindHost, fmt.Sprintf("%d", configuration.Listener.Port)))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Host Edge Proxy listener failed: %v\n", err)
		os.Exit(1)
	}
	shutdownContext, stopShutdown := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopShutdown()
	server := &http.Server{Handler: handler}
	fmt.Printf("host-edge-proxy listening proxyId=%s address=%s\n", configuration.ProxyID, listener.Addr().String())
	go func() {
		<-shutdownContext.Done()
		_ = server.Close()
	}()
	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "Host Edge Proxy server failed: %v\n", err)
		os.Exit(1)
	}
}

func loadHostEdgeProxyDeploymentConfigurationPath(arguments []string) (string, int) {
	flags := flag.NewFlagSet("host-edge-proxy", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var configurationPath string
	flags.StringVar(&configurationPath, "deployment-configuration", "", hostedgeproxydeployment.HostEdgeProxyDeploymentConfigurationPathDescription())
	if err := flags.Parse(arguments); err != nil {
		return "", 2
	}
	if configurationPath == "" {
		fmt.Fprintln(os.Stderr, "Host Edge Proxy deployment configuration path is required")
		return "", 2
	}
	return configurationPath, 0
}
