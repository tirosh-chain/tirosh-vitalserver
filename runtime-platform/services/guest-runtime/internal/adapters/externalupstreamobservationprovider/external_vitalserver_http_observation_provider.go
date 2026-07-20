package externalupstreamobservationprovider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumExternalVitalServerDeliveryConfigurationBytes int64 = 1 << 20

// ExternalVitalServerHTTPObservationProvider reads one explicit C46 document
// and probes only the administrator-approved observation endpoint it names.
// It neither derives a health route from packet delivery nor accepts redirects
// as evidence for a different upstream endpoint.
type ExternalVitalServerHTTPObservationProvider struct {
	reference                     guestruntimedomain.IntegrationProviderReference
	externalUpstreamIntegrationID string
	endpoint                      string
	acceptedStatusCodes           map[int]struct{}
	client                        *http.Client
}

// NewExternalVitalServerHTTPObservationProviderFromFile opens the explicit
// C46 owner document. It fails composition on unreadable, invalid, or
// mismatched desired configuration; such failure never becomes a configured
// empty upstream observation provider.
func NewExternalVitalServerHTTPObservationProviderFromFile(
	reference guestruntimedomain.IntegrationProviderReference,
	externalVitalServerDeliveryConfigurationPath string,
	requestTimeout time.Duration,
) (*ExternalVitalServerHTTPObservationProvider, error) {
	if reference.Kind != "external-vitalserver-http" || !guestruntimedomain.ValidIdentifier(reference.ID) || reference.CapabilityRevision < 1 {
		return nil, fmt.Errorf("External VitalServer HTTP observation provider reference must be explicit and valid")
	}
	if requestTimeout < time.Millisecond || requestTimeout > time.Minute {
		return nil, fmt.Errorf("External VitalServer HTTP observation request timeout must be between one millisecond and one minute")
	}
	configuration, err := loadExternalVitalServerDeliveryConfiguration(externalVitalServerDeliveryConfigurationPath)
	if err != nil {
		return nil, err
	}
	if configuration.ExternalUpstreamIntegrationReference.ResourceID != reference.ID || configuration.VitalServerDeliveryProvider.ID != reference.ID || configuration.VitalServerDeliveryProvider.CapabilityRevision != reference.CapabilityRevision {
		return nil, fmt.Errorf("C46 External VitalServer configuration does not match selected External Upstream provider")
	}
	endpoint, err := configuration.VitalServerObservationEndpoint.URL()
	if err != nil {
		return nil, err
	}
	acceptedStatusCodes := make(map[int]struct{}, len(configuration.VitalServerObservationEndpoint.AcceptedStatusCodes))
	for _, statusCode := range configuration.VitalServerObservationEndpoint.AcceptedStatusCodes {
		acceptedStatusCodes[statusCode] = struct{}{}
	}
	return &ExternalVitalServerHTTPObservationProvider{
		reference:                     reference,
		externalUpstreamIntegrationID: configuration.ExternalUpstreamIntegrationReference.ResourceID,
		endpoint:                      endpoint,
		acceptedStatusCodes:           acceptedStatusCodes,
		client: &http.Client{
			Timeout: requestTimeout,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}, nil
}

func (provider *ExternalVitalServerHTTPObservationProvider) ExternalUpstreamObservationProviderReference() guestruntimedomain.IntegrationProviderReference {
	return provider.reference
}

func (provider *ExternalVitalServerHTTPObservationProvider) ObserveExternalUpstream(ctx context.Context, integrationID string, spec guestruntimedomain.ExternalUpstreamSpec, observedAt string) (guestruntimedomain.ExternalUpstreamObservation, error) {
	if provider == nil || provider.client == nil {
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("External VitalServer HTTP observation provider is not configured")
	}
	if integrationID != provider.externalUpstreamIntegrationID || !guestruntimedomain.ExternalProviderReferenceEqual(provider.reference, spec.Provider) {
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("External Upstream integration does not match configured External VitalServer observation provider")
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, provider.endpoint, nil)
	if err != nil {
		return guestruntimedomain.ExternalUpstreamObservation{}, fmt.Errorf("create External VitalServer observation request: %w", err)
	}
	response, err := provider.client.Do(request)
	if err != nil {
		return externalVitalServerUnavailableObservation(provider.reference, observedAt, "external-vitalserver-observation-unavailable", "configured External VitalServer observation endpoint is unavailable"), nil
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if _, accepted := provider.acceptedStatusCodes[response.StatusCode]; !accepted {
		return externalVitalServerUnavailableObservation(provider.reference, observedAt, "external-vitalserver-observation-status-unaccepted", fmt.Sprintf("configured External VitalServer observation endpoint returned unaccepted HTTP status %d", response.StatusCode)), nil
	}
	capability, err := guestruntimedomain.NewExternalUpstreamCapabilityDocument(integrationID, provider.reference, observedAt)
	if err != nil {
		return guestruntimedomain.ExternalUpstreamObservation{}, err
	}
	return guestruntimedomain.ExternalUpstreamObservation{
		State:      "available",
		Connection: guestruntimedomain.ConnectionObservation{State: "reachable", ObservedAt: observedAt},
		Capability: &capability,
	}, nil
}

func externalVitalServerUnavailableObservation(reference guestruntimedomain.IntegrationProviderReference, observedAt string, code string, message string) guestruntimedomain.ExternalUpstreamObservation {
	retryable := true
	issue := &guestruntimedomain.Issue{Code: code, Message: message, Retryable: &retryable, Dependency: reference.ID}
	return guestruntimedomain.ExternalUpstreamObservation{State: "unavailable", Connection: guestruntimedomain.ConnectionObservation{State: "unavailable", ObservedAt: observedAt, Issue: issue}, Issue: issue}
}

type externalVitalServerDeliveryConfiguration struct {
	SchemaVersion                                         string                                     `json:"schemaVersion"`
	ConfigurationID                                       string                                     `json:"configurationId"`
	ExternalUpstreamIntegrationReference                  externalVitalServerResourceReference       `json:"externalUpstreamIntegrationReference"`
	VitalServerDeliveryProvider                           externalVitalServerProviderReference       `json:"vitalServerDeliveryProvider"`
	VitalServerPacketDeliveryEndpoint                     externalVitalServerEndpoint                `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int                                        `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
	VitalServerObservationEndpoint                        externalVitalServerHTTPObservationEndpoint `json:"vitalServerObservationEndpoint"`
	VitalServerArchiveProvider                            externalVitalServerProviderReference       `json:"vitalServerArchiveProvider"`
	VitalServerIndexedLibraryEndpoint                     externalVitalServerEndpoint                `json:"vitalServerIndexedLibraryEndpoint"`
	VitalServerArchiveCredentialReference                 externalVitalServerSecretReference         `json:"vitalServerArchiveCredentialReference"`
	VitalServerArchiveRequestTimeoutMilliseconds          int                                        `json:"vitalServerArchiveRequestTimeoutMilliseconds"`
}

type externalVitalServerResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
}

type externalVitalServerProviderReference struct {
	Kind               string `json:"kind"`
	ID                 string `json:"id"`
	CapabilityRevision int    `json:"capabilityRevision"`
}

type externalVitalServerEndpoint struct {
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

type externalVitalServerSecretReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

type externalVitalServerHTTPObservationEndpoint struct {
	Scheme              string `json:"scheme"`
	Host                string `json:"host"`
	Port                int    `json:"port"`
	Path                string `json:"path"`
	AcceptedStatusCodes []int  `json:"acceptedStatusCodes"`
}

func loadExternalVitalServerDeliveryConfiguration(path string) (externalVitalServerDeliveryConfiguration, error) {
	if !validExternalVitalServerConfigurationPath(path) {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration path is invalid")
	}
	fileInfo, err := os.Lstat(path)
	if err != nil || !fileInfo.Mode().IsRegular() {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration is unavailable")
	}
	file, err := os.Open(path)
	if err != nil {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration is unavailable")
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumExternalVitalServerDeliveryConfigurationBytes+1))
	if err != nil || int64(len(contents)) > maximumExternalVitalServerDeliveryConfigurationBytes {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration is unavailable")
	}
	var configuration externalVitalServerDeliveryConfiguration
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&configuration); err != nil {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration is invalid")
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) || !validExternalVitalServerDeliveryConfiguration(configuration) {
		return externalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 External VitalServer delivery configuration is invalid")
	}
	return configuration, nil
}

