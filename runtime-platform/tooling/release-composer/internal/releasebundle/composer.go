// Package releasebundle deterministically creates a signed product release bundle.
// It is release tooling, not a Host or Guest runtime dependency.
package releasebundle

import (
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
	"regexp"
	"sort"
	"strings"
)

const schemaVersion = "v1"

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// ReleaseBundleComposition is release-owned input. Artifact integrity is calculated from payload
// bytes rather than trusted from this declaration.
type ReleaseBundleComposition struct {
	SchemaVersion string                     `json:"schemaVersion"`
	BundleID      string                     `json:"bundleId"`
	ProductID     string                     `json:"productId"`
	Target        UpdateTarget               `json:"target"`
	TargetRelease TargetRelease              `json:"targetRelease"`
	LayerOrder    []string                   `json:"layerOrder"`
	NextUpdater   ReleaseArtifactDeclaration `json:"nextUpdater"`
	Specification ReleaseArtifactDeclaration `json:"specification"`
	SigningKeyID  string                     `json:"signingKeyId"`
	IssuedAt      string                     `json:"issuedAt"`
}

type UpdateTarget struct {
	Platform     string `json:"platform"`
	Architecture string `json:"architecture"`
}

type TargetRelease struct {
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
}

type ReleaseArtifactDeclaration struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	MediaType    string `json:"mediaType"`
}

type ReleaseArtifact struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
	MediaType    string `json:"mediaType"`
}

type ReleaseSignature struct {
	Algorithm    string `json:"algorithm"`
	KeyID        string `json:"keyId"`
	SignedSHA256 string `json:"signedSha256"`
	Value        string `json:"value"`
}

// BootstrapEnvelope has the same stable C25 JSON shape used by Host Agent.
type BootstrapEnvelope struct {
	SchemaVersion       string           `json:"schemaVersion"`
	ID                  string           `json:"id"`
	ProductID           string           `json:"productId"`
	Target              UpdateTarget     `json:"target"`
	TargetRelease       TargetRelease    `json:"targetRelease"`
	LayerOrder          []string         `json:"layerOrder"`
	NextUpdaterArtifact ReleaseArtifact  `json:"nextUpdaterArtifact"`
	Specification       ReleaseArtifact  `json:"specification"`
	Signature           ReleaseSignature `json:"signature"`
	IssuedAt            string           `json:"issuedAt"`
}

type ReleaseBundleContentFile struct {
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
}

type ReleaseBundleContentManifest struct {
	SchemaVersion string                     `json:"schemaVersion"`
	BundleID      string                     `json:"bundleId"`
	Files         []ReleaseBundleContentFile `json:"files"`
}

type ComposeReleaseBundleRequest struct {
	CompositionPath  string
	PayloadDirectory string
	PrivateKeyPath   string
	TrustStorePath   string
	OutputDirectory  string
}

type trustedUpdateKey struct {
	ID        string `json:"id"`
	Algorithm string `json:"algorithm"`
	PublicKey string `json:"publicKey"`
}

type hostUpdateTrustStore struct {
	SchemaVersion string             `json:"schemaVersion"`
	Keys          []trustedUpdateKey `json:"keys"`
}

type SignedReleaseBundle struct {
	BundleDirectory string
	Envelope        BootstrapEnvelope
	ContentManifest ReleaseBundleContentManifest
}

