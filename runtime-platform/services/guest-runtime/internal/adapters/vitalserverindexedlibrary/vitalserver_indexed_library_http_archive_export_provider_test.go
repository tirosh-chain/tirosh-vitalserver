package vitalserverindexedlibrary

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestVitalServerIndexedLibraryHTTPArchiveExportProviderSeparatesUploadAndIndexedLibraryEvidence(t *testing.T) {
	manifest, payload := testArtifactManifest(t)
	var uploaded bool
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/upload":
			if request.Method != http.MethodPost {
				t.Errorf("upload method = %s, want POST", request.Method)
			}
			mediaType, parameters, err := mime.ParseMediaType(request.Header.Get("Content-Type"))
			if err != nil || mediaType != "multipart/form-data" {
				t.Errorf("upload Content-Type = %q, want multipart/form-data", request.Header.Get("Content-Type"))
			}
			reader := multipart.NewReader(request.Body, parameters["boundary"])
			part, err := reader.NextPart()
			if err != nil {
				t.Fatalf("read upload form file: %v", err)
			}
			if part.FormName() != "vitalfile" || part.FileName() != manifest.Artifact.ArtifactID+".vital" {
				t.Errorf("upload form file = (%q, %q)", part.FormName(), part.FileName())
			}
			actual, err := io.ReadAll(part)
			if err != nil || !bytes.Equal(actual, payload) {
				t.Errorf("upload payload differs: error=%v", err)
			}
			uploaded = true
			_, _ = response.Write([]byte("success"))
		case "/api/login":
			if request.Method != http.MethodPost {
				t.Errorf("login method = %s, want POST", request.Method)
			}
			if err := request.ParseForm(); err != nil || request.Form.Get("id") != "archive-admin" || request.Form.Get("pw") != "not-logged" {
				t.Errorf("login form invalid: error=%v form=%v", err, request.Form)
			}
			_ = json.NewEncoder(response).Encode(map[string]any{"res": true, "access_token": "archive-token"})
		case "/api/filelist":
			if request.Method != http.MethodGet || request.URL.Query().Get("access_token") != "archive-token" || request.URL.Query().Get("unixtimestamp") != "1" {
				t.Errorf("file list request is invalid: %s %s", request.Method, request.URL.String())
			}
			response.Header().Set("Content-Type", "application/gzip")
			writer := gzip.NewWriter(response)
			_ = json.NewEncoder(writer).Encode([]map[string]string{{"filename": manifest.Artifact.ArtifactID + ".vital"}})
			_ = writer.Close()
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	provider := testProvider(t, server.URL)
	upload, err := provider.UploadArtifactExportPayload(context.Background(), manifest, payload, "2026-07-20T00:00:00Z")
	if err != nil || upload.State != "succeeded" || upload.ReceiptID != vitalServerUploadReceiptID(manifest) || !uploaded {
		t.Fatalf("upload = %+v error=%v uploaded=%t", upload, err, uploaded)
	}
	index, err := provider.VerifyUploadedArtifactIndex(context.Background(), manifest, upload, "2026-07-20T00:00:01Z")
	if err != nil || index.State != "succeeded" || index.ReceiptID != vitalServerIndexReceiptID(manifest) {
		t.Fatalf("index = %+v error=%v", index, err)
	}
}

func TestVitalServerIndexedLibraryHTTPArchiveExportProviderKeepsUploadSuccessDistinctFromMissingIndex(t *testing.T) {
	manifest, payload := testArtifactManifest(t)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/upload":
			_, _ = response.Write([]byte("success"))
		case "/api/login":
			_ = json.NewEncoder(response).Encode(map[string]any{"res": true, "access_token": "archive-token"})
		case "/api/filelist":
			writer := gzip.NewWriter(response)
			_ = json.NewEncoder(writer).Encode([]map[string]string{})
			_ = writer.Close()
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	provider := testProvider(t, server.URL)
	upload, err := provider.UploadArtifactExportPayload(context.Background(), manifest, payload, "2026-07-20T00:00:00Z")
	if err != nil || upload.State != "succeeded" {
		t.Fatalf("upload = %+v error=%v", upload, err)
	}
	index, err := provider.VerifyUploadedArtifactIndex(context.Background(), manifest, upload, "2026-07-20T00:00:01Z")
	if err != nil || index.State != "failed" || index.Issue == nil || index.Issue.Code != "vitalserver-indexed-library-artifact-not-indexed" || index.Issue.Retryable == nil || !*index.Issue.Retryable {
		t.Fatalf("index = %+v error=%v", index, err)
	}
}

func TestVitalServerIndexedLibraryHTTPArchiveExportProviderRejectsImplicitOrUnsafeConfiguration(t *testing.T) {
	reference := guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "bundled-vitalserver-library", CapabilityRevision: 1}
	for _, configuration := range []VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration{
		{Reference: reference, Endpoint: "http://127.0.0.1:8080/path", Credentials: VitalServerIndexedLibraryCredentials{UserID: "archive-admin", Password: "not-logged"}, RequestTimeout: time.Second},
		{Reference: reference, Endpoint: "https://archive.example.test", Credentials: VitalServerIndexedLibraryCredentials{}, RequestTimeout: time.Second},
		{Reference: reference, Endpoint: "https://archive.example.test", Credentials: VitalServerIndexedLibraryCredentials{UserID: "archive-admin", Password: "not-logged"}, RequestTimeout: 0},
	} {
		if _, err := NewVitalServerIndexedLibraryHTTPArchiveExportProvider(configuration); err == nil {
			t.Fatal("unsafe or incomplete VitalServer indexed-library configuration unexpectedly succeeded")
		}
	}
}

func TestOpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFilesRequiresMatchingPrivateMaterial(t *testing.T) {
	root := t.TempDir()
	configurationPath := filepath.Join(root, "external-vitalserver-delivery.json")
	credentialPath := filepath.Join(root, "archive-credential.json")
	writeExternalVitalServerDeliveryConfiguration(t, configurationPath)
	if err := os.WriteFile(credentialPath, []byte(`{"schemaVersion":"v1","credentialReference":{"kind":"vitalserver-library-credential","id":"library-primary"},"userId":"archive-admin","password":"private-password"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	reference := guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "library-primary", CapabilityRevision: 1}
	provider, err := OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(ExternalVitalServerDeliveryConfigurationKind, configurationPath, credentialPath, reference)
	if err != nil {
		t.Fatalf("open configured provider: %v", err)
	}
	if provider.ArchiveExportProviderReference() != reference {
		t.Fatalf("configured provider reference = %+v", provider.ArchiveExportProviderReference())
	}

	if err := os.Chmod(credentialPath, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(ExternalVitalServerDeliveryConfigurationKind, configurationPath, credentialPath, reference); err == nil {
		t.Fatal("world-readable credential material unexpectedly configured the provider")
	}
}

func TestOpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFilesAcceptsOnlyExplicitBundledC44LoopbackConfiguration(t *testing.T) {
	root := t.TempDir()
	configurationPath := filepath.Join(root, "bundled-vitalserver-topology.json")
	credentialPath := filepath.Join(root, "archive-credential.json")
	writeBundledVitalServerTopologyDeployment(t, configurationPath)
	if err := os.WriteFile(credentialPath, []byte(`{"schemaVersion":"v1","credentialReference":{"kind":"vitalserver-library-credential","id":"bundled-library"},"userId":"archive-admin","password":"private-password"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	reference := guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "bundled-library", CapabilityRevision: 1}
	provider, err := OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(BundledVitalServerTopologyDeploymentKind, configurationPath, credentialPath, reference)
	if err != nil {
		t.Fatalf("open explicit bundled C44 provider: %v", err)
	}
	if provider.endpoint.String() != "http://127.0.0.1:18300" {
		t.Fatalf("bundled C44 endpoint = %s", provider.endpoint.String())
	}
	if _, err := OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(ExternalVitalServerDeliveryConfigurationKind, configurationPath, credentialPath, reference); err == nil {
		t.Fatal("C44 topology was accepted as an external C46 configuration")
	}
}

func writeExternalVitalServerDeliveryConfiguration(t *testing.T, path string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"library-primary","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"https","host":"external-vitalserver.example.test","port":443},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"library-primary"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}`), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeBundledVitalServerTopologyDeployment(t *testing.T, path string) {
	t.Helper()
	contents := []byte(`{"schemaVersion":"v1","topologyDeploymentId":"bundled-vitalserver-primary","topologyKind":"bundled-vitalserver","vitalServerDeliveryProvider":{"kind":"bundled-vitalserver","id":"bundled-vitalserver-primary","capabilityRevision":1},"publicBrowserExposure":"not-exposed","bundledUpstreamImageSetDeployment":{"imageSetManagerConfigurationReference":{"resourceType":"guest-bundled-upstream-image-set-manager-configuration","resourceId":"bundled-image-set-manager"},"vitalServerPacketDeliveryEndpoint":{"scheme":"http","host":"127.0.0.1","port":18300},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"http","host":"127.0.0.1","port":18300,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"bundled-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"http","host":"127.0.0.1","port":18300},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"bundled-library"},"vitalServerArchiveRequestTimeoutMilliseconds":1000}}`)
	if err := os.WriteFile(path, contents, 0o644); err != nil {
		t.Fatal(err)
	}
}

func testProvider(t *testing.T, endpoint string) *VitalServerIndexedLibraryHTTPArchiveExportProvider {
	t.Helper()
	provider, err := NewVitalServerIndexedLibraryHTTPArchiveExportProvider(VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration{
		Reference:      guestruntimedomain.ArchiveProviderReference{Kind: "vitalserver-indexed-library", ID: "bundled-vitalserver-library", CapabilityRevision: 1},
		Endpoint:       endpoint,
		Credentials:    VitalServerIndexedLibraryCredentials{UserID: "archive-admin", Password: "not-logged"},
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("NewVitalServerIndexedLibraryHTTPArchiveExportProvider() error = %v", err)
	}
	return provider
}

func testArtifactManifest(t *testing.T) (guestruntimedomain.ArtifactManifest, []byte) {
	t.Helper()
	payload := []byte("formed-vital-artifact")
	digest := sha256.Sum256(payload)
	return guestruntimedomain.ArtifactManifest{
		SchemaVersion: "v1",
		ID:            "artifact-manifest-test-1",
		OperationID:   "guest-operation-test-1",
		Artifact: guestruntimedomain.ImmutableArtifact{
			ArtifactID: "artifact-test-1", Digest: hex.EncodeToString(digest[:]), ByteSize: len(payload), MediaType: "application/x-vital",
		},
	}, payload
}
