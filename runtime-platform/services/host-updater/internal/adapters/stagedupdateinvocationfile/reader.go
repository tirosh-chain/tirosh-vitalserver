// Package stagedupdateinvocationfile reads a Host-owned C30 invocation and
// its C26 specification without letting the updater's pure domain policy read
// files or infer path state.
package stagedupdateinvocationfile

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

const maximumDocumentBytes int64 = 1 << 20

// StagedProductUpdateInvocationFileReader is the filesystem adapter for the
// Host-owned C30/C26 staged product-update input.
type StagedProductUpdateInvocationFileReader struct{}

func (StagedProductUpdateInvocationFileReader) Read(invocationPath string) (hostupdaterdomain.StagedProductUpdatePlanningInput, error) {
	return ReadStagedProductUpdatePlanningInput(invocationPath)
}

// ReadStagedProductUpdatePlanningInput reads C30, verifies the C26 artifact digest, and returns
// explicit data to the pure planner. It rejects a missing, symlinked, invalid,
// or oversized staged file rather than converting it to an empty plan.
func ReadStagedProductUpdatePlanningInput(invocationPath string) (hostupdaterdomain.StagedProductUpdatePlanningInput, error) {
	if invocationPath == "" {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("C30 invocation path is required")
	}
	invocationBytes, err := readRegularFile(invocationPath)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("read C30 invocation: %w", err)
	}
	var invocation hostupdaterdomain.StagedProductUpdateInvocation
	if err := decodeExactly(invocationBytes, &invocation); err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("decode C30 invocation: %w", err)
	}
	if err := validateStagedProductUpdateInvocationShape(invocation); err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, err
	}
	specificationPath, err := safeChild(filepath.Dir(invocationPath), invocation.SpecificationRelativePath)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("resolve C26 specification path: %w", err)
	}
	specificationBytes, err := readRegularFile(specificationPath)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("read C26 specification: %w", err)
	}
	digest := sha256.Sum256(specificationBytes)
	if hex.EncodeToString(digest[:]) != invocation.UpdateSpecificationSHA256 {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("C26 specification sha256 does not match C30 invocation")
	}
	var specification hostupdaterdomain.ProductUpdateSpecification
	if err := decodeExactly(specificationBytes, &specification); err != nil {
		return hostupdaterdomain.StagedProductUpdatePlanningInput{}, fmt.Errorf("decode C26 specification: %w", err)
	}
	return hostupdaterdomain.StagedProductUpdatePlanningInput{Invocation: invocation, Specification: specification}, nil
}

func validateStagedProductUpdateInvocationShape(invocation hostupdaterdomain.StagedProductUpdateInvocation) error {
	if invocation.SchemaVersion != hostupdaterdomain.HostUpdaterDocumentSchemaVersion || !validIdentifier(invocation.UpdateID) || !validIdentifier(invocation.RequestID) || invocation.ExpectedHandoffJournalRevision < 1 || !validIdentifier(invocation.BootstrapEnvelopeID) || len(invocation.LayerOrder) == 0 || !validSHA256(invocation.UpdateSpecificationSHA256) {
		return fmt.Errorf("C30 invocation identity is invalid")
	}
	if _, err := safeRelativePayloadPath(invocation.SpecificationRelativePath); err != nil {
		return fmt.Errorf("C30 specification path is invalid: %w", err)
	}
	return nil
}

func validIdentifier(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != ':' && character != '-' {
			return false
		}
		if index == 0 && !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}

func validSHA256(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, character := range value {
		if !(character >= '0' && character <= '9') && !(character >= 'a' && character <= 'f') {
			return false
		}
	}
	return true
}

func safeChild(root string, relative string) (string, error) {
	clean, err := safeRelativePayloadPath(relative)
	if err != nil {
		return "", err
	}
	rootAbsolute, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	path := filepath.Join(rootAbsolute, clean)
	relativeToRoot, err := filepath.Rel(rootAbsolute, path)
	if err != nil || relativeToRoot == "." || strings.HasPrefix(relativeToRoot, ".."+string(filepath.Separator)) || relativeToRoot == ".." {
		return "", fmt.Errorf("path escapes staged update directory")
	}
	return path, nil
}

func safeRelativePayloadPath(path string) (string, error) {
	if !strings.HasPrefix(path, "payload/") || strings.Contains(path, "\\") || strings.Contains(path, "..") || filepath.IsAbs(path) {
		return "", fmt.Errorf("path must stay below payload without traversal")
	}
	clean := filepath.Clean(path)
	if clean == "payload" || !strings.HasPrefix(clean, "payload"+string(filepath.Separator)) {
		return "", fmt.Errorf("path must name a payload file")
	}
	return clean, nil
}

func readRegularFile(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is missing, not regular, or a symlink")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumDocumentBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(contents)) > maximumDocumentBytes {
		return nil, fmt.Errorf("file exceeds maximum document size")
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
