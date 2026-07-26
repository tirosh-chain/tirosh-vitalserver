//go:build darwin || linux

package hostlocalupdatecompletionpublisher

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"
)

func newHostLocalDescriptorHTTPClient(descriptor HostLocalAdministrationEndpointDescriptor, timeout time.Duration) (*http.Client, error) {
	if descriptor.Transport != "unix-domain-socket" {
		return nil, fmt.Errorf("C52 transport %q is not supported by this Host OS", descriptor.Transport)
	}
	dialer := &net.Dialer{Timeout: timeout}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, "unix", descriptor.Address)
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
