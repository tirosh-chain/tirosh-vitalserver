package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"
)

const (
	RecorderUploadArchiveSourceKind      = "recorder-upload"
	RecorderVitalUploadSourceReceiptType = "recorder-vital-upload-source-receipt"
	GatewayColdPathArchiveSourceKind     = "gateway-cold-path"
	LabExportArchiveSourceKind           = "lab-export"
	ManualUploadArchiveSourceKind        = "manual-upload"
	MatchedRecorderAttributionOutcome    = "matched"
	UnresolvedRecorderAttributionOutcome = "unresolved"
	AmbiguousRecorderAttributionOutcome  = "ambiguous"
)

type ArchiveArtifact struct {
	SchemaVersion     string                 `json:"schemaVersion"`
	ArtifactID        string                 `json:"artifactId"`
	SourceKind        string                 `json:"sourceKind"`
	SourceReceiptType string                 `json:"sourceReceiptType"`
	SourceReceiptID   string                 `json:"sourceReceiptId"`
	Manifest          ArchiveLineageManifest `json:"manifest"`
	OriginalFileName  string                 `json:"originalFileName"`
	MediaType         string                 `json:"mediaType"`
	ByteSize          int64                  `json:"byteSize"`
	SHA256            string                 `json:"sha256"`
	FinalizationState string                 `json:"finalizationState"`
	CreatedAt         string                 `json:"createdAt"`
	FinalizedAt       *string                `json:"finalizedAt,omitempty"`
}

type ArchiveLineageManifest struct {
	SchemaVersion string                         `json:"schemaVersion"`
	ID            string                         `json:"id"`
	Source        ArchiveLineageManifestSource   `json:"source"`
	Artifact      ArchiveLineageArtifactIdentity `json:"artifact"`
	CreatedAt     string                         `json:"createdAt"`
}

type ArchiveLineageManifestSource struct {
	Kind              string            `json:"kind"`
	ReceiptType       string            `json:"receiptType"`
	ReceiptID         string            `json:"receiptId"`
	FinalizedAt       string            `json:"finalizedAt"`
	EvidenceReference EvidenceReference `json:"evidenceReference"`
}

type ArchiveLineageArtifactIdentity struct {
	ArtifactID       string            `json:"artifactId"`
	SHA256           string            `json:"sha256"`
	ByteSize         int64             `json:"byteSize"`
	MediaType        string            `json:"mediaType"`
	StorageReference ResourceReference `json:"storageReference"`
}

// RecorderVitalUploadSourceReceipt is immutable Gateway-owned evidence. A
// reported bed name or declared Recorder identity is evidence only; neither
// field authorizes Archive Export to infer attribution.
type RecorderVitalUploadSourceReceipt struct {
	SchemaVersion        string            `json:"schemaVersion"`
	ID                   string            `json:"id"`
	SourceKind           string            `json:"sourceKind"`
	UploadID             string            `json:"uploadId"`
	OriginalFileName     string            `json:"originalFileName"`
	MediaType            string            `json:"mediaType"`
	ByteSize             int64             `json:"byteSize"`
	SHA256               string            `json:"sha256"`
	ReportedBedName      string            `json:"reportedBedName"`
	DeclaredRecorderID   *string           `json:"declaredRecorderId,omitempty"`
	DeclaredRecorderCode *string           `json:"declaredRecorderCode,omitempty"`
	State                string            `json:"state"`
	ContentReference     ResourceReference `json:"contentReference"`
	ReceivedAt           string            `json:"receivedAt"`
	FinalizedAt          string            `json:"finalizedAt"`
}

type ArchiveSourceAdmissionCommand struct {
	SchemaVersion string                           `json:"schemaVersion"`
	RequestID     string                           `json:"requestId"`
	Source        RecorderVitalUploadSourceReceipt `json:"source"`
}

type ArchiveSourceAdmissionReceipt struct {
	SchemaVersion     string             `json:"schemaVersion"`
	RequestID         string             `json:"requestId"`
	Outcome           string             `json:"outcome"`
	ArtifactReference *ResourceReference `json:"artifactReference,omitempty"`
	ReceivedAt        string             `json:"receivedAt"`
	PersistedAt       string             `json:"persistedAt"`
	Issue             *Issue             `json:"issue,omitempty"`
}

