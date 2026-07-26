//go:build windows

package hostlocalupdatecompletionpublisher

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/Microsoft/go-winio"
)

func newHostLocalDescriptorHTTPClient(descriptor HostLocalAdministrationEndpointDescriptor, timeout time.Duration) (*http.Client, error) {
	if descriptor.Transport != "windows-named-pipe" {
		return nil, fmt.Errorf("C52 transport %q is not supported by this Host OS", descriptor.Transport)
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return winio.DialPipeContext(ctx, descriptor.Address)
		},
	}
	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}, nil
}
