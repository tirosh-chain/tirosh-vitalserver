// Package hostagentapplication orchestrates Host Agent workflows through explicit ports.
package hostagentapplication

import (
	"context"
	"errors"
	"io"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

var ErrHostAgentOwnedResourceNotFound = errors.New("owned resource not found")
var ErrHostAgentOwnedResourceConflict = errors.New("owned resource conflict")
var ErrHostAgentOwnedResourceRevisionConflict = errors.New("owned resource revision conflict")

// HostAgentControlStateRepository persists the Host-owned installation,
// Guest Runtime Control endpoint, and Host guest-lifecycle operation state.
type HostAgentControlStateRepository interface {
	InitializeHostAgentControlState(context.Context, hostagentdomain.PlatformInstallation, hostagentdomain.GuestRuntimeControlEndpoint) error
	ReadHostPlatformInstallation(context.Context) (hostagentdomain.PlatformInstallation, error)
	ReadGuestRuntimeControlEndpoint(context.Context) (hostagentdomain.GuestRuntimeControlEndpoint, error)
	ReadHostOperation(context.Context, string) (hostagentdomain.Operation, error)
	ReadHostOperationByRequestID(context.Context, string) (hostagentdomain.Operation, error)
	PersistNewHostOperation(context.Context, hostagentdomain.Operation) error
	CommitGuestLifecycleOutcome(context.Context, hostagentdomain.GuestRuntimeControlEndpoint, hostagentdomain.Operation) error
	PersistGuestRuntimeControlEndpointObservation(context.Context, hostagentdomain.GuestRuntimeControlEndpoint) error
}

// PlatformProviderLifecycleClient invokes the selected Host platform provider.
type PlatformProviderLifecycleClient interface {
	Execute(context.Context, hostagentdomain.PlatformProviderLifecycleInvocation) hostagentdomain.ProviderLifecycleResult
}

type GuestRuntimeControlHTTPProbeResult struct {
	Reachable bool
	Issue     *hostagentdomain.Issue
}

type GuestRuntimeControlHTTPForwardedResponse struct {
	StatusCode  int
	ContentType string
	Body        []byte
}

type GuestRuntimeControlHTTPForwardingFailure struct {
	Issue *hostagentdomain.Issue
}

type GuestRuntimeControlHTTPStreamingRequest struct {
	Method        string
	Path          string
	ContentType   string
	ContentLength int64
	Body          io.Reader
	Headers       map[string]string
}

// GuestRuntimeControlHTTPTransport is the Host-side transport port for the
// explicit C33 Guest Runtime Control HTTP endpoint.
type GuestRuntimeControlHTTPTransport interface {
	Probe(context.Context, hostagentdomain.GuestRuntimeControlEndpoint) GuestRuntimeControlHTTPProbeResult
	Forward(context.Context, hostagentdomain.GuestRuntimeControlEndpoint, string, string, []byte, string) (GuestRuntimeControlHTTPForwardedResponse, *GuestRuntimeControlHTTPForwardingFailure)
	ForwardStream(context.Context, hostagentdomain.GuestRuntimeControlEndpoint, GuestRuntimeControlHTTPStreamingRequest) (GuestRuntimeControlHTTPForwardedResponse, *GuestRuntimeControlHTTPForwardingFailure)
}

type HostAgentClock interface {
	Now() time.Time
}

type SystemHostAgentClock struct{}

func (SystemHostAgentClock) Now() time.Time { return time.Now().UTC() }

type HostAgentRequestCorrelationIdentifierGenerator interface {
	NewRequestCorrelationIdentifier(string) (string, error)
}

type CryptoHostAgentRequestCorrelationIdentifierGenerator struct{}

func (CryptoHostAgentRequestCorrelationIdentifierGenerator) NewRequestCorrelationIdentifier(prefix string) (string, error) {
	return hostagentdomain.NewIdentifier(prefix)
}
