package vitalserverindexedlibrary

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider keeps the
// explicitly selected C44 or C46 composition separate from C51 availability.
// Guest Runtime can therefore
// start and expose the OS-local secret-owner contract before a credential has
// been provisioned. Each Archive effect opens the current private material
// explicitly; an unavailable C51 becomes a known failed export step, never a
// fabricated upload success or an unknown external-call result.
type DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider struct {
	vitalServerConfigurationKind string
	vitalServerConfigurationPath string
	credentialMaterialPath       string
	reference                    guestruntimedomain.ArchiveProviderReference
}

func NewDeferredVitalServerIndexedLibraryHTTPArchiveExportProvider(
	vitalServerConfigurationKind string,
	vitalServerConfigurationPath string,
	credentialMaterialPath string,
	reference guestruntimedomain.ArchiveProviderReference,
) *DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider {
	return &DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider{
		vitalServerConfigurationKind: vitalServerConfigurationKind,
		vitalServerConfigurationPath: vitalServerConfigurationPath,
		credentialMaterialPath:       credentialMaterialPath,
		reference:                    reference,
	}
}

func (provider *DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider) ArchiveExportProviderReference() guestruntimedomain.ArchiveProviderReference {
	return provider.reference
}

func (provider *DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider) UploadArtifactExportPayload(ctx context.Context, manifest guestruntimedomain.ArtifactManifest, payload []byte, completedAt string) (guestruntimedomain.ExportStep, error) {
	delegate, issue := provider.openDelegate()
	if issue != nil {
		return guestruntimedomain.FailedExportStep(completedAt, *issue), nil
	}
	return delegate.UploadArtifactExportPayload(ctx, manifest, payload, completedAt)
}

func (provider *DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider) VerifyUploadedArtifactIndex(ctx context.Context, manifest guestruntimedomain.ArtifactManifest, upload guestruntimedomain.ExportStep, completedAt string) (guestruntimedomain.ExportStep, error) {
	delegate, issue := provider.openDelegate()
	if issue != nil {
		return guestruntimedomain.FailedExportStep(completedAt, *issue), nil
	}
	return delegate.VerifyUploadedArtifactIndex(ctx, manifest, upload, completedAt)
}

func (provider *DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider) openDelegate() (*VitalServerIndexedLibraryHTTPArchiveExportProvider, *guestruntimedomain.Issue) {
	delegate, err := OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(
		provider.vitalServerConfigurationKind,
		provider.vitalServerConfigurationPath,
		provider.credentialMaterialPath,
		provider.reference,
	)
	if err == nil {
		return delegate, nil
	}
	retryable := true
	return nil, &guestruntimedomain.Issue{
		Code:       "archive-provider-credential-material-unavailable",
		Message:    "VitalServer indexed-library archive provider is unavailable because its private credential material is not ready",
		Retryable:  &retryable,
		Dependency: provider.reference.ID,
	}
}

var _ guestruntimeapplication.GuestRuntimeArchiveExportProvider = (*DeferredVitalServerIndexedLibraryHTTPArchiveExportProvider)(nil)
