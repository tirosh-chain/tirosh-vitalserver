package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

const ArtifactExportOperationKind = "archive.artifact.export"

type ArchiveProviderReference struct {
	Kind               string `json:"kind"`
	ID                 string `json:"id"`
	CapabilityRevision int    `json:"capabilityRevision"`
}

// ArchiveExportProviderConfiguration is Archive Export's non-secret public
// projection of the provider selected by the Guest deployment.  It is a
// configuration fact, not an upload, indexing, or .vital artifact outcome.
//
// An operator surface reads this document before requesting a manual export
// so it can carry the exact Archive-owned provider reference.  The surface
// must not construct a provider reference from a Lab display name, an
// endpoint, or a prior command response.
type ArchiveExportProviderConfiguration struct {
	SchemaVersion string                   `json:"schemaVersion"`
	Provider      ArchiveProviderReference `json:"provider"`
}

type ArtifactExportCommand struct {
	SchemaVersion            string                   `json:"schemaVersion"`
	RequestID                string                   `json:"requestId"`
	VirtualRecorderID        string                   `json:"virtualRecorderId"`
	ExpectedResourceRevision int                      `json:"expectedResourceRevision"`
	Source                   ArtifactExportSource     `json:"source"`
	Provider                 ArchiveProviderReference `json:"provider"`
}

// ArtifactExportSource is an explicit selection of the finalized source that
// Archive Export must consume.  A stopped Lab recorder alone is not source
// evidence: the named Recorder Gateway finalization receipt is required.
type ArtifactExportSource struct {
	Kind                          string `json:"kind"`
	ColdPathFinalizationReceiptID string `json:"coldPathFinalizationReceiptId"`
}

const RecorderGatewayColdPathArtifactExportSourceKind = "recorder-gateway-cold-path"

// FinalizedRecorderColdPathPacketSequence is the complete Gateway-owned
// source fact handed to Archive Export after the adapter has verified the
// Gateway receipt and raw stream digest.  It is intentionally not persisted
// as a Lab document and does not claim that .vital bytes exist.
type FinalizedRecorderColdPathPacketSequence struct {
	FinalizationReceiptID string
	CaptureID             string
	RecorderID            string
	FinalizedAt           string
	MediaType             string
	SHA256                string
	Bytes                 []byte
}

type ArtifactManifest struct {
	SchemaVersion string            `json:"schemaVersion"`
	ID            string            `json:"id"`
	OperationID   string            `json:"operationId"`
	Source        FinalizedSource   `json:"source"`
	Artifact      ImmutableArtifact `json:"artifact"`
	CreatedAt     string            `json:"createdAt"`
}

type FinalizedSource struct {
	ResourceType      string            `json:"resourceType"`
	ResourceID        string            `json:"resourceId"`
	FinalizedAt       string            `json:"finalizedAt"`
	EvidenceReference EvidenceReference `json:"evidenceReference"`
}

type ImmutableArtifact struct {
	ArtifactID       string            `json:"artifactId"`
	Digest           string            `json:"digest"`
	ByteSize         int               `json:"byteSize"`
	MediaType        string            `json:"mediaType"`
	StorageReference ResourceReference `json:"storageReference"`
}

type EvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
	URI  string `json:"uri,omitempty"`
}

type ExportStep struct {
	State       string `json:"state"`
	ReceiptID   string `json:"receiptId,omitempty"`
	CompletedAt string `json:"completedAt,omitempty"`
	Issue       *Issue `json:"issue,omitempty"`
}

type ExportReceipt struct {
	SchemaVersion             string                   `json:"schemaVersion"`
	ID                        string                   `json:"id"`
	OperationID               string                   `json:"operationId"`
	RequestID                 string                   `json:"requestId"`
	ArtifactManifestReference ResourceReference        `json:"artifactManifestReference"`
	Provider                  ArchiveProviderReference `json:"provider"`
	Upload                    ExportStep               `json:"upload"`
	Indexing                  ExportStep               `json:"indexing"`
	Outcome                   string                   `json:"outcome"`
	Retryable                 bool                     `json:"retryable"`
	CompletedAt               string                   `json:"completedAt"`
	Issue                     *Issue                   `json:"issue,omitempty"`
	EvidenceReferences        []EvidenceReference      `json:"evidenceReferences,omitempty"`
}