func (endpoint externalVitalServerHTTPObservationEndpoint) URL() (string, error) {
	if !validExternalVitalServerHTTPObservationEndpoint(endpoint) || externalVitalServerLoopbackHost(endpoint.Host) {
		return "", fmt.Errorf("C46 External VitalServer observation endpoint is invalid")
	}
	return endpoint.Scheme + "://" + net.JoinHostPort(endpoint.Host, strconv.Itoa(endpoint.Port)) + endpoint.Path, nil
}

func validExternalVitalServerDeliveryConfiguration(configuration externalVitalServerDeliveryConfiguration) bool {
	return configuration.SchemaVersion == "v1" && validExternalVitalServerIdentifier(configuration.ConfigurationID) && configuration.ExternalUpstreamIntegrationReference.ResourceType == guestruntimedomain.ExternalUpstreamIntegrationResourceType && validExternalVitalServerIdentifier(configuration.ExternalUpstreamIntegrationReference.ResourceID) && configuration.VitalServerDeliveryProvider.Kind == "external-vitalserver" && validExternalVitalServerProviderReference(configuration.VitalServerDeliveryProvider) && validExternalVitalServerEndpoint(configuration.VitalServerPacketDeliveryEndpoint) && configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds >= 1 && configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds <= 3600000 && validExternalVitalServerHTTPObservationEndpoint(configuration.VitalServerObservationEndpoint) && !externalVitalServerLoopbackHost(configuration.VitalServerObservationEndpoint.Host) && configuration.VitalServerArchiveProvider.Kind == "vitalserver-indexed-library" && validExternalVitalServerProviderReference(configuration.VitalServerArchiveProvider) && validExternalVitalServerEndpoint(configuration.VitalServerIndexedLibraryEndpoint) && !externalVitalServerLoopbackHost(configuration.VitalServerIndexedLibraryEndpoint.Host) && validExternalVitalServerIdentifier(configuration.VitalServerArchiveCredentialReference.Kind) && validExternalVitalServerIdentifier(configuration.VitalServerArchiveCredentialReference.ID) && configuration.VitalServerArchiveRequestTimeoutMilliseconds >= 1 && configuration.VitalServerArchiveRequestTimeoutMilliseconds <= 3600000
}

