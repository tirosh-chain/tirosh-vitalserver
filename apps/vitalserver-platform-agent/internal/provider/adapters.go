package provider

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

type HTTPReadinessProbe struct {
	Client *http.Client
}

func (probe HTTPReadinessProbe) Read(ctx context.Context, url string) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	response, err := probe.Client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("HTTP status=%d", response.StatusCode)
	}
	return nil
}

type FileStateOwner struct {
	LifecyclePath string
	EndpointPath  string
}

func (stateOwner FileStateOwner) WriteLifecycle(document Document) error {
	data, err := json.Marshal(document)
	if err != nil {
		return fmt.Errorf("runtime provider lifecycle encode failed: %w", err)
	}
	return owner.WriteRuntimeProvider(stateOwner.LifecyclePath, data)
}

func (stateOwner FileStateOwner) PublishEndpoint(address string) error {
	return owner.WriteEndpoint(stateOwner.EndpointPath, address)
}

func (stateOwner FileStateOwner) RemoveEndpoint() error {
	return owner.RemoveRuntimeEndpoint(stateOwner.EndpointPath)
}

func RandomID() (string, error) {
	data := make([]byte, 16)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return hex.EncodeToString(data), nil
}
