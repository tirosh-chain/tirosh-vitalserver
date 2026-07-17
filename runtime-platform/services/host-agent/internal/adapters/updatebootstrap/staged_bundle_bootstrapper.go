// Package updatebootstrap provides Host-native, explicit update staging.
// It validates C25, copies the complete bundle into Host-owned staging, and
// publishes C31 to a durable handoff queue. It never decodes C26.
package updatebootstrap

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const (
	bootstrapEnvelopeFile = "bootstrap-envelope.json"
	stagedInvocationFile  = "invocation.json"
)

// StagedBundleBootstrapperConfig identifies Host-owned directories. Each path is required;
// selecting this adapter with incomplete configuration is a startup error, not
// an implicit fallback to an unavailable or permissive update path.
type StagedBundleBootstrapperConfig struct {
	BundleStoreDirectory string
	StagingDirectory     string
	TrustStorePath       string
	Clock                hostagentapplication.HostAgentClock
}

// StagedBundleBootstrapper stages signed bundles below StagingDirectory. The deployment
// supervisor consumes C30 documents from its handoff-queue subdirectory.
type StagedBundleBootstrapper struct {
	bundleStoreDirectory string
	stagingDirectory     string
	trustStorePath       string
	clock                hostagentapplication.HostAgentClock
}

type trustedUpdateKey struct {
	ID        string `json:"id"`
	Algorithm string `json:"algorithm"`
	PublicKey string `json:"publicKey"`
}

type trustStore struct {
	SchemaVersion string             `json:"schemaVersion"`
	Keys          []trustedUpdateKey `json:"keys"`
}

// stagedUpdateInvocation is C30. The Host intentionally does not have a C26
// field: the staged next updater reads and validates the referenced file.
type stagedUpdateInvocation struct {
	SchemaVersion                  string   `json:"schemaVersion"`
	UpdateID                       string   `json:"updateId"`
	RequestID                      string   `json:"requestId"`
	ExpectedHandoffJournalRevision int      `json:"expectedHandoffJournalRevision"`
	BootstrapEnvelopeID            string   `json:"bootstrapEnvelopeId"`
	UpdateSpecificationSHA256      string   `json:"updateSpecificationSha256"`
	LayerOrder                     []string `json:"layerOrder"`
	SpecificationRelativePath      string   `json:"specificationRelativePath"`
}

// stagedUpdateHandoff is C31. It is deliberately separate from C30 because a
// durable queue lives outside the staged update directory. Copying C30 into
// that queue would change the base directory used to resolve its payload path.
// The launcher consumes C31, resolves the Host-owned relative path, then gives
// the original C30 document to the staged next updater.
type stagedUpdateHandoff struct {
	SchemaVersion          string `json:"schemaVersion"`
	UpdateID               string `json:"updateId"`
	InvocationRelativePath string `json:"invocationRelativePath"`
}

func NewStagedBundleBootstrapper(config StagedBundleBootstrapperConfig) (*StagedBundleBootstrapper, error) {
	if config.BundleStoreDirectory == "" || config.StagingDirectory == "" || config.TrustStorePath == "" || config.Clock == nil {
		return nil, fmt.Errorf("bundle store, staging directory, trust store, and clock are required for staged bundle bootstrap")
	}
	bundleStore, err := requireDirectory(config.BundleStoreDirectory)
	if err != nil {
		return nil, fmt.Errorf("configure update bundle store: %w", err)
	}
	staging, err := requireDirectory(config.StagingDirectory)
	if err != nil {
		return nil, fmt.Errorf("configure update staging directory: %w", err)
	}
	if _, err := requireRegularFile(config.TrustStorePath); err != nil {
		return nil, fmt.Errorf("configure update trust store: %w", err)
	}
	return &StagedBundleBootstrapper{bundleStoreDirectory: bundleStore, stagingDirectory: staging, trustStorePath: config.TrustStorePath, clock: config.Clock}, nil
}

