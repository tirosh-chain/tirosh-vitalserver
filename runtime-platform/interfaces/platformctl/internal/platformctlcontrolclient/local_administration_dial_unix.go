//go:build darwin || linux

package platformctlcontrolclient

import (
	"context"
	"fmt"
	"net"
)

func dialLocalAdministrationEndpoint(ctx context.Context, endpoint LocalControlEndpoint) (net.Conn, error) {
	if endpoint.transportKind != "unix-domain-socket" {
		return nil, fmt.Errorf("C52 transport %q is not supported on this operating system", endpoint.transportKind)
	}
	return (&net.Dialer{}).DialContext(ctx, "unix", endpoint.address)
}
