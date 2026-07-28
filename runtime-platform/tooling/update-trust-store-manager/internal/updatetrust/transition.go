// Package updatetrust owns release-process public update-key transitions.
// It never reads or writes private signing material.
package updatetrust

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	schemaVersion        = "v1"
	trustStoreFileName   = "update-trust-store.json"
	transitionFileName   = "transition-receipt.json"
	maxTrustStoreBytes   = 1 << 20
	maxPublicKeyFileSize = 4096
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

type TrustedUpdateKey struct {
	ID        string `json:"id"`
	Algorithm string `json:"algorithm"`
	PublicKey string `json:"publicKey"`
}

type HostUpdateTrustStore struct {
	SchemaVersion string             `json:"schemaVersion"`
	Keys          []TrustedUpdateKey `json:"keys"`
}

type TrustStoreArtifact struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type UpdatePublisherTrustTransitionReceipt struct {
	SchemaVersion          string   `json:"schemaVersion"`
	TransitionID           string   `json:"transitionId"`
	Action                 string   `json:"action"`
	SourceTrustStoreSHA256 *string  `json:"sourceTrustStoreSha256,omitempty"`
	ResultTrustStoreSHA256 string   `json:"resultTrustStoreSha256"`
	ResultKeyCount         int      `json:"resultKeyCount"`
	AddedKeyIDs            []string `json:"addedKeyIds"`
	RemovedKeyIDs          []string `json:"removedKeyIds"`
	RetainedKeyIDs         []string `json:"retainedKeyIds"`
	TransitionedAt         string   `json:"transitionedAt"`
}

type TransitionRequest struct {
	Action               string
	TransitionID         string
	SourceTrustStorePath string
	ExpectedSourceSHA256 string
	KeyID                string
	PublicKeyPath        string
	TransitionedAt       string
	OutputDirectory      string
}

type TransitionResult struct {
	TrustStore HostUpdateTrustStore                  `json:"trustStore"`
	Receipt    UpdatePublisherTrustTransitionReceipt `json:"receipt"`
	Artifacts  map[string]TrustStoreArtifact         `json:"artifacts"`
}

func Transition(request TransitionRequest) (TransitionResult, error) {
	if !identifierPattern.MatchString(request.TransitionID) || !identifierPattern.MatchString(request.KeyID) {
		return TransitionResult{}, fmt.Errorf("transition id and key id must be published identifiers")
	}
	if _, err := time.Parse(time.RFC3339, request.TransitionedAt); err != nil {
		return TransitionResult{}, fmt.Errorf("transitioned-at must be RFC3339: %w", err)
	}
	if request.OutputDirectory == "" {
		return TransitionResult{}, fmt.Errorf("output directory is required")
	}

	var source *HostUpdateTrustStore
	var sourceDigest *string
	switch request.Action {
	case "provision":
		if request.SourceTrustStorePath != "" || request.ExpectedSourceSHA256 != "" {
			return TransitionResult{}, fmt.Errorf("provision requires an explicitly absent source trust store")
		}
	case "rotate", "revoke":
		if request.SourceTrustStorePath == "" || !validSHA256(request.ExpectedSourceSHA256) {
			return TransitionResult{}, fmt.Errorf("%s requires a source trust store and expected source sha256", request.Action)
		}
		store, digest, err := readTrustStore(request.SourceTrustStorePath)
		if err != nil {
			return TransitionResult{}, err
		}
		if digest != request.ExpectedSourceSHA256 {
			return TransitionResult{}, fmt.Errorf("source trust store sha256 mismatch expected=%s actual=%s", request.ExpectedSourceSHA256, digest)
		}
		source = &store
		sourceDigest = &digest
	default:
		return TransitionResult{}, fmt.Errorf("action must be provision, rotate, or revoke")
	}

	resultStore, added, removed, retained, err := transitionStore(request, source)
	if err != nil {
		return TransitionResult{}, err
	}
	trustStoreBytes, err := canonicalJSON(resultStore)
	if err != nil {
		return TransitionResult{}, fmt.Errorf("encode result trust store: %w", err)
	}
	resultDigest := sha256Hex(trustStoreBytes)
	receipt := UpdatePublisherTrustTransitionReceipt{
		SchemaVersion:          schemaVersion,
		TransitionID:           request.TransitionID,
		Action:                 request.Action,
		SourceTrustStoreSHA256: sourceDigest,
		ResultTrustStoreSHA256: resultDigest,
		ResultKeyCount:         len(resultStore.Keys),
		AddedKeyIDs:            added,
		RemovedKeyIDs:          removed,
		RetainedKeyIDs:         retained,
		TransitionedAt:         request.TransitionedAt,
	}
	receiptBytes, err := canonicalJSON(receipt)
	if err != nil {
		return TransitionResult{}, fmt.Errorf("encode transition receipt: %w", err)
	}
	if err := publishOutputDirectory(request.OutputDirectory, trustStoreBytes, receiptBytes); err != nil {
		return TransitionResult{}, err
	}
	return TransitionResult{
		TrustStore: resultStore,
		Receipt:    receipt,
		Artifacts: map[string]TrustStoreArtifact{
			"trustStore": {Path: filepath.Join(request.OutputDirectory, trustStoreFileName), SHA256: resultDigest},
			"receipt":    {Path: filepath.Join(request.OutputDirectory, transitionFileName), SHA256: sha256Hex(receiptBytes)},
		},
	}, nil
}

