package hostupdaterdomain

import "fmt"

// StagedProductUpdateIssue is the next-updater representation of the shared C28 issue
// value. The staged updater owns the report it creates; Host independently
// validates the same boundary document before it changes C29 state.
type StagedProductUpdateIssue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

// StagedProductUpdateEvidenceReference names the concrete record that supports one layer
// or rollback outcome. It is evidence, never a substitute for the outcome.
type StagedProductUpdateEvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
	URI  string `json:"uri,omitempty"`
}

// StagedProductUpdateLayerExecutionEvidence is one ordered C28 layer result. A
// non-succeeded result ends the sequence, preserving the exact point at which
// the updater stopped applying the declared plan.
type StagedProductUpdateLayerExecutionEvidence struct {
	Layer          string                               `json:"layer"`
	State          string                               `json:"state"`
	ArtifactSHA256 string                               `json:"artifactSha256"`
	ObservedAt     string                               `json:"observedAt"`
	Evidence       StagedProductUpdateEvidenceReference `json:"evidence"`
	Issue          *StagedProductUpdateIssue            `json:"issue,omitempty"`
}

// StagedProductUpdateRollbackEvidence is C28 rollback fact. It remains independent from
// the failed layer evidence because a rollback can itself have a distinct
// outcome and proof.
type StagedProductUpdateRollbackEvidence struct {
	State      string                                `json:"state"`
	ObservedAt string                                `json:"observedAt"`
	Evidence   *StagedProductUpdateEvidenceReference `json:"evidence,omitempty"`
	Issue      *StagedProductUpdateIssue             `json:"issue,omitempty"`
}

// StagedProductUpdateExecutionReport is C28, owned and created by the staged next updater
// after its selected layer effect adapters have produced explicit outcomes.
type StagedProductUpdateExecutionReport struct {
	SchemaVersion             string                                      `json:"schemaVersion"`
	UpdateID                  string                                      `json:"updateId"`
	RequestID                 string                                      `json:"requestId"`
	BootstrapEnvelopeID       string                                      `json:"bootstrapEnvelopeId"`
	UpdateSpecificationSHA256 string                                      `json:"updateSpecificationSha256"`
	State                     string                                      `json:"state"`
	StartedAt                 string                                      `json:"startedAt"`
	FinishedAt                string                                      `json:"finishedAt"`
	LayerEvidence             []StagedProductUpdateLayerExecutionEvidence `json:"layerEvidence"`
	Rollback                  StagedProductUpdateRollbackEvidence         `json:"rollback"`
	Failure                   *StagedProductUpdateIssue                   `json:"failure,omitempty"`
}

// StagedProductUpdateCompletionCommand is C27 as sent by the staged updater to the
// Host-local completion endpoint. Its revision is deliberately named by the
// Host API contract; C30 calls the same value expectedHandoffJournalRevision
// to preserve the state from which that value originates.
type StagedProductUpdateCompletionCommand struct {
	SchemaVersion           string                             `json:"schemaVersion"`
	UpdateID                string                             `json:"updateId"`
	ExpectedJournalRevision int                                `json:"expectedJournalRevision"`
	Report                  StagedProductUpdateExecutionReport `json:"report"`
}

// ComposeStagedProductUpdateCompletionCommand validates C28 against the complete C30/C26
// input and binds the command to the exact C29 handoff revision. It performs
// no HTTP, filesystem, or layer effect.
func ComposeStagedProductUpdateCompletionCommand(input StagedProductUpdatePlanningInput, report StagedProductUpdateExecutionReport) (StagedProductUpdateCompletionCommand, error) {
	if _, err := PlanStagedProductUpdateExecution(input); err != nil {
		return StagedProductUpdateCompletionCommand{}, fmt.Errorf("plan staged product update before completion: %w", err)
	}
	if err := ValidateStagedProductUpdateExecutionReport(input, report); err != nil {
		return StagedProductUpdateCompletionCommand{}, err
	}
	return StagedProductUpdateCompletionCommand{
		SchemaVersion:           HostUpdaterDocumentSchemaVersion,
		UpdateID:                input.Invocation.UpdateID,
		ExpectedJournalRevision: input.Invocation.ExpectedHandoffJournalRevision,
		Report:                  report,
	}, nil
}

