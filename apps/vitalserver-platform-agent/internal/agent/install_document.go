package agent

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

type installDocument struct {
	SchemaVersion   int    `json:"schemaVersion"`
	State           string `json:"state"`
	PlatformVersion string `json:"platformVersion"`
}

func readInstallDocument(path string) (string, *string, *contract.ReadIssue) {
	if path == "" {
		return "unavailable", nil, &contract.ReadIssue{
			Source: "installation", Message: "install operation owner is not configured",
		}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "missing", nil, nil
		}
		return "read-failed", nil, &contract.ReadIssue{
			Source: "installation", Message: fmt.Sprintf("install document read failed path=%s: %v", path, err),
		}
	}
	var document installDocument
	if err := json.Unmarshal(data, &document); err != nil {
		return "invalid", nil, &contract.ReadIssue{
			Source: "installation", Message: fmt.Sprintf("install document decode failed path=%s: %v", path, err),
		}
	}
	if document.SchemaVersion != 1 || document.State != "installed" || document.PlatformVersion == "" {
		return "invalid", nil, &contract.ReadIssue{
			Source: "installation", Message: fmt.Sprintf(
				"install document contract is invalid path=%s schemaVersion=%d state=%q platformVersion=%q",
				path, document.SchemaVersion, document.State, document.PlatformVersion,
			),
		}
	}
	version := document.PlatformVersion
	return "installed", &version, nil
}

func readInstallOperation(path string) contract.OperationResource {
	if path == "" {
		reason := "install operation owner is not configured"
		return contract.OperationResource{State: "unavailable", ReadError: &reason}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return contract.OperationResource{State: "missing"}
		}
		reason := fmt.Sprintf("install document read failed path=%s: %v", path, err)
		return contract.OperationResource{State: "read-failed", ReadError: &reason}
	}
	var document installDocument
	if err := json.Unmarshal(data, &document); err != nil {
		reason := fmt.Sprintf("install document decode failed path=%s: %v", path, err)
		return contract.OperationResource{State: "invalid", ReadError: &reason}
	}
	if document.SchemaVersion != 1 || document.State != "installed" || document.PlatformVersion == "" {
		reason := fmt.Sprintf("install document contract is invalid path=%s", path)
		return contract.OperationResource{State: "invalid", Document: data, ReadError: &reason}
	}
	return contract.OperationResource{State: "loaded", Document: data}
}
