package updatetrust

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestProvisionRotateAndRevokePublisherTrust(t *testing.T) {
	root := t.TempDir()
	firstKey := writePublicKey(t, root, "first.key")
	provisionOutput := filepath.Join(root, "provisioned")
	provisioned, err := Transition(TransitionRequest{
		Action: "provision", TransitionID: "trust-provision-2026", KeyID: "release-key-2026",
		PublicKeyPath: firstKey, TransitionedAt: "2026-07-27T00:00:00Z", OutputDirectory: provisionOutput,
	})
	if err != nil {
		t.Fatalf("provision trust: %v", err)
	}
	if len(provisioned.TrustStore.Keys) != 1 || provisioned.Receipt.SourceTrustStoreSHA256 != nil {
		t.Fatalf("unexpected provision result=%+v", provisioned)
	}

	secondKey := writePublicKey(t, root, "second.key")
	rotationOutput := filepath.Join(root, "rotated")
	rotated, err := Transition(TransitionRequest{
		Action: "rotate", TransitionID: "trust-rotation-2027",
		SourceTrustStorePath: filepath.Join(provisionOutput, trustStoreFileName),
		ExpectedSourceSHA256: provisioned.Artifacts["trustStore"].SHA256,
		KeyID:                "release-key-2027", PublicKeyPath: secondKey,
		TransitionedAt: "2026-07-27T01:00:00Z", OutputDirectory: rotationOutput,
	})
	if err != nil {
		t.Fatalf("rotate trust: %v", err)
	}
	if len(rotated.TrustStore.Keys) != 2 || len(rotated.Receipt.RetainedKeyIDs) != 1 {
		t.Fatalf("rotation did not preserve overlap=%+v", rotated)
	}

	revocationOutput := filepath.Join(root, "revoked")
	revoked, err := Transition(TransitionRequest{
		Action: "revoke", TransitionID: "trust-revocation-2026",
		SourceTrustStorePath: filepath.Join(rotationOutput, trustStoreFileName),
		ExpectedSourceSHA256: rotated.Artifacts["trustStore"].SHA256,
		KeyID:                "release-key-2026", TransitionedAt: "2026-07-27T02:00:00Z",
		OutputDirectory: revocationOutput,
	})
	if err != nil {
		t.Fatalf("revoke trust: %v", err)
	}
	if len(revoked.TrustStore.Keys) != 1 || revoked.TrustStore.Keys[0].ID != "release-key-2027" {
		t.Fatalf("unexpected revoked result=%+v", revoked)
	}
	assertReceiptMatchesPublishedStore(t, revocationOutput)
}

func TestTrustTransitionsRejectUnsafeKeyChanges(t *testing.T) {
	root := t.TempDir()
	key := writePublicKey(t, root, "first.key")
	provisionOutput := filepath.Join(root, "provisioned")
	provisioned, err := Transition(TransitionRequest{
		Action: "provision", TransitionID: "trust-provision", KeyID: "release-key-2026",
		PublicKeyPath: key, TransitionedAt: "2026-07-27T00:00:00Z", OutputDirectory: provisionOutput,
	})
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(provisionOutput, trustStoreFileName)

	cases := []TransitionRequest{
		{Action: "rotate", TransitionID: "duplicate-id", SourceTrustStorePath: source, ExpectedSourceSHA256: provisioned.Artifacts["trustStore"].SHA256, KeyID: "release-key-2026", PublicKeyPath: writePublicKey(t, root, "other.key"), TransitionedAt: "2026-07-27T01:00:00Z", OutputDirectory: filepath.Join(root, "duplicate")},
		{Action: "rotate", TransitionID: "changed-source", SourceTrustStorePath: source, ExpectedSourceSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", KeyID: "release-key-2027", PublicKeyPath: writePublicKey(t, root, "third.key"), TransitionedAt: "2026-07-27T01:00:00Z", OutputDirectory: filepath.Join(root, "changed")},
		{Action: "revoke", TransitionID: "last-key", SourceTrustStorePath: source, ExpectedSourceSHA256: provisioned.Artifacts["trustStore"].SHA256, KeyID: "release-key-2026", TransitionedAt: "2026-07-27T01:00:00Z", OutputDirectory: filepath.Join(root, "empty")},
	}
	for _, request := range cases {
		if _, err := Transition(request); err == nil {
			t.Fatalf("expected transition %s to fail", request.TransitionID)
		}
	}
}

func TestTransitionRefusesExistingOutputDirectory(t *testing.T) {
	root := t.TempDir()
	output := filepath.Join(root, "existing")
	if err := os.Mkdir(output, 0o700); err != nil {
		t.Fatal(err)
	}
	_, err := Transition(TransitionRequest{
		Action: "provision", TransitionID: "trust-provision", KeyID: "release-key",
		PublicKeyPath: writePublicKey(t, root, "key"), TransitionedAt: "2026-07-27T00:00:00Z",
		OutputDirectory: output,
	})
	if err == nil {
		t.Fatal("expected existing output directory to be rejected")
	}
}

func writePublicKey(t *testing.T, directory string, name string) string {
	t.Helper()
	publicKey, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, name)
	if err := os.WriteFile(path, []byte(base64.StdEncoding.EncodeToString(publicKey)+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func assertReceiptMatchesPublishedStore(t *testing.T, output string) {
	t.Helper()
	storeBytes, err := os.ReadFile(filepath.Join(output, trustStoreFileName))
	if err != nil {
		t.Fatal(err)
	}
	receiptBytes, err := os.ReadFile(filepath.Join(output, transitionFileName))
	if err != nil {
		t.Fatal(err)
	}
	var receipt UpdatePublisherTrustTransitionReceipt
	if err := json.Unmarshal(receiptBytes, &receipt); err != nil {
		t.Fatal(err)
	}
	if receipt.ResultTrustStoreSHA256 != sha256Hex(storeBytes) {
		t.Fatalf("receipt trust digest mismatch")
	}
}