func (bootstrapper *StagedBundleBootstrapper) Stage(ctx context.Context, journal hostagentdomain.HostUpdateJournal, envelope hostagentdomain.UpdateBootstrapEnvelope) hostagentdomain.UpdateBootstrapReceipt {
	if issue := hostagentdomain.ValidateUpdateBootstrapEnvelope(envelope); issue != nil {
		return bootstrapper.failedReceipt(journal, issue.Code, issue.Message, "host-update-bootstrapper")
	}
	if err := ctx.Err(); err != nil {
		return bootstrapper.failedReceipt(journal, "update-bootstrap-stage-cancelled", err.Error(), "host-update-bootstrapper")
	}
	bundleDirectory, err := bootstrapper.bundleDirectory(journal.BundleReferenceID)
	if err != nil {
		return bootstrapper.failedReceipt(journal, "update-bundle-unavailable", err.Error(), "update-bundle-store")
	}
	bundleEnvelope, err := readBootstrapEnvelope(filepath.Join(bundleDirectory, bootstrapEnvelopeFile))
	if err != nil {
		return bootstrapper.failedReceipt(journal, "update-bundle-bootstrap-envelope-invalid", err.Error(), "update-bundle-store")
	}
	if !reflect.DeepEqual(bundleEnvelope, envelope) {
		return bootstrapper.failedReceipt(journal, "update-bundle-bootstrap-envelope-mismatch", "bundle bootstrap envelope differs from the admitted Host command", "update-bundle-store")
	}
	if err := bootstrapper.verifySignature(bundleEnvelope); err != nil {
		return bootstrapper.failedReceipt(journal, "update-bootstrap-signature-invalid", err.Error(), "update-trust-store")
	}
	if err := verifySignedBootstrapArtifact(bundleDirectory, bundleEnvelope.NextUpdaterArtifact); err != nil {
		return bootstrapper.failedReceipt(journal, "update-next-updater-artifact-invalid", err.Error(), "update-bundle-store")
	}
	if err := verifySignedBootstrapArtifact(bundleDirectory, bundleEnvelope.Specification); err != nil {
		return bootstrapper.failedReceipt(journal, "update-specification-artifact-invalid", err.Error(), "update-bundle-store")
	}
	if err := bootstrapper.ensureStaged(ctx, journal, bundleDirectory, bundleEnvelope); err != nil {
		return bootstrapper.failedReceipt(journal, "update-bundle-stage-failed", err.Error(), "host-update-staging")
	}
	return hostagentdomain.UpdateBootstrapReceipt{
		SchemaVersion:       hostagentdomain.SchemaVersion,
		UpdateID:            journal.ID,
		RequestID:           journal.RequestID,
		BootstrapEnvelopeID: journal.BootstrapEnvelopeID,
		NextUpdaterSHA256:   journal.NextUpdaterSHA256,
		State:               "staged",
		ObservedAt:          hostagentdomain.Timestamp(bootstrapper.clock.Now()),
	}
}

// RequestHandoff publishes C31 atomically. It does not claim that the next
// updater has executed: the deployment supervisor is the separate consumer of
// this durable Host-local queue and resolves C31 to the original C30 document.
func (bootstrapper *StagedBundleBootstrapper) RequestHandoff(ctx context.Context, journal hostagentdomain.HostUpdateJournal) *hostagentdomain.Issue {
	if err := ctx.Err(); err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-cancelled", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-update-bootstrapper"}
	}
	if journal.State != "handoff-pending" {
		return &hostagentdomain.Issue{Code: "update-handoff-journal-state-invalid", Message: "C30 handoff requires a durable handoff-pending Host update journal", Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	stageDirectory := bootstrapper.stagedDirectory(journal.ID)
	if err := verifyExistingStage(stageDirectory, journal.BootstrapEnvelope); err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-stage-invalid", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	invocation := composeStagedUpdateInvocation(journal)
	encodedInvocation, err := json.Marshal(invocation)
	if err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-invocation-encode-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	invocationPath := filepath.Join(stageDirectory, stagedInvocationFile)
	if err := writeSameOrAtomicallyCreate(invocationPath, encodedInvocation, 0o600); err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-invocation-publish-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	persistedInvocation, _, err := readStagedInvocation(invocationPath)
	if err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-invocation-invalid", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	if issue := validateStagedInvocation(journal, persistedInvocation); issue != nil {
		return &hostagentdomain.Issue{Code: issue.Code, Message: issue.Message, Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	handoff := stagedUpdateHandoff{
		SchemaVersion:          hostagentdomain.SchemaVersion,
		UpdateID:               journal.ID,
		InvocationRelativePath: filepath.ToSlash(filepath.Join("updates", journal.ID, stagedInvocationFile)),
	}
	encodedHandoff, err := json.Marshal(handoff)
	if err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-encode-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(false), Dependency: "host-update-staging"}
	}
	queueDirectory := filepath.Join(bootstrapper.stagingDirectory, "handoff-queue")
	if err := os.MkdirAll(queueDirectory, 0o700); err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-queue-create-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-update-staging"}
	}
	queueFile := filepath.Join(queueDirectory, journal.ID+".json")
	if err := writeSameOrAtomicallyCreate(queueFile, encodedHandoff, 0o600); err != nil {
		return &hostagentdomain.Issue{Code: "update-handoff-publish-failed", Message: err.Error(), Retryable: hostagentdomain.Bool(true), Dependency: "host-update-staging"}
	}
	return nil
}