type ArchiveArtifactObjectReceipt struct {
	SchemaVersion    string            `json:"schemaVersion"`
	ArtifactID       string            `json:"artifactId"`
	State            string            `json:"state"`
	ByteSize         int64             `json:"byteSize"`
	SHA256           string            `json:"sha256"`
	StorageReference ResourceReference `json:"storageReference"`
	PersistedAt      string            `json:"persistedAt"`
}

// RecorderAttributionResolutionInput is a complete answer supplied by the
// assignment owner. Archive policy consumes it but never discovers candidates
// from bed names, Recorder declarations, or Catalog absence.
type RecorderAttributionResolutionInput struct {
	ArtifactID                  string
	ReportedBedName             *string
	EvidenceObservedAt          string
	AssignmentEvidenceReference *EvidenceReference
	CandidateRecorderIDs        []string
	PolicyVersion               string
	ResolvedAt                  string
}

type RecorderArtifactAttribution struct {
	SchemaVersion               string             `json:"schemaVersion"`
	ArtifactID                  string             `json:"artifactId"`
	ReportedBedName             *string            `json:"reportedBedName,omitempty"`
	EvidenceObservedAt          string             `json:"evidenceObservedAt"`
	AssignmentEvidenceReference *EvidenceReference `json:"assignmentEvidenceReference,omitempty"`
	CandidateRecorderIDs        []string           `json:"candidateRecorderIds"`
	Outcome                     string             `json:"outcome"`
	MatchedRecorderID           *string            `json:"matchedRecorderId,omitempty"`
	PolicyVersion               string             `json:"policyVersion"`
	ResolvedAt                  string             `json:"resolvedAt"`
}

type ArchiveUploadAttempt struct {
	SchemaVersion string                   `json:"schemaVersion"`
	AttemptID     string                   `json:"attemptId"`
	RequestID     string                   `json:"requestId"`
	ArtifactID    string                   `json:"artifactId"`
	Provider      ArchiveProviderReference `json:"provider"`
	State         string                   `json:"state"`
	Issue         *Issue                   `json:"issue,omitempty"`
	StartedAt     string                   `json:"startedAt"`
	FinishedAt    *string                  `json:"finishedAt,omitempty"`
}

type ArchiveIndexingReceipt struct {
	SchemaVersion     string  `json:"schemaVersion"`
	ReceiptID         string  `json:"receiptId"`
	ArtifactID        string  `json:"artifactId"`
	UploadAttemptID   string  `json:"uploadAttemptId"`
	ProviderReceiptID *string `json:"providerReceiptId,omitempty"`
	Outcome           string  `json:"outcome"`
	Issue             *Issue  `json:"issue,omitempty"`
	ObservedAt        string  `json:"observedAt"`
	PersistedAt       string  `json:"persistedAt"`
}

type ArchiveArtifactDetail struct {
	SchemaVersion    string                      `json:"schemaVersion"`
	Artifact         ArchiveArtifact             `json:"artifact"`
	Attribution      RecorderArtifactAttribution `json:"attribution"`
	UploadAttempts   []ArchiveUploadAttempt      `json:"uploadAttempts"`
	IndexingReceipts []ArchiveIndexingReceipt    `json:"indexingReceipts"`
}

type RecorderArtifactPage struct {
	SchemaVersion string                  `json:"schemaVersion"`
	RecorderID    string                  `json:"recorderId"`
	Items         []ArchiveArtifactDetail `json:"items"`
	NextCursor    *string                 `json:"nextCursor,omitempty"`
}

