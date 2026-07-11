package owner

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func ReadDocument(path string) contract.DocumentResource {
	data, err := os.ReadFile(path)
	if err != nil {
		message := fmt.Sprintf("resource read failed path=%s reason=%v", path, err)
		if errors.Is(err, os.ErrNotExist) {
			return contract.DocumentResource{State: "missing", Document: nullJSON(), ReadError: &message}
		}
		return contract.DocumentResource{State: "failed", Document: nullJSON(), ReadError: &message}
	}
	if !json.Valid(data) || !isJSONObject(data) {
		message := fmt.Sprintf("resource decode failed path=%s reason=expected JSON object", path)
		return contract.DocumentResource{State: "failed", Document: nullJSON(), ReadError: &message}
	}
	return contract.DocumentResource{State: "loaded", Document: append(json.RawMessage(nil), data...)}
}

func ReadOperation(path string) contract.OperationResource {
	resource := ReadDocument(path)
	if resource.State == "loaded" {
		if reason := validateLeaseDocument(resource.Document); reason != "" {
			message := fmt.Sprintf("operation lease decode failed path=%s reason=%s", path, reason)
			resource = contract.DocumentResource{State: "failed", Document: nullJSON(), ReadError: &message}
		}
	}
	return contract.OperationResource{
		State:     operationState(resource.State),
		Document:  resource.Document,
		ReadError: resource.ReadError,
	}
}

func ReadRuntimeProvider(path string) contract.DocumentResource {
	resource := ReadDocument(path)
	if resource.State != "loaded" {
		return resource
	}
	if reason := validateRuntimeProviderDocument(resource.Document); reason != "" {
		message := fmt.Sprintf("runtime provider decode failed path=%s reason=%s", path, reason)
		return contract.DocumentResource{State: "failed", Document: nullJSON(), ReadError: &message}
	}
	return resource
}

func ReadPlatformWorkflow(path string) contract.PlatformWorkflowResource {
	resource := ReadDocument(path)
	if resource.State == "missing" {
		return contract.PlatformWorkflowResource{State: "missing", ReadError: resource.ReadError}
	}
	if resource.State != "loaded" {
		return contract.PlatformWorkflowResource{State: "failed", ReadError: resource.ReadError}
	}
	if reason := validatePlatformWorkflowDocument(resource.Document); reason != "" {
		message := fmt.Sprintf("platform workflow decode failed path=%s reason=%s", path, reason)
		return contract.PlatformWorkflowResource{State: "failed", ReadError: &message}
	}
	var operation contract.PlatformWorkflowOperation
	if err := json.Unmarshal(resource.Document, &operation); err != nil {
		message := fmt.Sprintf("platform workflow decode failed path=%s reason=%v", path, err)
		return contract.PlatformWorkflowResource{State: "failed", ReadError: &message}
	}
	return contract.PlatformWorkflowResource{State: "loaded", Operation: &operation}
}

func ReadEndpoint(path string) contract.EndpointResource {
	resource := ReadDocument(path)
	if resource.State != "loaded" {
		return contract.EndpointResource{State: resource.State, ReadError: resource.ReadError}
	}
	if reason := validateRequiredFields(
		resource.Document,
		map[string]string{"address": "string", "source": "string", "state": "string"},
		nil,
	); reason != "" {
		message := fmt.Sprintf("runtime endpoint decode failed path=%s reason=%s", path, reason)
		return contract.EndpointResource{State: "failed", ReadError: &message}
	}
	var document struct {
		Address string `json:"address"`
		Source  string `json:"source"`
		State   string `json:"state"`
	}
	if err := json.Unmarshal(resource.Document, &document); err != nil {
		message := fmt.Sprintf("runtime endpoint decode failed path=%s reason=%v", path, err)
		return contract.EndpointResource{State: "failed", ReadError: &message}
	}
	if document.State != "loaded" || document.Address == "" || document.Source != "platform-agent" {
		message := fmt.Sprintf("runtime endpoint invalid path=%s", path)
		return contract.EndpointResource{State: "failed", ReadError: &message}
	}
	address, source := document.Address, document.Source
	return contract.EndpointResource{
		State: "loaded",
		Read: &contract.EndpointRead{
			State: "loaded", Address: &address, Source: &source,
		},
	}
}

