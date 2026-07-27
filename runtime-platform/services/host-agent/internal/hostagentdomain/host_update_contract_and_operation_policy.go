package hostagentdomain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

// Update has two deliberately separate contracts.  The bootstrap envelope is
// a long-lived, small compatibility boundary that the currently installed
// updater can validate.  The product update specification is interpreted only
// after the next updater has been verified and handed off to.  This removes a
// minimum-updater-version gate without claiming that an old updater can parse
// every future product-update language.
const (
	UpdateLayerContainer    = "container"
	UpdateLayerGuestRuntime = "guest-runtime"
	UpdateLayerHostPlatform = "host-platform"
)

var updateSHA256Pattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type UpdateTarget struct {
	Platform     string `json:"platform"`
	Architecture string `json:"architecture"`
}

type UpdateArtifact struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
	MediaType    string `json:"mediaType"`
}

type UpdateSignature struct {
	Algorithm    string `json:"algorithm"`
	KeyID        string `json:"keyId"`
	SignedSHA256 string `json:"signedSha256"`
	Value        string `json:"value"`
}

// UpdateBootstrapEnvelope is C25.  The signature covers the canonical
// envelope with this signature object omitted.  Its specification artifact is
// opaque to the current updater; only the staged next updater parses it.
type UpdateBootstrapEnvelope struct {
	SchemaVersion       string          `json:"schemaVersion"`
	ID                  string          `json:"id"`
	ProductID           string          `json:"productId"`
	Target              UpdateTarget    `json:"target"`
	TargetRelease       Release         `json:"targetRelease"`
	LayerOrder          []string        `json:"layerOrder"`
	NextUpdaterArtifact UpdateArtifact  `json:"nextUpdaterArtifact"`
	Specification       UpdateArtifact  `json:"specification"`
	Signature           UpdateSignature `json:"signature"`
	IssuedAt            string          `json:"issuedAt"`
}

// HostUpdateCommand is C27.  Bundle reference ownership remains a Host-local
// affordance for the product installer/update UI; it is not a browser path.
type HostUpdateCommand struct {
	SchemaVersion                string                  `json:"schemaVersion"`
	RequestID                    string                  `json:"requestId"`
	InstallationID               string                  `json:"installationId"`
	ExpectedInstallationRevision int                     `json:"expectedInstallationRevision"`
	BundleReferenceID            string                  `json:"bundleReferenceId"`
	BootstrapEnvelope            UpdateBootstrapEnvelope `json:"bootstrapEnvelope"`
}

// UpdateCompletionCommand is sent only by the staged next updater over the
// Host-local update channel.  Its journal revision prevents an old updater
// process from settling a recovery attempt it no longer owns.
type UpdateCompletionCommand struct {
	SchemaVersion           string                `json:"schemaVersion"`
	UpdateID                string                `json:"updateId"`
	ExpectedJournalRevision int                   `json:"expectedJournalRevision"`
	Report                  UpdateExecutionReport `json:"report"`
}

// HostUpdateInterruptionRequest is the explicit Host-local command that asks
// the current update owner to stop. Requesting interruption does not claim
// that the next updater process has terminated; the journal remains active
// until a separate supervisor confirmation settles it.
type HostUpdateInterruptionRequest struct {
	SchemaVersion                string `json:"schemaVersion"`
	RequestID                    string `json:"requestId"`
	UpdateID                     string `json:"updateId"`
	InstallationID               string `json:"installationId"`
	ExpectedInstallationRevision int    `json:"expectedInstallationRevision"`
	ExpectedJournalRevision      int    `json:"expectedJournalRevision"`
	Reason                       Issue  `json:"reason"`
}

// HostUpdateInterruptionConfirmation is submitted only after the supervisor
// has cancelled and waited for the exact staged next-updater process.
type HostUpdateInterruptionConfirmation struct {
	SchemaVersion                string            `json:"schemaVersion"`
	RequestID                    string            `json:"requestId"`
	UpdateID                     string            `json:"updateId"`
	InstallationID               string            `json:"installationId"`
	ExpectedInstallationRevision int               `json:"expectedInstallationRevision"`
	ExpectedJournalRevision      int               `json:"expectedJournalRevision"`
	InterruptionRequestID        string            `json:"interruptionRequestId"`
	TerminationEvidence          EvidenceReference `json:"terminationEvidence"`
	Outcome                      Issue             `json:"outcome"`
	ObservedAt                   string            `json:"observedAt"`
}

// HostUpdateInterruption records the accepted request and the state whose
// owner must be cancelled and waited for by the handoff supervisor.
type HostUpdateInterruption struct {
	RequestID             string             `json:"requestId"`
	InterruptedState      string             `json:"interruptedState"`
	Reason                Issue              `json:"reason"`
	RequestedAt           string             `json:"requestedAt"`
	ConfirmationRequestID string             `json:"confirmationRequestId,omitempty"`
	TerminationEvidence   *EvidenceReference `json:"terminationEvidence,omitempty"`
	ConfirmedAt           string             `json:"confirmedAt,omitempty"`
}

