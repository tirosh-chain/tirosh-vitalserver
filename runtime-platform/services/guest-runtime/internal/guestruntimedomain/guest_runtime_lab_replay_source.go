package guestruntimedomain

import (
	"fmt"
	"strings"
)

const (
	LabReplaySourceMediaType       = "application/x-vital"
	LabReplaySourceStorageType     = "guest-lab-replay-source-object"
	MaximumLabReplaySourceByteSize = int64(1 << 30)
)

type LabReplaySourceAdmissionCommand struct {
	SchemaVersion    string `json:"schemaVersion"`
	RequestID        string `json:"requestId"`
	SourceID         string `json:"sourceId"`
	OriginalFileName string `json:"originalFileName"`
	MediaType        string `json:"mediaType"`
	ByteSize         int64  `json:"byteSize"`
	SHA256           string `json:"sha256"`
}

type LabReplaySourceObjectReceipt struct {
	SchemaVersion    string            `json:"schemaVersion"`
	SourceReference  ResourceReference `json:"sourceReference"`
	State            string            `json:"state"`
	ByteSize         int64             `json:"byteSize"`
	SHA256           string            `json:"sha256"`
	StorageReference ResourceReference `json:"storageReference"`
	PersistedAt      string            `json:"persistedAt"`
}

type LabReplaySourceAdmissionReceipt struct {
	SchemaVersion    string                       `json:"schemaVersion"`
	RequestID        string                       `json:"requestId"`
	Outcome          string                       `json:"outcome"`
	SourceReference  ResourceReference            `json:"sourceReference"`
	OriginalFileName string                       `json:"originalFileName"`
	MediaType        string                       `json:"mediaType"`
	ByteSize         int64                        `json:"byteSize"`
	SHA256           string                       `json:"sha256"`
	ObjectReceipt    LabReplaySourceObjectReceipt `json:"objectReceipt"`
	PersistedAt      string                       `json:"persistedAt"`
}

func ValidateLabReplaySourceAdmissionCommand(
	command LabReplaySourceAdmissionCommand,
	maximumByteSize int64,
) error {
	if maximumByteSize < 1 ||
		maximumByteSize > MaximumLabReplaySourceByteSize {
		return fmt.Errorf("Lab replay source maximum byte size is invalid")
	}
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) ||
		!ValidIdentifier(command.SourceID) ||
		!validLabReplaySourceFileName(command.OriginalFileName) ||
		command.MediaType != LabReplaySourceMediaType ||
		command.ByteSize < 1 ||
		command.ByteSize > maximumByteSize ||
		!validSHA256(command.SHA256) {
		return fmt.Errorf("Lab replay source admission command is incomplete or invalid")
	}
	return nil
}

func ValidateLabReplaySourceObjectReceipt(
	receipt LabReplaySourceObjectReceipt,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		receipt.SourceReference.ResourceType != LabReplaySourceResourceType ||
		!ValidIdentifier(receipt.SourceReference.ResourceID) ||
		(receipt.State != "committed" && receipt.State != "existing") ||
		receipt.ByteSize < 1 ||
		receipt.ByteSize > MaximumLabReplaySourceByteSize ||
		!validSHA256(receipt.SHA256) ||
		receipt.StorageReference.ResourceType != LabReplaySourceStorageType ||
		receipt.StorageReference.ResourceID != receipt.SourceReference.ResourceID ||
		!validTimestamp(receipt.PersistedAt) {
		return fmt.Errorf("Lab replay source object receipt is incomplete or invalid")
	}
	return nil
}

func ValidateLabReplaySourceAdmissionReceipt(
	receipt LabReplaySourceAdmissionReceipt,
) error {
	if receipt.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(receipt.RequestID) ||
		(receipt.Outcome != "accepted" && receipt.Outcome != "duplicate") ||
		receipt.SourceReference.ResourceType != LabReplaySourceResourceType ||
		!ValidIdentifier(receipt.SourceReference.ResourceID) ||
		!validLabReplaySourceFileName(receipt.OriginalFileName) ||
		receipt.MediaType != LabReplaySourceMediaType ||
		receipt.ByteSize < 1 ||
		receipt.ByteSize > MaximumLabReplaySourceByteSize ||
		!validSHA256(receipt.SHA256) ||
		receipt.ObjectReceipt.SourceReference != receipt.SourceReference ||
		receipt.ObjectReceipt.ByteSize != receipt.ByteSize ||
		receipt.ObjectReceipt.SHA256 != receipt.SHA256 ||
		receipt.ObjectReceipt.PersistedAt != receipt.PersistedAt ||
		!validTimestamp(receipt.PersistedAt) {
		return fmt.Errorf("Lab replay source admission receipt is incomplete or invalid")
	}
	if err := ValidateLabReplaySourceObjectReceipt(receipt.ObjectReceipt); err != nil {
		return err
	}
	return nil
}

func validLabReplaySourceFileName(value string) bool {
	return value != "" &&
		len(value) <= 255 &&
		strings.TrimSpace(value) == value &&
		!strings.ContainsAny(value, `/\`) &&
		value != "." &&
		value != ".."
}