func validExternalVitalServerProviderReference(reference externalVitalServerProviderReference) bool {
	return validExternalVitalServerIdentifier(reference.Kind) && validExternalVitalServerIdentifier(reference.ID) && reference.CapabilityRevision > 0
}

func validExternalVitalServerEndpoint(endpoint externalVitalServerEndpoint) bool {
	return (endpoint.Scheme == "http" || endpoint.Scheme == "https") && endpoint.Host != "" && !strings.ContainsAny(endpoint.Host, "/?#@") && endpoint.Port >= 1 && endpoint.Port <= 65535
}

func validExternalVitalServerHTTPObservationEndpoint(endpoint externalVitalServerHTTPObservationEndpoint) bool {
	if !validExternalVitalServerEndpoint(externalVitalServerEndpoint{Scheme: endpoint.Scheme, Host: endpoint.Host, Port: endpoint.Port}) || len(endpoint.Path) == 0 || len(endpoint.Path) > 2048 || endpoint.Path[0] != '/' || strings.ContainsAny(endpoint.Path, "?#") || len(endpoint.AcceptedStatusCodes) == 0 {
		return false
	}
	seen := make(map[int]struct{}, len(endpoint.AcceptedStatusCodes))
	for _, statusCode := range endpoint.AcceptedStatusCodes {
		if statusCode < 100 || statusCode > 599 {
			return false
		}
		if _, duplicate := seen[statusCode]; duplicate {
			return false
		}
		seen[statusCode] = struct{}{}
	}
	return true
}

func validExternalVitalServerConfigurationPath(value string) bool {
	if !filepath.IsAbs(value) || strings.Contains(value, "\\") || len(value) > 1024 {
		return false
	}
	return filepath.Clean(value) != "/" && !strings.Contains(filepath.Clean(value), "/../")
}

func validExternalVitalServerIdentifier(value string) bool {
	return guestruntimedomain.ValidIdentifier(value)
}

func externalVitalServerLoopbackHost(host string) bool {
	return host == "127.0.0.1" || host == "::1" || host == "localhost"
}

var _ guestruntimeapplication.GuestRuntimeExternalUpstreamProvider = (*ExternalVitalServerHTTPObservationProvider)(nil)
