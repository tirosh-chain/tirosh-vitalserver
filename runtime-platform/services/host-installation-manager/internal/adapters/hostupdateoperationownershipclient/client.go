// Package hostupdateoperationownershipclient reads the Host Agent-owned C80
// state through its declared OS-local administration descriptor.
package hostupdateoperationownershipclient

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

const maximumHostLocalDocumentBytes int64 = 1 << 20

type Client struct {
	descriptorPath string
	requestTimeout time.Duration
}

type endpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

type ownershipReadResult struct {
	SchemaVersion  string             `json:"schemaVersion"`
	State          string             `json:"state"`
	ObservedAt     string             `json:"observedAt"`
	Value          *updateOwnership   `json:"value,omitempty"`
	Issue          *coordinationIssue `json:"issue,omitempty"`
	SourceRevision *int               `json:"sourceRevision,omitempty"`
	Evidence       []json.RawMessage  `json:"evidenceReferences,omitempty"`
}

type updateOwnership struct {
	SchemaVersion         string `json:"schemaVersion"`
	InstallationID        string `json:"installationId"`
	InstallationRevision  int    `json:"installationRevision"`
	State                 string `json:"state"`
	UpdateID              string `json:"updateId,omitempty"`
	OperationID           string `json:"operationId,omitempty"`
	RequestID             string `json:"requestId,omitempty"`
	UpdateState           string `json:"updateState,omitempty"`
	JournalRevision       int    `json:"journalRevision,omitempty"`
	InterruptionRequested bool   `json:"interruptionRequested,omitempty"`
	InterruptionRequestID string `json:"interruptionRequestId,omitempty"`
}

type coordinationIssue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

func New(descriptorPath string, requestTimeout time.Duration) (*Client, error) {
	if descriptorPath == "" || !filepath.IsAbs(descriptorPath) || requestTimeout <= 0 {
		return nil, fmt.Errorf("absolute Host-local administration descriptor path and positive timeout are required")
	}
	return &Client{descriptorPath: descriptorPath, requestTimeout: requestTimeout}, nil
}

func (client *Client) ReadHostUpdateOperationOwnership(ctx context.Context) (hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation, error) {
	descriptor, err := readEndpointDescriptor(client.descriptorPath)
	if err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("read Host-local administration descriptor: %w", err)
	}
	httpClient, err := newDescriptorHTTPClient(descriptor, client.requestTimeout)
	if err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("configure Host-local administration client: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://host-agent/v1/platform/update-operation-ownership", nil)
	if err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("create Host update ownership request: %w", err)
	}
	request.Header.Set("Accept", "application/json")
	response, err := httpClient.Do(request)
	if err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("request Host update ownership: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK && response.StatusCode != http.StatusServiceUnavailable {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("Host update ownership returned HTTP %d", response.StatusCode)
	}
	contents, err := readBounded(response.Body)
	if err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("read Host update ownership response: %w", err)
	}
	var result ownershipReadResult
	if err := decodeExactly(contents, &result); err != nil {
		return hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{}, fmt.Errorf("decode Host update ownership response: %w", err)
	}
	observation := hostinstallationmanagerdomain.HostUpdateOperationOwnershipObservation{
		SchemaVersion: result.SchemaVersion,
		ReadState:     result.State,
		ObservedAt:    result.ObservedAt,
	}
	if result.Value != nil {
		observation.Ownership = &hostinstallationmanagerdomain.HostUpdateOperationOwnership{
			SchemaVersion:        result.Value.SchemaVersion,
			InstallationID:       result.Value.InstallationID,
			InstallationRevision: result.Value.InstallationRevision,
			State:                result.Value.State,
			UpdateID:             result.Value.UpdateID,
			OperationID:          result.Value.OperationID,
			RequestID:            result.Value.RequestID,
			UpdateState:          result.Value.UpdateState,
			JournalRevision:      result.Value.JournalRevision,
		}
	}
	if result.Issue != nil {
		observation.Issue = &hostinstallationmanagerdomain.HostInstallationIssue{Code: result.Issue.Code, Message: result.Issue.Message}
	}
	return observation, nil
}

func readEndpointDescriptor(path string) (endpointDescriptor, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return endpointDescriptor{}, fmt.Errorf("descriptor is missing, non-regular, or symbolic")
	}
	file, err := os.Open(path)
	if err != nil {
		return endpointDescriptor{}, err
	}
	defer file.Close()
	contents, err := readBounded(file)
	if err != nil {
		return endpointDescriptor{}, err
	}
	var descriptor endpointDescriptor
	if err := decodeExactly(contents, &descriptor); err != nil {
		return endpointDescriptor{}, err
	}
	if descriptor.SchemaVersion != hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion || descriptor.Address == "" {
		return endpointDescriptor{}, fmt.Errorf("descriptor identity is invalid")
	}
	return descriptor, nil
}

func readBounded(reader io.Reader) ([]byte, error) {
	contents, err := io.ReadAll(io.LimitReader(reader, maximumHostLocalDocumentBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(contents)) > maximumHostLocalDocumentBytes {
		return nil, fmt.Errorf("document exceeds maximum size")
	}
	return contents, nil
}

func decodeExactly(contents []byte, destination any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}
