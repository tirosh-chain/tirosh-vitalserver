// Package stagednextupdaterdispatchinputfile verifies C31, C30, and the C25
// selected next-updater bytes. It intentionally never decodes C26.
package stagednextupdaterdispatchinputfile

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

const maximumDocumentBytes int64 = 1 << 20

type StagedNextUpdaterDispatchInputFileReader struct{}

type stagedInvocation struct {
	SchemaVersion                  string   `json:"schemaVersion"`
	UpdateID                       string   `json:"updateId"`
	RequestID                      string   `json:"requestId"`
	ExpectedHandoffJournalRevision int      `json:"expectedHandoffJournalRevision"`
	BootstrapEnvelopeID            string   `json:"bootstrapEnvelopeId"`
	UpdateSpecificationSHA256      string   `json:"updateSpecificationSha256"`
	LayerOrder                     []string `json:"layerOrder"`
	SpecificationRelativePath      string   `json:"specificationRelativePath"`
}

type bootstrapEnvelope struct {
	SchemaVersion       string            `json:"schemaVersion"`
	ID                  string            `json:"id"`
	ProductID           string            `json:"productId"`
	Target              json.RawMessage   `json:"target"`
	TargetRelease       json.RawMessage   `json:"targetRelease"`
	LayerOrder          []string          `json:"layerOrder"`
	NextUpdaterArtifact bootstrapArtifact `json:"nextUpdaterArtifact"`
	Specification       json.RawMessage   `json:"specification"`
	Signature           json.RawMessage   `json:"signature"`
	IssuedAt            string            `json:"issuedAt"`
}

type bootstrapArtifact struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
	MediaType    string `json:"mediaType"`
}

