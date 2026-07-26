// Package guestruntimedomain contains pure Guest Runtime documents and validation rules.
package guestruntimedomain

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

type ResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
}

type SecretReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type ConnectionObservation struct {
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type TopologyStatus struct {
	ReadState                   string                `json:"readState"`
	Connection                  ConnectionObservation `json:"connection"`
	CapabilityDocumentReference *ResourceReference    `json:"capabilityDocumentReference,omitempty"`
	CapabilityRevision          *int                  `json:"capabilityRevision,omitempty"`
	LastOperationReference      *ResourceReference    `json:"lastOperationReference,omitempty"`
	ObservedAt                  string                `json:"observedAt"`
	Issue                       *Issue                `json:"issue,omitempty"`
}

type RuntimeTopologySpec struct {
	ProfileKind         string            `json:"profileKind"`
	ProviderKind        string            `json:"providerKind"`
	EndpointReference   ResourceReference `json:"endpointReference"`
	CredentialReference *SecretReference  `json:"credentialReference,omitempty"`
}

type RuntimeTopology struct {
	SchemaVersion    string              `json:"schemaVersion"`
	ID               string              `json:"id"`
	ResourceRevision int                 `json:"resourceRevision"`
	Spec             RuntimeTopologySpec `json:"spec"`
	Status           TopologyStatus      `json:"status"`
	CreatedAt        string              `json:"createdAt"`
	UpdatedAt        string              `json:"updatedAt"`
}

// CapabilityDocument is a Guest Runtime-owned provider observation. It states
// which contracts a selected topology profile can use; it never asserts a
// current upstream connection or a completed delivery.
type CapabilityDocument struct {
	SchemaVersion      string       `json:"schemaVersion"`
	ID                 string       `json:"id"`
	Provider           Provider     `json:"provider"`
	CapabilityRevision int          `json:"capabilityRevision"`
	ObservedAt         string       `json:"observedAt"`
	Commands           []Capability `json:"commands"`
	Reads              []Capability `json:"reads"`
}

type Provider struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type Capability struct {
	Name  string `json:"name"`
	State string `json:"state"`
	Issue *Issue `json:"issue,omitempty"`
}

type TopologyApplyCommand struct {
	SchemaVersion            string              `json:"schemaVersion"`
	RequestID                string              `json:"requestId"`
	TopologyID               string              `json:"topologyId"`
	ExpectedResourceRevision int                 `json:"expectedResourceRevision"`
	Spec                     RuntimeTopologySpec `json:"spec"`
}

type OperationTarget struct {
	ResourceType              string `json:"resourceType"`
	ResourceID                string `json:"resourceId"`
	RequestedResourceRevision int    `json:"requestedResourceRevision"`
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

// CommandAdmissionFailure preserves a failed command admission without
// asserting whether a durable Operation was created.
type CommandAdmissionFailure struct {
	SchemaVersion  string `json:"schemaVersion"`
	State          string `json:"state"`
	RequestID      string `json:"requestId"`
	ObservedAt     string `json:"observedAt"`
	AdmissionState string `json:"admissionState"`
	Issue          Issue  `json:"issue"`
}

type ServiceIdentity struct {
	Name       string `json:"name"`
	Version    string `json:"version"`
	InstanceID string `json:"instanceId,omitempty"`
}

type ServiceReadiness struct {
	SchemaVersion string          `json:"schemaVersion"`
	Service       ServiceIdentity `json:"service"`
	State         string          `json:"state"`
	ObservedAt    string          `json:"observedAt"`
	Issue         *Issue          `json:"issue,omitempty"`
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

func ValidateTopologyCommand(command TopologyApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) {
		return &Issue{Code: "invalid-request-id", Message: "requestId must be a non-empty v1 identifier"}
	}
	if !ValidIdentifier(command.TopologyID) {
		return &Issue{Code: "invalid-topology-id", Message: "topologyId must be a non-empty v1 identifier"}
	}
	if command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be zero or greater"}
	}
	if command.Spec.ProfileKind != "bundled-upstream" && command.Spec.ProfileKind != "external-upstream" {
		return &Issue{Code: "invalid-profile-kind", Message: "profileKind must name a supported topology profile"}
	}
	if command.Spec.ProviderKind != "vitalserver" {
		return &Issue{Code: "invalid-provider-kind", Message: "providerKind must be vitalserver"}
	}
	if !ValidIdentifier(command.Spec.EndpointReference.ResourceType) || !ValidIdentifier(command.Spec.EndpointReference.ResourceID) {
		return &Issue{Code: "invalid-endpoint-reference", Message: "endpointReference must contain valid resource type and id"}
	}
	if command.Spec.CredentialReference != nil && (!ValidIdentifier(command.Spec.CredentialReference.Kind) || !ValidIdentifier(command.Spec.CredentialReference.ID)) {
		return &Issue{Code: "invalid-credential-reference", Message: "credentialReference must contain valid kind and id"}
	}
	return nil
}