func transitionStore(request TransitionRequest, source *HostUpdateTrustStore) (HostUpdateTrustStore, []string, []string, []string, error) {
	switch request.Action {
	case "provision":
		key, err := readTrustedKey(request.KeyID, request.PublicKeyPath)
		if err != nil {
			return HostUpdateTrustStore{}, nil, nil, nil, err
		}
		return HostUpdateTrustStore{SchemaVersion: schemaVersion, Keys: []TrustedUpdateKey{key}}, []string{key.ID}, []string{}, []string{}, nil
	case "rotate":
		if request.PublicKeyPath == "" {
			return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("rotate requires a new public key")
		}
		key, err := readTrustedKey(request.KeyID, request.PublicKeyPath)
		if err != nil {
			return HostUpdateTrustStore{}, nil, nil, nil, err
		}
		keys := append([]TrustedUpdateKey(nil), source.Keys...)
		for _, existing := range keys {
			if existing.ID == key.ID {
				return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("rotation key id is already trusted: %s", key.ID)
			}
			if existing.PublicKey == key.PublicKey {
				return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("rotation public key is already trusted as %s", existing.ID)
			}
		}
		retained := keyIDs(keys)
		keys = append(keys, key)
		sortKeys(keys)
		return HostUpdateTrustStore{SchemaVersion: schemaVersion, Keys: keys}, []string{key.ID}, []string{}, retained, nil
	case "revoke":
		if request.PublicKeyPath != "" {
			return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("revoke does not accept public key input")
		}
		keys := make([]TrustedUpdateKey, 0, len(source.Keys)-1)
		found := false
		for _, key := range source.Keys {
			if key.ID == request.KeyID {
				found = true
				continue
			}
			keys = append(keys, key)
		}
		if !found {
			return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("revocation key id is not trusted: %s", request.KeyID)
		}
		if len(keys) == 0 {
			return HostUpdateTrustStore{}, nil, nil, nil, fmt.Errorf("revocation must retain at least one trusted update key")
		}
		sortKeys(keys)
		return HostUpdateTrustStore{SchemaVersion: schemaVersion, Keys: keys}, []string{}, []string{request.KeyID}, keyIDs(keys), nil
	default:
		panic("action validated before transition")
	}
}

func readTrustedKey(id string, path string) (TrustedUpdateKey, error) {
	if path == "" {
		return TrustedUpdateKey{}, fmt.Errorf("public key file is required")
	}
	contents, err := readBoundedRegularFile(path, maxPublicKeyFileSize)
	if err != nil {
		return TrustedUpdateKey{}, fmt.Errorf("read public key: %w", err)
	}
	encoded := strings.TrimSpace(string(contents))
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil || len(decoded) != ed25519.PublicKeySize {
		return TrustedUpdateKey{}, fmt.Errorf("public key must contain one base64 Ed25519 public key")
	}
	return TrustedUpdateKey{ID: id, Algorithm: "ed25519", PublicKey: base64.StdEncoding.EncodeToString(decoded)}, nil
}

