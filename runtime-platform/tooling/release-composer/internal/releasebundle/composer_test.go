package releasebundle

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeCompositionJSON(t *testing.T, path string, composition ReleaseBundleComposition) {
	t.Helper()
	contents, err := json.Marshal(composition)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
}

func releaseBundleFixture(t *testing.T) (ComposeReleaseBundleRequest, ReleaseBundleComposition, ed25519.PublicKey, string) {
	t.Helper()
	root := t.TempDir()
	payloadDirectory := filepath.Join(root, "payload-source")
	outputDirectory := filepath.Join(root, "bundles")
	if err := os.Mkdir(payloadDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(outputDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(payloadDirectory, "host-updater"), []byte("host-updater-020"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(payloadDirectory, "product-update.json"), []byte("{\"schemaVersion\":\"v1\"}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(payloadDirectory, "guest-runtime.tar"), []byte("guest-runtime-020"), 0o600); err != nil {
		t.Fatal(err)
	}
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	privateKeyPath := filepath.Join(root, "release-key.base64")
	if err := os.WriteFile(privateKeyPath, []byte(base64.StdEncoding.EncodeToString(privateKey)), 0o600); err != nil {
		t.Fatal(err)
	}
	trustStorePath := filepath.Join(root, "update-trust-store.json")
	trustStore := hostUpdateTrustStore{
		SchemaVersion: "v1",
		Keys: []trustedUpdateKey{{
			ID: "release-key-2026", Algorithm: "ed25519",
			PublicKey: base64.StdEncoding.EncodeToString(publicKey),
		}},
	}
	trustStoreBytes, err := json.Marshal(trustStore)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(trustStorePath, trustStoreBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	composition := ReleaseBundleComposition{SchemaVersion: "v1", BundleID: "release-bundle-020", ProductID: "vitalserver-runtime-platform", Target: UpdateTarget{Platform: "macos", Architecture: "arm64"}, TargetRelease: TargetRelease{ProductVersion: "0.2.0", RuntimeVersion: "0.2.0"}, LayerOrder: []string{"guest-runtime", "container", "host-platform"}, NextUpdater: ReleaseArtifactDeclaration{ID: "host-updater-020", RelativePath: "payload/host-updater", MediaType: "application/octet-stream"}, Specification: ReleaseArtifactDeclaration{ID: "product-update-020", RelativePath: "payload/product-update.json", MediaType: "application/json"}, SigningKeyID: "release-key-2026", IssuedAt: "2026-07-17T00:00:00Z"}
	compositionPath := filepath.Join(root, "release-bundle-composition.json")
	writeCompositionJSON(t, compositionPath, composition)
	return ComposeReleaseBundleRequest{
		CompositionPath: compositionPath, PayloadDirectory: payloadDirectory,
		PrivateKeyPath: privateKeyPath, TrustStorePath: trustStorePath,
		OutputDirectory: outputDirectory,
	}, composition, publicKey, root
}

func TestComposeReleaseBundleCreatesVerifiedDeterministicC25Bundle(t *testing.T) {
	request, composition, publicKey, root := releaseBundleFixture(t)
	first, err := ComposeReleaseBundle(request)
	if err != nil {
		t.Fatalf("compose first bundle: %v", err)
	}
	if first.Envelope.ID != composition.BundleID || first.Envelope.NextUpdaterArtifact.SizeBytes == 0 || len(first.ContentManifest.Files) != 3 {
		t.Fatalf("unexpected signed bundle=%+v", first)
	}
	payload, err := canonicalSignedEnvelope(first.Envelope)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(payload)
	if first.Envelope.Signature.SignedSHA256 != sha256Hex(digest[:]) || !ed25519.Verify(publicKey, payload, mustDecodeSignature(t, first.Envelope.Signature.Value)) {
		t.Fatalf("C25 signature cannot be verified")
	}
	if _, err := os.Stat(filepath.Join(first.BundleDirectory, "payload", "guest-runtime.tar")); err != nil {
		t.Fatalf("complete payload was not composed: %v", err)
	}
	secondOutput := filepath.Join(root, "bundles-second")
	if err := os.Mkdir(secondOutput, 0o700); err != nil {
		t.Fatal(err)
	}
	request.OutputDirectory = secondOutput
	second, err := ComposeReleaseBundle(request)
	if err != nil {
		t.Fatalf("compose second bundle: %v", err)
	}
	for _, file := range []string{"bootstrap-envelope.json", "bundle-content-manifest.json"} {
		firstBytes, firstErr := os.ReadFile(filepath.Join(first.BundleDirectory, file))
		secondBytes, secondErr := os.ReadFile(filepath.Join(second.BundleDirectory, file))
		if firstErr != nil || secondErr != nil || string(firstBytes) != string(secondBytes) {
			t.Fatalf("%s is not deterministic firstErr=%v secondErr=%v", file, firstErr, secondErr)
		}
	}
}

func TestComposeReleaseBundleRejectsPayloadTraversal(t *testing.T) {
	request, composition, _, _ := releaseBundleFixture(t)
	composition.NextUpdater.RelativePath = "payload/../release-key.base64"
	writeCompositionJSON(t, request.CompositionPath, composition)
	if _, err := ComposeReleaseBundle(request); err == nil {
		t.Fatal("expected unsafe release artifact path to be rejected")
	}
}

func TestComposeReleaseBundleRejectsSigningKeyNotProvisionedForHosts(t *testing.T) {
	request, _, _, root := releaseBundleFixture(t)
	otherPublicKey, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	contents, err := json.Marshal(hostUpdateTrustStore{
		SchemaVersion: "v1",
		Keys: []trustedUpdateKey{{
			ID: "release-key-2026", Algorithm: "ed25519",
			PublicKey: base64.StdEncoding.EncodeToString(otherPublicKey),
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	request.TrustStorePath = filepath.Join(root, "mismatched-trust-store.json")
	if err := os.WriteFile(request.TrustStorePath, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ComposeReleaseBundle(request); err == nil {
		t.Fatal("expected unprovisioned signing key to be rejected")
	}
}

func mustDecodeSignature(t *testing.T, encoded string) []byte {
	t.Helper()
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}

func sha256Hex(value []byte) string {
	const digits = "0123456789abcdef"
	encoded := make([]byte, len(value)*2)
	for index, byteValue := range value {
		encoded[index*2] = digits[byteValue>>4]
		encoded[index*2+1] = digits[byteValue&0x0f]
	}
	return string(encoded)
}
