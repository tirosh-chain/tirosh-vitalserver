package hostagentdomain

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
	TimeAuthorityApplyOperationKind = "platform.time-authority.apply"
	TelemetryPipelineOperationKind  = "platform.telemetry-pipeline.apply"
	TelemetryEmitOperationKind      = "platform.telemetry.emit"
)

var telemetryAttributeKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9_.-]*$`)
var traceIDPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)
var spanIDPattern = regexp.MustCompile(`^[a-f0-9]{16}$`)
var protocolVersionPattern = regexp.MustCompile(`^v[1-9][0-9]*$`)

type NodeReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type ResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
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

type ServiceIdentity struct {
	Name       string `json:"name"`
	Version    string `json:"version"`
	InstanceID string `json:"instanceId,omitempty"`
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
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.AuthorityID) || command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-time-authority-command", Message: "TimeAuthority command identity, schema, and revision must be explicit"}
	}
	if issue := validateNode(command.Node); issue != nil {
		return issue
	}
	return validateTimeSpec(command.Spec)
}

func NewTimeAuthority(command TimeAuthorityApplyCommand, revision int, createdAt string, observedAt time.Time, quality ClockQuality) (TimeAuthority, error) {
	if revision < 1 || createdAt == "" {
		return TimeAuthority{}, fmt.Errorf("invalid TimeAuthority revision or creation timestamp")
	}
	if issue := ValidateClockQuality(quality, command.Node, command.Spec.Source); issue != nil {
		return TimeAuthority{}, fmt.Errorf("invalid ClockQuality: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	return TimeAuthority{SchemaVersion: SchemaVersion, ID: command.AuthorityID, ResourceRevision: revision, Node: command.Node, Spec: command.Spec, ClockQuality: quality, CreatedAt: createdAt, UpdatedAt: at}, nil
}

func ValidateClockQuality(quality ClockQuality, node NodeReference, source TimeSource) *Issue {
	if quality.SchemaVersion != SchemaVersion || quality.Node != node || quality.ObservedAt == "" {
		return &Issue{Code: "clock-quality-owner-mismatch", Message: "ClockQuality must identify the configured Host node and schema"}
	}
	if _, err := time.Parse(time.RFC3339Nano, quality.ObservedAt); err != nil {
		return &Issue{Code: "clock-quality-observed-at-invalid", Message: "ClockQuality observedAt must be RFC3339"}
	}
	switch quality.State {
	case "configured", "synchronizing":
		if quality.Source == nil || *quality.Source != source || quality.Issue != nil {
			return &Issue{Code: "clock-quality-evidence-invalid", Message: "configured/synchronizing quality requires its configured source without issue"}
		}
	case "synchronized":
		if quality.Source == nil || *quality.Source != source || quality.Stratum == nil || *quality.Stratum < 0 || *quality.Stratum > 16 || quality.OffsetMs == nil || quality.UncertaintyMs == nil || *quality.UncertaintyMs < 0 || quality.LastSyncAt == nil || quality.Issue != nil {
			return &Issue{Code: "clock-quality-evidence-invalid", Message: "synchronized quality requires complete NTP evidence"}
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

func ValidateTelemetryPipelineApplyCommand(command TelemetryPipelineApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.PipelineID) || command.ExpectedResourceRevision < 0 {
		return &Issue{Code: "invalid-telemetry-pipeline-command", Message: "Telemetry pipeline command identity, schema, and revision must be explicit"}
	}
	if issue := validateNode(command.Node); issue != nil {
		return issue
	}
	return ValidateTelemetryPipelineSpec(command.Spec)
}

func ValidateTelemetryPipelineSpec(spec TelemetryPipelineSpec) *Issue {
	if spec.Protocol != "otlp-http" || !ValidIdentifier(spec.CollectorReference.ResourceType) || !ValidIdentifier(spec.CollectorReference.ResourceID) || !exactSignalKinds(spec.SignalKinds) {
		return &Issue{Code: "invalid-telemetry-pipeline-spec", Message: "TelemetryPipeline requires OTLP collector reference and logs/metrics/traces"}
	}
	if len(spec.Redaction.AllowedAttributeKeys) == 0 || len(spec.Redaction.AllowedAttributeKeys) > 32 || spec.Redaction.MaxAttributes < 1 || spec.Redaction.MaxAttributes > 32 || spec.Redaction.MaxValueLength < 1 || spec.Redaction.MaxValueLength > 256 || spec.Redaction.MaxDistinctValuesPerKey < 1 || spec.Redaction.MaxDistinctValuesPerKey > 100 {
		return &Issue{Code: "invalid-telemetry-redaction-policy", Message: "Telemetry redaction policy must be bounded"}
	}
	seen := map[string]bool{}
	for _, key := range spec.Redaction.AllowedAttributeKeys {
		if !telemetryAttributeKeyPattern.MatchString(key) || sensitiveTelemetryKey(key) || seen[key] {
			return &Issue{Code: "invalid-telemetry-redaction-policy", Message: "Telemetry allowlist must have unique non-sensitive keys"}
		}
		seen[key] = true
	}
	return nil
}

func NewTelemetryPipeline(command TelemetryPipelineApplyCommand, revision int, createdAt string, observedAt time.Time, observation TelemetryPipelineObservation) (TelemetryPipeline, error) {
	if revision < 1 || createdAt == "" {
		return TelemetryPipeline{}, fmt.Errorf("invalid TelemetryPipeline revision or creation timestamp")
	}
	if issue := validatePipelineObservation(observation); issue != nil {
		return TelemetryPipeline{}, fmt.Errorf("invalid telemetry pipeline observation: %s", issue.Code)
	}
	at := Timestamp(observedAt)
	return TelemetryPipeline{SchemaVersion: SchemaVersion, ID: command.PipelineID, ResourceRevision: revision, Node: command.Node, Spec: command.Spec, Status: TelemetryPipelineStatus{State: observation.State, ObservedAt: at, Issue: observation.Issue}, CreatedAt: createdAt, UpdatedAt: at}, nil
}

func ValidateTelemetrySignalEmitCommand(command TelemetrySignalEmitCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.PipelineID) || command.ExpectedResourceRevision < 1 || len(command.Attributes) > 64 {
		return &Issue{Code: "invalid-telemetry-signal-command", Message: "Telemetry signal command identity, revision, and attributes must be bounded"}
	}
	for key, value := range command.Attributes {
		if !telemetryAttributeKeyPattern.MatchString(key) || len(value) > 4096 {
			return &Issue{Code: "invalid-telemetry-attribute", Message: "Telemetry attribute key/value violates input bounds"}
		}
	}
	return ValidateTelemetryCorrelation(command.Signal)
}

func ValidateTelemetryCorrelation(correlation TelemetryCorrelation) *Issue {
	if correlation.SchemaVersion != SchemaVersion || !ValidIdentifier(correlation.Service.Name) || correlation.Service.Version == "" || !telemetryAttributeKeyPattern.MatchString(correlation.SignalName) || !exactNonemptySignalKinds(correlation.SignalKinds) {
		return &Issue{Code: "invalid-telemetry-correlation", Message: "Telemetry correlation must identify service and OpenTelemetry signal kinds"}
	}
	if _, err := time.Parse(time.RFC3339Nano, correlation.EmittedAt); err != nil {
		return &Issue{Code: "invalid-telemetry-emitted-at", Message: "Telemetry emittedAt must be RFC3339"}
	}
	for _, identifier := range []*string{correlation.RequestID, correlation.OperationID, correlation.Component, correlation.OutcomeCode} {
		if identifier != nil && !ValidIdentifier(*identifier) {
			return &Issue{Code: "invalid-telemetry-correlation-reference", Message: "Telemetry correlation references must be valid identifiers"}
		}
	}
	if correlation.TraceID != nil && !traceIDPattern.MatchString(*correlation.TraceID) {
		return &Issue{Code: "invalid-telemetry-trace-id", Message: "Telemetry traceId must be lowercase 32-character hex"}
	}
	if correlation.SpanID != nil && !spanIDPattern.MatchString(*correlation.SpanID) {
		return &Issue{Code: "invalid-telemetry-span-id", Message: "Telemetry spanId must be lowercase 16-character hex"}
	}
	return nil
}

func SanitizeTelemetryAttributes(policy TelemetryRedactionPolicy, attributes map[string]string, known map[string]map[string]bool) SanitizedTelemetrySignal {
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
		if !allowed[key] || sensitiveTelemetryKey(key) || len(value) > policy.MaxValueLength {
			result.RedactedKeys = append(result.RedactedKeys, key)
			continue
		}
		if len(result.Attributes) >= policy.MaxAttributes {
			result.DroppedKeys = append(result.DroppedKeys, key)
			continue
		}
		digest := valueDigest(value)
		if known[key] == nil || !known[key][digest] {
			if len(known[key])+len(added[key]) >= policy.MaxDistinctValuesPerKey {
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
	if issue := validateExportResult(result); issue != nil {
		return TelemetryEmissionReceipt{}, fmt.Errorf("invalid telemetry export result: %s", issue.Code)
	}
	return TelemetryEmissionReceipt{SchemaVersion: SchemaVersion, ID: id, RequestID: command.RequestID, PipelineReference: ResourceReference{ResourceType: TelemetryPipelineResourceType, ResourceID: pipeline.ID}, Signal: command.Signal, Outcome: result.Outcome, EmittedAt: Timestamp(at), ExportedAttributeCount: len(sanitized.Attributes), RedactedAttributeKeys: explicitAttributeKeys(sanitized.RedactedKeys), DroppedAttributeKeys: explicitAttributeKeys(sanitized.DroppedKeys), Issue: result.Issue}, nil
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

func CommandDigest(command any) (string, error) {
	encoded, err := json.Marshal(command)
	if err != nil {
		return "", fmt.Errorf("encode command: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func NewOperationalOperation(id string, kind string, requestID string, targetType string, targetID string, expectedRevision int, requestedAt string, digest string) Operation {
	return Operation{SchemaVersion: SchemaVersion, ID: id, Kind: kind, RequestID: requestID, Target: OperationTarget{ResourceType: targetType, ResourceID: targetID, RequestedResourceRevision: expectedRevision}, RequestedAt: requestedAt, State: "requested", CommandDigest: digest}
}

func validateNode(node NodeReference) *Issue {
	if (node.Kind != "host" && node.Kind != "guest" && node.Kind != "recorder") || !ValidIdentifier(node.ID) {
		return &Issue{Code: "invalid-node-reference", Message: "node must be host, guest, or recorder with a valid id"}
	}
	return nil
}

func validateTimeSpec(spec TimeAuthoritySpec) *Issue {
	if (spec.Profile != "enterprise-ntp" && spec.Profile != "helper-ntp") || spec.Source.Profile != spec.Profile || !ValidIdentifier(spec.Source.SourceID) {
		return &Issue{Code: "invalid-time-authority-spec", Message: "TimeAuthority requires an explicit matching NTP source"}
	}
	return nil
}

func validatePipelineObservation(observation TelemetryPipelineObservation) *Issue {
	switch observation.State {
	case "ready":
		if observation.Issue != nil {
			return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "ready pipeline must not carry an issue"}
		}
	case "unavailable", "failed", "unsupported":
		if observation.Issue == nil {
			return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "non-ready pipeline requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-telemetry-pipeline-observation", Message: "telemetry pipeline state is unsupported"}
	}
	return nil
}

func validateExportResult(result TelemetryExportResult) *Issue {
	switch result.Outcome {
	case "exported":
		if result.Issue != nil {
			return &Issue{Code: "invalid-telemetry-export-result", Message: "exported result must not carry an issue"}
		}
	case "dropped", "unavailable", "failed", "unknown":
		if result.Issue == nil {
			return &Issue{Code: "invalid-telemetry-export-result", Message: "non-exported result requires a typed issue"}
		}
	default:
		return &Issue{Code: "invalid-telemetry-export-result", Message: "telemetry export outcome is unsupported"}
	}
	return nil
}

func exactSignalKinds(kinds []string) bool {
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

func exactNonemptySignalKinds(kinds []string) bool {
	if len(kinds) == 0 {
		return false
	}
	seen := map[string]bool{}
	for _, kind := range kinds {
		if (kind != "logs" && kind != "metrics" && kind != "traces") || seen[kind] {
			return false
		}
		seen[kind] = true
	}
	return true
}

func sensitiveTelemetryKey(key string) bool {
	for _, forbidden := range []string{"waveform", "packet", "patient", "credential", "authorization", "secret", "token", "password"} {
		if strings.Contains(key, forbidden) {
			return true
		}
	}
	return false
}

func valueDigest(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func ValidProtocolVersion(value string) bool { return protocolVersionPattern.MatchString(value) }