// UpdateBootstrapReceipt is returned by the selected bootstrap adapter after
// it has verified and staged the next updater.  `staged` is not an update
// success: Host persists a handoff-pending journal and waits for C28 evidence.
type UpdateBootstrapReceipt struct {
	SchemaVersion       string `json:"schemaVersion"`
	UpdateID            string `json:"updateId"`
	RequestID           string `json:"requestId"`
	BootstrapEnvelopeID string `json:"bootstrapEnvelopeId"`
	NextUpdaterSHA256   string `json:"nextUpdaterSha256"`
	State               string `json:"state"`
	ObservedAt          string `json:"observedAt"`
	Issue               *Issue `json:"issue,omitempty"`
}

type UpdateLayerEvidence struct {
	Layer          string            `json:"layer"`
	State          string            `json:"state"`
	ArtifactSHA256 string            `json:"artifactSha256"`
	ObservedAt     string            `json:"observedAt"`
	Evidence       EvidenceReference `json:"evidence"`
	Issue          *Issue            `json:"issue,omitempty"`
}

type UpdateRollbackEvidence struct {
	State      string             `json:"state"`
	ObservedAt string             `json:"observedAt"`
	Evidence   *EvidenceReference `json:"evidence,omitempty"`
	Issue      *Issue             `json:"issue,omitempty"`
}

// UpdateExecutionReport is C28.  It is made by the staged next updater after
// parsing the evolving product update specification.  Host verifies only the
// stable correlation, declared layer order, and explicit result semantics.
type UpdateExecutionReport struct {
	SchemaVersion             string                 `json:"schemaVersion"`
	UpdateID                  string                 `json:"updateId"`
	RequestID                 string                 `json:"requestId"`
	BootstrapEnvelopeID       string                 `json:"bootstrapEnvelopeId"`
	UpdateSpecificationSHA256 string                 `json:"updateSpecificationSha256"`
	State                     string                 `json:"state"`
	StartedAt                 string                 `json:"startedAt"`
	FinishedAt                string                 `json:"finishedAt"`
	LayerEvidence             []UpdateLayerEvidence  `json:"layerEvidence"`
	Rollback                  UpdateRollbackEvidence `json:"rollback"`
	Failure                   *Issue                 `json:"failure,omitempty"`
}

// HostUpdateJournal is C29.  Host owns this durable admission and recovery
// record.  The journal does not contain the evolving specification itself.
type HostUpdateJournal struct {
	SchemaVersion                string `json:"schemaVersion"`
	ID                           string `json:"id"`
	JournalRevision              int    `json:"journalRevision"`
	OperationID                  string `json:"operationId"`
	RequestID                    string `json:"requestId"`
	InstallationID               string `json:"installationId"`
	ExpectedInstallationRevision int    `json:"expectedInstallationRevision"`
	BundleReferenceID            string `json:"bundleReferenceId"`
	// BootstrapEnvelope is durable recovery input.  It is the immutable C25
	// document that the Host can re-verify; C26 remains opaque and is never
	// stored or decoded by the current Host updater.
	BootstrapEnvelope         UpdateBootstrapEnvelope `json:"bootstrapEnvelope"`
	BootstrapEnvelopeID       string                  `json:"bootstrapEnvelopeId"`
	BootstrapSignedSHA256     string                  `json:"bootstrapSignedSha256"`
	NextUpdaterSHA256         string                  `json:"nextUpdaterSha256"`
	UpdateSpecificationSHA256 string                  `json:"updateSpecificationSha256"`
	TargetRelease             Release                 `json:"targetRelease"`
	LayerOrder                []string                `json:"layerOrder"`
	State                     string                  `json:"state"`
	BootstrapReceipt          *UpdateBootstrapReceipt `json:"bootstrapReceipt,omitempty"`
	ExecutionReport           *UpdateExecutionReport  `json:"executionReport,omitempty"`
	Interruption              *HostUpdateInterruption `json:"interruption,omitempty"`
	Failure                   *Issue                  `json:"failure,omitempty"`
	CreatedAt                 string                  `json:"createdAt"`
	UpdatedAt                 string                  `json:"updatedAt"`
	CommandDigest             string                  `json:"-"`
	ExecutionDigest           string                  `json:"-"`
}

// HostUpdateOperationOwnership is the Host Agent-owned public projection used
// by other Host lifecycle workflows before they mutate an installation.
// "idle" is an explicit successful owner query, not absence inferred by a
// consumer. "active" identifies the one durable Update Journal owner.
type HostUpdateOperationOwnership struct {
	SchemaVersion         string `json:"schemaVersion"`
	InstallationID        string `json:"installationId"`
	InstallationRevision  int    `json:"installationRevision"`
	State                 string `json:"state"`
	UpdateID              string `json:"updateId,omitempty"`
	OperationID           string `json:"operationId,omitempty"`
	RequestID             string `json:"requestId,omitempty"`
	UpdateState           string `json:"updateState,omitempty"`
	InterruptionRequested bool   `json:"interruptionRequested,omitempty"`
	InterruptionRequestID string `json:"interruptionRequestId,omitempty"`
	JournalRevision       int    `json:"journalRevision,omitempty"`
}

func ValidUpdateTarget(target UpdateTarget) bool {
	if target.Architecture != "arm64" && target.Architecture != "amd64" {
		return false
	}
	switch target.Platform {
	case "macos", "windows", "linux":
		return true
	default:
		return false
	}
}