func ActiveOperation(lease contract.OperationResource) *string {
	if lease.State != "loaded" {
		return nil
	}
	var document struct {
		Operation string `json:"operation"`
	}
	if err := json.Unmarshal(lease.Document, &document); err != nil || document.Operation == "" {
		return nil
	}
	return &document.Operation
}

func PresentOperationAt(resource contract.OperationResource, now time.Time) contract.OperationResource {
	if resource.State != "loaded" {
		return resource
	}
	var document leaseDocument
	if err := json.Unmarshal(resource.Document, &document); err != nil {
		message := "runtime operation lease decode failed: " + err.Error()
		return contract.OperationResource{State: "failed", Document: nullJSON(), ReadError: &message}
	}
	if document.ExpiresAt == nil {
		return resource
	}
	expiration, err := time.Parse(time.RFC3339Nano, *document.ExpiresAt)
	if err != nil {
		message := fmt.Sprintf(
			"runtime operation lease expiresAt is invalid operationId=%s expiresAt=%s",
			document.OperationID,
			*document.ExpiresAt,
		)
		return contract.OperationResource{State: "failed", Document: nullJSON(), ReadError: &message}
	}
	if !now.After(expiration) {
		return resource
	}
	expiredSeconds := int(math.Round(now.Sub(expiration).Seconds()))
	reason := fmt.Sprintf(
		"runtime operation lease expired operationId=%s expiresAt=%s expiredSeconds=%d",
		document.OperationID,
		*document.ExpiresAt,
		expiredSeconds,
	)
	resource.State = "stale"
	resource.StaleReason = &reason
	return resource
}

func UnavailableOperation(reason string) contract.OperationResource {
	return contract.OperationResource{
		State: "unavailable", Document: nullJSON(), ReadError: &reason,
	}
}

func operationState(state string) string {
	if state == "missing" {
		return "unavailable"
	}
	return state
}

func nullJSON() json.RawMessage {
	return json.RawMessage("null")
}

func isJSONObject(data []byte) bool {
	trimmed := bytes.TrimSpace(data)
	return len(trimmed) >= 2 && trimmed[0] == '{' && trimmed[len(trimmed)-1] == '}'
}

func validateRuntimeProviderDocument(data json.RawMessage) string {
	if reason := validateRequiredFields(
		data,
		map[string]string{
			"schemaVersion": "number", "state": "string", "startedAt": "string", "updatedAt": "string",
		},
		[]string{"operation", "operationID", "bootID", "deadlineAt", "terminalReason", "message"},
	); reason != "" {
		return reason
	}
	var document struct {
		SchemaVersion  int     `json:"schemaVersion"`
		State          string  `json:"state"`
		Operation      *string `json:"operation"`
		OperationID    *string `json:"operationID"`
		BootID         *string `json:"bootID"`
		StartedAt      string  `json:"startedAt"`
		UpdatedAt      string  `json:"updatedAt"`
		DeadlineAt     *string `json:"deadlineAt"`
		TerminalReason *string `json:"terminalReason"`
		Message        *string `json:"message"`
	}
	if err := json.Unmarshal(data, &document); err != nil {
		return err.Error()
	}
	if document.SchemaVersion != 1 {
		return fmt.Sprintf("unsupported schemaVersion %d", document.SchemaVersion)
	}
	knownStates := map[string]struct{}{
		"starting": {}, "bootstrapping": {}, "running": {},
		"stopping": {}, "stopped": {}, "failed": {},
	}
	if _, exists := knownStates[document.State]; !exists {
		return "unknown state " + document.State
	}
	if _, err := time.Parse(time.RFC3339Nano, document.StartedAt); err != nil {
		return "startedAt must be RFC3339"
	}
	if _, err := time.Parse(time.RFC3339Nano, document.UpdatedAt); err != nil {
		return "updatedAt must be RFC3339"
	}
	if document.DeadlineAt != nil {
		if _, err := time.Parse(time.RFC3339Nano, *document.DeadlineAt); err != nil {
			return "deadlineAt must be null or RFC3339"
		}
	}
	if (document.State == "starting" || document.State == "bootstrapping") && document.DeadlineAt == nil {
		return "active startup state requires deadlineAt"
	}
	if document.State == "failed" {
		if document.TerminalReason == nil || *document.TerminalReason == "" {
			return "failed state requires terminalReason"
		}
		if document.Message == nil || *document.Message == "" {
			return "failed state requires message"
		}
	} else if document.TerminalReason != nil {
		return "non-failed state requires null terminalReason"
	}
	return ""
}

