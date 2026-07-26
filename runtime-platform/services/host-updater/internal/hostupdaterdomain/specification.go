// Package hostupdaterdomain owns the next-updater-only product update specification.
// The currently installed Host Agent must not import or parse this package.
package hostupdaterdomain

import (
	"fmt"
	"regexp"
)

// HostUpdaterDocumentSchemaVersion is shared by the C26, C27, C28, and C30
// documents that this bounded context reads or produces.
const HostUpdaterDocumentSchemaVersion = "v1"

const (
	ProductUpdateLayerContainer    = "container"
	ProductUpdateLayerGuestRuntime = "guest-runtime"
	ProductUpdateLayerHostPlatform = "host-platform"
)

var (
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]*$`)
)

// ProductUpdateArtifact is one immutable byte payload declared by C26 for a
// single product-update layer or its explicitly available rollback.
type ProductUpdateArtifact struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
	MediaType    string `json:"mediaType"`
}

// ProductUpdateLayerEffectExecutor is the one release payload executable that
// can perform a declared layer operation. The next updater invokes it through
// a fixed argument protocol; a C26 document never carries a Host command path,
// shell expression, or caller-defined arguments.
type ProductUpdateLayerEffectExecutor struct {
	ID                    string                `json:"id"`
	RelativePath          string                `json:"relativePath"`
	SHA256                string                `json:"sha256"`
	SizeBytes             int64                 `json:"sizeBytes"`
	MediaType             string                `json:"mediaType"`
	ConfigurationArtifact ProductUpdateArtifact `json:"configurationArtifact"`
}

// ProductUpdateLayerRollbackPlan declares whether the selected update layer
// has a rollback artifact; it is desired input, not rollback execution fact.
type ProductUpdateLayerRollbackPlan struct {
	State    string                 `json:"state"`
	Artifact *ProductUpdateArtifact `json:"artifact,omitempty"`
	Reason   string                 `json:"reason,omitempty"`
}

// ProductUpdateLayerPlan is the ordered desired work declaration for one
// C26 product-update layer.
type ProductUpdateLayerPlan struct {
	Layer          string                           `json:"layer"`
	DependsOn      []string                         `json:"dependsOn"`
	Artifact       ProductUpdateArtifact            `json:"artifact"`
	EffectExecutor ProductUpdateLayerEffectExecutor `json:"effectExecutor"`
	Rollback       ProductUpdateLayerRollbackPlan   `json:"rollback"`
}

// ProductUpdateSpecification is C26.  It can evolve independently because it
// is parsed only by the staged next updater selected by C25.
type ProductUpdateSpecification struct {
	SchemaVersion       string                   `json:"schemaVersion"`
	ID                  string                   `json:"id"`
	BootstrapEnvelopeID string                   `json:"bootstrapEnvelopeId"`
	LayerPlan           []ProductUpdateLayerPlan `json:"layerPlan"`
}

// StagedProductUpdateInvocation is C30, the Host-to-next-updater local handoff input.
// It intentionally points to C26 rather than embedding it: the currently
// installed Host Agent never needs to decode the evolving specification.
type StagedProductUpdateInvocation struct {
	SchemaVersion                  string   `json:"schemaVersion"`
	UpdateID                       string   `json:"updateId"`
	RequestID                      string   `json:"requestId"`
	ExpectedHandoffJournalRevision int      `json:"expectedHandoffJournalRevision"`
	BootstrapEnvelopeID            string   `json:"bootstrapEnvelopeId"`
	UpdateSpecificationSHA256      string   `json:"updateSpecificationSha256"`
	LayerOrder                     []string `json:"layerOrder"`
	SpecificationRelativePath      string   `json:"specificationRelativePath"`
}

// StagedProductUpdatePlanningInput joins the verified C30 handoff with the C26
// bytes read by the next-updater adapter. It is complete explicit input to
// pure planning policy.
type StagedProductUpdatePlanningInput struct {
	Invocation    StagedProductUpdateInvocation
	Specification ProductUpdateSpecification
}

// StagedProductUpdateExecutionPlan is the pure execution decision derived
// from one C30 handoff and its verified C26 specification.
type StagedProductUpdateExecutionPlan struct {
	SchemaVersion string                   `json:"schemaVersion"`
	UpdateID      string                   `json:"updateId"`
	LayerPlan     []ProductUpdateLayerPlan `json:"layerPlan"`
}

func validLayer(layer string) bool {
	switch layer {
	case ProductUpdateLayerContainer, ProductUpdateLayerGuestRuntime, ProductUpdateLayerHostPlatform:
		return true
	default:
		return false
	}
}

func validateProductUpdateArtifact(artifact ProductUpdateArtifact) error {
	if artifact.ID == "" || artifact.RelativePath == "" || artifact.SizeBytes < 1 || artifact.MediaType == "" || !sha256Pattern.MatchString(artifact.SHA256) {
		return fmt.Errorf("layer artifact identity, digest, size, and media type are required")
	}
	if len(artifact.RelativePath) < len("payload/") || artifact.RelativePath[:len("payload/")] != "payload/" || containsTraversal(artifact.RelativePath) {
		return fmt.Errorf("layer artifact relativePath must stay below payload/ without traversal")
	}
	return nil
}

func validateProductUpdateLayerEffectExecutor(executor ProductUpdateLayerEffectExecutor, artifact ProductUpdateArtifact, rollback ProductUpdateLayerRollbackPlan) error {
	if executor.ID == "" || executor.RelativePath == "" || executor.SizeBytes < 1 || executor.MediaType != "application/vnd.tirosh.vitalserver.update-layer-effect-executor" || !sha256Pattern.MatchString(executor.SHA256) {
		return fmt.Errorf("layer effect executor identity, digest, size, and media type are required")
	}
	if len(executor.RelativePath) < len("payload/") || executor.RelativePath[:len("payload/")] != "payload/" || containsTraversal(executor.RelativePath) {
		return fmt.Errorf("layer effect executor relativePath must stay below payload/ without traversal")
	}
	if executor.ID == artifact.ID || executor.RelativePath == artifact.RelativePath || executor.SHA256 == artifact.SHA256 {
		return fmt.Errorf("layer effect executor must be distinct from the applied artifact")
	}
	if err := validateProductUpdateArtifact(executor.ConfigurationArtifact); err != nil || executor.ConfigurationArtifact.MediaType != "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json" {
		return fmt.Errorf("layer effect executor configuration artifact identity, digest, size, and media type are required")
	}
	if executor.ConfigurationArtifact.ID == executor.ID || executor.ConfigurationArtifact.RelativePath == executor.RelativePath || executor.ConfigurationArtifact.SHA256 == executor.SHA256 || executor.ConfigurationArtifact.ID == artifact.ID || executor.ConfigurationArtifact.RelativePath == artifact.RelativePath || executor.ConfigurationArtifact.SHA256 == artifact.SHA256 {
		return fmt.Errorf("layer effect executor configuration artifact must be distinct from the executor and applied artifact")
	}
	if rollback.State == "available" && (executor.ID == rollback.Artifact.ID || executor.RelativePath == rollback.Artifact.RelativePath || executor.SHA256 == rollback.Artifact.SHA256) {
		return fmt.Errorf("layer effect executor must be distinct from the rollback artifact")
	}
	if rollback.State == "available" && (executor.ConfigurationArtifact.ID == rollback.Artifact.ID || executor.ConfigurationArtifact.RelativePath == rollback.Artifact.RelativePath || executor.ConfigurationArtifact.SHA256 == rollback.Artifact.SHA256) {
		return fmt.Errorf("layer effect executor configuration artifact must be distinct from the rollback artifact")
	}
	return nil
}

func containsTraversal(path string) bool {
	for _, runeValue := range path {
		if runeValue == '\\' {
			return true
		}
	}
	for index := 0; index+1 < len(path); index++ {
		if path[index:index+2] == ".." {
			return true
		}
	}
	return false
}

func validateProductUpdateLayerRollbackPlan(plan ProductUpdateLayerRollbackPlan) error {
	switch plan.State {
	case "available":
		if plan.Artifact == nil || plan.Reason != "" {
			return fmt.Errorf("available rollback requires an artifact and no reason")
		}
		return validateProductUpdateArtifact(*plan.Artifact)
	case "unsupported":
		if plan.Artifact != nil || plan.Reason == "" {
			return fmt.Errorf("unsupported rollback requires a reason and no artifact")
		}
		return nil
	default:
		return fmt.Errorf("rollback state is unsupported")
	}
}

// PlanStagedProductUpdateExecution validates the explicit list order rather than sorting it. A future
// updater may add steps inside a layer, but the bootstrap-declared layer order
// remains the cross-updater safety boundary.
func PlanStagedProductUpdateExecution(input StagedProductUpdatePlanningInput) (StagedProductUpdateExecutionPlan, error) {
	invocation := input.Invocation
	if invocation.SchemaVersion != HostUpdaterDocumentSchemaVersion || !validIdentifier(invocation.UpdateID) || !validIdentifier(invocation.RequestID) || invocation.ExpectedHandoffJournalRevision < 1 || !validIdentifier(invocation.BootstrapEnvelopeID) || !sha256Pattern.MatchString(invocation.UpdateSpecificationSHA256) {
		return StagedProductUpdateExecutionPlan{}, fmt.Errorf("staged product update invocation identity is invalid")
	}
	if len(invocation.LayerOrder) == 0 || !validStagedSpecificationPath(invocation.SpecificationRelativePath) {
		return StagedProductUpdateExecutionPlan{}, fmt.Errorf("staged product update invocation layer order or specification path is invalid")
	}
	specification := input.Specification
	if specification.SchemaVersion != HostUpdaterDocumentSchemaVersion || specification.ID == "" || specification.BootstrapEnvelopeID != invocation.BootstrapEnvelopeID {
		return StagedProductUpdateExecutionPlan{}, fmt.Errorf("product update specification does not match the bootstrap envelope")
	}
	if len(invocation.LayerOrder) == 0 || len(specification.LayerPlan) != len(invocation.LayerOrder) {
		return StagedProductUpdateExecutionPlan{}, fmt.Errorf("product update specification must cover the bootstrap-declared layers exactly")
	}
	seen := map[string]bool{}
	for index, layer := range specification.LayerPlan {
		if layer.Layer != invocation.LayerOrder[index] || !validLayer(layer.Layer) || seen[layer.Layer] {
			return StagedProductUpdateExecutionPlan{}, fmt.Errorf("product update layer plan must preserve the bootstrap layer order")
		}
		seen[layer.Layer] = true
		if layer.Layer == ProductUpdateLayerHostPlatform && index != len(specification.LayerPlan)-1 {
			return StagedProductUpdateExecutionPlan{}, fmt.Errorf("host-platform must be the final layer after updater handoff")
		}
		if err := validateProductUpdateArtifact(layer.Artifact); err != nil {
			return StagedProductUpdateExecutionPlan{}, err
		}
		if err := validateProductUpdateLayerRollbackPlan(layer.Rollback); err != nil {
			return StagedProductUpdateExecutionPlan{}, err
		}
		if err := validateProductUpdateLayerEffectExecutor(layer.EffectExecutor, layer.Artifact, layer.Rollback); err != nil {
			return StagedProductUpdateExecutionPlan{}, err
		}
		for _, dependency := range layer.DependsOn {
			if !seen[dependency] {
				return StagedProductUpdateExecutionPlan{}, fmt.Errorf("product update layer dependency %q must appear before its dependent layer", dependency)
			}
		}
	}
	return StagedProductUpdateExecutionPlan{SchemaVersion: HostUpdaterDocumentSchemaVersion, UpdateID: invocation.UpdateID, LayerPlan: specification.LayerPlan}, nil
}

func validIdentifier(value string) bool {
	return identifierPattern.MatchString(value) && len(value) <= 128
}

func validStagedSpecificationPath(path string) bool {
	if len(path) < len("payload/a") || path[:len("payload/")] != "payload/" || containsTraversal(path) {
		return false
	}
	return true
}