func ValidUpdateLayer(layer string) bool {
	switch layer {
	case UpdateLayerContainer, UpdateLayerGuestRuntime, UpdateLayerHostPlatform:
		return true
	default:
		return false
	}
}

func ValidateUpdateLayerOrder(layers []string) *Issue {
	if len(layers) == 0 || len(layers) > 3 {
		return &Issue{Code: "invalid-update-layer-order", Message: "layerOrder must contain one to three explicit layers"}
	}
	seen := map[string]bool{}
	for index, layer := range layers {
		if !ValidUpdateLayer(layer) || seen[layer] {
			return &Issue{Code: "invalid-update-layer-order", Message: "layerOrder contains an unsupported or duplicate layer"}
		}
		seen[layer] = true
		if layer == UpdateLayerHostPlatform && index != len(layers)-1 {
			return &Issue{Code: "invalid-update-layer-order", Message: "host-platform must be the final layer after bootstrap handoff"}
		}
	}
	return nil
}

func ValidateUpdateArtifact(artifact UpdateArtifact) *Issue {
	if !ValidIdentifier(artifact.ID) || !updateSHA256Pattern.MatchString(artifact.SHA256) || artifact.SizeBytes < 1 || artifact.MediaType == "" {
		return &Issue{Code: "invalid-update-artifact", Message: "artifact id, sha256, positive sizeBytes, and mediaType are required"}
	}
	if !strings.HasPrefix(artifact.RelativePath, "payload/") || strings.Contains(artifact.RelativePath, "..") || strings.Contains(artifact.RelativePath, "\\") {
		return &Issue{Code: "invalid-update-artifact", Message: "artifact relativePath must stay below payload/ without traversal"}
	}
	return nil
}

func ValidateUpdateBootstrapEnvelope(envelope UpdateBootstrapEnvelope) *Issue {
	if envelope.SchemaVersion != SchemaVersion || !ValidIdentifier(envelope.ID) || !ValidIdentifier(envelope.ProductID) || !ValidUpdateTarget(envelope.Target) {
		return &Issue{Code: "invalid-update-bootstrap-envelope", Message: "bootstrap envelope identity, schemaVersion, and target are invalid"}
	}
	if envelope.TargetRelease.ProductVersion == "" || envelope.TargetRelease.RuntimeVersion == "" || envelope.IssuedAt == "" {
		return &Issue{Code: "invalid-update-bootstrap-envelope", Message: "bootstrap envelope target release and issuedAt are required"}
	}
	if issue := ValidateUpdateLayerOrder(envelope.LayerOrder); issue != nil {
		return issue
	}
	if issue := ValidateUpdateArtifact(envelope.NextUpdaterArtifact); issue != nil {
		return issue
	}
	if issue := ValidateUpdateArtifact(envelope.Specification); issue != nil {
		return issue
	}
	if envelope.NextUpdaterArtifact.ID == envelope.Specification.ID || envelope.NextUpdaterArtifact.SHA256 == envelope.Specification.SHA256 {
		return &Issue{Code: "invalid-update-bootstrap-envelope", Message: "next updater and update specification must be distinct artifacts"}
	}
	if envelope.Signature.Algorithm != "ed25519" || !ValidIdentifier(envelope.Signature.KeyID) || !updateSHA256Pattern.MatchString(envelope.Signature.SignedSHA256) || envelope.Signature.Value == "" {
		return &Issue{Code: "invalid-update-bootstrap-envelope", Message: "bootstrap envelope requires ed25519 trust evidence"}
	}
	return nil
}

func ValidateHostUpdateCommand(command HostUpdateCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.InstallationID) || command.ExpectedInstallationRevision < 1 || !ValidIdentifier(command.BundleReferenceID) {
		return &Issue{Code: "invalid-host-update-command", Message: "Host update command identity and expected installation revision are required"}
	}
	return ValidateUpdateBootstrapEnvelope(command.BootstrapEnvelope)
}

func ValidateUpdateCompletionCommand(command UpdateCompletionCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.UpdateID) || command.ExpectedJournalRevision < 1 {
		return &Issue{Code: "invalid-update-completion-command", Message: "updateId and expectedJournalRevision are required"}
	}
	if command.Report.UpdateID != command.UpdateID {
		return &Issue{Code: "invalid-update-completion-command", Message: "completion report updateId must match the command"}
	}
	return nil
}

