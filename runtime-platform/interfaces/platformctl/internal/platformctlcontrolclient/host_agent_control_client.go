// Package platformctlcontrolclient is the HTTP adapter used by platformctl to
// consume the public Host Agent control facade.
package platformctlcontrolclient

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const maximumControlResponseBytes int64 = 4 << 20
const maximumDescriptorBytes int64 = 16 << 10

// LocalControlEndpoint is a parsed, explicit loopback-only Host Agent HTTP
// address. It does not discover a deployment configuration or resolve a host
// name: the operator supplies the exact endpoint for each invocation.
type LocalControlEndpoint struct {
	baseURL       url.URL
	transportKind string
	address       string
}

// LocalAdministrationEndpointDescriptor is C52 as consumed by platformctl.
// It intentionally excludes the C33 authorization policy and Host deployment
// configuration; the selected OS listener enforces authorization itself.
type LocalAdministrationEndpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

// ParseLocalControlEndpoint rejects remote, ambiguous, or credential-bearing
// addresses before any HTTP request is made.
func ParseLocalControlEndpoint(raw string) (LocalControlEndpoint, error) {
	parsed, err := url.Parse(raw)
	if err != nil {
		return LocalControlEndpoint{}, fmt.Errorf("parse control endpoint: %w", err)
	}
	if parsed.Scheme != "http" {
		return LocalControlEndpoint{}, errors.New("control endpoint scheme must be http")
	}
	if parsed.User != nil || parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return LocalControlEndpoint{}, errors.New("control endpoint must contain only scheme, loopback host, and optional port")
	}
	if parsed.Host == "" || !isNumericLoopbackHost(parsed.Hostname()) {
		return LocalControlEndpoint{}, errors.New("control endpoint host must be 127.0.0.1 or ::1")
	}
	return LocalControlEndpoint{baseURL: *parsed, transportKind: "loopback-http"}, nil
}