func (StagedNextUpdaterDispatchInputFileReader) Read(configuration hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, handoffPath string) (hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput, error) {
	stagingDirectory, err := requireDirectory(configuration.StagingDirectory)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, unavailable("update-staging-unavailable", err, "host-update-staging")
	}
	queueDirectory, err := requireDirectory(configuration.HandoffQueueDirectory)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, unavailable("handoff-queue-unavailable", err, "host-update-handoff-queue")
	}
	if filepath.Clean(filepath.Dir(handoffPath)) != queueDirectory || !filepath.IsAbs(handoffPath) {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("handoff-path-invalid", fmt.Errorf("C31 handoff must be an absolute direct child of the configured queue"), "host-update-handoff-queue")
	}
	handoffContents, err := readRegularFile(handoffPath)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("handoff-unreadable", err, "host-update-handoff-queue")
	}
	var handoff hostupdatehandoffsupervisordomain.StagedUpdateHandoff
	if err := decodeExactly(handoffContents, &handoff); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("handoff-invalid", err, "host-update-handoff-queue")
	}
	if err := hostupdatehandoffsupervisordomain.ValidateHandoff(handoff); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("handoff-invalid", err, "host-update-handoff-queue")
	}
	expectedInvocationRelativePath := filepath.ToSlash(filepath.Join("updates", handoff.UpdateID, "invocation.json"))
	if handoff.InvocationRelativePath != expectedInvocationRelativePath {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("handoff-invocation-path-invalid", fmt.Errorf("C31 invocation path must name its update's original C30"), "host-update-handoff-queue")
	}
	invocationPath, err := safeChild(stagingDirectory, handoff.InvocationRelativePath, "updates")
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("handoff-invocation-path-invalid", err, "host-update-staging")
	}
	invocationContents, err := readRegularFile(invocationPath)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("staged-invocation-unreadable", err, "host-update-staging")
	}
	var invocation stagedInvocation
	if err := decodeExactly(invocationContents, &invocation); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("staged-invocation-invalid", err, "host-update-staging")
	}
	if invocation.SchemaVersion != hostupdatehandoffsupervisordomain.SchemaVersion || invocation.UpdateID != handoff.UpdateID || invocation.RequestID == "" || invocation.BootstrapEnvelopeID == "" || invocation.UpdateSpecificationSHA256 == "" || len(invocation.LayerOrder) == 0 || invocation.ExpectedHandoffJournalRevision < 1 || !safePayloadRelativePath(invocation.SpecificationRelativePath) {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("staged-invocation-invalid", fmt.Errorf("C30 does not correlate to C31 or names an invalid C26 path"), "host-update-staging")
	}
	stageDirectory := filepath.Dir(invocationPath)
	envelopeContents, err := readRegularFile(filepath.Join(stageDirectory, "bootstrap-envelope.json"))
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("staged-bootstrap-envelope-unreadable", err, "host-update-staging")
	}
	var envelope bootstrapEnvelope
	if err := decodeExactly(envelopeContents, &envelope); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("staged-bootstrap-envelope-invalid", err, "host-update-staging")
	}
	if envelope.SchemaVersion != hostupdatehandoffsupervisordomain.SchemaVersion || envelope.ID != invocation.BootstrapEnvelopeID || envelope.ProductID == "" || len(envelope.Target) == 0 || len(envelope.TargetRelease) == 0 || len(envelope.LayerOrder) == 0 || len(envelope.Specification) == 0 || len(envelope.Signature) == 0 || envelope.IssuedAt == "" || !safePayloadRelativePath(envelope.NextUpdaterArtifact.RelativePath) || envelope.NextUpdaterArtifact.ID == "" || envelope.NextUpdaterArtifact.MediaType == "" || envelope.NextUpdaterArtifact.SizeBytes < 1 || len(envelope.NextUpdaterArtifact.SHA256) != 64 {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("staged-bootstrap-envelope-invalid", fmt.Errorf("C25 selected next updater declaration is invalid"), "host-update-staging")
	}
	nextUpdaterPath, err := safeChild(stageDirectory, envelope.NextUpdaterArtifact.RelativePath, "payload")
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, failed("staged-next-updater-path-invalid", err, "host-update-staging")
	}
	if err := verifyExecutableArtifact(nextUpdaterPath, envelope.NextUpdaterArtifact); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("staged-next-updater-invalid", err, "host-update-staging")
	}
	if _, err := readRegularFile(configuration.HostLocalAdministrationDescriptorPath); err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("host-local-administration-descriptor-unreadable", err, "host-agent")
	}
	executionMode, err := executionMode(configuration.ExecutionEvidenceDirectory, handoff.UpdateID)
	if err != nil {
		return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{}, classifyReadFailure("update-execution-evidence-unavailable", err, "host-update-evidence")
	}
	return hostupdatehandoffsupervisordomain.StagedNextUpdaterDispatchInput{
		UpdateID:                       handoff.UpdateID,
		InvocationRelativePath:         handoff.InvocationRelativePath,
		InvocationPath:                 invocationPath,
		ExpectedHandoffJournalRevision: invocation.ExpectedHandoffJournalRevision,
		NextUpdaterPath:                nextUpdaterPath,
		NextUpdaterSHA256:              envelope.NextUpdaterArtifact.SHA256,
		ExecutionReportPath:            filepath.Join(configuration.ExecutionEvidenceDirectory, handoff.UpdateID, "execution-report.json"),
		LayerEffectReceiptPath:         filepath.Join(configuration.LayerEffectReceiptDirectory, handoff.UpdateID),
		CompletionDescriptorPath:       configuration.HostLocalAdministrationDescriptorPath,
		LayerEffectTimeoutMilliseconds: configuration.LayerEffectTimeoutMilliseconds,
		CompletionTimeoutMilliseconds:  configuration.CompletionTimeoutMilliseconds,
		ExecutionMode:                  executionMode,
	}, nil
}

func executionMode(evidenceDirectory string, updateID string) (string, error) {
	if err := ensureDirectoryWithoutSymlink(filepath.Join(evidenceDirectory, updateID)); err != nil {
		return "", err
	}
	reportPath := filepath.Join(evidenceDirectory, updateID, "execution-report.json")
	info, err := os.Lstat(reportPath)
	if errors.Is(err, os.ErrNotExist) {
		return "execute", nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("existing C28 report is not a regular file")
	}
	return "complete", nil
}