func HostUpdateCommandDigest(command HostUpdateCommand) (string, error) {
	encoded, err := json.Marshal(command)
	if err != nil {
		return "", fmt.Errorf("encode Host update command: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func NewHostUpdateOperation(id string, command HostUpdateCommand, requestedAt string, digest string) Operation {
	return Operation{
		SchemaVersion: SchemaVersion,
		ID:            id,
		Kind:          "platform.update.apply",
		RequestID:     command.RequestID,
		Target: OperationTarget{
			ResourceType:              "platform-installation",
			ResourceID:                command.InstallationID,
			RequestedResourceRevision: command.ExpectedInstallationRevision,
		},
		RequestedAt:   requestedAt,
		State:         "requested",
		CommandDigest: digest,
	}
}

func NewHostUpdateJournal(id string, operation Operation, command HostUpdateCommand, at string) HostUpdateJournal {
	return HostUpdateJournal{
		SchemaVersion:                SchemaVersion,
		ID:                           id,
		JournalRevision:              1,
		OperationID:                  operation.ID,
		RequestID:                    command.RequestID,
		InstallationID:               command.InstallationID,
		ExpectedInstallationRevision: command.ExpectedInstallationRevision,
		BundleReferenceID:            command.BundleReferenceID,
		BootstrapEnvelope:            command.BootstrapEnvelope,
		BootstrapEnvelopeID:          command.BootstrapEnvelope.ID,
		BootstrapSignedSHA256:        command.BootstrapEnvelope.Signature.SignedSHA256,
		NextUpdaterSHA256:            command.BootstrapEnvelope.NextUpdaterArtifact.SHA256,
		UpdateSpecificationSHA256:    command.BootstrapEnvelope.Specification.SHA256,
		TargetRelease:                command.BootstrapEnvelope.TargetRelease,
		LayerOrder:                   append([]string(nil), command.BootstrapEnvelope.LayerOrder...),
		State:                        "requested",
		CreatedAt:                    at,
		UpdatedAt:                    at,
		CommandDigest:                operation.CommandDigest,
	}
}

// DecideHostUpdateAdmission preserves one durable update owner at a time.
// The repository supplies every explicitly active journal; this pure policy
// validates those owner records rather than treating an empty or malformed
// read as permission to admit another update.
func DecideHostUpdateAdmission(activeJournals []HostUpdateJournal) *Issue {
	for _, journal := range activeJournals {
		if issue := ValidateHostUpdateJournal(journal); issue != nil {
			return &Issue{
				Code:       "active-host-update-state-invalid",
				Message:    "Host Agent cannot admit an update while an active update owner record is invalid",
				Retryable:  Bool(false),
				Dependency: "host-state-store",
			}
		}
		if !HostUpdateJournalIsActive(journal) {
			return &Issue{
				Code:       "active-host-update-query-invalid",
				Message:    "Host Agent active-update query returned a terminal update journal",
				Retryable:  Bool(false),
				Dependency: "host-state-store",
			}
		}
		return &Issue{
			Code:      "host-update-operation-active",
			Message:   "another Host update operation owns the Host update workflow",
			Retryable: Bool(false),
		}
	}
	return nil
}

// HostUpdateJournalIsActive names the non-terminal states that retain update
// ownership. It is shared by admission policy and repository query tests so
// terminal failure, interruption, and success remain distinct from activity.
func HostUpdateJournalIsActive(journal HostUpdateJournal) bool {
	switch journal.State {
	case "requested", "bootstrap-staged", "handoff-pending", "applying":
		return true
	default:
		return false
	}
}

// ProjectHostUpdateOperationOwnership derives one complete public ownership
// fact from Host-owned installation and journal state. More than one active
// journal is invalid even if an infrastructure constraint should prevent it.
func ProjectHostUpdateOperationOwnership(installation PlatformInstallation, activeJournals []HostUpdateJournal) (HostUpdateOperationOwnership, *Issue) {
	if issue := ValidatePlatformInstallation(installation); issue != nil {
		return HostUpdateOperationOwnership{}, &Issue{
			Code:       "host-installation-state-invalid",
			Message:    issue.Message,
			Retryable:  Bool(false),
			Dependency: "host-state-store",
		}
	}
	if len(activeJournals) > 1 {
		return HostUpdateOperationOwnership{}, &Issue{
			Code:       "multiple-active-host-updates",
			Message:    "Host state contains more than one active update owner",
			Retryable:  Bool(false),
			Dependency: "host-state-store",
		}
	}
	ownership := HostUpdateOperationOwnership{
		SchemaVersion:        SchemaVersion,
		InstallationID:       installation.ID,
		InstallationRevision: installation.ResourceRevision,
		State:                "idle",
	}
	if len(activeJournals) == 0 {
		return ownership, nil
	}
	journal := activeJournals[0]
	if issue := ValidateHostUpdateJournal(journal); issue != nil {
		return HostUpdateOperationOwnership{}, &Issue{
			Code:       "active-host-update-state-invalid",
			Message:    issue.Message,
			Retryable:  Bool(false),
			Dependency: "host-state-store",
		}
	}
	if !HostUpdateJournalIsActive(journal) || journal.InstallationID != installation.ID || journal.ExpectedInstallationRevision != installation.ResourceRevision {
		return HostUpdateOperationOwnership{}, &Issue{
			Code:       "active-host-update-owner-mismatch",
			Message:    "active update owner does not match the current Host installation identity and revision",
			Retryable:  Bool(false),
			Dependency: "host-state-store",
		}
	}
	ownership.State = "active"
	ownership.UpdateID = journal.ID
	ownership.OperationID = journal.OperationID
	ownership.RequestID = journal.RequestID
	ownership.UpdateState = journal.State
	ownership.InterruptionRequested = journal.Interruption != nil
	if journal.Interruption != nil {
		ownership.InterruptionRequestID = journal.Interruption.RequestID
	}
	ownership.JournalRevision = journal.JournalRevision
	return ownership, nil
}

// ValidateHostUpdateJournal validates the complete Host-owned durable record
// after decoding it from SQLite.  A JSON document that happens to decode but
// loses its cross-field correlations is invalid state, not an available
// update.  C26 is intentionally absent: only its C25 digest is retained.
func ValidateHostUpdateJournal(journal HostUpdateJournal) *Issue {
	if journal.SchemaVersion != SchemaVersion || !ValidIdentifier(journal.ID) || journal.JournalRevision < 1 || !ValidIdentifier(journal.OperationID) || !ValidIdentifier(journal.RequestID) || !ValidIdentifier(journal.InstallationID) || journal.ExpectedInstallationRevision < 1 || !ValidIdentifier(journal.BundleReferenceID) || journal.CreatedAt == "" || journal.UpdatedAt == "" {
		return &Issue{Code: "host-update-journal-invalid", Message: "Host update journal identity and revision fields are invalid"}
	}
	if issue := ValidateUpdateBootstrapEnvelope(journal.BootstrapEnvelope); issue != nil {
		return &Issue{Code: "host-update-journal-invalid", Message: "persisted bootstrap envelope is invalid: " + issue.Code}
	}
	if journal.BootstrapEnvelope.ID != journal.BootstrapEnvelopeID || journal.BootstrapEnvelope.Signature.SignedSHA256 != journal.BootstrapSignedSHA256 || journal.BootstrapEnvelope.NextUpdaterArtifact.SHA256 != journal.NextUpdaterSHA256 || journal.BootstrapEnvelope.Specification.SHA256 != journal.UpdateSpecificationSHA256 || journal.BootstrapEnvelope.TargetRelease != journal.TargetRelease || !sameUpdateLayerOrder(journal.BootstrapEnvelope.LayerOrder, journal.LayerOrder) {
		return &Issue{Code: "host-update-journal-invalid", Message: "persisted bootstrap envelope does not match Host update journal correlations"}
	}
	switch journal.State {
	case "requested":
		if journal.BootstrapReceipt != nil || journal.ExecutionReport != nil || journal.Failure != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "requested update journal cannot carry receipt, report, or failure"}
		}
		if issue := validateHostUpdateInterruption(journal); issue != nil {
			return issue
		}
	case "bootstrap-staged", "handoff-pending", "applying":
		if journal.BootstrapReceipt == nil || journal.BootstrapReceipt.State != "staged" || journal.ExecutionReport != nil || journal.Failure != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "active update journal requires only a staged bootstrap receipt"}
		}
		if issue := ValidateUpdateBootstrapReceipt(journal, *journal.BootstrapReceipt); issue != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "active bootstrap receipt is invalid: " + issue.Code}
		}
		if issue := validateHostUpdateInterruption(journal); issue != nil {
			return issue
		}
	case "succeeded":
		if journal.BootstrapReceipt == nil || journal.BootstrapReceipt.State != "staged" || journal.ExecutionReport == nil || journal.ExecutionReport.State != "succeeded" || journal.Interruption != nil || journal.Failure != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "succeeded update journal requires staged receipt and succeeded execution report"}
		}
		if issue := ValidateUpdateBootstrapReceipt(journal, *journal.BootstrapReceipt); issue != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "succeeded bootstrap receipt is invalid: " + issue.Code}
		}
		if issue := ValidateUpdateExecutionReport(journal, *journal.ExecutionReport); issue != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "succeeded execution report is invalid: " + issue.Code}
		}
	case "failed":
		if journal.Failure == nil || !ValidIdentifier(journal.Failure.Code) || journal.Interruption != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "failed update journal requires a typed failure"}
		}
		if journal.BootstrapReceipt != nil {
			if issue := ValidateUpdateBootstrapReceipt(journal, *journal.BootstrapReceipt); issue != nil {
				return &Issue{Code: "host-update-journal-invalid", Message: "failed bootstrap receipt is invalid: " + issue.Code}
			}
		}
		if journal.ExecutionReport != nil {
			if journal.ExecutionReport.State != "failed" {
				return &Issue{Code: "host-update-journal-invalid", Message: "failed update journal execution report must be failed"}
			}
			if issue := ValidateUpdateExecutionReport(journal, *journal.ExecutionReport); issue != nil {
				return &Issue{Code: "host-update-journal-invalid", Message: "failed execution report is invalid: " + issue.Code}
			}
		}
	case "interrupted":
		if journal.Interruption == nil || journal.Failure == nil || !ValidIdentifier(journal.Failure.Code) || journal.ExecutionReport != nil {
			return &Issue{Code: "host-update-journal-invalid", Message: "interrupted update journal requires its request, a typed reason, and no execution report"}
		}
		if issue := validateTerminalHostUpdateInterruption(journal.Interruption); issue != nil {
			return issue
		}
		if !ValidIdentifier(journal.Interruption.ConfirmationRequestID) || journal.Interruption.TerminationEvidence == nil || !ValidIdentifier(journal.Interruption.TerminationEvidence.Kind) || !ValidIdentifier(journal.Interruption.TerminationEvidence.ID) || journal.Interruption.ConfirmedAt == "" {
			return &Issue{Code: "host-update-journal-invalid", Message: "interrupted update journal requires explicit supervisor termination evidence"}
		}
	default:
		return &Issue{Code: "host-update-journal-invalid", Message: "Host update journal state is unsupported"}
	}
	return nil
}

