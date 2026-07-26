// Package hostservicerunner owns the narrow OS-service adapter input. The
// definition is release-owned, hash-bound by C48, and names exactly one Host
// executable; it is not Host, Guest, Recorder, or update state.
package hostservicerunner

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const executionDefinitionSchemaVersion = "v1"
const executionDefinitionDocumentKind = "host-service-execution-definition"

// ExecutionDefinition is an adapter-owned process command for one service
// manager registration. C48 owns the file identity and the SCM registration;
// this adapter only validates and executes its named child process.
type ExecutionDefinition struct {
	SchemaVersion string                     `json:"schemaVersion"`
	DocumentKind  string                     `json:"documentKind"`
	ServiceName   string                     `json:"serviceName"`
	Role          string                     `json:"role"`
	Command       DeclaredHostServiceCommand `json:"command"`
}

// DeclaredHostServiceCommand has no shell string. Arguments are preserved as
// declared array elements so the runner never interprets shell metacharacters.
type DeclaredHostServiceCommand struct {
	ExecutablePath string   `json:"executablePath"`
	Arguments      []string `json:"arguments"`
}

// ReadExecutionDefinition reads one regular, non-symbolic, explicit file.
// Missing, unreadable, malformed, and invalid inputs remain distinct errors
// to the service manager; none become an empty or default command.
func ReadExecutionDefinition(path string) (ExecutionDefinition, error) {
	if !filepath.IsAbs(path) {
		return ExecutionDefinition{}, fmt.Errorf("service definition path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return ExecutionDefinition{}, fmt.Errorf("inspect service definition: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return ExecutionDefinition{}, fmt.Errorf("service definition must be one regular non-symbolic file")
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return ExecutionDefinition{}, fmt.Errorf("read service definition: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	var definition ExecutionDefinition
	if err := decoder.Decode(&definition); err != nil {
		return ExecutionDefinition{}, fmt.Errorf("decode service definition: %w", err)
	}
	if decoder.More() {
		return ExecutionDefinition{}, fmt.Errorf("service definition must contain one JSON document")
	}
	if err := validateExecutionDefinition(definition); err != nil {
		return ExecutionDefinition{}, err
	}
	return definition, nil
}

func validateExecutionDefinition(definition ExecutionDefinition) error {
	if definition.SchemaVersion != executionDefinitionSchemaVersion || definition.DocumentKind != executionDefinitionDocumentKind {
		return fmt.Errorf("service definition identity is invalid")
	}
	if !validServiceName(definition.ServiceName) || !validRole(definition.Role) {
		return fmt.Errorf("service definition service name or role is invalid")
	}
	if !filepath.IsAbs(definition.Command.ExecutablePath) || filepath.Base(definition.Command.ExecutablePath) == "host-service-runner" || filepath.Base(definition.Command.ExecutablePath) == "host-service-runner.exe" {
		return fmt.Errorf("service definition command executable is invalid")
	}
	if len(definition.Command.Arguments) > 64 {
		return fmt.Errorf("service definition command has too many arguments")
	}
	for _, argument := range definition.Command.Arguments {
		if argument == "" || len(argument) > 4096 || strings.ContainsRune(argument, '\x00') {
			return fmt.Errorf("service definition command argument is invalid")
		}
	}
	return nil
}

func validServiceName(value string) bool {
	if value == "" || len(value) > 255 {
		return false
	}
	for _, character := range value {
		if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character == '-' || character == '_' || character == '.' {
			continue
		}
		return false
	}
	return true
}

func validRole(value string) bool {
	return value == "host-agent" || value == "host-edge-proxy" || value == "host-update-handoff-supervisor"
}
