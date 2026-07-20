//go:build windows

package hostlocaladministration

import (
	"fmt"
	"net"

	"github.com/Microsoft/go-winio"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostdeployment"
)

func openPlatformLocalControlListener(configuration hostdeployment.HostLocalAdministrationConfiguration) (net.Listener, func() error, error) {
	if configuration.Transport != "windows-named-pipe" {
		return nil, nil, fmt.Errorf("local administration transport %q is not supported by this Host OS", configuration.Transport)
	}
	listener, err := winio.ListenPipe(configuration.EndpointAddress, &winio.PipeConfig{SecurityDescriptor: configuration.SecurityDescriptor})
	if err != nil {
		return nil, nil, fmt.Errorf("listen on local administration named pipe: %w", err)
	}
	return listener, listener.Close, nil
}