// ValidateStagedProductUpdateExecutionReport keeps C28 generation inside the next-updater
// bounded context. Host repeats stable boundary validation before it settles
// C29; neither side trusts a missing or malformed report as success.
func ValidateStagedProductUpdateExecutionReport(input StagedProductUpdatePlanningInput, report StagedProductUpdateExecutionReport) error {
	invocation := input.Invocation
	if report.SchemaVersion != HostUpdaterDocumentSchemaVersion || report.UpdateID != invocation.UpdateID || report.RequestID != invocation.RequestID || report.BootstrapEnvelopeID != invocation.BootstrapEnvelopeID || report.UpdateSpecificationSHA256 != invocation.UpdateSpecificationSHA256 || report.StartedAt == "" || report.FinishedAt == "" {
		return fmt.Errorf("C28 report does not match the staged update invocation")
	}
	if len(report.LayerEvidence) == 0 || len(report.LayerEvidence) > len(input.Specification.LayerPlan) {
		return fmt.Errorf("C28 report layer evidence length is invalid")
	}
	for index, evidence := range report.LayerEvidence {
		plannedLayer := input.Specification.LayerPlan[index]
		if evidence.Layer != plannedLayer.Layer || evidence.ArtifactSHA256 != plannedLayer.Artifact.SHA256 || evidence.ObservedAt == "" || !validStagedProductUpdateEvidenceReference(evidence.Evidence) {
			return fmt.Errorf("C28 layer evidence does not match the planned layer artifact")
		}
		switch evidence.State {
		case "succeeded":
			if evidence.Issue != nil {
				return fmt.Errorf("C28 succeeded layer evidence must not carry an issue")
			}
		case "failed", "unavailable", "unsupported":
			if index != len(report.LayerEvidence)-1 || !validStagedProductUpdateIssue(evidence.Issue) {
				return fmt.Errorf("C28 non-successful layer evidence must be final and carry a typed issue")
			}
		default:
			return fmt.Errorf("C28 layer evidence state is unsupported")
		}
	}
	switch report.State {
	case "succeeded":
		if len(report.LayerEvidence) != len(input.Specification.LayerPlan) || report.Failure != nil || report.Rollback.State != "not-required" || report.Rollback.Issue != nil {
			return fmt.Errorf("C28 succeeded report requires every layer and no rollback or failure")
		}
		for _, evidence := range report.LayerEvidence {
			if evidence.State != "succeeded" {
				return fmt.Errorf("C28 succeeded report requires succeeded evidence for every layer")
			}
		}
	case "failed":
		if !validStagedProductUpdateIssue(report.Failure) {
			return fmt.Errorf("C28 failed report requires a typed failure")
		}
		if report.LayerEvidence[len(report.LayerEvidence)-1].State == "succeeded" {
			return fmt.Errorf("C28 failed report requires non-successful final layer evidence")
		}
		if len(report.LayerEvidence) > 1 && report.Rollback.State == "not-required" {
			return fmt.Errorf("C28 failed report after applied layers requires explicit rollback evidence")
		}
		if err := validateStagedProductUpdateRollbackEvidence(report.Rollback); err != nil {
			return err
		}
	default:
		return fmt.Errorf("C28 report state is unsupported")
	}
	return nil
}

func validStagedProductUpdateEvidenceReference(reference StagedProductUpdateEvidenceReference) bool {
	return validIdentifier(reference.Kind) && validIdentifier(reference.ID)
}

func validStagedProductUpdateIssue(issue *StagedProductUpdateIssue) bool {
	return issue != nil && validIdentifier(issue.Code) && (issue.Dependency == "" || validIdentifier(issue.Dependency))
}

func validateStagedProductUpdateRollbackEvidence(rollback StagedProductUpdateRollbackEvidence) error {
	switch rollback.State {
	case "not-required", "succeeded":
		if rollback.Issue != nil {
			return fmt.Errorf("C28 rollback %s must not carry an issue", rollback.State)
		}
	case "failed", "not-attempted":
		if !validStagedProductUpdateIssue(rollback.Issue) {
			return fmt.Errorf("C28 rollback %s requires a typed issue", rollback.State)
		}
	default:
		return fmt.Errorf("C28 rollback state is unsupported")
	}
	if rollback.ObservedAt == "" {
		return fmt.Errorf("C28 rollback observedAt is required")
	}
	if rollback.Evidence != nil && !validStagedProductUpdateEvidenceReference(*rollback.Evidence) {
		return fmt.Errorf("C28 rollback evidence is invalid")
	}
	return nil
}
