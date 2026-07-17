// Package hostagentdomain contains pure Host Agent documents and lifecycle policy.
package hostagentdomain

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"regexp"
	"time"
)

const SchemaVersion = "v1"

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)

type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type PlatformInstallation struct {
	SchemaVersion    string  `json:"schemaVersion"`
	ID               string  `json:"id"`
	ResourceRevision int     `json:"resourceRevision"`
	Release          Release `json:"release"`
	DataDirectory    string  `json:"dataDirectory"`
	InstalledAt      string  `json:"installedAt"`
	UpdatedAt        string  `json:"updatedAt"`
}

type Release struct {
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
}

// ConfiguredGuestRuntimeControlHTTPAddress is Host deployment input copied
// into the Host-owned endpoint resource. It is never a discovered Guest address
// or transport reachability observation.
type ConfiguredGuestRuntimeControlHTTPAddress struct {
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

type PlatformProviderObservation struct {
	Kind       string `json:"kind"`
	ID         string `json:"id"`
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type GuestRuntimeControlTransportObservation struct {
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

// GuestRuntimeControlEndpoint is the Host-owned revisioned aggregate for one
// configured Guest Runtime Control target and its independent observations.
type GuestRuntimeControlEndpoint struct {
	SchemaVersion    string                                   `json:"schemaVersion"`
	ID               string                                   `json:"id"`
	ResourceRevision int                                      `json:"resourceRevision"`
	Address          ConfiguredGuestRuntimeControlHTTPAddress `json:"address"`
	Provider         PlatformProviderObservation              `json:"provider"`
	Transport        GuestRuntimeControlTransportObservation  `json:"transport"`
	CreatedAt        string                                   `json:"createdAt"`
	UpdatedAt        string                                   `json:"updatedAt"`
}

type GuestLifecycleCommand struct {
	SchemaVersion                 string `json:"schemaVersion"`
	RequestID                     string `json:"requestId"`
	GuestRuntimeControlEndpointID string `json:"guestRuntimeControlEndpointId"`
	ExpectedResourceRevision      int    `json:"expectedResourceRevision"`
	Action                        string `json:"action"`
}

type ProviderLifecycleRequest struct {
	SchemaVersion string `json:"schemaVersion"`
	RequestID     string `json:"requestId"`
	ProviderID    string `json:"providerId"`
	Action        string `json:"action"`
}

type ProviderLifecycleResult struct {
	SchemaVersion string `json:"schemaVersion"`
	RequestID     string `json:"requestId"`
	ProviderID    string `json:"providerId"`
	ObservedState string `json:"observedState"`
	ObservedAt    string `json:"observedAt"`
	Issue         *Issue `json:"issue,omitempty"`
}

type OperationTarget struct {
	ResourceType              string `json:"resourceType"`
	ResourceID                string `json:"resourceId"`
	RequestedResourceRevision int    `json:"requestedResourceRevision"`
}

// EvidenceReference links a durable operation to a separately owned, durable
// fact. It is a reference only: the operation never embeds a receipt or
// recreates its state from this link.
type EvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
	URI  string `json:"uri,omitempty"`
}

type Operation struct {
	SchemaVersion      string              `json:"schemaVersion"`
	ID                 string              `json:"id"`
	Kind               string              `json:"kind"`
	RequestID          string              `json:"requestId"`
	Target             OperationTarget     `json:"target"`
	RequestedAt        string              `json:"requestedAt"`
	AcceptedAt         *string             `json:"acceptedAt,omitempty"`
	StartedAt          *string             `json:"startedAt,omitempty"`
	FinishedAt         *string             `json:"finishedAt,omitempty"`
	State              string              `json:"state"`
	Failure            *Issue              `json:"failure,omitempty"`
	TerminalReason     *Issue              `json:"terminalReason,omitempty"`
	EvidenceReferences []EvidenceReference `json:"evidenceReferences,omitempty"`
	CommandDigest      string              `json:"-"`
}

type ReadResult struct {
	SchemaVersion  string `json:"schemaVersion"`
	State          string `json:"state"`
	ObservedAt     string `json:"observedAt"`
	Value          any    `json:"value,omitempty"`
	Issue          *Issue `json:"issue,omitempty"`
	SourceRevision *int   `json:"sourceRevision,omitempty"`
}

type CommandRejection struct {
	SchemaVersion string `json:"schemaVersion"`
	State         string `json:"state"`
	RequestID     string `json:"requestId"`
	RejectedAt    string `json:"rejectedAt"`
	Issue         Issue  `json:"issue"`
}

// CommandAdmissionFailure preserves an unknown admission outcome without
// claiming whether a durable Operation exists. Callers retry the same request
// identifier after the Host owner recovers.
type CommandAdmissionFailure struct {
	SchemaVersion  string `json:"schemaVersion"`
	State          string `json:"state"`
	RequestID      string `json:"requestId"`
	ObservedAt     string `json:"observedAt"`
	AdmissionState string `json:"admissionState"`
	Issue          Issue  `json:"issue"`
}

type FacadeForwardingFailure struct {
	SchemaVersion       string `json:"schemaVersion"`
	State               string `json:"state"`
	RequestID           string `json:"requestId"`
	ObservedAt          string `json:"observedAt"`
	DeliveryDisposition string `json:"deliveryDisposition"`
	Issue               Issue  `json:"issue"`
}

func Timestamp(now time.Time) string {
	return now.UTC().Format(time.RFC3339Nano)
}

func ValidIdentifier(value string) bool {
	return len(value) > 0 && len(value) <= 128 && identifierPattern.MatchString(value)
}

func NewIdentifier(prefix string) (string, error) {
	if !ValidIdentifier(prefix) {
		return "", fmt.Errorf("invalid identifier prefix %q", prefix)
	}
	bytes := make([]byte, 12)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate identifier entropy: %w", err)
	}
	return prefix + "-" + hex.EncodeToString(bytes), nil
}

func Bool(value bool) *bool {
	return &value
}