func (bootstrapper *StagedBundleBootstrapper) failedReceipt(journal hostagentdomain.HostUpdateJournal, code string, message string, dependency string) hostagentdomain.UpdateBootstrapReceipt {
	return hostagentdomain.UpdateBootstrapReceipt{
		SchemaVersion:       hostagentdomain.SchemaVersion,
		UpdateID:            journal.ID,
		RequestID:           journal.RequestID,
		BootstrapEnvelopeID: journal.BootstrapEnvelopeID,
		NextUpdaterSHA256:   journal.NextUpdaterSHA256,
		State:               "failed",
		ObservedAt:          hostagentdomain.Timestamp(bootstrapper.clock.Now()),
		Issue:               &hostagentdomain.Issue{Code: code, Message: message, Retryable: hostagentdomain.Bool(false), Dependency: dependency},
	}
}

func (bootstrapper *StagedBundleBootstrapper) bundleDirectory(bundleReferenceID string) (string, error) {
	if !hostagentdomain.ValidIdentifier(bundleReferenceID) {
		return "", fmt.Errorf("bundle reference id is invalid")
	}
	return childDirectory(bootstrapper.bundleStoreDirectory, bundleReferenceID)
}

func (bootstrapper *StagedBundleBootstrapper) stagedDirectory(updateID string) string {
	return filepath.Join(bootstrapper.stagingDirectory, "updates", updateID)
}

func composeStagedUpdateInvocation(journal hostagentdomain.HostUpdateJournal) stagedUpdateInvocation {
	return stagedUpdateInvocation{
		SchemaVersion:                  hostagentdomain.SchemaVersion,
		UpdateID:                       journal.ID,
		RequestID:                      journal.RequestID,
		ExpectedHandoffJournalRevision: journal.JournalRevision,
		BootstrapEnvelopeID:            journal.BootstrapEnvelopeID,
		UpdateSpecificationSHA256:      journal.UpdateSpecificationSHA256,
		LayerOrder:                     append([]string(nil), journal.LayerOrder...),
		SpecificationRelativePath:      journal.BootstrapEnvelope.Specification.RelativePath,
	}
}

func (bootstrapper *StagedBundleBootstrapper) ensureStaged(ctx context.Context, journal hostagentdomain.HostUpdateJournal, bundleDirectory string, envelope hostagentdomain.UpdateBootstrapEnvelope) error {
	target := bootstrapper.stagedDirectory(journal.ID)
	if _, err := os.Lstat(target); err == nil {
		return verifyExistingStage(target, envelope)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect staged update directory: %w", err)
	}
	updatesDirectory := filepath.Dir(target)
	if err := os.MkdirAll(updatesDirectory, 0o700); err != nil {
		return fmt.Errorf("create update staging root: %w", err)
	}
	temporary, err := os.MkdirTemp(updatesDirectory, "."+journal.ID+".staging-")
	if err != nil {
		return fmt.Errorf("create temporary staged update directory: %w", err)
	}
	defer os.RemoveAll(temporary)
	if err := copyReleaseBundlePayload(ctx, bundleDirectory, temporary); err != nil {
		return err
	}
	canonicalEnvelope, err := json.Marshal(envelope)
	if err != nil {
		return fmt.Errorf("encode staged bootstrap envelope: %w", err)
	}
	if err := writeFileSynced(filepath.Join(temporary, bootstrapEnvelopeFile), canonicalEnvelope, 0o600); err != nil {
		return fmt.Errorf("write staged bootstrap envelope: %w", err)
	}
	if err := syncDirectory(temporary); err != nil {
		return fmt.Errorf("sync staged update directory: %w", err)
	}
	if err := os.Rename(temporary, target); err != nil {
		if !errors.Is(err, fs.ErrExist) {
			return fmt.Errorf("publish staged update directory: %w", err)
		}
		return verifyExistingStage(target, envelope)
	}
	if err := syncDirectory(updatesDirectory); err != nil {
		return fmt.Errorf("sync update staging root: %w", err)
	}
	return nil
}