func ComposeReleaseBundle(request ComposeReleaseBundleRequest) (SignedReleaseBundle, error) {
	composition, err := readReleaseBundleComposition(request.CompositionPath)
	if err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := validateReleaseBundleComposition(composition); err != nil {
		return SignedReleaseBundle{}, err
	}
	payloadDirectory, err := requireDirectory(request.PayloadDirectory)
	if err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("payload directory: %w", err)
	}
	outputDirectory, err := requireDirectory(request.OutputDirectory)
	if err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("output directory: %w", err)
	}
	privateKey, err := readPrivateKey(request.PrivateKeyPath)
	if err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := verifySigningKeyIsTrusted(request.TrustStorePath, composition.SigningKeyID, privateKey.Public().(ed25519.PublicKey)); err != nil {
		return SignedReleaseBundle{}, err
	}
	nextUpdater, err := artifactFromPayload(payloadDirectory, composition.NextUpdater)
	if err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("next updater: %w", err)
	}
	specification, err := artifactFromPayload(payloadDirectory, composition.Specification)
	if err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("update specification: %w", err)
	}
	if nextUpdater.SHA256 == specification.SHA256 || nextUpdater.ID == specification.ID {
		return SignedReleaseBundle{}, fmt.Errorf("next updater and specification must be distinct artifacts")
	}
	envelope := BootstrapEnvelope{SchemaVersion: schemaVersion, ID: composition.BundleID, ProductID: composition.ProductID, Target: composition.Target, TargetRelease: composition.TargetRelease, LayerOrder: append([]string(nil), composition.LayerOrder...), NextUpdaterArtifact: nextUpdater, Specification: specification, IssuedAt: composition.IssuedAt}
	payload, err := canonicalSignedEnvelope(envelope)
	if err != nil {
		return SignedReleaseBundle{}, err
	}
	digest := sha256.Sum256(payload)
	envelope.Signature = ReleaseSignature{Algorithm: "ed25519", KeyID: composition.SigningKeyID, SignedSHA256: hex.EncodeToString(digest[:]), Value: base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, payload))}
	manifest, err := createReleaseBundleContentManifest(composition.BundleID, payloadDirectory)
	if err != nil {
		return SignedReleaseBundle{}, err
	}
	bundleDirectory := filepath.Join(outputDirectory, composition.BundleID)
	if _, err := os.Lstat(bundleDirectory); err == nil {
		return SignedReleaseBundle{}, fmt.Errorf("bundle output already exists: %s", bundleDirectory)
	} else if !errors.Is(err, os.ErrNotExist) {
		return SignedReleaseBundle{}, fmt.Errorf("inspect bundle output: %w", err)
	}
	temporary, err := os.MkdirTemp(outputDirectory, "."+composition.BundleID+".compose-")
	if err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("create temporary bundle: %w", err)
	}
	defer os.RemoveAll(temporary)
	if err := copyTree(payloadDirectory, filepath.Join(temporary, "payload")); err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := writeJSON(filepath.Join(temporary, "bootstrap-envelope.json"), envelope); err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := writeJSON(filepath.Join(temporary, "bundle-content-manifest.json"), manifest); err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := syncDirectory(temporary); err != nil {
		return SignedReleaseBundle{}, err
	}
	if err := os.Rename(temporary, bundleDirectory); err != nil {
		return SignedReleaseBundle{}, fmt.Errorf("publish release bundle: %w", err)
	}
	if err := syncDirectory(outputDirectory); err != nil {
		return SignedReleaseBundle{}, err
	}
	return SignedReleaseBundle{BundleDirectory: bundleDirectory, Envelope: envelope, ContentManifest: manifest}, nil
}

func verifySigningKeyIsTrusted(path string, keyID string, signingPublicKey ed25519.PublicKey) error {
	contents, err := readRegularFile(path, 1<<20)
	if err != nil {
		return fmt.Errorf("read Host update trust store: %w", err)
	}
	var store hostUpdateTrustStore
	if err := decodeExactly(contents, &store); err != nil {
		return fmt.Errorf("decode Host update trust store: %w", err)
	}
	if store.SchemaVersion != schemaVersion || len(store.Keys) == 0 || len(store.Keys) > 128 {
		return fmt.Errorf("Host update trust store schemaVersion and one to 128 keys are required")
	}
	seenIDs := map[string]bool{}
	seenKeys := map[string]bool{}
	var selected *trustedUpdateKey
	for index := range store.Keys {
		key := &store.Keys[index]
		decoded, decodeErr := base64.StdEncoding.DecodeString(key.PublicKey)
		if !validIdentifier(key.ID) || key.Algorithm != "ed25519" || decodeErr != nil || len(decoded) != ed25519.PublicKeySize || seenIDs[key.ID] || seenKeys[key.PublicKey] {
			return fmt.Errorf("Host update trust store contains an invalid or duplicate public key")
		}
		seenIDs[key.ID] = true
		seenKeys[key.PublicKey] = true
		if key.ID == keyID {
			selected = key
		}
	}
	if selected == nil {
		return fmt.Errorf("signing key id %q is not provisioned in the Host update trust store", keyID)
	}
	expected := base64.StdEncoding.EncodeToString(signingPublicKey)
	if selected.PublicKey != expected {
		return fmt.Errorf("private signing key does not match trusted public key %q", keyID)
	}
	return nil
}

