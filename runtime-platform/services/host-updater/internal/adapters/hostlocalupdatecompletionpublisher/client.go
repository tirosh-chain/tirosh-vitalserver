// Package hostlocalupdatecompletionpublisher publishes an explicit C27 command
// through the Host Agent-published C52 OS-local transport. It owns transport
// only; C28 meaning stays in the staged next-updater domain.
package hostlocalupdatecompletionpublisher

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

const maximumResponseBytes int64 = 1 << 20

func publishStagedProductUpdateCompletion(ctx context.Context, httpClient *http.Client, endpoint string, command hostupdaterdomain.StagedProductUpdateCompletionCommand) error {
	if httpClient == nil {
		return fmt.Errorf("Host-local completion HTTP client is required")
	}
	body, err := json.Marshal(command)
	if err != nil {
		return fmt.Errorf("encode C27 update completion command: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create C27 update completion request: %w", err)
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")
	response, err := httpClient.Do(request)
	if err != nil {
		return fmt.Errorf("publish C27 update completion: %w", err)
	}
	defer response.Body.Close()
	contents, readErr := io.ReadAll(io.LimitReader(response.Body, maximumResponseBytes+1))
	if readErr != nil {
		return fmt.Errorf("read C27 completion response: %w", readErr)
	}
	if int64(len(contents)) > maximumResponseBytes {
		return fmt.Errorf("C27 completion response exceeds maximum document size")
	}
	if response.StatusCode != http.StatusAccepted {
		return fmt.Errorf("Host-local C27 completion was rejected status=%d response=%s", response.StatusCode, strings.TrimSpace(string(contents)))
	}
	return nil
}

// stagedProductUpdateCompletionURL is shared by OS-local transports after
// they have authenticated their own C52 endpoint. It validates URL syntax but
// intentionally does not make a network-locality decision itself.
func stagedProductUpdateCompletionURL(completionEndpoint string, updateID string) (string, error) {
	if !validEndpointIdentifier(updateID) {
		return "", fmt.Errorf("C27 completion updateId is invalid")
	}
	endpoint, err := url.ParseRequestURI(completionEndpoint)
	if err != nil || (endpoint.Scheme != "http" && endpoint.Scheme != "https") || endpoint.Host == "" || endpoint.RawQuery != "" || endpoint.Fragment != "" || endpoint.User != nil {
		return "", fmt.Errorf("Host-local completion endpoint must be an explicit http or https origin")
	}
	path := strings.TrimRight(endpoint.Path, "/")
	if path != "" {
		return "", fmt.Errorf("Host-local completion endpoint must not include a path")
	}
	endpoint.Path = "/v1/platform/updates/" + url.PathEscape(updateID) + ":complete"
	return endpoint.String(), nil
}

func validEndpointIdentifier(value string) bool {
	if len(value) < 1 || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != ':' && character != '-' {
			return false
		}
		if index == 0 && !(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}