func ValidateArtifactExportCommand(command ArtifactExportCommand) *Issue {
	if command.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.VirtualRecorderID) {
		return &Issue{Code: "invalid-artifact-export-reference", Message: "requestId and virtualRecorderId must be valid v1 identifiers"}
	}
	if command.ExpectedResourceRevision < 1 {
		return &Issue{Code: "invalid-expected-resource-revision", Message: "expectedResourceRevision must be one or greater"}
	}
	if !ValidIdentifier(command.Provider.Kind) || !ValidIdentifier(command.Provider.ID) || command.Provider.CapabilityRevision < 1 {
		return &Issue{Code: "invalid-archive-provider-reference", Message: "provider kind, id, and capabilityRevision must be explicit and valid"}
	}
	if command.Source.Kind != RecorderGatewayColdPathArtifactExportSourceKind || !ValidIdentifier(command.Source.ColdPathFinalizationReceiptID) {
		return &Issue{Code: "invalid-artifact-export-source", Message: "source must explicitly select one finalized Recorder Gateway cold-path receipt"}
	}
	return nil
}

func NewArtifactManifest(id string, artifactID string, operationID string, source StoppedRecorderSource, sourceEvidence EvidenceReference, finalizedAt string, payload []byte) (ArtifactManifest, error) {
	if !ValidIdentifier(id) || !ValidIdentifier(artifactID) || !ValidIdentifier(operationID) || !ValidIdentifier(source.VirtualRecorderID) || !ValidIdentifier(sourceEvidence.Kind) || !ValidIdentifier(sourceEvidence.ID) || finalizedAt == "" || len(payload) == 0 {
		return ArtifactManifest{}, fmt.Errorf("invalid artifact manifest construction input")
	}
	digest := sha256.Sum256(payload)
	return ArtifactManifest{
		SchemaVersion: SchemaVersion,
		ID:            id,
		OperationID:   operationID,
		Source: FinalizedSource{
			ResourceType:      VirtualRecorderResourceType,
			ResourceID:        source.VirtualRecorderID,
			FinalizedAt:       finalizedAt,
			EvidenceReference: sourceEvidence,
		},
		Artifact: ImmutableArtifact{
			ArtifactID:       artifactID,
			Digest:           hex.EncodeToString(digest[:]),
			ByteSize:         len(payload),
			MediaType:        "application/x-vital",
			StorageReference: ResourceReference{ResourceType: "guest-archive-object", ResourceID: artifactID},
		},
		CreatedAt: finalizedAt,
	}, nil
}

func SucceededExportStep(receiptID string, completedAt string) ExportStep {
	return ExportStep{State: "succeeded", ReceiptID: receiptID, CompletedAt: completedAt}
}

func FailedExportStep(completedAt string, issue Issue) ExportStep {
	return ExportStep{State: "failed", CompletedAt: completedAt, Issue: &issue}
}

func NotRequestedExportStep() ExportStep {
	return ExportStep{State: "not-requested"}
}

func NewExportReceipt(id string, operation Operation, manifest ArtifactManifest, provider ArchiveProviderReference, upload ExportStep, indexing ExportStep, completedAt string) (ExportReceipt, error) {
	if !ValidIdentifier(id) || operation.ID == "" || manifest.ID == "" || completedAt == "" {
		return ExportReceipt{}, fmt.Errorf("invalid export receipt construction input")
	}
	receipt := ExportReceipt{
		SchemaVersion:             SchemaVersion,
		ID:                        id,
		OperationID:               operation.ID,
		RequestID:                 operation.RequestID,
		ArtifactManifestReference: ResourceReference{ResourceType: "artifact-manifest", ResourceID: manifest.ID},
		Provider:                  provider,
		Upload:                    upload,
		Indexing:                  indexing,
		CompletedAt:               completedAt,
	}
	if upload.State == "succeeded" && indexing.State == "succeeded" {
		receipt.Outcome = "succeeded"
		receipt.Retryable = false
		return receipt, nil
	}
	receipt.Outcome = "failed"
	receipt.Retryable = exportStepRetryable(upload) || exportStepRetryable(indexing)
	if upload.Issue != nil {
		receipt.Issue = upload.Issue
	} else if indexing.Issue != nil {
		receipt.Issue = indexing.Issue
	} else {
		return ExportReceipt{}, fmt.Errorf("failed export receipt requires a failed step issue")
	}
	return receipt, nil
}

func exportStepRetryable(step ExportStep) bool {
	return step.Issue != nil && step.Issue.Retryable != nil && *step.Issue.Retryable
}