func readTrustStore(path string) (HostUpdateTrustStore, string, error) {
	contents, err := readBoundedRegularFile(path, maxTrustStoreBytes)
	if err != nil {
		return HostUpdateTrustStore{}, "", fmt.Errorf("read source trust store: %w", err)
	}
	var store HostUpdateTrustStore
	if err := decodeExactly(contents, &store); err != nil {
		return HostUpdateTrustStore{}, "", fmt.Errorf("decode source trust store: %w", err)
	}
	if err := validateTrustStore(store); err != nil {
		return HostUpdateTrustStore{}, "", err
	}
	return store, sha256Hex(contents), nil
}

func validateTrustStore(store HostUpdateTrustStore) error {
	if store.SchemaVersion != schemaVersion || len(store.Keys) == 0 || len(store.Keys) > 128 {
		return fmt.Errorf("source trust store schemaVersion and one to 128 keys are required")
	}
	ids := map[string]bool{}
	publicKeys := map[string]bool{}
	for _, key := range store.Keys {
		if !identifierPattern.MatchString(key.ID) || key.Algorithm != "ed25519" || ids[key.ID] || publicKeys[key.PublicKey] {
			return fmt.Errorf("source trust store contains an invalid or duplicate key")
		}
		decoded, err := base64.StdEncoding.DecodeString(key.PublicKey)
		if err != nil || len(decoded) != ed25519.PublicKeySize {
			return fmt.Errorf("source trust store key %s is not an Ed25519 public key", key.ID)
		}
		ids[key.ID] = true
		publicKeys[key.PublicKey] = true
	}
	return nil
}

func publishOutputDirectory(output string, trustStore []byte, receipt []byte) error {
	parent := filepath.Dir(output)
	if info, err := os.Stat(parent); err != nil || !info.IsDir() {
		return fmt.Errorf("output parent directory is unavailable: %s", parent)
	}
	if _, err := os.Lstat(output); err == nil {
		return fmt.Errorf("output directory already exists: %s", output)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect output directory: %w", err)
	}
	temporary, err := os.MkdirTemp(parent, "."+filepath.Base(output)+".compose-")
	if err != nil {
		return fmt.Errorf("create temporary output directory: %w", err)
	}
	defer os.RemoveAll(temporary)
	if err := writeFileSynced(filepath.Join(temporary, trustStoreFileName), trustStore, 0o644); err != nil {
		return err
	}
	if err := writeFileSynced(filepath.Join(temporary, transitionFileName), receipt, 0o644); err != nil {
		return err
	}
	if err := syncDirectory(temporary); err != nil {
		return err
	}
	if err := os.Rename(temporary, output); err != nil {
		return fmt.Errorf("publish trust transition output: %w", err)
	}
	return syncDirectory(parent)
}

func readBoundedRegularFile(path string, maximum int64) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maximum {
		return nil, fmt.Errorf("path must be a bounded regular file")
	}
	return os.ReadFile(path)
}

func decodeExactly(contents []byte, value any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}

func canonicalJSON(value any) ([]byte, error) {
	contents, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	return append(contents, '\n'), nil
}

func writeFileSynced(path string, contents []byte, mode os.FileMode) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return fmt.Errorf("create %s: %w", path, err)
	}
	if _, err := file.Write(contents); err != nil {
		file.Close()
		return fmt.Errorf("write %s: %w", path, err)
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("sync %s: %w", path, err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close %s: %w", path, err)
	}
	return nil
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open directory for sync: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("sync directory: %w", err)
	}
	return nil
}

func sortKeys(keys []TrustedUpdateKey) {
	sort.Slice(keys, func(left int, right int) bool { return keys[left].ID < keys[right].ID })
}

func keyIDs(keys []TrustedUpdateKey) []string {
	ids := make([]string, len(keys))
	for index, key := range keys {
		ids[index] = key.ID
	}
	sort.Strings(ids)
	return ids
}

func validSHA256(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size && value == strings.ToLower(value)
}

func sha256Hex(contents []byte) string {
	digest := sha256.Sum256(contents)
	return hex.EncodeToString(digest[:])
}