func ValidateFinalizedArchiveArtifact(
	artifact ArchiveArtifact,
	attribution RecorderArtifactAttribution,
) error {
	if artifact.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(artifact.ArtifactID) ||
		!validArchiveSourceKind(artifact.SourceKind) ||
		!ValidIdentifier(artifact.SourceReceiptType) ||
		!ValidIdentifier(artifact.SourceReceiptID) ||
		artifact.Manifest.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(artifact.Manifest.ID) ||
		artifact.Manifest.Source.Kind != artifact.SourceKind ||
		artifact.Manifest.Source.ReceiptType != artifact.SourceReceiptType ||
		artifact.Manifest.Source.ReceiptID != artifact.SourceReceiptID ||
		artifact.Manifest.Source.FinalizedAt == "" ||
		!ValidIdentifier(artifact.Manifest.Source.EvidenceReference.Kind) ||
		!ValidIdentifier(artifact.Manifest.Source.EvidenceReference.ID) ||
		artifact.Manifest.Artifact.ArtifactID != artifact.ArtifactID ||
		artifact.Manifest.Artifact.SHA256 != artifact.SHA256 ||
		artifact.Manifest.Artifact.ByteSize != artifact.ByteSize ||
		artifact.Manifest.Artifact.MediaType != artifact.MediaType ||
		!ValidIdentifier(artifact.Manifest.Artifact.StorageReference.ResourceType) ||
		!ValidIdentifier(artifact.Manifest.Artifact.StorageReference.ResourceID) ||
		artifact.Manifest.CreatedAt == "" ||
		artifact.OriginalFileName == "" ||
		artifact.MediaType == "" ||
		artifact.ByteSize < 0 ||
		!validSHA256(artifact.SHA256) ||
		artifact.FinalizationState != "finalized" ||
		artifact.CreatedAt == "" ||
		artifact.FinalizedAt == nil ||
		*artifact.FinalizedAt == "" {
		return fmt.Errorf("finalized Archive artifact is incomplete or invalid")
	}
	if attribution.SchemaVersion != SchemaVersion ||
		attribution.ArtifactID != artifact.ArtifactID ||
		attribution.EvidenceObservedAt == "" ||
		attribution.PolicyVersion == "" ||
		attribution.ResolvedAt == "" {
		return fmt.Errorf("Archive artifact attribution is incomplete or invalid")
	}
	switch attribution.Outcome {
	case MatchedRecorderAttributionOutcome:
		if attribution.MatchedRecorderID == nil ||
			!ValidIdentifier(*attribution.MatchedRecorderID) ||
			len(attribution.CandidateRecorderIDs) != 1 ||
			attribution.CandidateRecorderIDs[0] != *attribution.MatchedRecorderID {
			return fmt.Errorf("matched attribution requires exactly one matching Recorder candidate")
		}
	case UnresolvedRecorderAttributionOutcome:
		if attribution.MatchedRecorderID != nil || len(attribution.CandidateRecorderIDs) != 0 {
			return fmt.Errorf("unresolved attribution cannot claim Recorder candidates or identity")
		}
	case AmbiguousRecorderAttributionOutcome:
		if attribution.MatchedRecorderID != nil || len(attribution.CandidateRecorderIDs) < 2 {
			return fmt.Errorf("ambiguous attribution requires multiple candidates and no matched Recorder")
		}
	default:
		return fmt.Errorf("Archive artifact attribution outcome is unsupported")
	}
	for _, candidate := range attribution.CandidateRecorderIDs {
		if !ValidIdentifier(candidate) {
			return fmt.Errorf("Archive artifact attribution contains an invalid Recorder candidate")
		}
	}
	return nil
}

func ValidateRecorderVitalUploadSourceReceipt(
	receipt RecorderVitalUploadSourceReceipt,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.ID) ||
		receipt.SourceKind != RecorderUploadArchiveSourceKind ||
		!ValidIdentifier(receipt.UploadID) ||
		!validVitalFileName(receipt.OriginalFileName) ||
		receipt.MediaType != "application/x-vital" ||
		receipt.ByteSize < 1 ||
		!validSHA256(receipt.SHA256) ||
		receipt.ReportedBedName == "" ||
		len(receipt.ReportedBedName) > 255 ||
		receipt.State != "admitted" ||
		receipt.ContentReference.ResourceType != "recorder-vital-upload-content" ||
		receipt.ContentReference.ResourceID != receipt.ID ||
		!validTimestamp(receipt.ReceivedAt) ||
		!validTimestamp(receipt.FinalizedAt) {
		return fmt.Errorf("Recorder Vital upload source receipt is incomplete or invalid")
	}
	if receipt.DeclaredRecorderID != nil &&
		!ValidIdentifier(*receipt.DeclaredRecorderID) {
		return fmt.Errorf("Recorder Vital upload declared Recorder identity is invalid")
	}
	if receipt.DeclaredRecorderCode != nil &&
		*receipt.DeclaredRecorderCode == "" {
		return fmt.Errorf("Recorder Vital upload declared Recorder code is invalid")
	}
	return nil
}