// LoadLocalAdministrationEndpointDescriptor opens exactly one C52 regular
// file. It does not read C33, follow a symlink, infer an endpoint, or convert
// a missing descriptor into an available loopback connection.
func LoadLocalAdministrationEndpointDescriptor(path string) (LocalControlEndpoint, error) {
	if !isSafeCurrentHostAbsolutePath(path) {
		return LocalControlEndpoint{}, errors.New("local control descriptor path must be an absolute non-traversing path")
	}
	information, err := os.Lstat(path)
	if err != nil {
		return LocalControlEndpoint{}, fmt.Errorf("read local control descriptor metadata: %w", err)
	}
	if !information.Mode().IsRegular() || information.Mode()&os.ModeSymlink != 0 {
		return LocalControlEndpoint{}, errors.New("local control descriptor must be a regular non-symlink file")
	}
	if information.Size() > maximumDescriptorBytes {
		return LocalControlEndpoint{}, errors.New("local control descriptor exceeds 16 KiB limit")
	}
	encoded, err := os.ReadFile(path)
	if err != nil {
		return LocalControlEndpoint{}, fmt.Errorf("read local control descriptor: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	var descriptor LocalAdministrationEndpointDescriptor
	if err := decoder.Decode(&descriptor); err != nil {
		return LocalControlEndpoint{}, errors.New("local control descriptor is not valid C52 JSON")
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return LocalControlEndpoint{}, errors.New("local control descriptor must contain exactly one C52 document")
	}
	if descriptor.SchemaVersion != "v1" {
		return LocalControlEndpoint{}, errors.New("local control descriptor schemaVersion must be v1")
	}
	baseURL, err := url.Parse("http://host-agent.local")
	if err != nil {
		return LocalControlEndpoint{}, fmt.Errorf("construct local control URL: %w", err)
	}
	switch descriptor.Transport {
	case "unix-domain-socket":
		if !isSafeUnixSocketAddress(descriptor.Address) {
			return LocalControlEndpoint{}, errors.New("local control descriptor Unix socket address is invalid")
		}
	case "windows-named-pipe":
		if !isWindowsNamedPipeAddress(descriptor.Address) {
			return LocalControlEndpoint{}, errors.New("local control descriptor Windows named-pipe address is invalid")
		}
	default:
		return LocalControlEndpoint{}, errors.New("local control descriptor transport is unsupported")
	}
	return LocalControlEndpoint{baseURL: *baseURL, transportKind: descriptor.Transport, address: descriptor.Address}, nil
}

func isNumericLoopbackHost(host string) bool {
	return host == "127.0.0.1" || host == "::1"
}

// URL joins one published control route to this exact loopback endpoint.
func (endpoint LocalControlEndpoint) URL(route string) (string, error) {
	if !strings.HasPrefix(route, "/") || strings.Contains(route, "?") || strings.Contains(route, "#") {
		return "", errors.New("control route must be an absolute path without query or fragment")
	}
	resolved := endpoint.baseURL
	resolved.Path = route
	return resolved.String(), nil
}

// Response preserves the actual HTTP status and JSON document. The document
// is not re-modelled as CLI state.
type Response struct {
	HTTPStatus int             `json:"httpStatus"`
	Document   json.RawMessage `json:"document"`
}

// ResponseStatusError reports that the public facade returned a non-success
// HTTP status. Its associated Response still contains the owner-supplied
// document for the caller to display.
type ResponseStatusError struct {
	Status int
}

func (responseError *ResponseStatusError) Error() string {
	return fmt.Sprintf("control facade returned HTTP %d", responseError.Status)
}

// Client performs one public control-facade request at a time.
type Client struct {
	httpClient *http.Client
}

// NewClient accepts an explicit HTTP client so callers and tests choose
// timeout, transport, and cancellation behavior deliberately.
func NewClient(httpClient *http.Client) (*Client, error) {
	if httpClient == nil {
		return nil, errors.New("HTTP client is required")
	}
	configuredClient := *httpClient
	configuredClient.CheckRedirect = func(request *http.Request, previousRequests []*http.Request) error {
		return http.ErrUseLastResponse
	}
	return &Client{httpClient: &configuredClient}, nil
}

// NewClientForLocalAdministrationEndpoint makes one C52-selected OS-local
// transport available to platformctl. It disables environment proxy selection
// and has no TCP/remote fallback.
func NewClientForLocalAdministrationEndpoint(endpoint LocalControlEndpoint, timeout time.Duration) (*Client, error) {
	if endpoint.transportKind != "unix-domain-socket" && endpoint.transportKind != "windows-named-pipe" {
		return nil, errors.New("local administration client requires a C52 Unix socket or Windows named-pipe endpoint")
	}
	if timeout <= 0 {
		return nil, errors.New("local administration client timeout must be positive")
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
		return dialLocalAdministrationEndpoint(ctx, endpoint)
	}
	return NewClient(&http.Client{Timeout: timeout, Transport: transport})
}

// Execute sends an already-selected public route. It neither retries nor
// invents an idempotency key; command retry policy remains the state owner's
// published contract.
func (client *Client) Execute(ctx context.Context, endpoint LocalControlEndpoint, method string, route string, body []byte) (Response, error) {
	if method != http.MethodGet && method != http.MethodPost {
		return Response{}, fmt.Errorf("unsupported control method %q", method)
	}
	address, err := endpoint.URL(route)
	if err != nil {
		return Response{}, err
	}
	request, err := http.NewRequestWithContext(ctx, method, address, bytes.NewReader(body))
	if err != nil {
		return Response{}, fmt.Errorf("create control request: %w", err)
	}
	request.Header.Set("Accept", "application/json")
	if method == http.MethodPost {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.httpClient.Do(request)
	if err != nil {
		return Response{}, fmt.Errorf("execute control request: %w", err)
	}
	defer response.Body.Close()
	encodedDocument, err := io.ReadAll(io.LimitReader(response.Body, maximumControlResponseBytes+1))
	if err != nil {
		return Response{}, fmt.Errorf("read control response: %w", err)
	}
	if len(encodedDocument) > int(maximumControlResponseBytes) {
		return Response{}, errors.New("control response exceeds 4 MiB limit")
	}
	if !json.Valid(encodedDocument) {
		return Response{}, errors.New("control facade response is not valid JSON")
	}
	result := Response{HTTPStatus: response.StatusCode, Document: json.RawMessage(encodedDocument)}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return result, &ResponseStatusError{Status: response.StatusCode}
	}
	return result, nil
}

func isSafeCurrentHostAbsolutePath(value string) bool {
	if !filepath.IsAbs(value) || strings.ContainsRune(value, '\x00') {
		return false
	}
	for _, component := range strings.FieldsFunc(filepath.Clean(value), func(character rune) bool { return character == '/' || character == '\\' }) {
		if component == ".." {
			return false
		}
	}
	return true
}

func isSafeUnixSocketAddress(value string) bool {
	if !strings.HasPrefix(value, "/") || strings.Contains(value, `\`) || len(value) > 104 {
		return false
	}
	for _, component := range strings.Split(value, "/") {
		if component == ".." {
			return false
		}
	}
	return true
}

func isWindowsNamedPipeAddress(value string) bool {
	const prefix = `\\.\pipe\`
	if !strings.HasPrefix(value, prefix) {
		return false
	}
	name := strings.TrimPrefix(value, prefix)
	if name == "" || len(name) > 128 {
		return false
	}
	for _, character := range name {
		if !(character >= 'A' && character <= 'Z' || character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '.' || character == '_' || character == '-') {
			return false
		}
	}
	return true
}