// ensureDirectoryWithoutSymlink creates the Host-owned evidence branch one
// component at a time. os.MkdirAll would follow a pre-existing symbolic link
// and could let a C31 handoff redirect the next updater's C28 evidence.
func ensureDirectoryWithoutSymlink(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	current := string(filepath.Separator)
	if volume := filepath.VolumeName(abs); volume != "" {
		current = volume + string(filepath.Separator)
	}
	trimmed := strings.TrimPrefix(abs, filepath.VolumeName(abs))
	for _, component := range strings.FieldsFunc(filepath.Clean(trimmed), func(character rune) bool { return character == '/' || character == '\\' }) {
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			if err := os.Mkdir(current, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
				return err
			}
			continue
		}
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("C28 evidence directory contains a missing, non-directory, or symbolic-link component")
		}
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
		return "", fmt.Errorf("directory is missing, not a directory, or a symbolic link")
	}
	return abs, nil
}

func safeChild(root string, relative string, requiredTopLevelDirectory string) (string, error) {
	if !strings.HasPrefix(relative, requiredTopLevelDirectory+"/") || strings.Contains(relative, "\\") || strings.Contains(relative, "..") || filepath.IsAbs(relative) {
		return "", fmt.Errorf("path must stay below %s without traversal", requiredTopLevelDirectory)
	}
	clean := filepath.Clean(relative)
	if clean == requiredTopLevelDirectory || !strings.HasPrefix(clean, requiredTopLevelDirectory+string(filepath.Separator)) {
		return "", fmt.Errorf("path is invalid")
	}
	rootAbsolute, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	rootInfo, err := os.Lstat(rootAbsolute)
	if err != nil || !rootInfo.IsDir() || rootInfo.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("staged update root is missing, non-directory, or a symbolic link")
	}
	path := filepath.Join(rootAbsolute, clean)
	contained, err := filepath.Rel(rootAbsolute, path)
	if err != nil || contained == ".." || strings.HasPrefix(contained, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes staging")
	}
	current := rootAbsolute
	for _, component := range strings.Split(contained, string(filepath.Separator)) {
		current = filepath.Join(current, component)
		info, statErr := os.Lstat(current)
		if errors.Is(statErr, os.ErrNotExist) {
			break
		}
		if statErr != nil || info.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("staged path contains an unreadable or symbolic-link component")
		}
	}
	return path, nil
}

func safePayloadRelativePath(path string) bool {
	return strings.HasPrefix(path, "payload/") && !strings.Contains(path, "\\") && !strings.Contains(path, "..") && !filepath.IsAbs(path)
}

func verifyExecutableArtifact(path string, artifact bootstrapArtifact) error {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() != artifact.SizeBytes {
		return fmt.Errorf("selected next updater is missing, non-regular, or has a different size")
	}
	if info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("selected next updater is not executable")
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return err
	}
	if hex.EncodeToString(digest.Sum(nil)) != artifact.SHA256 {
		return fmt.Errorf("selected next updater digest does not match C25")
	}
	return nil
}

func readRegularFile(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is not regular or is a symbolic link")
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
		return nil, fmt.Errorf("file exceeds maximum size")
	}
	return contents, nil
}

func decodeExactly(contents []byte, output any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(output); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}

func unavailable(code string, err error, dependency string) error {
	return hostupdatehandoffsupervisordomain.DispatchFailure{State: "unavailable", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: code, Message: err.Error(), Dependency: dependency}}
}
func failed(code string, err error, dependency string) error {
	return hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: code, Message: err.Error(), Dependency: dependency}}
}
func classifyReadFailure(code string, err error, dependency string) error {
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
		return unavailable(code, err, dependency)
	}
	return failed(code, err, dependency)
}