func ValidateArchiveSourceAdmissionCommand(
	command ArchiveSourceAdmissionCommand,
) error {
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) {
		return fmt.Errorf("Archive source admission command is incomplete or invalid")
	}
	return ValidateRecorderVitalUploadSourceReceipt(command.Source)
}

func ValidateArchiveSourceAdmissionReceipt(
	receipt ArchiveSourceAdmissionReceipt,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.RequestID) ||
		!validTimestamp(receipt.ReceivedAt) ||
		!validTimestamp(receipt.PersistedAt) {
		return fmt.Errorf("Archive source admission receipt is incomplete or invalid")
	}
	switch receipt.Outcome {
	case "accepted", "duplicate":
		if receipt.ArtifactReference == nil ||
			receipt.ArtifactReference.ResourceType != "archive-artifact" ||
			!ValidIdentifier(receipt.ArtifactReference.ResourceID) ||
			receipt.Issue != nil {
			return fmt.Errorf("accepted or duplicate Archive source admission requires an artifact and no issue")
		}
	case "quarantined":
		if receipt.ArtifactReference != nil ||
			receipt.Issue == nil ||
			!ValidIdentifier(receipt.Issue.Code) {
			return fmt.Errorf("quarantined Archive source admission requires an issue and no artifact")
		}
	default:
		return fmt.Errorf("Archive source admission outcome is unsupported")
	}
	return nil
}

func ArchiveArtifactIDForSourceReceipt(
	sourceKind string,
	sourceReceiptType string,
	sourceReceiptID string,
) (string, error) {
	if !validArchiveSourceKind(sourceKind) ||
		!ValidIdentifier(sourceReceiptType) ||
		!ValidIdentifier(sourceReceiptID) {
		return "", fmt.Errorf("Archive source identity is incomplete or invalid")
	}
	digest := sha256.Sum256(
		[]byte(sourceKind + "\x00" + sourceReceiptType + "\x00" + sourceReceiptID),
	)
	return "archive-artifact-" + hex.EncodeToString(digest[:]), nil
}

func ValidateArchiveArtifactObjectReceipt(
	receipt ArchiveArtifactObjectReceipt,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.ArtifactID) ||
		(receipt.State != "committed" && receipt.State != "existing") ||
		receipt.ByteSize < 1 ||
		!validSHA256(receipt.SHA256) ||
		receipt.StorageReference.ResourceType != "guest-archive-object" ||
		receipt.StorageReference.ResourceID != receipt.ArtifactID ||
		!validTimestamp(receipt.PersistedAt) {
		return fmt.Errorf("Archive artifact object receipt is incomplete or invalid")
	}
	return nil
}

func ResolveRecorderArtifactAttribution(
	input RecorderAttributionResolutionInput,
) (RecorderArtifactAttribution, error) {
	if !ValidIdentifier(input.ArtifactID) ||
		!validTimestamp(input.EvidenceObservedAt) ||
		!ValidIdentifier(input.PolicyVersion) ||
		!validTimestamp(input.ResolvedAt) {
		return RecorderArtifactAttribution{}, fmt.Errorf("Recorder attribution resolution input is incomplete or invalid")
	}
	if input.AssignmentEvidenceReference != nil &&
		(!ValidIdentifier(input.AssignmentEvidenceReference.Kind) ||
			!ValidIdentifier(input.AssignmentEvidenceReference.ID)) {
		return RecorderArtifactAttribution{}, fmt.Errorf("Recorder attribution assignment evidence reference is invalid")
	}
	candidates := append([]string(nil), input.CandidateRecorderIDs...)
	seen := make(map[string]struct{}, len(candidates))
	for _, candidate := range candidates {
		if !ValidIdentifier(candidate) {
			return RecorderArtifactAttribution{}, fmt.Errorf("Recorder attribution candidate is invalid")
		}
		if _, exists := seen[candidate]; exists {
			return RecorderArtifactAttribution{}, fmt.Errorf("Recorder attribution candidates must be unique")
		}
		seen[candidate] = struct{}{}
	}
	attribution := RecorderArtifactAttribution{
		SchemaVersion:               SchemaVersion,
		ArtifactID:                  input.ArtifactID,
		ReportedBedName:             input.ReportedBedName,
		EvidenceObservedAt:          input.EvidenceObservedAt,
		AssignmentEvidenceReference: input.AssignmentEvidenceReference,
		CandidateRecorderIDs:        candidates,
		PolicyVersion:               input.PolicyVersion,
		ResolvedAt:                  input.ResolvedAt,
	}
	switch len(candidates) {
	case 0:
		attribution.Outcome = UnresolvedRecorderAttributionOutcome
	case 1:
		attribution.Outcome = MatchedRecorderAttributionOutcome
		attribution.MatchedRecorderID = &attribution.CandidateRecorderIDs[0]
	default:
		attribution.Outcome = AmbiguousRecorderAttributionOutcome
	}
	return attribution, nil
}

