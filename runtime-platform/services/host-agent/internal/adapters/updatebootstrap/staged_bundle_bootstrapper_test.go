package updatebootstrap

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type staticClock struct{ value time.Time }

func (clock staticClock) Now() time.Time { return clock.value }

func checksum(contents string) string {
	digest := sha256.Sum256([]byte(contents))
	return hex.EncodeToString(digest[:])
}

func writeJSON(t *testing.T, path string, value any) {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("encode JSON %s: %v", path, err)
	}
	if err := os.WriteFile(path, encoded, 0o600); err != nil {
		t.Fatalf("write JSON %s: %v", path, err)
	}
}

func stagedFixture(t *testing.T) (*StagedBundleBootstrapper, hostagentdomain.HostUpdateJournal, hostagentdomain.UpdateBootstrapEnvelope, string) {
	t.Helper()
	root := t.TempDir()
	bundleStore := filepath.Join(root, "bundles")
	stagingDirectory := filepath.Join(root, "staging")
	bundleDirectory := filepath.Join(bundleStore, "release-bundle-020")
	if err := os.MkdirAll(filepath.Join(bundleDirectory, "payload"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(stagingDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	updater := "host-updater-release-020"
	specification := "{\"schemaVersion\":\"v1\"}"
	if err := os.WriteFile(filepath.Join(bundleDirectory, "payload", "host-updater"), []byte(updater), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bundleDirectory, "payload", "product-update.json"), []byte(specification), 0o600); err != nil {
		t.Fatal(err)
	}
	envelope := hostagentdomain.UpdateBootstrapEnvelope{
		SchemaVersion: "v1", ID: "release-bootstrap-020", ProductID: "vitalserver-runtime-platform",
		Target:              hostagentdomain.UpdateTarget{Platform: "macos", Architecture: "arm64"},
		TargetRelease:       hostagentdomain.Release{ProductVersion: "0.2.0", RuntimeVersion: "0.2.0"},
		LayerOrder:          []string{hostagentdomain.UpdateLayerGuestRuntime, hostagentdomain.UpdateLayerContainer, hostagentdomain.UpdateLayerHostPlatform},
		NextUpdaterArtifact: hostagentdomain.UpdateArtifact{ID: "host-updater-020", RelativePath: "payload/host-updater", SHA256: checksum(updater), SizeBytes: int64(len(updater)), MediaType: "application/octet-stream"},
		Specification:       hostagentdomain.UpdateArtifact{ID: "product-update-020", RelativePath: "payload/product-update.json", SHA256: checksum(specification), SizeBytes: int64(len(specification)), MediaType: "application/json"},
		IssuedAt:            "2026-07-17T00:00:00Z",
	}
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	payload, err := canonicalSignedEnvelope(envelope)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(payload)
	envelope.Signature = hostagentdomain.UpdateSignature{Algorithm: "ed25519", KeyID: "release-key-2026", SignedSHA256: hex.EncodeToString(digest[:]), Value: base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, payload))}
	writeJSON(t, filepath.Join(bundleDirectory, bootstrapEnvelopeFile), envelope)
	trustStorePath := filepath.Join(root, "update-trust.json")
	writeJSON(t, trustStorePath, trustStore{SchemaVersion: "v1", Keys: []trustedUpdateKey{{ID: "release-key-2026", Algorithm: "ed25519", PublicKey: base64.StdEncoding.EncodeToString(publicKey)}}})
	bootstrapper, err := NewStagedBundleBootstrapper(StagedBundleBootstrapperConfig{BundleStoreDirectory: bundleStore, StagingDirectory: stagingDirectory, TrustStorePath: trustStorePath, Clock: staticClock{value: time.Date(2026, 7, 17, 0, 0, 0, 0, time.UTC)}})
	if err != nil {
		t.Fatalf("new staged bundle bootstrapper: %v", err)
	}
	command := hostagentdomain.HostUpdateCommand{SchemaVersion: "v1", RequestID: "update-request-020", InstallationID: "host-installation", ExpectedInstallationRevision: 1, BundleReferenceID: "release-bundle-020", BootstrapEnvelope: envelope}
	operation := hostagentdomain.NewHostUpdateOperation("operation-update-020", command, "2026-07-17T00:00:00Z", strings.Repeat("a", 64))
	journal := hostagentdomain.NewHostUpdateJournal("update-020", operation, command, "2026-07-17T00:00:00Z")
	return bootstrapper, journal, envelope, stagingDirectory
}