func validateHostUpdateInterruption(journal HostUpdateJournal) *Issue {
	if journal.Interruption == nil {
		return nil
	}
	if issue := validateTerminalHostUpdateInterruption(journal.Interruption); issue != nil {
		return issue
	}
	if journal.Interruption.InterruptedState != journal.State || journal.Interruption.ConfirmationRequestID != "" || journal.Interruption.TerminationEvidence != nil || journal.Interruption.ConfirmedAt != "" {
		return &Issue{Code: "host-update-journal-invalid", Message: "active update journal interruption request is invalid"}
	}
	return nil
}

func validateTerminalHostUpdateInterruption(interruption *HostUpdateInterruption) *Issue {
	if interruption == nil || !ValidIdentifier(interruption.RequestID) || !ValidIdentifier(interruption.Reason.Code) || interruption.Reason.Message == "" || interruption.RequestedAt == "" {
		return &Issue{Code: "host-update-journal-invalid", Message: "Host update journal interruption request is invalid"}
	}
	switch interruption.InterruptedState {
	case "requested", "bootstrap-staged", "handoff-pending", "applying":
		return nil
	default:
		return &Issue{Code: "host-update-journal-invalid", Message: "Host update journal interruption source state is invalid"}
	}
}

func sameUpdateLayerOrder(left []string, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func ValidateUpdateBootstrapReceipt(journal HostUpdateJournal, receipt UpdateBootstrapReceipt) *Issue {
	if receipt.SchemaVersion != SchemaVersion || receipt.UpdateID != journal.ID || receipt.RequestID != journal.RequestID || receipt.BootstrapEnvelopeID != journal.BootstrapEnvelopeID || receipt.NextUpdaterSHA256 != journal.NextUpdaterSHA256 || receipt.ObservedAt == "" {
		return &Issue{Code: "update-bootstrap-contract-invalid", Message: "bootstrap receipt does not match the Host-owned update journal"}
	}
	switch receipt.State {
	case "staged":
		if receipt.Issue != nil {
			return &Issue{Code: "update-bootstrap-contract-invalid", Message: "staged bootstrap receipt must not carry an issue"}
		}
	case "failed", "unavailable":
		if receipt.Issue == nil {
			return &Issue{Code: "update-bootstrap-contract-invalid", Message: "failed or unavailable bootstrap receipt requires an issue"}
		}
	default:
		return &Issue{Code: "update-bootstrap-contract-invalid", Message: "bootstrap receipt state is unsupported"}
	}
	return nil
}

func StageUpdateBootstrap(journal HostUpdateJournal, receipt UpdateBootstrapReceipt) (HostUpdateJournal, error) {
	if journal.State != "requested" {
		return HostUpdateJournal{}, fmt.Errorf("update bootstrap can only stage a requested journal")
	}
	if issue := ValidateUpdateBootstrapReceipt(journal, receipt); issue != nil {
		return HostUpdateJournal{}, fmt.Errorf("%s", issue.Code)
	}
	next := journal
	next.BootstrapReceipt = &receipt
	next.UpdatedAt = receipt.ObservedAt
	next.JournalRevision++
	if receipt.State == "staged" {
		next.State = "bootstrap-staged"
		return next, nil
	}
	next.State = "failed"
	next.Failure = receipt.Issue
	return next, nil
}

func MarkUpdateHandoffPending(journal HostUpdateJournal, at string) (HostUpdateJournal, error) {
	if journal.State != "bootstrap-staged" {
		return HostUpdateJournal{}, fmt.Errorf("update handoff can only follow a staged bootstrap")
	}
	next := journal
	next.State = "handoff-pending"
	next.UpdatedAt = at
	next.JournalRevision++
	return next, nil
}

func BeginUpdateExecution(journal HostUpdateJournal, at string) (HostUpdateJournal, error) {
	if journal.State != "handoff-pending" {
		return HostUpdateJournal{}, fmt.Errorf("update execution can only claim a handoff-pending journal")
	}
	next := journal
	next.State = "applying"
	next.UpdatedAt = at
	next.JournalRevision++
	return next, nil
}

func ValidateUpdateExecutionReport(journal HostUpdateJournal, report UpdateExecutionReport) *Issue {
	if report.SchemaVersion != SchemaVersion || report.UpdateID != journal.ID || report.RequestID != journal.RequestID || report.BootstrapEnvelopeID != journal.BootstrapEnvelopeID || report.UpdateSpecificationSHA256 != journal.UpdateSpecificationSHA256 || report.StartedAt == "" || report.FinishedAt == "" {
		return &Issue{Code: "update-execution-report-invalid", Message: "update execution report does not match the Host-owned bootstrap journal"}
	}
	if len(report.LayerEvidence) == 0 || len(report.LayerEvidence) > len(journal.LayerOrder) {
		return &Issue{Code: "update-execution-report-invalid", Message: "update execution report has an invalid layer evidence length"}
	}
	for index, evidence := range report.LayerEvidence {
		if evidence.Layer != journal.LayerOrder[index] || evidence.ObservedAt == "" || !updateSHA256Pattern.MatchString(evidence.ArtifactSHA256) || evidence.Evidence.Kind == "" || evidence.Evidence.ID == "" {
			return &Issue{Code: "update-execution-report-invalid", Message: "layer evidence must follow the bootstrap layer order and carry explicit evidence"}
		}
		switch evidence.State {
		case "succeeded":
			if evidence.Issue != nil {
				return &Issue{Code: "update-execution-report-invalid", Message: "succeeded layer evidence must not carry an issue"}
			}
		case "failed", "unavailable", "unsupported":
			if evidence.Issue == nil || index != len(report.LayerEvidence)-1 {
				return &Issue{Code: "update-execution-report-invalid", Message: "a non-successful layer must be final and carry an issue"}
			}
		default:
			return &Issue{Code: "update-execution-report-invalid", Message: "layer evidence state is unsupported"}
		}
	}
	switch report.State {
	case "succeeded":
		if len(report.LayerEvidence) != len(journal.LayerOrder) || report.Failure != nil || report.Rollback.State != "not-required" || report.Rollback.Issue != nil {
			return &Issue{Code: "update-execution-report-invalid", Message: "a successful update requires every declared layer and no rollback or failure"}
		}
		for _, evidence := range report.LayerEvidence {
			if evidence.State != "succeeded" {
				return &Issue{Code: "update-execution-report-invalid", Message: "a successful update requires succeeded evidence for every layer"}
			}
		}
	case "failed":
		if report.Failure == nil {
			return &Issue{Code: "update-execution-report-invalid", Message: "a failed update requires a failure issue"}
		}
		last := report.LayerEvidence[len(report.LayerEvidence)-1]
		if last.State == "succeeded" {
			return &Issue{Code: "update-execution-report-invalid", Message: "a failed update requires a non-successful final layer"}
		}
		priorSuccess := len(report.LayerEvidence) > 1
		if priorSuccess && report.Rollback.State == "not-required" {
			return &Issue{Code: "update-execution-report-invalid", Message: "a failed update after applied layers requires explicit rollback evidence"}
		}
		if report.Rollback.State != "not-required" && report.Rollback.State != "succeeded" && report.Rollback.State != "failed" && report.Rollback.State != "not-attempted" {
			return &Issue{Code: "update-execution-report-invalid", Message: "failed update rollback state is unsupported"}
		}
		if (report.Rollback.State == "failed" || report.Rollback.State == "not-attempted") && report.Rollback.Issue == nil {
			return &Issue{Code: "update-execution-report-invalid", Message: "failed or unattempted rollback requires an issue"}
		}
	default:
		return &Issue{Code: "update-execution-report-invalid", Message: "update execution report state is unsupported"}
	}
	return nil
}

func CompleteUpdateExecution(journal HostUpdateJournal, report UpdateExecutionReport) (HostUpdateJournal, error) {
	if journal.State != "applying" {
		return HostUpdateJournal{}, fmt.Errorf("update execution report can only settle an applying journal")
	}
	if issue := ValidateUpdateExecutionReport(journal, report); issue != nil {
		return HostUpdateJournal{}, fmt.Errorf("%s", issue.Code)
	}
	digest, err := UpdateExecutionReportDigest(report)
	if err != nil {
		return HostUpdateJournal{}, fmt.Errorf("encode update execution report: %w", err)
	}
	next := journal
	next.ExecutionReport = &report
	next.ExecutionDigest = digest
	next.UpdatedAt = report.FinishedAt
	next.JournalRevision++
	if report.State == "succeeded" {
		next.State = "succeeded"
		return next, nil
	}
	next.State = "failed"
	next.Failure = report.Failure
	return next, nil
}

func UpdateExecutionReportDigest(report UpdateExecutionReport) (string, error) {
	encoded, err := json.Marshal(report)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:]), nil
}