func ValidateArchiveUploadAttempt(attempt ArchiveUploadAttempt) error {
	if attempt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(attempt.AttemptID) ||
		!ValidIdentifier(attempt.RequestID) ||
		!ValidIdentifier(attempt.ArtifactID) ||
		!ValidIdentifier(attempt.Provider.Kind) ||
		!ValidIdentifier(attempt.Provider.ID) ||
		attempt.Provider.CapabilityRevision < 1 ||
		attempt.StartedAt == "" {
		return fmt.Errorf("Archive upload attempt is incomplete or invalid")
	}
	switch attempt.State {
	case "requested", "running":
		if attempt.FinishedAt != nil || attempt.Issue != nil {
			return fmt.Errorf("non-terminal Archive upload attempt cannot contain terminal evidence")
		}
	case "succeeded":
		if attempt.FinishedAt == nil || *attempt.FinishedAt == "" || attempt.Issue != nil {
			return fmt.Errorf("succeeded Archive upload attempt requires finish time and no issue")
		}
	case "failed", "unknown":
		if attempt.FinishedAt == nil || *attempt.FinishedAt == "" || attempt.Issue == nil {
			return fmt.Errorf("failed or unknown Archive upload attempt requires finish time and issue")
		}
	default:
		return fmt.Errorf("Archive upload attempt state is unsupported")
	}
	return nil
}

func ValidateArchiveIndexingReceipt(receipt ArchiveIndexingReceipt) error {
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.ReceiptID) ||
		!ValidIdentifier(receipt.ArtifactID) ||
		!ValidIdentifier(receipt.UploadAttemptID) ||
		receipt.ObservedAt == "" ||
		receipt.PersistedAt == "" {
		return fmt.Errorf("Archive indexing receipt is incomplete or invalid")
	}
	switch receipt.Outcome {
	case "indexed":
		if receipt.ProviderReceiptID == nil ||
			!ValidIdentifier(*receipt.ProviderReceiptID) ||
			receipt.Issue != nil {
			return fmt.Errorf("indexed receipt requires provider receipt identity and no issue")
		}
	case "not-indexed", "unknown", "unsupported", "failed":
		if receipt.ProviderReceiptID != nil || receipt.Issue == nil {
			return fmt.Errorf("non-indexed receipt requires an issue and no provider receipt identity")
		}
	default:
		return fmt.Errorf("Archive indexing outcome is unsupported")
	}
	return nil
}

func validArchiveSourceKind(kind string) bool {
	switch kind {
	case RecorderUploadArchiveSourceKind,
		GatewayColdPathArchiveSourceKind,
		LabExportArchiveSourceKind,
		ManualUploadArchiveSourceKind:
		return true
	default:
		return false
	}
}

func validSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, character := range value {
		if (character < '0' || character > '9') &&
			(character < 'a' || character > 'f') {
			return false
		}
	}
	return true
}

func validVitalFileName(value string) bool {
	if len(value) < len(".vital")+1 || len(value) > 255 {
		return false
	}
	for _, character := range value {
		if character == '/' || character == '\\' {
			return false
		}
	}
	return strings.HasSuffix(strings.ToLower(value), ".vital")
}

func validTimestamp(value string) bool {
	_, err := time.Parse(time.RFC3339Nano, value)
	return err == nil
}
