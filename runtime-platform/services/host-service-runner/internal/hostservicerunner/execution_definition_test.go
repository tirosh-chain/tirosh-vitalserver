package hostservicerunner

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadExecutionDefinitionAcceptsOneExplicitHostCommand(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "host-agent-service.json")
	contents := `{"schemaVersion":"v1","documentKind":"host-service-execution-definition","serviceName":"VitalServerHostAgent","role":"host-agent","command":{"executablePath":"` + filepath.Join(directory, "host-agent") + `","arguments":["--deployment-configuration","` + filepath.Join(directory, "host-agent.json") + `"]}}`
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	definition, err := ReadExecutionDefinition(path)
	if err != nil {
		t.Fatal(err)
	}
	if definition.Role != "host-agent" || definition.Command.ExecutablePath != filepath.Join(directory, "host-agent") || len(definition.Command.Arguments) != 2 {
		t.Fatalf("unexpected definition: %#v", definition)
	}
}

func TestReadExecutionDefinitionRejectsUnknownFieldsAndRunnerRecursion(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "host-agent-service.json")
	contents := `{"schemaVersion":"v1","documentKind":"host-service-execution-definition","serviceName":"VitalServerHostAgent","role":"host-agent","command":{"executablePath":"` + filepath.Join(directory, "host-service-runner") + `","arguments":[]},"unexpected":true}`
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadExecutionDefinition(path); err == nil {
		t.Fatal("expected invalid explicit service definition rejection")
	}
}
