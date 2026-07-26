package vitalserverindexedlibrary

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestDeferredVitalServerIndexedLibraryArchiveProviderTurnsMissingC51IntoKnownFailedStep(t *testing.T) {
	root := t.TempDir()
	configurationPath := filepath.Join(root, "external-vitalserver-delivery.json")
	writeExternalVitalServerDeliveryConfiguration(t, configurationPath)
	provider := NewDeferredVitalServerIndexedLibraryHTTPArchiveExportProvider(
		ExternalVitalServerDeliveryConfigurationKind,
		configurationPath,
		filepath.Join(root, "secrets", "library-primary.json"),
		guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "library-primary", CapabilityRevision: 1},
	)

	step, err := provider.UploadArtifactExportPayload(context.Background(), guestruntimedomain.ArtifactManifest{}, nil, "2026-07-19T00:00:00Z")
	if err != nil {
		t.Fatalf("missing C51 must be a known Archive effect failure, not an unknown error: %v", err)
	}
	if step.State != "failed" || step.Issue == nil || step.Issue.Code != "archive-provider-credential-material-unavailable" {
		t.Fatalf("missing C51 export step = %#v", step)
	}
}
