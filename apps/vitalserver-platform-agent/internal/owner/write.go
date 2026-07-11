package owner

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

func WriteRuntimeProvider(path string, document json.RawMessage) error {
	if reason := validateRuntimeProviderDocument(document); reason != "" {
		return fmt.Errorf("runtime provider document invalid: %s", reason)
	}
	return writeAtomic(path, document)
}

func WritePlatformWorkflow(path string, document contract.PlatformWorkflowOperation) error {
	data, err := json.Marshal(document)
	if err != nil {
		return fmt.Errorf("platform workflow document encode failed: %w", err)
	}
	if reason := validatePlatformWorkflowDocument(data); reason != "" {
		return fmt.Errorf("platform workflow document invalid: %s", reason)
	}
	return writeAtomic(path, data)
}

func RemoveRuntimeEndpoint(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("runtime endpoint remove failed path=%s: %w", path, err)
	}
	return nil
}

func WriteEndpoint(path, address string) error {
	document, err := json.Marshal(map[string]string{
		"address": address,
		"source":  "platform-agent",
		"state":   "loaded",
	})
	if err != nil {
		return fmt.Errorf("runtime endpoint encode failed: %w", err)
	}
	return writeAtomic(path, document)
}

func writeAtomic(path string, data []byte) (resultErr error) {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".vitalserver-owner-*")
	if err != nil {
		return fmt.Errorf("owner temporary file create failed path=%s: %w", path, err)
	}
	temporaryPath := temporary.Name()
	defer func() {
		if cleanupErr := os.Remove(temporaryPath); cleanupErr != nil && !os.IsNotExist(cleanupErr) && resultErr == nil {
			resultErr = fmt.Errorf("owner temporary file cleanup failed path=%s: %w", temporaryPath, cleanupErr)
		}
	}()
	if err := temporary.Chmod(0o600); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("owner temporary file permission failed path=%s: %w", temporaryPath, err)
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("owner temporary file write failed path=%s: %w", temporaryPath, err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("owner temporary file sync failed path=%s: %w", temporaryPath, err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("owner temporary file close failed path=%s: %w", temporaryPath, err)
	}
	if err := replaceFile(temporaryPath, path); err != nil {
		return fmt.Errorf("owner atomic replace failed path=%s: %w", path, err)
	}
	return nil
}
