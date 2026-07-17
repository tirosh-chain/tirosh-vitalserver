package guestruntimedomain

import (
	"fmt"
	"time"
)

const (
	ExternalUpstreamIntegrationResourceType = "external-upstream-integration"
	OutboundRelayTargetResourceType         = "outbound-relay-target"
	ExternalUpstreamApplyOperationKind      = "runtime.external-upstream.apply"
	OutboundRelayApplyOperationKind         = "runtime.outbound-relay.apply"
)

// IntegrationProviderReference identifies an adapter/capability profile. The
// endpoint and credential remain references so neither secret nor provider
// private topology is copied into Guest Runtime state.
type IntegrationProviderReference struct {
	Kind               string `json:"kind"`
	ID                 string `json:"id"`
	CapabilityRevision int    `json:"capabilityRevision"`
}

type ExternalUpstreamSpec struct {
	Provider            IntegrationProviderReference `json:"provider"`
	EndpointReference   ResourceReference            `json:"endpointReference"`
	CredentialReference *SecretReference             `json:"credentialReference,omitempty"`
}

type ExternalUpstreamStatus struct {
	State                       string                `json:"state"`
	Connection                  ConnectionObservation `json:"connection"`
	CapabilityDocumentReference *ResourceReference    `json:"capabilityDocumentReference,omitempty"`
	CapabilityRevision          *int                  `json:"capabilityRevision,omitempty"`
	ObservedAt                  string                `json:"observedAt"`
	Issue                       *Issue                `json:"issue,omitempty"`
}

type ExternalUpstreamIntegration struct {
	SchemaVersion    string                 `json:"schemaVersion"`
	ID               string                 `json:"id"`
	ResourceRevision int                    `json:"resourceRevision"`
	Spec             ExternalUpstreamSpec   `json:"spec"`
	Status           ExternalUpstreamStatus `json:"status"`
	CreatedAt        string                 `json:"createdAt"`
	UpdatedAt        string                 `json:"updatedAt"`
}

type ExternalUpstreamApplyCommand struct {
	SchemaVersion            string               `json:"schemaVersion"`
	RequestID                string               `json:"requestId"`
	IntegrationID            string               `json:"integrationId"`
	ExpectedResourceRevision int                  `json:"expectedResourceRevision"`
	Spec                     ExternalUpstreamSpec `json:"spec"`
}

// ExternalUpstreamObservation is the adapter's complete known answer. A Go
// error from the port means the adapter outcome is unknown and must not be
// converted into this document.
type ExternalUpstreamObservation struct {
	State      string                `json:"state"`
	Connection ConnectionObservation `json:"connection"`
	Capability *CapabilityDocument   `json:"capability,omitempty"`
	Issue      *Issue                `json:"issue,omitempty"`
}

type OutboundRelayTargetSpec struct {
	Provider            IntegrationProviderReference `json:"provider"`
	EndpointReference   ResourceReference            `json:"endpointReference"`
	CredentialReference *SecretReference             `json:"credentialReference,omitempty"`
}

type OutboundRelayTargetStatus struct {
	State                    string             `json:"state"`
	AcknowledgementReference *EvidenceReference `json:"acknowledgementReference,omitempty"`
	ObservedAt               string             `json:"observedAt"`
	Issue                    *Issue             `json:"issue,omitempty"`
}

type OutboundRelayTarget struct {
	SchemaVersion    string                    `json:"schemaVersion"`
	ID               string                    `json:"id"`
	ResourceRevision int                       `json:"resourceRevision"`
	Spec             OutboundRelayTargetSpec   `json:"spec"`
	Status           OutboundRelayTargetStatus `json:"status"`
	CreatedAt        string                    `json:"createdAt"`
	UpdatedAt        string                    `json:"updatedAt"`
}

type OutboundRelayApplyCommand struct {
	SchemaVersion            string                  `json:"schemaVersion"`
	RequestID                string                  `json:"requestId"`
	TargetID                 string                  `json:"targetId"`
	ExpectedResourceRevision int                     `json:"expectedResourceRevision"`
	Spec                     OutboundRelayTargetSpec `json:"spec"`
}

type OutboundRelayObservation struct {
	State                    string             `json:"state"`
	AcknowledgementReference *EvidenceReference `json:"acknowledgementReference,omitempty"`
	Issue                    *Issue             `json:"issue,omitempty"`
}