func validatePlatformWorkflowDocument(data json.RawMessage) string {
	if reason := validateRequiredFields(
		data,
		map[string]string{
			"schemaVersion": "number", "operationId": "string", "kind": "string",
			"state": "string", "startedAt": "string", "updatedAt": "string",
		},
		[]string{"release", "artifact", "failure"},
	); reason != "" {
		return reason
	}
	var document contract.PlatformWorkflowOperation
	if err := json.Unmarshal(data, &document); err != nil {
		return err.Error()
	}
	if document.SchemaVersion != 1 {
		return fmt.Sprintf("unsupported schemaVersion %d", document.SchemaVersion)
	}
	knownKinds := map[string]struct{}{
		"update-verify": {}, "update-apply": {}, "rollback": {}, "uninstall": {}, "support-export": {},
	}
	if _, exists := knownKinds[document.Kind]; !exists {
		return "unknown kind " + document.Kind
	}
	knownStates := map[string]struct{}{
		"accepted": {}, "running": {}, "completed": {}, "failed": {},
	}
	if _, exists := knownStates[document.State]; !exists {
		return "unknown state " + document.State
	}
	if document.OperationID == "" {
		return "operationId must not be empty"
	}
	if _, err := time.Parse(time.RFC3339Nano, document.StartedAt); err != nil {
		return "startedAt must be RFC3339"
	}
	if _, err := time.Parse(time.RFC3339Nano, document.UpdatedAt); err != nil {
		return "updatedAt must be RFC3339"
	}
	if document.State == "failed" {
		if document.Failure == nil || document.Failure.Kind == "" || document.Failure.Message == "" {
			return "failed state requires failure kind and message"
		}
	} else if document.Failure != nil {
		return "non-failed state requires null failure"
	}
	if document.Release != nil && (document.Release.PlatformVersion == "" || document.Release.RuntimeBundleVersion == "") {
		return "release versions must not be empty"
	}
	if document.Artifact != nil {
		if document.Kind != "support-export" || document.State != "completed" {
			return "artifact is only allowed for completed support-export"
		}
		if document.Artifact.Path == "" || !filepath.IsAbs(document.Artifact.Path) || document.Artifact.SizeBytes < 0 {
			return "support export artifact path and sizeBytes are invalid"
		}
		decoded, err := hex.DecodeString(document.Artifact.SHA256)
		if err != nil || len(decoded) != sha256.Size || document.Artifact.SHA256 != strings.ToLower(document.Artifact.SHA256) {
			return "support export artifact sha256 is invalid"
		}
	} else if document.Kind == "support-export" && document.State == "completed" {
		return "completed support-export requires artifact"
	}
	return ""
}

func validateLeaseDocument(data json.RawMessage) string {
	return validateRequiredFields(
		data,
		map[string]string{
			"schemaVersion": "number", "operationId": "string", "operation": "string",
			"startedAt": "string", "heartbeatAt": "string",
		},
		[]string{"ownerPID", "expiresAt", "message"},
	)
}

func validateRequiredFields(
	data json.RawMessage,
	typed map[string]string,
	nullable []string,
) string {
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		return err.Error()
	}
	for field, expected := range typed {
		value, exists := document[field]
		if !exists {
			return "missing field " + field
		}
		valid := (expected == "string" && isString(value)) || (expected == "number" && isNumber(value))
		if !valid {
			return fmt.Sprintf("field %s must be %s", field, expected)
		}
	}
	for _, field := range nullable {
		if _, exists := document[field]; !exists {
			return "missing explicit nullable field " + field
		}
	}
	allowed := make(map[string]struct{}, len(typed)+len(nullable))
	for field := range typed {
		allowed[field] = struct{}{}
	}
	for _, field := range nullable {
		allowed[field] = struct{}{}
	}
	for field := range document {
		if _, exists := allowed[field]; !exists {
			return "unknown field " + field
		}
	}
	return ""
}

func isString(value any) bool {
	_, ok := value.(string)
	return ok
}

func isNumber(value any) bool {
	_, ok := value.(float64)
	return ok
}
