package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	TimeAuthorityResourceType       = "time-authority"
	TelemetryPipelineResourceType   = "telemetry-pipeline"
	CatalogObservationResourceType  = "catalog-observation"
	TimeAuthorityApplyOperationKind = "runtime.time-authority.apply"
	CatalogIngestOperationKind      = "runtime.catalog-observation.ingest"
	TelemetryPipelineOperationKind  = "runtime.telemetry-pipeline.apply"
	TelemetryEmitOperationKind      = "runtime.telemetry.emit"
)

var telemetryAttributeKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9_.-]*$`)

// NodeReference is local to the service that owns the resource. A Guest
// Runtime never uses this document to state a Host or Recorder clock fact.
type NodeReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type TimeSource struct {
	Profile  string `json:"profile"`
	SourceID string `json:"sourceId"`
}

type ClockQuality struct {
	SchemaVersion string        `json:"schemaVersion"`
	Node          NodeReference `json:"node"`
	State         string        `json:"state"`
	Source        *TimeSource   `json:"source,omitempty"`
	Stratum       *int          `json:"stratum,omitempty"`
	OffsetMs      *float64      `json:"offsetMs,omitempty"`
	UncertaintyMs *float64      `json:"uncertaintyMs,omitempty"`
	LastSyncAt    *string       `json:"lastSyncAt,omitempty"`
	ObservedAt    string        `json:"observedAt"`
	Issue         *Issue        `json:"issue,omitempty"`
}

type TimeAuthoritySpec struct {
	Profile string     `json:"profile"`
	Source  TimeSource `json:"source"`
}

type TimeAuthority struct {
	SchemaVersion    string            `json:"schemaVersion"`
	ID               string            `json:"id"`
	ResourceRevision int               `json:"resourceRevision"`
	Node             NodeReference     `json:"node"`
	Spec             TimeAuthoritySpec `json:"spec"`
	ClockQuality     ClockQuality      `json:"clockQuality"`
	CreatedAt        string            `json:"createdAt"`
	UpdatedAt        string            `json:"updatedAt"`
}

type TimeAuthorityApplyCommand struct {
	SchemaVersion            string            `json:"schemaVersion"`
	RequestID                string            `json:"requestId"`
	AuthorityID              string            `json:"authorityId"`
	ExpectedResourceRevision int               `json:"expectedResourceRevision"`
	Node                     NodeReference     `json:"node"`
	Spec                     TimeAuthoritySpec `json:"spec"`
}

// RecorderObservationEnvelope is device-owned evidence. Catalog may store it,
// but it must preserve occurredAt and must not turn packet arrival into a
// device observation.
type RecorderTimeObservation struct {
	State         string   `json:"state"`
	SourceID      *string  `json:"sourceId,omitempty"`
	OffsetMs      *float64 `json:"offsetMs,omitempty"`
	UncertaintyMs *float64 `json:"uncertaintyMs,omitempty"`
	LastSyncAt    *string  `json:"lastSyncAt,omitempty"`
	Issue         *Issue   `json:"issue,omitempty"`
}

type RecorderRuntimeObservation struct {
	State   string  `json:"state"`
	Version *string `json:"version,omitempty"`
	Issue   *Issue  `json:"issue,omitempty"`
}

type RecorderObservationEnvelope struct {
	SchemaVersion   string                     `json:"schemaVersion"`
	ProtocolVersion string                     `json:"protocolVersion"`
	RecorderID      string                     `json:"recorderId"`
	BootID          string                     `json:"bootId"`
	Sequence        int                        `json:"sequence"`
	OccurredAt      string                     `json:"occurredAt"`
	Time            RecorderTimeObservation    `json:"time"`
	Runtime         RecorderRuntimeObservation `json:"runtime"`
}

type CatalogSourceIdentity struct {
	Kind       string `json:"kind"`
	RecorderID string `json:"recorderId"`
	BootID     string `json:"bootId"`
	Sequence   int    `json:"sequence"`
	OccurredAt string `json:"occurredAt"`
}

type CatalogObservation struct {
	SchemaVersion  string                      `json:"schemaVersion"`
	ID             string                      `json:"id"`
	SourceIdentity CatalogSourceIdentity       `json:"sourceIdentity"`
	Envelope       RecorderObservationEnvelope `json:"envelope"`
	ReceivedAt     string                      `json:"receivedAt"`
	PersistedAt    string                      `json:"persistedAt"`
}

type CatalogObservationIngestCommand struct {
	SchemaVersion string                      `json:"schemaVersion"`
	RequestID     string                      `json:"requestId"`
	ObservationID string                      `json:"observationId"`
	Envelope      RecorderObservationEnvelope `json:"envelope"`
}

type CatalogObservationAdmission struct {
	SchemaVersion                   string             `json:"schemaVersion"`
	RequestID                       string             `json:"requestId"`
	Outcome                         string             `json:"outcome"`
	ObservationReference            *ResourceReference `json:"observationReference,omitempty"`
	DuplicateOfObservationReference *ResourceReference `json:"duplicateOfObservationReference,omitempty"`
	Issue                           *Issue             `json:"issue,omitempty"`
	ReceivedAt                      string             `json:"receivedAt"`
	PersistedAt                     string             `json:"persistedAt"`
}

type RecorderObservabilitySummary struct {
	SchemaVersion              string             `json:"schemaVersion"`
	RecorderID                 string             `json:"recorderId"`
	ResourceRevision           int                `json:"resourceRevision"`
	SupportState               string             `json:"supportState"`
	ExpectationState           string             `json:"expectationState"`
	ReportState                string             `json:"reportState"`
	ReadState                  string             `json:"readState"`
	LatestObservationReference *ResourceReference `json:"latestObservationReference,omitempty"`
	LatestBootID               *string            `json:"latestBootId,omitempty"`
	LatestSequence             *int               `json:"latestSequence,omitempty"`
	LatestOccurredAt           *string            `json:"latestOccurredAt,omitempty"`
	LatestReceivedAt           *string            `json:"latestReceivedAt,omitempty"`
	LatestPersistedAt          *string            `json:"latestPersistedAt,omitempty"`
	Issue                      *Issue             `json:"issue,omitempty"`
	UpdatedAt                  string             `json:"updatedAt"`
}

type TelemetryRedactionPolicy struct {
	AllowedAttributeKeys    []string `json:"allowedAttributeKeys"`
	MaxAttributes           int      `json:"maxAttributes"`
	MaxValueLength          int      `json:"maxValueLength"`
	MaxDistinctValuesPerKey int      `json:"maxDistinctValuesPerKey"`
}

type TelemetryPipelineSpec struct {
	Protocol           string                   `json:"protocol"`
	CollectorReference ResourceReference        `json:"collectorReference"`
	SignalKinds        []string                 `json:"signalKinds"`
	Redaction          TelemetryRedactionPolicy `json:"redaction"`
}

type TelemetryPipelineStatus struct {
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type TelemetryPipeline struct {
	SchemaVersion    string                  `json:"schemaVersion"`
	ID               string                  `json:"id"`
	ResourceRevision int                     `json:"resourceRevision"`
	Node             NodeReference           `json:"node"`
	Spec             TelemetryPipelineSpec   `json:"spec"`
	Status           TelemetryPipelineStatus `json:"status"`
	CreatedAt        string                  `json:"createdAt"`
	UpdatedAt        string                  `json:"updatedAt"`
}

type TelemetryPipelineApplyCommand struct {
	SchemaVersion            string                `json:"schemaVersion"`
	RequestID                string                `json:"requestId"`
	PipelineID               string                `json:"pipelineId"`
	ExpectedResourceRevision int                   `json:"expectedResourceRevision"`
	Node                     NodeReference         `json:"node"`
	Spec                     TelemetryPipelineSpec `json:"spec"`
}

type TelemetryCorrelation struct {
	SchemaVersion string          `json:"schemaVersion"`
	Service       ServiceIdentity `json:"service"`
	SignalKinds   []string        `json:"signalKinds"`
	SignalName    string          `json:"signalName"`
	EmittedAt     string          `json:"emittedAt"`
	RequestID     *string         `json:"requestId,omitempty"`
	OperationID   *string         `json:"operationId,omitempty"`
	TraceID       *string         `json:"traceId,omitempty"`
	SpanID        *string         `json:"spanId,omitempty"`
	Component     *string         `json:"component,omitempty"`
	OutcomeCode   *string         `json:"outcomeCode,omitempty"`
}

type TelemetrySignalEmitCommand struct {
	SchemaVersion            string               `json:"schemaVersion"`
	RequestID                string               `json:"requestId"`
	PipelineID               string               `json:"pipelineId"`
	ExpectedResourceRevision int                  `json:"expectedResourceRevision"`
	Signal                   TelemetryCorrelation `json:"signal"`
	Attributes               map[string]string    `json:"attributes"`
}

type TelemetryEmissionReceipt struct {
	SchemaVersion          string               `json:"schemaVersion"`
	ID                     string               `json:"id"`
	RequestID              string               `json:"requestId"`
	PipelineReference      ResourceReference    `json:"pipelineReference"`
	Signal                 TelemetryCorrelation `json:"signal"`
	Outcome                string               `json:"outcome"`
	EmittedAt              string               `json:"emittedAt"`
	ExportedAttributeCount int                  `json:"exportedAttributeCount"`
	RedactedAttributeKeys  []string             `json:"redactedAttributeKeys"`
	DroppedAttributeKeys   []string             `json:"droppedAttributeKeys"`
	Issue                  *Issue               `json:"issue,omitempty"`
}

type TelemetryPipelineObservation struct {
	State string `json:"state"`
	Issue *Issue `json:"issue,omitempty"`
}

type TelemetryExportResult struct {
	Outcome string `json:"outcome"`
	Issue   *Issue `json:"issue,omitempty"`
}

type SanitizedTelemetrySignal struct {
	Attributes       map[string]string
	AttributeDigests map[string]string
	RedactedKeys     []string
	DroppedKeys      []string
}

func ValidateTimeAuthorityApplyCommand(command TimeAuthorityApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.AuthorityID) {
		return &Issue{Code: "invalid-time-authority-command-id", Message: "requestId and authorityId must be valid v1 identifiers"}
	}
	if command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be zero or greater"}
	}
	if issue := validateNodeReference(command.Node); issue != nil {
		return issue
	}
	return validateTimeAuthoritySpec(command.Spec)
}

func NewTimeAuthority(command TimeAuthorityApplyCommand, revision int, createdAt string, observedAt time.Time, quality ClockQuality) (TimeAuthority, error) {
	if revision < 1 || createdAt == "" {
		return TimeAuthority{}, fmt.Errorf("invalid time authority revision or creation timestamp")
	}
	if issue := ValidateClockQuality(quality, command.Node, command.Spec.Source); issue != nil {
		return TimeAuthority{}, fmt.Errorf("invalid clock quality: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	return TimeAuthority{SchemaVersion: SchemaVersion, ID: command.AuthorityID, ResourceRevision: revision, Node: command.Node, Spec: command.Spec, ClockQuality: quality, CreatedAt: createdAt, UpdatedAt: at}, nil
}

func ValidateClockQuality(quality ClockQuality, node NodeReference, source TimeSource) *Issue {
	if quality.SchemaVersion != SchemaVersion || !nodeEqual(quality.Node, node) || quality.ObservedAt == "" {
		return &Issue{Code: "clock-quality-owner-mismatch", Message: "ClockQuality must identify the configured node and schema version"}
	}
	if _, err := time.Parse(time.RFC3339Nano, quality.ObservedAt); err != nil {
		return &Issue{Code: "clock-quality-observed-at-invalid", Message: "ClockQuality observedAt must be RFC3339"}
	}
	switch quality.State {
	case "configured", "synchronizing":
		if quality.Source == nil || !timeSourceEqual(*quality.Source, source) || quality.Issue != nil {
			return &Issue{Code: "clock-quality-evidence-invalid", Message: "configured or synchronizing ClockQuality requires the configured source without issue"}
		}
	case "synchronized":
		if quality.Source == nil || !timeSourceEqual(*quality.Source, source) || quality.Stratum == nil || *quality.Stratum < 0 || *quality.Stratum > 16 || quality.OffsetMs == nil || quality.UncertaintyMs == nil || *quality.UncertaintyMs < 0 || quality.LastSyncAt == nil || quality.Issue != nil {
			return &Issue{Code: "clock-quality-evidence-invalid", Message: "synchronized ClockQuality requires complete source, stratum, offset, uncertainty, and last-sync evidence"}
		}
		if _, err := time.Parse(time.RFC3339Nano, *quality.LastSyncAt); err != nil {
			return &Issue{Code: "clock-quality-last-sync-invalid", Message: "ClockQuality lastSyncAt must be RFC3339"}
		}
	case "unsynchronized", "stale", "unsupported", "failed":
		if quality.Issue == nil {
			return &Issue{Code: "clock-quality-issue-required", Message: "non-synchronized ClockQuality requires a typed issue"}
		}
	default:
		return &Issue{Code: "clock-quality-state-invalid", Message: "ClockQuality state is unsupported"}
	}
	return nil
}

func ValidateCatalogObservationIngestCommand(command CatalogObservationIngestCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.ObservationID) {
		return &Issue{Code: "invalid-catalog-observation-command-id", Message: "requestId and observationId must be valid v1 identifiers"}
	}
	return ValidateRecorderObservationEnvelope(command.Envelope)
}

func ValidateRecorderObservationEnvelope(envelope RecorderObservationEnvelope) *Issue {
	if envelope.SchemaVersion != SchemaVersion || !ValidProtocolVersion(envelope.ProtocolVersion) || !ValidIdentifier(envelope.RecorderID) || !ValidIdentifier(envelope.BootID) || envelope.Sequence < 0 || envelope.OccurredAt == "" {
		return &Issue{Code: "invalid-recorder-observation-envelope", Message: "Recorder observation identity and protocol fields must be explicit and valid"}
	}
	if _, err := time.Parse(time.RFC3339Nano, envelope.OccurredAt); err != nil {
		return &Issue{Code: "invalid-recorder-observation-occurred-at", Message: "Recorder observation occurredAt must be RFC3339"}
	}
	if issue := validateRecorderTimeObservation(envelope.Time); issue != nil {
		return issue
	}
	return validateRecorderRuntimeObservation(envelope.Runtime)
}

func NewCatalogObservation(command CatalogObservationIngestCommand, receivedAt time.Time, persistedAt time.Time) (CatalogObservation, error) {
	if issue := ValidateCatalogObservationIngestCommand(command); issue != nil {
		return CatalogObservation{}, fmt.Errorf("invalid CatalogObservation command: %s", issue.Code)
	}
	return CatalogObservation{
		SchemaVersion:  SchemaVersion,
		ID:             command.ObservationID,
		SourceIdentity: CatalogSourceIdentity{Kind: "recorder-self-observation", RecorderID: command.Envelope.RecorderID, BootID: command.Envelope.BootID, Sequence: command.Envelope.Sequence, OccurredAt: command.Envelope.OccurredAt},
		Envelope:       command.Envelope,
		ReceivedAt:     Timestamp(receivedAt),
		PersistedAt:    Timestamp(persistedAt),
	}, nil
}

func NewAcceptedCatalogObservationAdmission(command CatalogObservationIngestCommand, receivedAt time.Time, persistedAt time.Time) (CatalogObservationAdmission, error) {
	if issue := ValidateCatalogObservationIngestCommand(command); issue != nil {
		return CatalogObservationAdmission{}, fmt.Errorf("invalid CatalogObservation command: %s", issue.Code)
	}
	reference := ResourceReference{ResourceType: CatalogObservationResourceType, ResourceID: command.ObservationID}
	return CatalogObservationAdmission{
		SchemaVersion:        SchemaVersion,
		RequestID:            command.RequestID,
		Outcome:              "accepted",
		ObservationReference: &reference,
		ReceivedAt:           Timestamp(receivedAt),
		PersistedAt:          Timestamp(persistedAt),
	}, nil
}

func NewDuplicateCatalogObservationAdmission(requestID string, originalObservationID string, receivedAt time.Time, persistedAt time.Time) (CatalogObservationAdmission, error) {
	if !ValidIdentifier(requestID) || !ValidIdentifier(originalObservationID) {
		return CatalogObservationAdmission{}, fmt.Errorf("duplicate Catalog admission requires valid request and observation identifiers")
	}
	reference := ResourceReference{ResourceType: CatalogObservationResourceType, ResourceID: originalObservationID}
	return CatalogObservationAdmission{
		SchemaVersion:                   SchemaVersion,
		RequestID:                       requestID,
		Outcome:                         "duplicate",
		DuplicateOfObservationReference: &reference,
		ReceivedAt:                      Timestamp(receivedAt),
		PersistedAt:                     Timestamp(persistedAt),
	}, nil
}

func NewQuarantinedCatalogObservationAdmission(requestID string, issue Issue, receivedAt time.Time, persistedAt time.Time) (CatalogObservationAdmission, error) {
	if !ValidIdentifier(requestID) || issue.Code == "" || issue.Message == "" {
		return CatalogObservationAdmission{}, fmt.Errorf("quarantined Catalog admission requires valid request identity and typed issue")
	}
	return CatalogObservationAdmission{
		SchemaVersion: SchemaVersion,
		RequestID:     requestID,
		Outcome:       "quarantined",
		Issue:         &issue,
		ReceivedAt:    Timestamp(receivedAt),
		PersistedAt:   Timestamp(persistedAt),
	}, nil
}
func ProjectRecorderObservabilitySummary(
	observation CatalogObservation,
	previous *RecorderObservabilitySummary,
) (RecorderObservabilitySummary, error) {
	if !ValidIdentifier(observation.Envelope.RecorderID) || !ValidIdentifier(observation.ID) {
		return RecorderObservabilitySummary{}, fmt.Errorf("Recorder observability projection requires a valid observation identity")
	}
	resourceRevision := 1
	expectationState := "unset"
	if previous != nil {
		if previous.RecorderID != observation.Envelope.RecorderID || previous.ResourceRevision < 1 {
			return RecorderObservabilitySummary{}, fmt.Errorf("Recorder observability previous projection identity is invalid")
		}
		if previous.ExpectationState != "expected" && previous.ExpectationState != "not-expected" && previous.ExpectationState != "unset" {
			return RecorderObservabilitySummary{}, fmt.Errorf("Recorder observability previous expectation state is invalid")
		}
		resourceRevision = previous.ResourceRevision + 1
		expectationState = previous.ExpectationState
	}
	observationReference := ResourceReference{
		ResourceType: CatalogObservationResourceType,
		ResourceID:   observation.ID,
	}
	bootID := observation.Envelope.BootID
	sequence := observation.Envelope.Sequence
	occurredAt := observation.Envelope.OccurredAt
	receivedAt := observation.ReceivedAt
	persistedAt := observation.PersistedAt
	return RecorderObservabilitySummary{
		SchemaVersion:              SchemaVersion,
		RecorderID:                 observation.Envelope.RecorderID,
		ResourceRevision:           resourceRevision,
		SupportState:               "supported",
		ExpectationState:           expectationState,
		ReportState:                "current",
		ReadState:                  "available",
		LatestObservationReference: &observationReference,
		LatestBootID:               &bootID,
		LatestSequence:             &sequence,
		LatestOccurredAt:           &occurredAt,
		LatestReceivedAt:           &receivedAt,
		LatestPersistedAt:          &persistedAt,
		UpdatedAt:                  persistedAt,
	}, nil
}

func CatalogSourceKey(envelope RecorderObservationEnvelope) string {
	// Length prefixes preserve tuple boundaries without using NUL, which
	// PostgreSQL text values reject.
	return fmt.Sprintf(
		"%d:%s%d:%s%d",
		len(envelope.RecorderID),
		envelope.RecorderID,
		len(envelope.BootID),
		envelope.BootID,
		envelope.Sequence,
	)
}

func CatalogEnvelopeDigest(envelope RecorderObservationEnvelope) (string, error) {
	encoded, err := json.Marshal(envelope)
	if err != nil {
		return "", fmt.Errorf("encode RecorderObservationEnvelope: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func ValidateTelemetryPipelineApplyCommand(command TelemetryPipelineApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.PipelineID) {
		return &Issue{Code: "invalid-telemetry-pipeline-command-id", Message: "requestId and pipelineId must be valid v1 identifiers"}
	}
	if command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be zero or greater"}
	}
	if issue := validateNodeReference(command.Node); issue != nil {
		return issue
	}
	return ValidateTelemetryPipelineSpec(command.Spec)
}

func ValidateTelemetryPipelineSpec(spec TelemetryPipelineSpec) *Issue {
	if spec.Protocol != "otlp-http" || !ValidIdentifier(spec.CollectorReference.ResourceType) || !ValidIdentifier(spec.CollectorReference.ResourceID) {
		return &Issue{Code: "invalid-telemetry-pipeline-spec", Message: "TelemetryPipeline requires explicit OTLP collector reference"}
	}
	if !hasExactlySignalKinds(spec.SignalKinds) {
		return &Issue{Code: "invalid-telemetry-signal-kinds", Message: "TelemetryPipeline must support logs, metrics, and traces exactly once"}
	}
	return validateTelemetryRedactionPolicy(spec.Redaction)
}

func NewTelemetryPipeline(command TelemetryPipelineApplyCommand, revision int, createdAt string, observedAt time.Time, observation TelemetryPipelineObservation) (TelemetryPipeline, error) {
	if revision < 1 || createdAt == "" {
		return TelemetryPipeline{}, fmt.Errorf("invalid telemetry pipeline revision or creation timestamp")
	}
	if issue := validateTelemetryPipelineObservation(observation); issue != nil {
		return TelemetryPipeline{}, fmt.Errorf("invalid telemetry pipeline observation: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	return TelemetryPipeline{SchemaVersion: SchemaVersion, ID: command.PipelineID, ResourceRevision: revision, Node: command.Node, Spec: command.Spec, Status: TelemetryPipelineStatus{State: observation.State, ObservedAt: at, Issue: observation.Issue}, CreatedAt: createdAt, UpdatedAt: at}, nil
}

func ValidateTelemetrySignalEmitCommand(command TelemetrySignalEmitCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.PipelineID) || command.ExpectedResourceRevision < 1 {
		return &Issue{Code: "invalid-telemetry-signal-command", Message: "Telemetry signal command identity and expected pipeline revision must be explicit"}
	}
	if len(command.Attributes) > 64 {
		return &Issue{Code: "telemetry-attributes-too-many", Message: "Telemetry signal has more than 64 untrusted attributes"}
	}
	for key, value := range command.Attributes {
		if !telemetryAttributeKeyPattern.MatchString(key) || len(value) > 4096 {
			return &Issue{Code: "invalid-telemetry-attribute", Message: "Telemetry attribute keys and values exceed input contract limits"}
		}
	}
	return ValidateTelemetryCorrelation(command.Signal)
}

func ValidateTelemetryCorrelation(correlation TelemetryCorrelation) *Issue {
	if correlation.SchemaVersion != SchemaVersion || !ValidIdentifier(correlation.Service.Name) || correlation.Service.Version == "" || !telemetryAttributeKeyPattern.MatchString(correlation.SignalName) || correlation.EmittedAt == "" || len(correlation.SignalKinds) == 0 {
		return &Issue{Code: "invalid-telemetry-correlation", Message: "Telemetry correlation identity and signal fields must be explicit"}
	}
	if _, err := time.Parse(time.RFC3339Nano, correlation.EmittedAt); err != nil {
		return &Issue{Code: "invalid-telemetry-emitted-at", Message: "Telemetry correlation emittedAt must be RFC3339"}
	}
	seen := map[string]bool{}
	for _, kind := range correlation.SignalKinds {
		if (kind != "logs" && kind != "metrics" && kind != "traces") || seen[kind] {
			return &Issue{Code: "invalid-telemetry-signal-kind", Message: "Telemetry correlation signalKinds must be unique OpenTelemetry signal kinds"}
		}
		seen[kind] = true
	}
	for _, value := range []*string{correlation.RequestID, correlation.OperationID, correlation.Component, correlation.OutcomeCode} {
		if value != nil && !ValidIdentifier(*value) {
			return &Issue{Code: "invalid-telemetry-correlation-reference", Message: "Telemetry correlation references must be valid identifiers"}
		}
	}
	if correlation.TraceID != nil && !regexp.MustCompile(`^[a-f0-9]{32}$`).MatchString(*correlation.TraceID) {
		return &Issue{Code: "invalid-telemetry-trace-id", Message: "Telemetry traceId must be a lowercase 32-character hex id"}
	}
	if correlation.SpanID != nil && !regexp.MustCompile(`^[a-f0-9]{16}$`).MatchString(*correlation.SpanID) {
		return &Issue{Code: "invalid-telemetry-span-id", Message: "Telemetry spanId must be a lowercase 16-character hex id"}
	}
	return nil
}

func SanitizeTelemetryAttributes(policy TelemetryRedactionPolicy, attributes map[string]string, knownDigests map[string]map[string]bool) SanitizedTelemetrySignal {
	allowed := map[string]bool{}
	for _, key := range policy.AllowedAttributeKeys {
		allowed[key] = true
	}
	keys := make([]string, 0, len(attributes))
	for key := range attributes {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := SanitizedTelemetrySignal{Attributes: map[string]string{}, AttributeDigests: map[string]string{}}
	added := map[string]map[string]bool{}
	for _, key := range keys {
		value := attributes[key]
		if !allowed[key] || sensitiveTelemetryAttributeKey(key) || len(value) > policy.MaxValueLength {
			result.RedactedKeys = append(result.RedactedKeys, key)
			continue
		}
		if len(result.Attributes) >= policy.MaxAttributes {
			result.DroppedKeys = append(result.DroppedKeys, key)
			continue
		}
		digest := telemetryValueDigest(value)
		if knownDigests[key] == nil || !knownDigests[key][digest] {
			if len(knownDigests[key])+len(added[key]) >= policy.MaxDistinctValuesPerKey {
				result.DroppedKeys = append(result.DroppedKeys, key)
				continue
			}
			if added[key] == nil {
				added[key] = map[string]bool{}
			}
			added[key][digest] = true
		}
		result.Attributes[key] = value
		result.AttributeDigests[key] = digest
	}
	return result
}

func NewTelemetryEmissionReceipt(id string, command TelemetrySignalEmitCommand, pipeline TelemetryPipeline, at time.Time, sanitized SanitizedTelemetrySignal, result TelemetryExportResult) (TelemetryEmissionReceipt, error) {
	if !ValidIdentifier(id) || pipeline.ID != command.PipelineID || pipeline.ResourceRevision != command.ExpectedResourceRevision {
		return TelemetryEmissionReceipt{}, fmt.Errorf("invalid telemetry receipt identity or pipeline revision")
	}
	if issue := validateTelemetryExportResult(result); issue != nil {
		return TelemetryEmissionReceipt{}, fmt.Errorf("invalid telemetry export result: %s", issue.Code)
	}
	return TelemetryEmissionReceipt{
		SchemaVersion:          SchemaVersion,
		ID:                     id,
		RequestID:              command.RequestID,
		PipelineReference:      ResourceReference{ResourceType: TelemetryPipelineResourceType, ResourceID: pipeline.ID},
		Signal:                 command.Signal,
		Outcome:                result.Outcome,
		EmittedAt:              Timestamp(at),
		ExportedAttributeCount: len(sanitized.Attributes),
		RedactedAttributeKeys:  explicitAttributeKeys(sanitized.RedactedKeys),
		DroppedAttributeKeys:   explicitAttributeKeys(sanitized.DroppedKeys),
		Issue:                  result.Issue,
	}, nil
}

// The public receipt contract distinguishes an explicit empty collection from
// an omitted/null value. Preserve that distinction at the serialization edge
// without deriving any product state from the absence of a sanitized key.
func explicitAttributeKeys(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func ValidProtocolVersion(value string) bool {
	return regexp.MustCompile(`^v[1-9][0-9]*$`).MatchString(value)
}

func validateNodeReference(node NodeReference) *Issue {
	if (node.Kind != "host" && node.Kind != "guest" && node.Kind != "recorder") || !ValidIdentifier(node.ID) {
		return &Issue{Code: "invalid-node-reference", Message: "node must name host, guest, or recorder with a valid identifier"}
	}
	return nil
}

func validateTimeAuthoritySpec(spec TimeAuthoritySpec) *Issue {
	if (spec.Profile != "enterprise-ntp" && spec.Profile != "helper-ntp") || spec.Source.Profile != spec.Profile || !ValidIdentifier(spec.Source.SourceID) {
		return &Issue{Code: "invalid-time-authority-spec", Message: "TimeAuthority must declare an explicit profile and matching NTP source"}
	}
	return nil
}

func validateRecorderTimeObservation(observation RecorderTimeObservation) *Issue {
	switch observation.State {
	case "not-reported", "synchronizing":
		if observation.Issue != nil {
			return &Issue{Code: "invalid-recorder-time-observation", Message: "reported/synchronizing recorder time observation must not carry an issue"}
		}
	case "synchronized":
		if observation.SourceID == nil || !ValidIdentifier(*observation.SourceID) || observation.OffsetMs == nil || observation.UncertaintyMs == nil || *observation.UncertaintyMs < 0 || observation.LastSyncAt == nil || observation.Issue != nil {
			return &Issue{Code: "invalid-recorder-time-observation", Message: "synchronized recorder time requires complete source, offset, uncertainty, and last-sync evidence"}
		}
	case "unsynchronized", "stale", "unsupported", "failed":
		if observation.Issue == nil {
			return &Issue{Code: "invalid-recorder-time-observation", Message: "non-synchronized recorder time requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-recorder-time-observation", Message: "recorder time state is unsupported"}
	}
	return nil
}

func validateRecorderRuntimeObservation(observation RecorderRuntimeObservation) *Issue {
	switch observation.State {
	case "not-reported":
		if observation.Issue != nil {
			return &Issue{Code: "invalid-recorder-runtime-observation", Message: "not-reported recorder runtime must not carry an issue"}
		}
	case "ready":
		if observation.Version == nil || *observation.Version == "" || observation.Issue != nil {
			return &Issue{Code: "invalid-recorder-runtime-observation", Message: "ready recorder runtime requires a version without issue"}
		}
	case "not-ready", "failed", "unsupported":
		if observation.Issue == nil {
			return &Issue{Code: "invalid-recorder-runtime-observation", Message: "non-ready recorder runtime requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-recorder-runtime-observation", Message: "recorder runtime state is unsupported"}
	}
	return nil
}

func validateTelemetryRedactionPolicy(policy TelemetryRedactionPolicy) *Issue {
	if len(policy.AllowedAttributeKeys) == 0 || len(policy.AllowedAttributeKeys) > 32 || policy.MaxAttributes < 1 || policy.MaxAttributes > 32 || policy.MaxValueLength < 1 || policy.MaxValueLength > 256 || policy.MaxDistinctValuesPerKey < 1 || policy.MaxDistinctValuesPerKey > 100 {
		return &Issue{Code: "invalid-telemetry-redaction-policy", Message: "Telemetry redaction limits are outside the explicit bounded contract"}
	}
	seen := map[string]bool{}
	for _, key := range policy.AllowedAttributeKeys {
		if !telemetryAttributeKeyPattern.MatchString(key) || seen[key] || sensitiveTelemetryAttributeKey(key) {
			return &Issue{Code: "invalid-telemetry-redaction-policy", Message: "Telemetry allowlist must contain unique non-sensitive bounded keys"}
		}
		seen[key] = true
	}
	return nil
}

func validateTelemetryPipelineObservation(observation TelemetryPipelineObservation) *Issue {
	switch observation.State {
	case "ready":
		if observation.Issue != nil {
			return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "ready telemetry pipeline must not carry an issue"}
		}
	case "unavailable", "failed", "unsupported":
		if observation.Issue == nil {
			return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "non-ready telemetry pipeline requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "telemetry pipeline state is unsupported"}
	}
	return nil
}

func validateTelemetryExportResult(result TelemetryExportResult) *Issue {
	switch result.Outcome {
	case "exported":
		if result.Issue != nil {
			return &Issue{Code: "invalid-telemetry-export-result", Message: "exported telemetry result must not carry an issue"}
		}
	case "dropped", "unavailable", "failed", "unknown":
		if result.Issue == nil {
			return &Issue{Code: "invalid-telemetry-export-result", Message: "non-exported telemetry result requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-telemetry-export-result", Message: "telemetry export outcome is unsupported"}
	}
	return nil
}

func hasExactlySignalKinds(kinds []string) bool {
	if len(kinds) != 3 {
		return false
	}
	seen := map[string]bool{}
	for _, kind := range kinds {
		if (kind != "logs" && kind != "metrics" && kind != "traces") || seen[kind] {
			return false
		}
		seen[kind] = true
	}
	return seen["logs"] && seen["metrics"] && seen["traces"]
}

func nodeEqual(left NodeReference, right NodeReference) bool {
	return left.Kind == right.Kind && left.ID == right.ID
}

func timeSourceEqual(left TimeSource, right TimeSource) bool {
	return left.Profile == right.Profile && left.SourceID == right.SourceID
}

func sensitiveTelemetryAttributeKey(key string) bool {
	for _, forbidden := range []string{"waveform", "packet", "patient", "credential", "authorization", "secret", "token", "password"} {
		if strings.Contains(key, forbidden) {
			return true
		}
	}
	return false
}

func telemetryValueDigest(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