func ValidateExternalUpstreamApplyCommand(command ExternalUpstreamApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.IntegrationID) {
		return &Issue{Code: "invalid-external-upstream-command-id", Message: "requestId and integrationId must be valid v1 identifiers"}
	}
	if command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be zero or greater"}
	}
	if issue := validateIntegrationProviderReference(command.Spec.Provider); issue != nil {
		return issue
	}
	if issue := validateResourceReference(command.Spec.EndpointReference, "external upstream endpointReference"); issue != nil {
		return issue
	}
	if command.Spec.CredentialReference != nil && (!ValidIdentifier(command.Spec.CredentialReference.Kind) || !ValidIdentifier(command.Spec.CredentialReference.ID)) {
		return &Issue{Code: "invalid-external-upstream-credential-reference", Message: "credentialReference must contain valid kind and id"}
	}
	return nil
}

func ValidateOutboundRelayApplyCommand(command OutboundRelayApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.TargetID) {
		return &Issue{Code: "invalid-outbound-relay-command-id", Message: "requestId and targetId must be valid v1 identifiers"}
	}
	if command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be zero or greater"}
	}
	if issue := validateIntegrationProviderReference(command.Spec.Provider); issue != nil {
		return issue
	}
	if issue := validateResourceReference(command.Spec.EndpointReference, "relay endpointReference"); issue != nil {
		return issue
	}
	if command.Spec.CredentialReference != nil && (!ValidIdentifier(command.Spec.CredentialReference.Kind) || !ValidIdentifier(command.Spec.CredentialReference.ID)) {
		return &Issue{Code: "invalid-outbound-relay-credential-reference", Message: "credentialReference must contain valid kind and id"}
	}
	return nil
}

func ExternalProviderReferenceEqual(left IntegrationProviderReference, right IntegrationProviderReference) bool {
	return left.Kind == right.Kind && left.ID == right.ID && left.CapabilityRevision == right.CapabilityRevision
}

func NewExternalUpstreamIntegration(command ExternalUpstreamApplyCommand, revision int, createdAt string, observedAt time.Time, observation ExternalUpstreamObservation) (ExternalUpstreamIntegration, *CapabilityDocument, error) {
	if revision < 1 || createdAt == "" {
		return ExternalUpstreamIntegration{}, nil, fmt.Errorf("invalid external upstream resource revision or creation timestamp")
	}
	status, capability, err := externalUpstreamStatus(command.IntegrationID, command.Spec, observedAt, observation)
	if err != nil {
		return ExternalUpstreamIntegration{}, nil, err
	}
	at := Timestamp(observedAt)
	return ExternalUpstreamIntegration{
		SchemaVersion:    SchemaVersion,
		ID:               command.IntegrationID,
		ResourceRevision: revision,
		Spec:             command.Spec,
		Status:           status,
		CreatedAt:        createdAt,
		UpdatedAt:        at,
	}, capability, nil
}