func verifyExistingStage(directory string, envelope hostagentdomain.UpdateBootstrapEnvelope) error {
	info, err := os.Lstat(directory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("existing staged update directory is invalid")
	}
	stagedEnvelope, err := readBootstrapEnvelope(filepath.Join(directory, bootstrapEnvelopeFile))
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(stagedEnvelope, envelope) {
		return fmt.Errorf("existing staged bootstrap envelope differs from the admitted update")
	}
	if err := verifySignedBootstrapArtifact(directory, envelope.NextUpdaterArtifact); err != nil {
		return fmt.Errorf("existing staged next updater is invalid: %w", err)
	}
	if err := verifySignedBootstrapArtifact(directory, envelope.Specification); err != nil {
		return fmt.Errorf("existing staged update specification is invalid: %w", err)
	}
	return nil
}

func (bootstrapper *StagedBundleBootstrapper) verifySignature(envelope hostagentdomain.UpdateBootstrapEnvelope) error {
	store, err := readUpdateTrustStore(bootstrapper.trustStorePath)
	if err != nil {
		return err
	}
	var key *trustedUpdateKey
	for index := range store.Keys {
		if store.Keys[index].ID == envelope.Signature.KeyID {
			key = &store.Keys[index]
			break
		}
	}
	if key == nil {
		return fmt.Errorf("trust store has no key %q", envelope.Signature.KeyID)
	}
	if key.Algorithm != "ed25519" {
		return fmt.Errorf("trusted key %q uses unsupported algorithm", key.ID)
	}
	publicKey, err := base64.StdEncoding.DecodeString(key.PublicKey)
	if err != nil || len(publicKey) != ed25519.PublicKeySize {
		return fmt.Errorf("trusted key %q is not an ed25519 public key", key.ID)
	}
	payload, err := canonicalSignedEnvelope(envelope)
	if err != nil {
		return err
	}
	digest := sha256.Sum256(payload)
	if hex.EncodeToString(digest[:]) != envelope.Signature.SignedSHA256 {
		return fmt.Errorf("bootstrap signedSha256 does not match its canonical payload")
	}
	signature, err := base64.StdEncoding.DecodeString(envelope.Signature.Value)
	if err != nil || len(signature) != ed25519.SignatureSize {
		return fmt.Errorf("bootstrap signature is not an ed25519 signature")
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKey), payload, signature) {
		return fmt.Errorf("bootstrap signature verification failed")
	}
	return nil
}

func canonicalSignedEnvelope(envelope hostagentdomain.UpdateBootstrapEnvelope) ([]byte, error) {
	type signedEnvelope struct {
		SchemaVersion       string                         `json:"schemaVersion"`
		ID                  string                         `json:"id"`
		ProductID           string                         `json:"productId"`
		Target              hostagentdomain.UpdateTarget   `json:"target"`
		TargetRelease       hostagentdomain.Release        `json:"targetRelease"`
		LayerOrder          []string                       `json:"layerOrder"`
		NextUpdaterArtifact hostagentdomain.UpdateArtifact `json:"nextUpdaterArtifact"`
		Specification       hostagentdomain.UpdateArtifact `json:"specification"`
		IssuedAt            string                         `json:"issuedAt"`
	}
	return json.Marshal(signedEnvelope{SchemaVersion: envelope.SchemaVersion, ID: envelope.ID, ProductID: envelope.ProductID, Target: envelope.Target, TargetRelease: envelope.TargetRelease, LayerOrder: envelope.LayerOrder, NextUpdaterArtifact: envelope.NextUpdaterArtifact, Specification: envelope.Specification, IssuedAt: envelope.IssuedAt})
}