func FailUpdateJournal(journal HostUpdateJournal, at string, issue Issue) (HostUpdateJournal, error) {
	switch journal.State {
	case "requested", "bootstrap-staged", "handoff-pending", "applying":
	default:
		return HostUpdateJournal{}, fmt.Errorf("only non-terminal update journals can fail")
	}
	next := journal
	next.State = "failed"
	next.Failure = &issue
	next.UpdatedAt = at
	next.JournalRevision++
	return next, nil
}

func ValidateHostUpdateInterruptionConfirmation(command HostUpdateInterruptionConfirmation) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.UpdateID) || !ValidIdentifier(command.InstallationID) || command.ExpectedInstallationRevision < 1 || command.ExpectedJournalRevision < 1 || !ValidIdentifier(command.InterruptionRequestID) || !ValidIdentifier(command.TerminationEvidence.Kind) || !ValidIdentifier(command.TerminationEvidence.ID) || !ValidIdentifier(command.Outcome.Code) || command.Outcome.Message == "" || command.ObservedAt == "" {
		return &Issue{Code: "host-update-interruption-confirmation-invalid", Message: "Host update interruption confirmation identity, revisions, outcome, and termination evidence are required"}
	}
	return nil
}

// ConfirmUpdateInterruption consumes explicit supervisor termination evidence.
// A cancellation request alone cannot release active ownership.
func ConfirmUpdateInterruption(journal HostUpdateJournal, command HostUpdateInterruptionConfirmation) (HostUpdateJournal, error) {
	if issue := ValidateHostUpdateInterruptionConfirmation(command); issue != nil {
		return HostUpdateJournal{}, fmt.Errorf("%s", issue.Code)
	}
	if !HostUpdateJournalIsActive(journal) || journal.Interruption == nil {
		return HostUpdateJournal{}, fmt.Errorf("host-update-interruption-confirmation-state-conflict")
	}
	if journal.ID != command.UpdateID || journal.InstallationID != command.InstallationID || journal.ExpectedInstallationRevision != command.ExpectedInstallationRevision || journal.JournalRevision != command.ExpectedJournalRevision || journal.Interruption.RequestID != command.InterruptionRequestID {
		return HostUpdateJournal{}, fmt.Errorf("host-update-interruption-confirmation-owner-mismatch")
	}
	next := journal
	next.State = "interrupted"
	next.Failure = &command.Outcome
	next.Interruption.ConfirmationRequestID = command.RequestID
	next.Interruption.TerminationEvidence = &command.TerminationEvidence
	next.Interruption.ConfirmedAt = command.ObservedAt
	next.UpdatedAt = command.ObservedAt
	next.JournalRevision++
	return next, nil
}