func readReleaseBundleComposition(path string) (ReleaseBundleComposition, error) {
	contents, err := readRegularFile(path, 1<<20)
	if err != nil {
		return ReleaseBundleComposition{}, fmt.Errorf("read release bundle composition: %w", err)
	}
	var composition ReleaseBundleComposition
	if err := decodeExactly(contents, &composition); err != nil {
		return ReleaseBundleComposition{}, fmt.Errorf("decode release bundle composition: %w", err)
	}
	return composition, nil
}

func validateReleaseBundleComposition(composition ReleaseBundleComposition) error {
	if composition.SchemaVersion != schemaVersion || !validIdentifier(composition.BundleID) || !validIdentifier(composition.ProductID) || !validIdentifier(composition.SigningKeyID) || composition.TargetRelease.ProductVersion == "" || composition.TargetRelease.RuntimeVersion == "" || composition.IssuedAt == "" {
		return fmt.Errorf("release bundle identity, release, key id, and issuedAt are required")
	}
	if (composition.Target.Platform != "macos" && composition.Target.Platform != "windows" && composition.Target.Platform != "linux") || (composition.Target.Architecture != "arm64" && composition.Target.Architecture != "amd64") {
		return fmt.Errorf("release bundle target is unsupported")
	}
	if err := validateLayerOrder(composition.LayerOrder); err != nil {
		return err
	}
	for _, artifact := range []ReleaseArtifactDeclaration{composition.NextUpdater, composition.Specification} {
		if !validIdentifier(artifact.ID) || artifact.MediaType == "" {
			return fmt.Errorf("release artifact id and media type are required")
		}
		if _, err := safePayloadPath(artifact.RelativePath); err != nil {
			return err
		}
	}
	return nil
}

func validateLayerOrder(layers []string) error {
	if len(layers) == 0 || len(layers) > 3 {
		return fmt.Errorf("release layer order must contain one to three layers")
	}
	seen := map[string]bool{}
	for index, layer := range layers {
		if (layer != "container" && layer != "guest-runtime" && layer != "host-platform") || seen[layer] {
			return fmt.Errorf("release layer order contains an unsupported or duplicate layer")
		}
		if layer == "host-platform" && index != len(layers)-1 {
			return fmt.Errorf("host-platform must be the final release layer")
		}
		seen[layer] = true
	}
	return nil
}

func artifactFromPayload(payloadDirectory string, declaration ReleaseArtifactDeclaration) (ReleaseArtifact, error) {
	relative, err := safePayloadPath(declaration.RelativePath)
	if err != nil {
		return ReleaseArtifact{}, err
	}
	path, err := safeChild(payloadDirectory, relative)
	if err != nil {
		return ReleaseArtifact{}, err
	}
	contents, err := readRegularFile(path, -1)
	if err != nil {
		return ReleaseArtifact{}, err
	}
	digest := sha256.Sum256(contents)
	return ReleaseArtifact{ID: declaration.ID, RelativePath: declaration.RelativePath, SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(contents)), MediaType: declaration.MediaType}, nil
}

