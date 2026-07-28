//go:build darwin || linux

package hostlocalupdatecoordination

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

func newDescriptorHTTPClient(descriptor endpointDescriptor, timeout time.Duration) (*http.Client, error) {
	if descriptor.Transport != "unix-domain-socket" || !filepath.IsAbs(descriptor.Address) || strings.Contains(descriptor.Address, "..") || len(descriptor.Address) > 104 {
		return nil, fmt.Errorf("Host-local Unix socket descriptor is invalid")
	}
	dialer := &net.Dialer{Timeout: timeout}
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return dialer.DialContext(ctx, "unix", descriptor.Address)
	}}
	return &http.Client{Timeout: timeout, Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}, nil
}
