// Package archiveprovider adapts an explicitly configured Archive provider
// outcome to the Archive Export port. It does not pretend to be a VitalServer
// upload adapter; a selected bundled-image adapter replaces this test/deployment
// adapter only after its image and proxy proof exists.
package archiveprovider

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const (
	ModeSucceed              = "succeed"
	ModeUploadFailed         = "upload-failed"
	ModeIndexFailed          = "index-failed"
	ModeUploadOutcomeUnknown = "upload-outcome-unknown"
	ModeIndexOutcomeUnknown  = "index-outcome-unknown"
)

// ConfiguredArchiveExportOutcomeProfile returns preconfigured, explicit
// test/deployment outcomes. The two
// *outcome-unknown modes model an interrupted external call: Archive keeps its
// operation running and deliberately writes no guessed terminal receipt.
type ConfiguredArchiveExportOutcomeProfile struct {
	reference guestruntimedomain.ArchiveProviderReference
	mode      string
}

func NewConfiguredArchiveExportOutcomeProfile(reference guestruntimedomain.ArchiveProviderReference, mode string) (*ConfiguredArchiveExportOutcomeProfile, error) {
	if !guestruntimedomain.ValidIdentifier(reference.Kind) || !guestruntimedomain.ValidIdentifier(reference.ID) || reference.CapabilityRevision < 1 {
		return nil, fmt.Errorf("Archive provider reference must be explicit and valid")
	}
	switch mode {
	case ModeSucceed, ModeUploadFailed, ModeIndexFailed, ModeUploadOutcomeUnknown, ModeIndexOutcomeUnknown:
	default:
		return nil, fmt.Errorf("unsupported Archive provider mode %q", mode)
	}
	return &ConfiguredArchiveExportOutcomeProfile{reference: reference, mode: mode}, nil
}

func (provider *ConfiguredArchiveExportOutcomeProfile) ArchiveExportProviderReference() guestruntimedomain.ArchiveProviderReference {
	return provider.reference
}

func (provider *ConfiguredArchiveExportOutcomeProfile) UploadArtifactExportPayload(_ context.Context, manifest guestruntimedomain.ArtifactManifest, payload []byte, completedAt string) (guestruntimedomain.ExportStep, error) {
	if len(payload) == 0 || manifest.Artifact.ArtifactID == "" {
		return guestruntimedomain.ExportStep{}, fmt.Errorf("Archive provider received an invalid finalized artifact")
	}
	switch provider.mode {
	case ModeUploadOutcomeUnknown:
		return guestruntimedomain.ExportStep{}, fmt.Errorf("configured Archive upload outcome is unknown")
	case ModeUploadFailed:
		retryable := true
		return guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{Code: "archive-provider-upload-failed", Message: "configured Archive provider rejected artifact upload", Retryable: &retryable, Dependency: provider.reference.ID}), nil
	default:
		return guestruntimedomain.SucceededExportStep("upload-"+manifest.Artifact.ArtifactID, completedAt), nil
	}
}

func (provider *ConfiguredArchiveExportOutcomeProfile) VerifyUploadedArtifactIndex(_ context.Context, manifest guestruntimedomain.ArtifactManifest, upload guestruntimedomain.ExportStep, completedAt string) (guestruntimedomain.ExportStep, error) {
	if upload.State != "succeeded" || manifest.Artifact.ArtifactID == "" {
		return guestruntimedomain.ExportStep{}, fmt.Errorf("Archive index verification requires a succeeded upload")
	}
	switch provider.mode {
	case ModeIndexOutcomeUnknown:
		return guestruntimedomain.ExportStep{}, fmt.Errorf("configured Archive index outcome is unknown")
	case ModeIndexFailed:
		retryable := true
		return guestruntimedomain.FailedExportStep(completedAt, guestruntimedomain.Issue{Code: "archive-provider-index-failed", Message: "configured Archive provider did not index uploaded artifact", Retryable: &retryable, Dependency: provider.reference.ID}), nil
	default:
		return guestruntimedomain.SucceededExportStep("index-"+manifest.Artifact.ArtifactID, completedAt), nil
	}
}

var _ guestruntimeapplication.GuestRuntimeArchiveExportProvider = (*ConfiguredArchiveExportOutcomeProfile)(nil)
