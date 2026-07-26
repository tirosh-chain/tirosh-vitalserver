//go:build windows

package platformctlcontrolclient

import (
	"context"
	"fmt"
	"net"

	"github.com/Microsoft/go-winio"
)

func dialLocalAdministrationEndpoint(ctx context.Context, endpoint LocalControlEndpoint) (net.Conn, error) {
	if endpoint.transportKind != "windows-named-pipe" {
		return nil, fmt.Errorf("C52 transport %q is not supported on this operating system", endpoint.transportKind)
	}
	return winio.DialPipeContext(ctx, endpoint.address)
}
