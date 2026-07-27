// Package hostlocalupdatecoordination consumes the Host Agent-published
// OS-local administration descriptor. It observes only explicit Host-owned
// update ownership and publishes exact interruption termination evidence.
package hostlocalupdatecoordination

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

const maximumHostLocalResponseBytes int64 = 1 << 20

type Client struct{}

type ownershipReadResult struct {
	SchemaVersion  string             `json:"schemaVersion"`
	State          string             `json:"state"`
	ObservedAt     string             `json:"observedAt"`
	Value          *updateOwnership   `json:"value,omitempty"`
	Issue          *coordinationIssue `json:"issue,omitempty"`
	SourceRevision *int               `json:"sourceRevision,omitempty"`
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

func (Client) ObserveInterruption(ctx context.Context, descriptorPath string, updateID string, requestTimeout time.Duration) (hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation, bool, error) {
	if requestTimeout <= 0 {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-update-interruption-monitor-configuration-invalid", fmt.Errorf("request timeout must be positive"))
	}
	_, httpClient, err := openDescriptorClient(descriptorPath, requestTimeout)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-local-administration-unavailable", err)
	}
	return readInterruption(ctx, httpClient, updateID)
}

func (Client) WaitForInterruption(ctx context.Context, descriptorPath string, updateID string, pollInterval time.Duration, requestTimeout time.Duration) (hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation, error) {
	if pollInterval <= 0 || requestTimeout <= 0 {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, unavailable("host-update-interruption-monitor-configuration-invalid", fmt.Errorf("poll interval and request timeout must be positive"))
	}
	_, httpClient, err := openDescriptorClient(descriptorPath, requestTimeout)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, unavailable("host-local-administration-unavailable", err)
	}
	for {
		observation, interrupted, err := readInterruption(ctx, httpClient, updateID)
		if err != nil {
			return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, err
		}
		if interrupted {
			return observation, nil
		}
		timer := time.NewTimer(pollInterval)
		select {
		case <-ctx.Done():
			if !timer.Stop() {
				<-timer.C
			}
			return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, ctx.Err()
		case <-timer.C:
		}
	}
}

func (Client) PublishInterruptionConfirmation(ctx context.Context, descriptorPath string, requestTimeout time.Duration, confirmation hostupdatehandoffsupervisordomain.HostUpdateInterruptionConfirmation) error {
	if requestTimeout <= 0 {
		return unavailable("host-update-interruption-confirmation-configuration-invalid", fmt.Errorf("request timeout must be positive"))
	}
	descriptor, httpClient, err := openDescriptorClient(descriptorPath, requestTimeout)
	if err != nil {
		return unavailable("host-local-administration-unavailable", err)
	}
	body, err := json.Marshal(confirmation)
	if err != nil {
		return failed("host-update-interruption-confirmation-encode-failed", err)
	}
	endpoint := "http://host-agent/v1/platform/updates/" + url.PathEscape(confirmation.UpdateID) + ":confirm-interruption"
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return failed("host-update-interruption-confirmation-request-invalid", err)
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")
	response, err := httpClient.Do(request)
	if err != nil {
		return unavailable("host-update-interruption-confirmation-unavailable", err)
	}
	defer response.Body.Close()
	contents, err := readBounded(response.Body)
	if err != nil {
		return unavailable("host-update-interruption-confirmation-response-unreadable", err)
	}
	if response.StatusCode != http.StatusAccepted {
		return failed("host-update-interruption-confirmation-rejected", fmt.Errorf("Host Agent status=%d response=%s", response.StatusCode, string(contents)))
	}
	_ = descriptor
	return nil
}

func readInterruption(ctx context.Context, httpClient *http.Client, updateID string) (hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation, bool, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://host-agent/v1/platform/update-operation-ownership", nil)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-request-invalid", err)
	}
	request.Header.Set("Accept", "application/json")
	response, err := httpClient.Do(request)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-update-ownership-unavailable", err)
	}
	defer response.Body.Close()
	contents, err := readBounded(response.Body)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-update-ownership-response-unreadable", err)
	}
	if response.StatusCode != http.StatusOK {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-update-ownership-unavailable", fmt.Errorf("Host Agent status=%d", response.StatusCode))
	}
	var result ownershipReadResult
	if err := decodeExactly(contents, &result); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-response-invalid", err)
	}
	if result.SchemaVersion != hostupdatehandoffsupervisordomain.SchemaVersion || result.State != "available" || result.ObservedAt == "" || result.Value == nil || result.Issue != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, unavailable("host-update-ownership-not-available", fmt.Errorf("Host Agent did not provide available ownership"))
	}
	value := result.Value
	if value.SchemaVersion != hostupdatehandoffsupervisordomain.SchemaVersion || value.InstallationID == "" || value.InstallationRevision < 1 {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-invalid", fmt.Errorf("ownership installation identity is invalid"))
	}
	if value.State == "idle" {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, nil
	}
	if value.State != "active" || value.UpdateID != updateID || value.OperationID == "" || value.RequestID == "" || value.UpdateState == "" || value.JournalRevision < 1 {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-mismatch", fmt.Errorf("active ownership does not match the dispatched update"))
	}
	if !value.InterruptionRequested {
		if value.InterruptionRequestID != "" {
			return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-invalid", fmt.Errorf("interruption request identity exists without interruption intent"))
		}
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, nil
	}
	observation := hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{
		InstallationID:        value.InstallationID,
		InstallationRevision:  value.InstallationRevision,
		UpdateID:              value.UpdateID,
		JournalRevision:       value.JournalRevision,
		InterruptionRequestID: value.InterruptionRequestID,
	}
	if err := hostupdatehandoffsupervisordomain.ValidateHostUpdateInterruptionObservation(observation, updateID); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateInterruptionObservation{}, false, failed("host-update-ownership-invalid", err)
	}
	return observation, true, nil
}

func readBounded(reader io.Reader) ([]byte, error) {
	contents, err := io.ReadAll(io.LimitReader(reader, maximumHostLocalResponseBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(contents)) > maximumHostLocalResponseBytes {
		return nil, fmt.Errorf("Host-local response exceeds maximum document size")
	}
	return contents, nil
}

func failed(code string, err error) error {
	return hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: code, Message: err.Error(), Dependency: "host-agent"}}
}

func unavailable(code string, err error) error {
	return hostupdatehandoffsupervisordomain.DispatchFailure{State: "unavailable", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: code, Message: err.Error(), Dependency: "host-agent"}}
}
