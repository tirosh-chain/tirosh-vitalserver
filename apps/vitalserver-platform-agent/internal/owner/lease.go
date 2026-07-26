package owner

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
)

type LeaseErrorKind string

const (
	LeaseInvalid  LeaseErrorKind = "invalid"
	LeaseConflict LeaseErrorKind = "conflict"
	LeaseRead     LeaseErrorKind = "read-failed"
	LeaseWrite    LeaseErrorKind = "write-failed"
)

type LeaseError struct {
	Kind    LeaseErrorKind
	Message string
}

func (err LeaseError) Error() string { return err.Message }

type leaseDocument struct {
	SchemaVersion int     `json:"schemaVersion"`
	OperationID   string  `json:"operationId"`
	Operation     string  `json:"operation"`
	OwnerPID      *int    `json:"ownerPID"`
	StartedAt     string  `json:"startedAt"`
	HeartbeatAt   string  `json:"heartbeatAt"`
	ExpiresAt     *string `json:"expiresAt"`
	Message       *string `json:"message"`
}

func AcquireLease(path string, document json.RawMessage) error {
	if reason := validateLeaseDocument(document); reason != "" {
		return LeaseError{Kind: LeaseInvalid, Message: "operation lease document invalid: " + reason}
	}
	return withExclusiveFileLock(path+".lock", func() error {
		existing := ReadOperation(path)
		switch existing.State {
		case "unavailable":
			if err := writeAtomic(path, document); err != nil {
				return LeaseError{Kind: LeaseWrite, Message: err.Error()}
			}
			return nil
		case "loaded":
			var lease leaseDocument
			if err := json.Unmarshal(existing.Document, &lease); err != nil {
				return LeaseError{Kind: LeaseRead, Message: "existing operation lease decode failed: " + err.Error()}
			}
			return LeaseError{
				Kind:    LeaseConflict,
				Message: fmt.Sprintf("operation lease already exists operationId=%s operation=%s", lease.OperationID, lease.Operation),
			}
		default:
			return LeaseError{Kind: LeaseRead, Message: valueOr(existing.ReadError, "operation lease read failed")}
		}
	})
}

func HeartbeatLease(path, operationID, heartbeatAt string, expiresAt *string) error {
	if operationID == "" || heartbeatAt == "" {
		return LeaseError{Kind: LeaseInvalid, Message: "operationId and heartbeatAt are required"}
	}
	return withExclusiveFileLock(path+".lock", func() error {
		existing, err := requiredLease(path, "heartbeat")
		if err != nil {
			return err
		}
		if existing.OperationID != operationID {
			return LeaseError{
				Kind:    LeaseConflict,
				Message: fmt.Sprintf("operation lease id mismatch expected=%s actual=%s", operationID, existing.OperationID),
			}
		}
		existing.HeartbeatAt = heartbeatAt
		existing.ExpiresAt = expiresAt
		data, marshalErr := json.Marshal(existing)
		if marshalErr != nil {
			return LeaseError{Kind: LeaseWrite, Message: "operation lease encode failed: " + marshalErr.Error()}
		}
		if writeErr := writeAtomic(path, data); writeErr != nil {
			return LeaseError{Kind: LeaseWrite, Message: writeErr.Error()}
		}
		return nil
	})
}

func ReleaseLease(path, operationID string) error {
	if operationID == "" {
		return LeaseError{Kind: LeaseInvalid, Message: "operationId is required"}
	}
	return withExclusiveFileLock(path+".lock", func() error {
		existing := ReadOperation(path)
		if existing.State == "unavailable" {
			return nil
		}
		if existing.State != "loaded" {
			return LeaseError{Kind: LeaseRead, Message: valueOr(existing.ReadError, "operation lease read failed")}
		}
		var lease leaseDocument
		if err := json.Unmarshal(existing.Document, &lease); err != nil {
			return LeaseError{Kind: LeaseRead, Message: "existing operation lease decode failed: " + err.Error()}
		}
		if lease.OperationID != operationID {
			return LeaseError{
				Kind:    LeaseConflict,
				Message: fmt.Sprintf("operation lease id mismatch expected=%s actual=%s", operationID, lease.OperationID),
			}
		}
		if err := os.Remove(path); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			return LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease remove failed path=%s: %v", path, err)}
		}
		return nil
	})
}

func requiredLease(path, operation string) (leaseDocument, error) {
	resource := ReadOperation(path)
	if resource.State != "loaded" {
		return leaseDocument{}, LeaseError{
			Kind:    LeaseRead,
			Message: fmt.Sprintf("operation lease unavailable during %s: %s", operation, valueOr(resource.ReadError, resource.State)),
		}
	}
	var document leaseDocument
	if err := json.Unmarshal(resource.Document, &document); err != nil {
		return leaseDocument{}, LeaseError{Kind: LeaseRead, Message: "operation lease decode failed: " + err.Error()}
	}
	return document, nil
}

func valueOr(value *string, fallback string) string {
	if value != nil {
		return *value
	}
	return fallback
}
