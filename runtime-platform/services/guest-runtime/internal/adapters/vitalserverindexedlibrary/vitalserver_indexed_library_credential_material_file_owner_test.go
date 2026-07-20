package vitalserverindexedlibrary

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestCredentialMaterialFileOwnerMakesMissingMaterialExplicitThenAtomicallyProvisionsPrivateMaterial(t *testing.T) {
	root := t.TempDir()
	configurationPath := filepath.Join(root, "external-vitalserver-delivery.json")
	writeCredentialOwnerExternalDeliveryConfiguration(t, configurationPath)
	privateDirectory := filepath.Join(root, "secrets")
	credentialPath := filepath.Join(privateDirectory, "external-library.json")
	owner, err := newVitalServerIndexedLibraryCredentialMaterialFileOwner(
		ExternalVitalServerDeliveryConfigurationKind,
		configurationPath,
		credentialPath,
		guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "external-library", CapabilityRevision: 1},
		privateDirectory,
	)
	if err != nil {
		t.Fatalf("compose credential material owner: %v", err)
	}
	state, issue := owner.ObserveVitalServerIndexedLibraryCredentialMaterial(context.Background())
	if state != "missing" || issue == nil || issue.Code != "credential-material-missing" {
		t.Fatalf("missing material observation = state %q issue %#v", state, issue)
	}

	provisionIssue := owner.ProvisionVitalServerIndexedLibraryCredentialMaterial(context.Background(), guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial{
		SchemaVersion:       "v1",
		CredentialReference: guestruntimedomain.VitalServerIndexedLibraryCredentialReference{Kind: "vitalserver-library-credential", ID: "external-library"},
		UserID:              "operator",
		Password:            "test-only-password",
	})
	if provisionIssue != nil {
		t.Fatalf("provision credential material: %#v", provisionIssue)
	}
	state, issue = owner.ObserveVitalServerIndexedLibraryCredentialMaterial(context.Background())
	if state != "available" || issue != nil {
		t.Fatalf("provisioned material observation = state %q issue %#v", state, issue)
	}
	fileInfo, err := os.Lstat(credentialPath)
	if err != nil {
		t.Fatalf("stat provisioned material: %v", err)
	}
	if !fileInfo.Mode().IsRegular() || fileInfo.Mode().Perm() != 0o600 {
		t.Fatalf("credential material mode = %v, want private regular 0600", fileInfo.Mode())
	}
	directoryInfo, err := os.Lstat(privateDirectory)
	if err != nil {
		t.Fatalf("stat private directory: %v", err)
	}
	if !directoryInfo.IsDir() || directoryInfo.Mode().Perm() != 0o700 {
		t.Fatalf("private directory mode = %v, want 0700", directoryInfo.Mode())
	}
}

func TestCredentialMaterialFileOwnerRejectsAReferenceThatDoesNotMatchC46WithoutCreatingMaterial(t *testing.T) {
	root := t.TempDir()
	configurationPath := filepath.Join(root, "external-vitalserver-delivery.json")
	writeCredentialOwnerExternalDeliveryConfiguration(t, configurationPath)
	privateDirectory := filepath.Join(root, "secrets")
	credentialPath := filepath.Join(privateDirectory, "external-library.json")
	owner, err := newVitalServerIndexedLibraryCredentialMaterialFileOwner(
		ExternalVitalServerDeliveryConfigurationKind,
		configurationPath,
		credentialPath,
		guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "external-library", CapabilityRevision: 1},
		privateDirectory,
	)
	if err != nil {
		t.Fatalf("compose credential material owner: %v", err)
	}
	issue := owner.ProvisionVitalServerIndexedLibraryCredentialMaterial(context.Background(), guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial{
		SchemaVersion:       "v1",
		CredentialReference: guestruntimedomain.VitalServerIndexedLibraryCredentialReference{Kind: "vitalserver-library-credential", ID: "another-library"},
		UserID:              "operator",
		Password:            "test-only-password",
	})
	if issue == nil || issue.Code != "credential-reference-mismatch" {
		t.Fatalf("mismatched credential provision issue = %#v", issue)
	}
	if _, statErr := os.Lstat(credentialPath); !os.IsNotExist(statErr) {
		t.Fatalf("mismatched material created a file: %v", statErr)
	}
}

func writeCredentialOwnerExternalDeliveryConfiguration(t *testing.T, path string) {
	t.Helper()
	contents := []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"external-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"external-library"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}`)
	if err := os.WriteFile(path, contents, 0o644); err != nil {
		t.Fatalf("write C46 configuration: %v", err)
	}
}
