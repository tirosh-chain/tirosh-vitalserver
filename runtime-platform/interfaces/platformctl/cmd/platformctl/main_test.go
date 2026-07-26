package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcommand"
)

func TestRunPrintsUsageForHelpWithoutSelectingAnEndpoint(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	if err := run([]string{"help"}, &stdout, &stderr); err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if !strings.Contains(stdout.String(), "--control-endpoint") {
		t.Fatalf("stdout = %q", stdout.String())
	}
}

func TestRunRejectsRemoteEndpointBeforeAnyRequest(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	err := run([]string{"--control-endpoint", "http://192.0.2.20:18280", "installation"}, &stdout, &stderr)
	if err == nil || !strings.Contains(err.Error(), "127.0.0.1 or ::1") {
		t.Fatalf("run() error = %v, want loopback rejection", err)
	}
}

func TestMaterializePasswordFromStandardInputAddsOnlyTheTransientPassword(t *testing.T) {
	invocation := platformctlcommand.Invocation{
		Method:                         "POST",
		Route:                          "/v1/runtime/archive/credential-material",
		ReadsPasswordFromStandardInput: true,
		Body:                           []byte(`{"schemaVersion":"v1","credentialReference":{"kind":"vitalserver-library-credential","id":"external-library"},"userId":"operator"}`),
	}
	materialized, err := materializePasswordFromStandardInput(invocation, strings.NewReader("not-logged-or-persisted\n"))
	if err != nil {
		t.Fatalf("materializePasswordFromStandardInput() error = %v", err)
	}
	if materialized.ReadsPasswordFromStandardInput {
		t.Fatal("materialized invocation still requested standard input")
	}
	var body map[string]any
	if err := json.Unmarshal(materialized.Body, &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["password"] != "not-logged-or-persisted" || body["userId"] != "operator" {
		t.Fatalf("body = %#v", body)
	}
}

func TestMaterializePasswordFromStandardInputRejectsEmptyMultilineAndOversizedSecrets(t *testing.T) {
	invocation := platformctlcommand.Invocation{ReadsPasswordFromStandardInput: true, Body: []byte(`{"schemaVersion":"v1","credentialReference":{"kind":"kind","id":"id"},"userId":"operator"}`)}
	for _, input := range []string{"", "\n", "first\nsecond\n", strings.Repeat("x", 4097)} {
		if _, err := materializePasswordFromStandardInput(invocation, strings.NewReader(input)); err == nil {
			t.Fatalf("materializePasswordFromStandardInput(%q) succeeded", input)
		}
	}
}
