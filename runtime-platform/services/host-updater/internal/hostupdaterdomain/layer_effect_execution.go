package hostupdaterdomain

import "fmt"

const (
	StagedUpdateLayerEffectOperationApply    = "apply"
	StagedUpdateLayerEffectOperationRollback = "rollback"
)

// StagedUpdateLayerEffectReceipt is C55. A release-owned executor writes one
// of these after a fixed-protocol apply or rollback invocation. It is not a
// process exit interpretation: the staged next updater validates its explicit
// correlation before it can become C28 evidence.
type StagedUpdateLayerEffectReceipt struct {
	SchemaVersion    string                               `json:"schemaVersion"`
	UpdateID         string                               `json:"updateId"`
	Layer            string                               `json:"layer"`
	EffectExecutorID string                               `json:"effectExecutorId"`
	Operation        string                               `json:"operation"`
	ArtifactSHA256   string                               `json:"artifactSha256"`
	State            string                               `json:"state"`
	ObservedAt       string                               `json:"observedAt"`
	Evidence         StagedProductUpdateEvidenceReference `json:"evidence"`
	Issue            *StagedProductUpdateIssue            `json:"issue,omitempty"`
}

// ValidateStagedUpdateLayerEffectReceipt enforces the one layer effect that
// the next updater requested. The receipt cannot turn a different payload,
// executor, layer, or operation into a successful update outcome.
func ValidateStagedUpdateLayerEffectReceipt(
	input StagedProductUpdatePlanningInput,
	layer ProductUpdateLayerPlan,
	operation string,
	artifact ProductUpdateArtifact,
	receipt StagedUpdateLayerEffectReceipt,
) error {
	if receipt.SchemaVersion != HostUpdaterDocumentSchemaVersion || receipt.UpdateID != input.Invocation.UpdateID || receipt.Layer != layer.Layer || receipt.EffectExecutorID != layer.EffectExecutor.ID || receipt.Operation != operation || receipt.ArtifactSHA256 != artifact.SHA256 || receipt.ObservedAt == "" || !validStagedProductUpdateEvidenceReference(receipt.Evidence) {
		return fmt.Errorf("C55 layer effect receipt does not match the requested effect")
	}
	switch receipt.State {
	case "succeeded":
		if receipt.Issue != nil {
			return fmt.Errorf("C55 succeeded layer effect receipt must not carry an issue")
		}
	case "failed", "unavailable", "unsupported":
		if !validStagedProductUpdateIssue(receipt.Issue) {
			return fmt.Errorf("C55 non-successful layer effect receipt requires a typed issue")
		}
	default:
		return fmt.Errorf("C55 layer effect receipt state is unsupported")
	}
	return nil
}
