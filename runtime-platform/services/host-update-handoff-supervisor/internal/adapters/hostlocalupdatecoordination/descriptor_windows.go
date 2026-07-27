//go:build windows

package hostlocalupdatecoordination

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/Microsoft/go-winio"
)

func newDescriptorHTTPClient(descriptor endpointDescriptor, timeout time.Duration) (*http.Client, error) {
	const prefix = `\\.\pipe\`
	name := strings.TrimPrefix(descriptor.Address, prefix)
	if descriptor.Transport != "windows-named-pipe" || !strings.HasPrefix(descriptor.Address, prefix) || name == "" || len(name) > 128 || !validPipeName(name) {
		return nil, fmt.Errorf("Host-local Windows named-pipe descriptor is invalid")
	}
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return winio.DialPipeContext(ctx, descriptor.Address)
	}}
	return &http.Client{Timeout: timeout, Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}, nil
}

func validPipeName(value string) bool {
	for index, character := range value {
		alphanumeric := (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')
		if !alphanumeric && character != '.' && character != '_' && character != '-' {
			return false
		}
		if index == 0 && !alphanumeric {
			return false
		}
	}
	return true
}