func TestFilesystemStagesVerifiedBundleAndPublishesIdempotentHandoff(t *testing.T) {
	bootstrapper, journal, envelope, stagingDirectory := stagedFixture(t)
	receipt := bootstrapper.Stage(context.Background(), journal, envelope)
	if receipt.State != "staged" || receipt.Issue != nil {
		t.Fatalf("stage receipt=%+v", receipt)
	}
	stage := filepath.Join(stagingDirectory, "updates", journal.ID)
	if _, err := os.Stat(filepath.Join(stage, stagedInvocationFile)); !os.IsNotExist(err) {
		t.Fatalf("C30 must not be created before the handoff journal commit: %v", err)
	}
	if err := verifySignedBootstrapArtifact(stage, envelope.NextUpdaterArtifact); err != nil {
		t.Fatalf("verify staged updater: %v", err)
	}
	if err := verifySignedBootstrapArtifact(stage, envelope.Specification); err != nil {
		t.Fatalf("verify staged specification: %v", err)
	}
	stagedJournal, err := hostagentdomain.StageUpdateBootstrap(journal, receipt)
	if err != nil {
		t.Fatalf("mark bootstrap staged: %v", err)
	}
	journal, err = hostagentdomain.MarkUpdateHandoffPending(stagedJournal, "2026-07-17T00:00:01Z")
	if err != nil {
		t.Fatalf("mark handoff pending: %v", err)
	}
	if issue := bootstrapper.RequestHandoff(context.Background(), journal); issue != nil {
		t.Fatalf("publish handoff: %+v", issue)
	}
	if issue := bootstrapper.RequestHandoff(context.Background(), journal); issue != nil {
		t.Fatalf("republish handoff: %+v", issue)
	}
	invocation, _, err := readStagedInvocation(filepath.Join(stage, stagedInvocationFile))
	if err != nil {
		t.Fatalf("read handoff invocation: %v", err)
	}
	if issue := validateStagedInvocation(journal, invocation); issue != nil {
		t.Fatalf("validate handoff invocation: %+v", issue)
	}
	if invocation.RequestID != journal.RequestID || invocation.ExpectedHandoffJournalRevision != journal.JournalRevision {
		t.Fatalf("handoff invocation must preserve Host completion correlation: %+v", invocation)
	}
	queue, err := os.ReadFile(filepath.Join(stagingDirectory, "handoff-queue", journal.ID+".json"))
	if err != nil {
		t.Fatalf("read durable handoff: %v", err)
	}
	var handoff stagedUpdateHandoff
	if err := json.Unmarshal(queue, &handoff); err != nil {
		t.Fatalf("decode durable handoff: %v", err)
	}
	if handoff.SchemaVersion != hostagentdomain.SchemaVersion || handoff.UpdateID != journal.ID || handoff.InvocationRelativePath != "updates/"+journal.ID+"/"+stagedInvocationFile {
		t.Fatalf("durable handoff=%+v", handoff)
	}
	second := bootstrapper.Stage(context.Background(), stagedJournal, envelope)
	if second.State != "staged" || second.Issue != nil {
		t.Fatalf("restage receipt=%+v", second)
	}
}

func TestStagedBundleBootstrapperDoesNotPublishC30BeforeDurableHandoffState(t *testing.T) {
	bootstrapper, journal, envelope, _ := stagedFixture(t)
	if receipt := bootstrapper.Stage(context.Background(), journal, envelope); receipt.State != "staged" || receipt.Issue != nil {
		t.Fatalf("stage receipt=%+v", receipt)
	}
	issue := bootstrapper.RequestHandoff(context.Background(), journal)
	if issue == nil || issue.Code != "update-handoff-journal-state-invalid" {
		t.Fatalf("handoff issue=%+v", issue)
	}
}

func TestStagedBundleBootstrapperRejectsCommandBundleEnvelopeMismatchBeforePublishingStage(t *testing.T) {
	bootstrapper, journal, envelope, stagingDirectory := stagedFixture(t)
	envelope.Signature.Value = base64.StdEncoding.EncodeToString([]byte("not-an-ed25519-signature"))
	receipt := bootstrapper.Stage(context.Background(), journal, envelope)
	if receipt.State != "failed" || receipt.Issue == nil || receipt.Issue.Code != "update-bundle-bootstrap-envelope-mismatch" {
		t.Fatalf("stage receipt=%+v", receipt)
	}
	if _, err := os.Stat(filepath.Join(stagingDirectory, "updates", journal.ID)); !os.IsNotExist(err) {
		t.Fatalf("invalid bundle unexpectedly staged: %v", err)
	}
}

func TestFilesystemRejectsTamperedSignedArtifactBeforePublishingStage(t *testing.T) {
	bootstrapper, journal, envelope, stagingDirectory := stagedFixture(t)
	bundlePayload := filepath.Join(filepath.Dir(stagingDirectory), "bundles", journal.BundleReferenceID, "payload", "host-updater")
	if err := os.WriteFile(bundlePayload, []byte("tampered-updater"), 0o700); err != nil {
		t.Fatal(err)
	}
	receipt := bootstrapper.Stage(context.Background(), journal, envelope)
	if receipt.State != "failed" || receipt.Issue == nil || receipt.Issue.Code != "update-next-updater-artifact-invalid" {
		t.Fatalf("stage receipt=%+v", receipt)
	}
	if _, err := os.Stat(filepath.Join(stagingDirectory, "updates", journal.ID)); !os.IsNotExist(err) {
		t.Fatalf("tampered bundle unexpectedly staged: %v", err)
	}
}