func readUpdateTrustStore(path string) (trustStore, error) {
	encoded, err := readBoundedRegularFile(path, 1<<20)
	if err != nil {
		return trustStore{}, fmt.Errorf("read update trust store: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var store trustStore
	if err := decoder.Decode(&store); err != nil {
		return trustStore{}, fmt.Errorf("decode update trust store: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return trustStore{}, fmt.Errorf("update trust store must contain exactly one JSON object")
	}
	if store.SchemaVersion != hostagentdomain.SchemaVersion || len(store.Keys) == 0 {
		return trustStore{}, fmt.Errorf("update trust store schemaVersion and keys are required")
	}
	seen := map[string]bool{}
	for _, key := range store.Keys {
		if !hostagentdomain.ValidIdentifier(key.ID) || key.Algorithm != "ed25519" || key.PublicKey == "" || seen[key.ID] {
			return trustStore{}, fmt.Errorf("update trust store key is invalid")
		}
		seen[key.ID] = true
	}
	return store, nil
}

func readBootstrapEnvelope(path string) (hostagentdomain.UpdateBootstrapEnvelope, error) {
	encoded, err := readBoundedRegularFile(path, 1<<20)
	if err != nil {
		return hostagentdomain.UpdateBootstrapEnvelope{}, fmt.Errorf("read bootstrap envelope: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var envelope hostagentdomain.UpdateBootstrapEnvelope
	if err := decoder.Decode(&envelope); err != nil {
		return hostagentdomain.UpdateBootstrapEnvelope{}, fmt.Errorf("decode bootstrap envelope: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return hostagentdomain.UpdateBootstrapEnvelope{}, fmt.Errorf("bootstrap envelope must contain exactly one JSON object")
	}
	if issue := hostagentdomain.ValidateUpdateBootstrapEnvelope(envelope); issue != nil {
		return hostagentdomain.UpdateBootstrapEnvelope{}, fmt.Errorf("bootstrap envelope is invalid: %s", issue.Code)
	}
	return envelope, nil
}

func readStagedInvocation(path string) (stagedUpdateInvocation, []byte, error) {
	encoded, err := readBoundedRegularFile(path, 1<<20)
	if err != nil {
		return stagedUpdateInvocation{}, nil, fmt.Errorf("read C30 staged invocation: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var invocation stagedUpdateInvocation
	if err := decoder.Decode(&invocation); err != nil {
		return stagedUpdateInvocation{}, nil, fmt.Errorf("decode C30 staged invocation: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return stagedUpdateInvocation{}, nil, fmt.Errorf("C30 staged invocation must contain exactly one JSON object")
	}
	return invocation, encoded, nil
}

func validateStagedInvocation(journal hostagentdomain.HostUpdateJournal, invocation stagedUpdateInvocation) *hostagentdomain.Issue {
	if invocation.SchemaVersion != hostagentdomain.SchemaVersion || invocation.UpdateID != journal.ID || invocation.RequestID != journal.RequestID || invocation.ExpectedHandoffJournalRevision != journal.JournalRevision || invocation.BootstrapEnvelopeID != journal.BootstrapEnvelopeID || invocation.UpdateSpecificationSHA256 != journal.UpdateSpecificationSHA256 || !sameLayers(invocation.LayerOrder, journal.LayerOrder) || invocation.SpecificationRelativePath != journal.BootstrapEnvelope.Specification.RelativePath {
		return &hostagentdomain.Issue{Code: "staged-update-invocation-invalid", Message: "C30 staged invocation does not match the Host-owned update journal"}
	}
	if _, err := safePayloadPath(invocation.SpecificationRelativePath); err != nil {
		return &hostagentdomain.Issue{Code: "staged-update-invocation-invalid", Message: err.Error()}
	}
	return nil
}

func sameLayers(left []string, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func verifySignedBootstrapArtifact(root string, artifact hostagentdomain.UpdateArtifact) error {
	path, err := safePayloadPath(artifact.RelativePath)
	if err != nil {
		return err
	}
	file, err := secureChildFile(root, path)
	if err != nil {
		return err
	}
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return fmt.Errorf("stat artifact: %w", err)
	}
	if info.Size() != artifact.SizeBytes {
		file.Close()
		return fmt.Errorf("artifact size does not match signed metadata")
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		file.Close()
		return fmt.Errorf("hash artifact: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close artifact: %w", err)
	}
	if hex.EncodeToString(hash.Sum(nil)) != artifact.SHA256 {
		return fmt.Errorf("artifact sha256 does not match signed metadata")
	}
	return nil
}

func copyReleaseBundlePayload(ctx context.Context, sourceRoot string, destinationRoot string) error {
	sourcePayload, err := childDirectory(sourceRoot, "payload")
	if err != nil {
		return fmt.Errorf("read update bundle payload: %w", err)
	}
	destinationPayload := filepath.Join(destinationRoot, "payload")
	if err := os.Mkdir(destinationPayload, 0o700); err != nil {
		return fmt.Errorf("create staged payload directory: %w", err)
	}
	return filepath.WalkDir(sourcePayload, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		relative, err := filepath.Rel(sourcePayload, path)
		if err != nil {
			return fmt.Errorf("resolve payload path: %w", err)
		}
		if relative == "." {
			return nil
		}
		if strings.Contains(relative, "..") || filepath.IsAbs(relative) || entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("update bundle payload contains unsafe path")
		}
		destination := filepath.Join(destinationPayload, relative)
		if entry.IsDir() {
			return os.Mkdir(destination, 0o700)
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("update bundle payload contains non-regular file")
		}
		return copyRegularFile(path, destination)
	})
}

func copyRegularFile(source string, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("open bundle payload file: %w", err)
	}
	defer input.Close()
	info, err := input.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("bundle payload file is not regular")
	}
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o700)
	if err != nil {
		return fmt.Errorf("create staged payload file: %w", err)
	}
	if _, err := io.Copy(output, input); err != nil {
		output.Close()
		return fmt.Errorf("copy bundle payload file: %w", err)
	}
	if err := output.Sync(); err != nil {
		output.Close()
		return fmt.Errorf("sync staged payload file: %w", err)
	}
	if err := output.Close(); err != nil {
		return fmt.Errorf("close staged payload file: %w", err)
	}
	return nil
}

func requireDirectory(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("directory is missing, not a directory, or a symlink: %s", path)
	}
	return abs, nil
}

func childDirectory(parent string, name string) (string, error) {
	if name == "" || strings.Contains(name, "/") || strings.Contains(name, "\\") || name == "." || name == ".." {
		return "", fmt.Errorf("directory child name is unsafe")
	}
	path := filepath.Join(parent, name)
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("directory child is missing, not a directory, or a symlink: %s", name)
	}
	return path, nil
}

func requireRegularFile(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("file is missing, not regular, or a symlink: %s", path)
	}
	return abs, nil
}

func readBoundedRegularFile(path string, limit int64) ([]byte, error) {
	if _, err := requireRegularFile(path); err != nil {
		return nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := io.LimitReader(file, limit+1)
	encoded, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}
	if int64(len(encoded)) > limit {
		return nil, fmt.Errorf("file exceeds maximum supported size")
	}
	return encoded, nil
}

func safePayloadPath(relative string) (string, error) {
	if !strings.HasPrefix(relative, "payload/") || strings.Contains(relative, "\\") || strings.Contains(relative, "..") || filepath.IsAbs(relative) {
		return "", fmt.Errorf("artifact path must stay below payload without traversal")
	}
	clean := filepath.Clean(relative)
	if clean == "payload" || !strings.HasPrefix(clean, "payload"+string(filepath.Separator)) {
		return "", fmt.Errorf("artifact path must name a file below payload")
	}
	return clean, nil
}

func secureChildFile(root string, relative string) (*os.File, error) {
	current := root
	for _, component := range strings.Split(filepath.Clean(relative), string(filepath.Separator)) {
		if component == "" || component == "." || component == ".." {
			return nil, fmt.Errorf("artifact path component is unsafe")
		}
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if err != nil || info.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("artifact path component is unavailable or a symlink")
		}
	}
	file, err := os.Open(current)
	if err != nil {
		return nil, fmt.Errorf("open artifact: %w", err)
	}
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		file.Close()
		return nil, fmt.Errorf("artifact is not a regular file")
	}
	return file, nil
}

func writeFileSynced(path string, contents []byte, mode fs.FileMode) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := file.Write(contents); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func writeSameOrAtomicallyCreate(path string, contents []byte, mode fs.FileMode) error {
	if existing, err := os.ReadFile(path); err == nil {
		if string(existing) != string(contents) {
			return fmt.Errorf("existing durable document differs from the staged update")
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read existing durable document: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".handoff-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Link(temporaryPath, path); err != nil {
		if errors.Is(err, fs.ErrExist) {
			existing, readErr := os.ReadFile(path)
			if readErr != nil || string(existing) != string(contents) {
				return fmt.Errorf("existing durable document differs from the staged update")
			}
			return nil
		}
		return err
	}
	return syncDirectory(filepath.Dir(path))
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