func canonicalSignedEnvelope(envelope BootstrapEnvelope) ([]byte, error) {
	type signedEnvelope struct {
		SchemaVersion       string          `json:"schemaVersion"`
		ID                  string          `json:"id"`
		ProductID           string          `json:"productId"`
		Target              UpdateTarget    `json:"target"`
		TargetRelease       TargetRelease   `json:"targetRelease"`
		LayerOrder          []string        `json:"layerOrder"`
		NextUpdaterArtifact ReleaseArtifact `json:"nextUpdaterArtifact"`
		Specification       ReleaseArtifact `json:"specification"`
		IssuedAt            string          `json:"issuedAt"`
	}
	return json.Marshal(signedEnvelope{SchemaVersion: envelope.SchemaVersion, ID: envelope.ID, ProductID: envelope.ProductID, Target: envelope.Target, TargetRelease: envelope.TargetRelease, LayerOrder: envelope.LayerOrder, NextUpdaterArtifact: envelope.NextUpdaterArtifact, Specification: envelope.Specification, IssuedAt: envelope.IssuedAt})
}

func createReleaseBundleContentManifest(bundleID string, payloadDirectory string) (ReleaseBundleContentManifest, error) {
	files := []ReleaseBundleContentFile{}
	err := filepath.WalkDir(payloadDirectory, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("payload contains a symlink")
		}
		if entry.IsDir() {
			return nil
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("payload contains a non-regular file")
		}
		relative, err := filepath.Rel(payloadDirectory, path)
		if err != nil {
			return err
		}
		contents, err := readRegularFile(path, -1)
		if err != nil {
			return err
		}
		digest := sha256.Sum256(contents)
		files = append(files, ReleaseBundleContentFile{RelativePath: filepath.ToSlash(filepath.Join("payload", relative)), SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(contents))})
		return nil
	})
	if err != nil {
		return ReleaseBundleContentManifest{}, err
	}
	sort.Slice(files, func(left int, right int) bool { return files[left].RelativePath < files[right].RelativePath })
	return ReleaseBundleContentManifest{SchemaVersion: schemaVersion, BundleID: bundleID, Files: files}, nil
}

func copyTree(source string, destination string) error {
	if err := os.Mkdir(destination, 0o700); err != nil {
		return fmt.Errorf("create payload destination: %w", err)
	}
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		if relative == "." {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("payload contains a symlink")
		}
		target := filepath.Join(destination, relative)
		if entry.IsDir() {
			return os.Mkdir(target, 0o700)
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("payload contains a non-regular file")
		}
		contents, err := readRegularFile(path, -1)
		if err != nil {
			return err
		}
		return os.WriteFile(target, contents, 0o700)
	})
}

func readPrivateKey(path string) (ed25519.PrivateKey, error) {
	contents, err := readRegularFile(path, 1<<20)
	if err != nil {
		return nil, fmt.Errorf("read release private key: %w", err)
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(contents)))
	if err != nil || len(decoded) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("release private key is not a base64 ed25519 private key")
	}
	return ed25519.PrivateKey(decoded), nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

func requireDirectory(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(abs)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("directory is missing, not a directory, or a symlink")
	}
	return abs, nil
}

func safePayloadPath(path string) (string, error) {
	if !strings.HasPrefix(path, "payload/") || strings.Contains(path, "\\") || strings.Contains(path, "..") || filepath.IsAbs(path) {
		return "", fmt.Errorf("artifact path must stay below payload without traversal")
	}
	clean := filepath.Clean(strings.TrimPrefix(path, "payload/"))
	if clean == "." || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("artifact path must name a payload file")
	}
	return clean, nil
}

func safeChild(root string, relative string) (string, error) {
	path := filepath.Join(root, relative)
	relativeToRoot, err := filepath.Rel(root, path)
	if err != nil || relativeToRoot == ".." || strings.HasPrefix(relativeToRoot, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("artifact path escapes payload")
	}
	return path, nil
}

func readRegularFile(path string, limit int64) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is missing, not regular, or a symlink")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := io.Reader(file)
	if limit >= 0 {
		reader = io.LimitReader(file, limit+1)
	}
	contents, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}
	if limit >= 0 && int64(len(contents)) > limit {
		return nil, fmt.Errorf("file exceeds maximum supported size")
	}
	return contents, nil
}

func decodeExactly(contents []byte, destination any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}

func writeJSON(path string, value any) error {
	contents, err := json.Marshal(value)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
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

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