func HostUpdateInterruptionConfirmationIsReplay(journal HostUpdateJournal, command HostUpdateInterruptionConfirmation) bool {
	return journal.State == "interrupted" &&
		journal.Interruption != nil &&
		journal.Interruption.ConfirmationRequestID == command.RequestID &&
		journal.Interruption.RequestID == command.InterruptionRequestID &&
		journal.Interruption.TerminationEvidence != nil &&
		*journal.Interruption.TerminationEvidence == command.TerminationEvidence &&
		journal.Interruption.ConfirmedAt == command.ObservedAt &&
		journal.Failure != nil &&
		sameIssue(*journal.Failure, command.Outcome) &&
		journal.ID == command.UpdateID &&
		journal.InstallationID == command.InstallationID &&
		journal.ExpectedInstallationRevision == command.ExpectedInstallationRevision &&
		journal.JournalRevision == command.ExpectedJournalRevision+1
}

func ValidateHostUpdateInterruptionRequest(command HostUpdateInterruptionRequest) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.UpdateID) || !ValidIdentifier(command.InstallationID) || command.ExpectedInstallationRevision < 1 || command.ExpectedJournalRevision < 1 || !ValidIdentifier(command.Reason.Code) || command.Reason.Message == "" {
		return &Issue{Code: "host-update-interruption-request-invalid", Message: "Host update interruption request identity, revision, and reason are required"}
	}
	return nil
}