func NewOutboundRelayTarget(command OutboundRelayApplyCommand, revision int, createdAt string, observedAt time.Time, observation OutboundRelayObservation) (OutboundRelayTarget, error) {
	if revision < 1 || createdAt == "" {
		return OutboundRelayTarget{}, fmt.Errorf("invalid outbound relay target resource revision or creation timestamp")
	}
	if issue := validateRelayObservation(observation); issue != nil {
		return OutboundRelayTarget{}, fmt.Errorf("invalid outbound relay observation: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	return OutboundRelayTarget{
		SchemaVersion:    SchemaVersion,
		ID:               command.TargetID,
		ResourceRevision: revision,
		Spec:             command.Spec,
		Status: OutboundRelayTargetStatus{
			State:                    observation.State,
			AcknowledgementReference: observation.AcknowledgementReference,
			ObservedAt:               at,
			Issue:                    observation.Issue,
		},
		CreatedAt: createdAt,
		UpdatedAt: at,
	}, nil
}

func ExternalTopologyStatus(integration ExternalUpstreamIntegration, operationID string) TopologyStatus {
	// RuntimeTopology selects an integration; it does not run a second network
	// probe or reinterpret the integration owner's `reachable` observation as
	// a topology-owned `connected` fact. The integration resource remains the
	// sole connection owner. Known non-available states are copied as their
	// compatible explicit failure observations; an available integration leaves
	// topology connection explicitly not checked.
	connection := integration.Status.Connection
	if connection.State == "reachable" {
		connection = ConnectionObservation{State: "not-checked", ObservedAt: integration.Status.ObservedAt}
	}
	return TopologyStatus{
		ReadState:                   integration.Status.State,
		Connection:                  connection,
		CapabilityDocumentReference: integration.Status.CapabilityDocumentReference,
		CapabilityRevision:          integration.Status.CapabilityRevision,
		LastOperationReference: &ResourceReference{
			ResourceType: "operation",
			ResourceID:   operationID,
		},
		ObservedAt: integration.Status.ObservedAt,
		Issue:      integration.Status.Issue,
	}
}

func externalUpstreamStatus(integrationID string, spec ExternalUpstreamSpec, observedAt time.Time, observation ExternalUpstreamObservation) (ExternalUpstreamStatus, *CapabilityDocument, error) {
	if issue := validateExternalUpstreamObservation(observation); issue != nil {
		return ExternalUpstreamStatus{}, nil, fmt.Errorf("invalid external upstream observation: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	status := ExternalUpstreamStatus{
		State:      observation.State,
		Connection: observation.Connection,
		ObservedAt: at,
		Issue:      observation.Issue,
	}
	if observation.Capability == nil {
		return status, nil, nil
	}
	capability := *observation.Capability
	if capability.SchemaVersion != SchemaVersion || capability.Provider.Kind != spec.Provider.Kind || capability.Provider.ID != spec.Provider.ID || capability.CapabilityRevision != spec.Provider.CapabilityRevision || !ValidIdentifier(capability.ID) {
		return ExternalUpstreamStatus{}, nil, fmt.Errorf("external provider capability does not match explicit integration provider reference")
	}
	status.CapabilityDocumentReference = &ResourceReference{ResourceType: "capability-document", ResourceID: capability.ID}
	revision := capability.CapabilityRevision
	status.CapabilityRevision = &revision
	return status, &capability, nil
}

func validateExternalUpstreamObservation(observation ExternalUpstreamObservation) *Issue {
	switch observation.State {
	case "available":
		if observation.Connection.State != "reachable" || observation.Connection.Issue != nil || observation.Capability == nil || observation.Issue != nil {
			return &Issue{Code: "external-upstream-observation-invalid", Message: "available external upstream observation requires reachable connection and capability without issue"}
		}
	case "unavailable":
		if observation.Connection.State != "unavailable" || observation.Connection.Issue == nil || observation.Issue == nil || observation.Capability != nil {
			return &Issue{Code: "external-upstream-observation-invalid", Message: "unavailable external upstream observation requires explicit connection and status issue"}
		}
	case "failed":
		if observation.Connection.State != "failed" || observation.Connection.Issue == nil || observation.Issue == nil || observation.Capability != nil {
			return &Issue{Code: "external-upstream-observation-invalid", Message: "failed external upstream observation requires explicit connection and status issue"}
		}
	case "unsupported":
		if observation.Connection.State != "not-checked" || observation.Connection.Issue != nil || observation.Issue == nil || observation.Capability != nil {
			return &Issue{Code: "external-upstream-observation-invalid", Message: "unsupported external upstream observation requires a typed status issue and no capability"}
		}
	default:
		return &Issue{Code: "external-upstream-observation-invalid", Message: "external upstream observation state is unsupported"}
	}
	return nil
}

func validateRelayObservation(observation OutboundRelayObservation) *Issue {
	switch observation.State {
	case "available":
		if observation.AcknowledgementReference == nil || !ValidIdentifier(observation.AcknowledgementReference.Kind) || !ValidIdentifier(observation.AcknowledgementReference.ID) || observation.Issue != nil {
			return &Issue{Code: "outbound-relay-observation-invalid", Message: "available relay observation requires an acknowledgement reference without issue"}
		}
	case "unavailable", "failed", "unsupported":
		if observation.Issue == nil {
			return &Issue{Code: "outbound-relay-observation-invalid", Message: "non-available relay observation requires an issue"}
		}
	default:
		return &Issue{Code: "outbound-relay-observation-invalid", Message: "outbound relay observation state is unsupported"}
	}
	return nil
}

func validateIntegrationProviderReference(reference IntegrationProviderReference) *Issue {
	if !ValidIdentifier(reference.Kind) || !ValidIdentifier(reference.ID) || reference.CapabilityRevision < 1 {
		return &Issue{Code: "invalid-integration-provider-reference", Message: "provider kind, id, and capabilityRevision must be explicit and valid"}
	}
	return nil
}

func validateResourceReference(reference ResourceReference, subject string) *Issue {
	if !ValidIdentifier(reference.ResourceType) || !ValidIdentifier(reference.ResourceID) {
		return &Issue{Code: "invalid-resource-reference", Message: subject + " must contain valid resourceType and resourceId"}
	}
	return nil
}
