package owner

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeProviderWriteAtomicallyReplacesValidatedDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime-provider.json")
	initial := providerDocument("stopped")
	if err := WriteRuntimeProvider(path, initial); err != nil {
		t.Fatal(err)
	}
	updated := providerDocument("running")
	if err := WriteRuntimeProvider(path, updated); err != nil {
		t.Fatal(err)
	}
	resource := ReadRuntimeProvider(path)
	if resource.State != "loaded" || string(resource.Document) != string(updated) {
		t.Fatalf("resource=%+v document=%s", resource, resource.Document)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("owner document permissions=%o", info.Mode().Perm())
	}
}

func TestInvalidRuntimeProviderWritePreservesPreviousOwnerDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime-provider.json")
	initial := providerDocument("stopped")
	if err := WriteRuntimeProvider(path, initial); err != nil {
		t.Fatal(err)
	}
	if err := WriteRuntimeProvider(path, json.RawMessage(`{"state":"running"}`)); err == nil {
		t.Fatal("incomplete provider document must fail")
	}
	withUnknownField := append(json.RawMessage(nil), initial[:len(initial)-1]...)
	withUnknownField = append(withUnknownField, []byte(`,"fallback":true}`)...)
	if err := WriteRuntimeProvider(path, withUnknownField); err == nil {
		t.Fatal("unknown provider document field must fail")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != string(initial) {
		t.Fatalf("invalid write changed owner document: %s", data)
	}
}

func TestRuntimeProviderWriteRejectsInvalidLifecycleMeaning(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime-provider.json")
	tests := map[string]string{
		"unknown state":            `{"schemaVersion":1,"state":"healthy","operation":null,"operationID":null,"bootID":null,"startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":null}`,
		"invalid time":             `{"schemaVersion":1,"state":"stopped","operation":null,"operationID":null,"bootID":null,"startedAt":"today","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":null}`,
		"startup without deadline": `{"schemaVersion":1,"state":"starting","operation":"start-services","operationID":"operation-1","bootID":"boot-1","startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:00Z","deadlineAt":null,"terminalReason":null,"message":"starting"}`,
		"failed without evidence":  `{"schemaVersion":1,"state":"failed","operation":"start-services","operationID":"operation-1","bootID":"boot-1","startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:01Z","deadlineAt":null,"terminalReason":null,"message":null}`,
		"nullable wrong type":      `{"schemaVersion":1,"state":"stopped","operation":3,"operationID":null,"bootID":null,"startedAt":"2026-07-11T00:00:00Z","updatedAt":"2026-07-11T00:00:01Z","deadlineAt":null,"terminalReason":null,"message":null}`,
	}
	for name, document := range tests {
		t.Run(name, func(t *testing.T) {
			if err := WriteRuntimeProvider(path, json.RawMessage(document)); err == nil {
				t.Fatal("invalid lifecycle write succeeded")
			}
		})
	}
}

func TestEndpointWritePublishesCanonicalOwnerDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime-endpoint.json")
	if err := WriteEndpoint(path, "127.0.0.1"); err != nil {
		t.Fatal(err)
	}
	resource := ReadEndpoint(path)
	if resource.State != "loaded" || resource.Read == nil || resource.Read.Address == nil || *resource.Read.Address != "127.0.0.1" {
		t.Fatalf("endpoint resource=%+v", resource)
	}
}

func providerDocument(state string) json.RawMessage {
	document, _ := json.Marshal(map[string]any{
		"schemaVersion":  1,
		"state":          state,
		"operation":      nil,
		"operationID":    nil,
		"bootID":         nil,
		"startedAt":      "2026-07-11T00:00:00Z",
		"updatedAt":      "2026-07-11T00:00:00Z",
		"deadlineAt":     nil,
		"terminalReason": nil,
		"message":        nil,
	})
	return document
}