// RequestUpdateInterruption records intent without releasing active ownership.
// Process termination and wait evidence must arrive before the journal can
// become terminal.
func RequestUpdateInterruption(journal HostUpdateJournal, command HostUpdateInterruptionRequest, at string) (HostUpdateJournal, error) {
	if issue := ValidateHostUpdateInterruptionRequest(command); issue != nil {
		return HostUpdateJournal{}, fmt.Errorf("%s", issue.Code)
	}
	if journal.ID != command.UpdateID || journal.InstallationID != command.InstallationID || journal.ExpectedInstallationRevision != command.ExpectedInstallationRevision {
		return HostUpdateJournal{}, fmt.Errorf("host-update-interruption-owner-mismatch")
	}
	if journal.JournalRevision != command.ExpectedJournalRevision {
		return HostUpdateJournal{}, fmt.Errorf("host-update-interruption-revision-conflict")
	}
	if !HostUpdateJournalIsActive(journal) || journal.Interruption != nil {
		return HostUpdateJournal{}, fmt.Errorf("host-update-interruption-state-conflict")
	}
	next := journal
	next.Interruption = &HostUpdateInterruption{
		RequestID:        command.RequestID,
		InterruptedState: journal.State,
		Reason:           command.Reason,
		RequestedAt:      at,
	}
	next.UpdatedAt = at
	next.JournalRevision++
	return next, nil
}

func HostUpdateInterruptionRequestIsReplay(journal HostUpdateJournal, command HostUpdateInterruptionRequest) bool {
	return journal.Interruption != nil &&
		journal.Interruption.RequestID == command.RequestID &&
		journal.Interruption.InterruptedState != "" &&
		sameIssue(journal.Interruption.Reason, command.Reason) &&
		journal.ID == command.UpdateID &&
		journal.InstallationID == command.InstallationID &&
		journal.ExpectedInstallationRevision == command.ExpectedInstallationRevision &&
		journal.JournalRevision == command.ExpectedJournalRevision+1
}

func sameIssue(left Issue, right Issue) bool {
	if left.Code != right.Code || left.Message != right.Message || left.Dependency != right.Dependency {
		return false
	}
	if left.Retryable == nil || right.Retryable == nil {
		return left.Retryable == nil && right.Retryable == nil
	}
	return *left.Retryable == *right.Retryable
}

func ApplyUpdateRelease(installation PlatformInstallation, journal HostUpdateJournal, at string) (PlatformInstallation, error) {
	if journal.State != "succeeded" || journal.ExecutionReport == nil {
		return PlatformInstallation{}, fmt.Errorf("only a successful update journal can advance an installation release")
	}
	if installation.ID != journal.InstallationID || installation.ResourceRevision != journal.ExpectedInstallationRevision {
		return PlatformInstallation{}, fmt.Errorf("Host installation no longer matches the admitted update target")
	}
	next := installation
	next.ResourceRevision++
	next.Release = journal.TargetRelease
	next.UpdatedAt = at
	return next, nil
}
