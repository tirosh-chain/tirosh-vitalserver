package vitalserverindexedlibrary

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const maximumVitalServerIndexedLibraryConfigurationBytes int64 = 1 << 20

const (
	ExternalVitalServerDeliveryConfigurationKind = "external-vitalserver-delivery-configuration"
	BundledVitalServerTopologyDeploymentKind     = "bundled-vitalserver-topology-deployment"
)

var (
	errVitalServerIndexedLibraryCredentialMaterialUnavailable = errors.New("VitalServer indexed-library credential material is unavailable")
	errVitalServerIndexedLibraryCredentialMaterialInvalid     = errors.New("VitalServer indexed-library credential material is invalid")
)

// VitalServerIndexedLibrarySecretReference is an identity-only C46 reference.
// The C51 value uses the domain's matching private-material reference so the
// adapter can compare identities without returning secret-bearing material to
// an outer layer.
type VitalServerIndexedLibrarySecretReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

// ExternalVitalServerDeliveryConfiguration is the C46 subset consumed by the
// Archive adapter. The complete fields are decoded strictly so a C46 document
// cannot silently lose packet-delivery semantics while being reused here.
type ExternalVitalServerDeliveryConfiguration struct {
	SchemaVersion                                         string                                     `json:"schemaVersion"`
	ConfigurationID                                       string                                     `json:"configurationId"`
	ExternalUpstreamIntegrationReference                  vitalServerIndexedLibraryResourceReference `json:"externalUpstreamIntegrationReference"`
	VitalServerDeliveryProvider                           vitalServerIndexedLibraryProviderReference `json:"vitalServerDeliveryProvider"`
	VitalServerPacketDeliveryEndpoint                     vitalServerIndexedLibraryEndpoint          `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int                                        `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
	VitalServerObservationEndpoint                        vitalServerHTTPObservationEndpoint         `json:"vitalServerObservationEndpoint"`
	VitalServerArchiveProvider                            vitalServerIndexedLibraryProviderReference `json:"vitalServerArchiveProvider"`
	VitalServerIndexedLibraryEndpoint                     vitalServerIndexedLibraryEndpoint          `json:"vitalServerIndexedLibraryEndpoint"`
	VitalServerArchiveCredentialReference                 VitalServerIndexedLibrarySecretReference   `json:"vitalServerArchiveCredentialReference"`
	VitalServerArchiveRequestTimeoutMilliseconds          int                                        `json:"vitalServerArchiveRequestTimeoutMilliseconds"`
}

// BundledVitalServerTopologyDeployment is the C44 subset consumed by the
// Archive adapter. C44 explicitly describes a C64-owned Guest-loopback
// image-set endpoint; it is not reclassified as an external upstream merely
// because the same indexed-library protocol is used.
type BundledVitalServerTopologyDeployment struct {
	SchemaVersion                     string                                     `json:"schemaVersion"`
	TopologyDeploymentID              string                                     `json:"topologyDeploymentId"`
	TopologyKind                      string                                     `json:"topologyKind"`
	VitalServerDeliveryProvider       vitalServerIndexedLibraryProviderReference `json:"vitalServerDeliveryProvider"`
	PublicBrowserExposure             string                                     `json:"publicBrowserExposure"`
	BundledUpstreamImageSetDeployment *BundledUpstreamImageSetDeployment         `json:"bundledUpstreamImageSetDeployment"`
}

type BundledUpstreamImageSetDeployment struct {
	ImageSetManagerConfigurationReference                 vitalServerIndexedLibraryResourceReference `json:"imageSetManagerConfigurationReference"`
	VitalServerPacketDeliveryEndpoint                     vitalServerIndexedLibraryEndpoint          `json:"vitalServerPacketDeliveryEndpoint"`
	VitalServerDeliveryAcknowledgementTimeoutMilliseconds int                                        `json:"vitalServerDeliveryAcknowledgementTimeoutMilliseconds"`
	VitalServerObservationEndpoint                        vitalServerHTTPObservationEndpoint         `json:"vitalServerObservationEndpoint"`
	VitalServerArchiveProvider                            vitalServerIndexedLibraryProviderReference `json:"vitalServerArchiveProvider"`
	VitalServerIndexedLibraryEndpoint                     vitalServerIndexedLibraryEndpoint          `json:"vitalServerIndexedLibraryEndpoint"`
	VitalServerArchiveCredentialReference                 VitalServerIndexedLibrarySecretReference   `json:"vitalServerArchiveCredentialReference"`
	VitalServerArchiveRequestTimeoutMilliseconds          int                                        `json:"vitalServerArchiveRequestTimeoutMilliseconds"`
}

type loadedVitalServerIndexedLibraryConfiguration struct {
	archiveProvider                           vitalServerIndexedLibraryProviderReference
	indexedLibraryEndpoint                    vitalServerIndexedLibraryEndpoint
	archiveCredentialReference                VitalServerIndexedLibrarySecretReference
	archiveRequestTimeoutMilliseconds         int
	indexedLibraryEndpointMustBeGuestLoopback bool
}

type vitalServerIndexedLibraryResourceReference struct {
	ResourceType string `json:"resourceType"`
	ResourceID   string `json:"resourceId"`
}

type vitalServerIndexedLibraryProviderReference struct {
	Kind               string `json:"kind"`
	ID                 string `json:"id"`
	CapabilityRevision int    `json:"capabilityRevision"`
}

type vitalServerIndexedLibraryEndpoint struct {
	Scheme string `json:"scheme"`
	Host   string `json:"host"`
	Port   int    `json:"port"`
}

type vitalServerHTTPObservationEndpoint struct {
	Scheme              string `json:"scheme"`
	Host                string `json:"host"`
	Port                int    `json:"port"`
	Path                string `json:"path"`
	AcceptedStatusCodes []int  `json:"acceptedStatusCodes"`
}

// OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles reads the
// explicitly selected C44 or C46 desired configuration and separately owned
// secret material. The configuration kind is an explicit C37 fact: this
// adapter never infers a bundled topology from a loopback address. Neither an
// unreadable input nor a reference mismatch becomes an empty configured
// provider.
func OpenVitalServerIndexedLibraryHTTPArchiveExportProviderFromFiles(
	vitalServerConfigurationKind string,
	vitalServerConfigurationPath string,
	credentialMaterialPath string,
	expectedReference guestruntimedomain.ArchiveProviderReference,
) (*VitalServerIndexedLibraryHTTPArchiveExportProvider, error) {
	configuration, err := loadVitalServerIndexedLibraryConfiguration(vitalServerConfigurationKind, vitalServerConfigurationPath)
	if err != nil {
		return nil, err
	}
	if !sameProviderReference(configuration.archiveProvider, expectedReference) {
		return nil, fmt.Errorf("VitalServer indexed-library configuration provider does not match the selected Archive provider")
	}
	credentialMaterial, err := loadVitalServerIndexedLibraryCredentialMaterial(credentialMaterialPath)
	if err != nil {
		return nil, err
	}
	if !sameSecretReference(configuration.archiveCredentialReference, credentialMaterial.CredentialReference) {
		return nil, fmt.Errorf("VitalServer indexed-library credential material does not match the selected configuration credential reference")
	}
	endpoint, err := endpointURL(configuration.indexedLibraryEndpoint, configuration.indexedLibraryEndpointMustBeGuestLoopback)
	if err != nil {
		return nil, err
	}
	return NewVitalServerIndexedLibraryHTTPArchiveExportProvider(VitalServerIndexedLibraryHTTPArchiveExportProviderConfiguration{
		Reference: expectedReference,
		Endpoint:  endpoint,
		Credentials: VitalServerIndexedLibraryCredentials{
			UserID:   credentialMaterial.UserID,
			Password: credentialMaterial.Password,
		},
		RequestTimeout: time.Duration(configuration.archiveRequestTimeoutMilliseconds) * time.Millisecond,
	})
}

func loadVitalServerIndexedLibraryConfiguration(kind string, path string) (loadedVitalServerIndexedLibraryConfiguration, error) {
	switch kind {
	case ExternalVitalServerDeliveryConfigurationKind:
		configuration, err := loadExternalVitalServerDeliveryConfiguration(path)
		if err != nil {
			return loadedVitalServerIndexedLibraryConfiguration{}, err
		}
		return loadedVitalServerIndexedLibraryConfiguration{
			archiveProvider:                   configuration.VitalServerArchiveProvider,
			indexedLibraryEndpoint:            configuration.VitalServerIndexedLibraryEndpoint,
			archiveCredentialReference:        configuration.VitalServerArchiveCredentialReference,
			archiveRequestTimeoutMilliseconds: configuration.VitalServerArchiveRequestTimeoutMilliseconds,
		}, nil
	case BundledVitalServerTopologyDeploymentKind:
		configuration, err := loadBundledVitalServerTopologyDeployment(path)
		if err != nil {
			return loadedVitalServerIndexedLibraryConfiguration{}, err
		}
		return loadedVitalServerIndexedLibraryConfiguration{
			archiveProvider:                           configuration.BundledUpstreamImageSetDeployment.VitalServerArchiveProvider,
			indexedLibraryEndpoint:                    configuration.BundledUpstreamImageSetDeployment.VitalServerIndexedLibraryEndpoint,
			archiveCredentialReference:                configuration.BundledUpstreamImageSetDeployment.VitalServerArchiveCredentialReference,
			archiveRequestTimeoutMilliseconds:         configuration.BundledUpstreamImageSetDeployment.VitalServerArchiveRequestTimeoutMilliseconds,
			indexedLibraryEndpointMustBeGuestLoopback: true,
		}, nil
	default:
		return loadedVitalServerIndexedLibraryConfiguration{}, fmt.Errorf("VitalServer indexed-library configuration kind is unsupported")
	}
}

func loadExternalVitalServerDeliveryConfiguration(path string) (ExternalVitalServerDeliveryConfiguration, error) {
	contents, err := readRegularConfigurationFile(path, "C46 external VitalServer delivery configuration")
	if err != nil {
		return ExternalVitalServerDeliveryConfiguration{}, err
	}
	var configuration ExternalVitalServerDeliveryConfiguration
	if err := decodeOneVitalServerIndexedLibraryJSONDocument(contents, &configuration); err != nil {
		return ExternalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 external VitalServer delivery configuration is invalid")
	}
	if !validExternalVitalServerDeliveryConfiguration(configuration) {
		return ExternalVitalServerDeliveryConfiguration{}, fmt.Errorf("C46 external VitalServer delivery configuration is invalid")
	}
	return configuration, nil
}

func loadBundledVitalServerTopologyDeployment(path string) (BundledVitalServerTopologyDeployment, error) {
	contents, err := readRegularConfigurationFile(path, "C44 bundled VitalServer topology deployment")
	if err != nil {
		return BundledVitalServerTopologyDeployment{}, err
	}
	var configuration BundledVitalServerTopologyDeployment
	if err := decodeOneVitalServerIndexedLibraryJSONDocument(contents, &configuration); err != nil {
		return BundledVitalServerTopologyDeployment{}, fmt.Errorf("C44 bundled VitalServer topology deployment is invalid")
	}
	if !validBundledVitalServerTopologyDeployment(configuration) {
		return BundledVitalServerTopologyDeployment{}, fmt.Errorf("C44 bundled VitalServer topology deployment is invalid")
	}
	return configuration, nil
}

func loadVitalServerIndexedLibraryCredentialMaterial(path string) (guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial, error) {
	contents, err := readPrivateRegularSecretFile(path)
	if err != nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial{}, fmt.Errorf("%w", errVitalServerIndexedLibraryCredentialMaterialUnavailable)
	}
	var material guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial
	if err := decodeOneVitalServerIndexedLibraryJSONDocument(contents, &material); err != nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial{}, fmt.Errorf("%w", errVitalServerIndexedLibraryCredentialMaterialInvalid)
	}
	if guestruntimedomain.ValidateVitalServerIndexedLibraryCredentialMaterial(material) != nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial{}, fmt.Errorf("%w", errVitalServerIndexedLibraryCredentialMaterialInvalid)
	}
	return material, nil
}

func readRegularConfigurationFile(path string, subject string) ([]byte, error) {
	if !validAbsolutePath(path) {
		return nil, fmt.Errorf("%s path is invalid", subject)
	}
	fileInfo, err := os.Lstat(path)
	if err != nil || !fileInfo.Mode().IsRegular() {
		return nil, fmt.Errorf("%s is unavailable", subject)
	}
	contents, err := readBoundedFile(path)
	if err != nil {
		return nil, fmt.Errorf("%s is unavailable", subject)
	}
	return contents, nil
}

func readPrivateRegularSecretFile(path string) ([]byte, error) {
	if !validAbsolutePath(path) {
		return nil, fmt.Errorf("VitalServer indexed-library credential material path is invalid")
	}
	fileInfo, err := os.Lstat(path)
	if err != nil || !fileInfo.Mode().IsRegular() || fileInfo.Mode().Perm()&0o077 != 0 {
		return nil, fmt.Errorf("VitalServer indexed-library credential material is unavailable")
	}
	contents, err := readBoundedFile(path)
	if err != nil {
		return nil, fmt.Errorf("VitalServer indexed-library credential material is unavailable")
	}
	return contents, nil
}

func readBoundedFile(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumVitalServerIndexedLibraryConfigurationBytes+1))
	if err != nil || int64(len(contents)) > maximumVitalServerIndexedLibraryConfigurationBytes {
		return nil, fmt.Errorf("file cannot be read")
	}
	return contents, nil
}

func decodeOneVitalServerIndexedLibraryJSONDocument(contents []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("multiple JSON documents")
	}
	return nil
}

func validExternalVitalServerDeliveryConfiguration(configuration ExternalVitalServerDeliveryConfiguration) bool {
	return configuration.SchemaVersion == "v1" && validIdentifier(configuration.ConfigurationID) && configuration.ExternalUpstreamIntegrationReference.ResourceType == "external-upstream-integration" && validIdentifier(configuration.ExternalUpstreamIntegrationReference.ResourceID) && validProviderReference(configuration.VitalServerDeliveryProvider) && validEndpoint(configuration.VitalServerPacketDeliveryEndpoint) && configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds > 0 && configuration.VitalServerDeliveryAcknowledgementTimeoutMilliseconds <= 3600000 && validHTTPObservationEndpoint(configuration.VitalServerObservationEndpoint) && !isLoopbackHost(configuration.VitalServerObservationEndpoint.Host) && configuration.VitalServerArchiveProvider.Kind == "vitalserver-indexed-library" && validProviderReference(configuration.VitalServerArchiveProvider) && validEndpoint(configuration.VitalServerIndexedLibraryEndpoint) && !isLoopbackHost(configuration.VitalServerIndexedLibraryEndpoint.Host) && validSecretReference(configuration.VitalServerArchiveCredentialReference) && configuration.VitalServerArchiveRequestTimeoutMilliseconds > 0 && configuration.VitalServerArchiveRequestTimeoutMilliseconds <= 3600000
}

func validBundledVitalServerTopologyDeployment(configuration BundledVitalServerTopologyDeployment) bool {
	if configuration.SchemaVersion != "v1" || !validIdentifier(configuration.TopologyDeploymentID) || configuration.TopologyKind != "bundled-vitalserver" || configuration.VitalServerDeliveryProvider.Kind != "bundled-vitalserver" || !validProviderReference(configuration.VitalServerDeliveryProvider) || (configuration.PublicBrowserExposure != "not-exposed" && configuration.PublicBrowserExposure != "guest-virtio-route") || configuration.BundledUpstreamImageSetDeployment == nil {
		return false
	}
	bundled := configuration.BundledUpstreamImageSetDeployment
	return bundled.ImageSetManagerConfigurationReference.ResourceType == "guest-bundled-upstream-image-set-manager-configuration" && validIdentifier(bundled.ImageSetManagerConfigurationReference.ResourceID) && validGuestLoopbackEndpoint(bundled.VitalServerPacketDeliveryEndpoint) && bundled.VitalServerDeliveryAcknowledgementTimeoutMilliseconds > 0 && bundled.VitalServerDeliveryAcknowledgementTimeoutMilliseconds <= 3600000 && validGuestLoopbackHTTPObservationEndpoint(bundled.VitalServerObservationEndpoint) && bundled.VitalServerArchiveProvider.Kind == "vitalserver-indexed-library" && validProviderReference(bundled.VitalServerArchiveProvider) && validGuestLoopbackEndpoint(bundled.VitalServerIndexedLibraryEndpoint) && validSecretReference(bundled.VitalServerArchiveCredentialReference) && bundled.VitalServerArchiveRequestTimeoutMilliseconds > 0 && bundled.VitalServerArchiveRequestTimeoutMilliseconds <= 3600000
}

func validProviderReference(reference vitalServerIndexedLibraryProviderReference) bool {
	return validIdentifier(reference.Kind) && validIdentifier(reference.ID) && reference.CapabilityRevision > 0
}

func sameProviderReference(actual vitalServerIndexedLibraryProviderReference, expected guestruntimedomain.ArchiveProviderReference) bool {
	return actual.Kind == expected.Kind && actual.ID == expected.ID && actual.CapabilityRevision == expected.CapabilityRevision
}

func validSecretReference(reference VitalServerIndexedLibrarySecretReference) bool {
	return validIdentifier(reference.Kind) && validIdentifier(reference.ID)
}

func sameSecretReference(left VitalServerIndexedLibrarySecretReference, right guestruntimedomain.VitalServerIndexedLibraryCredentialReference) bool {
	return left.Kind == right.Kind && left.ID == right.ID
}

func endpointURL(endpoint vitalServerIndexedLibraryEndpoint, mustBeGuestLoopback bool) (string, error) {
	if !validEndpoint(endpoint) || isLoopbackHost(endpoint.Host) != mustBeGuestLoopback {
		return "", fmt.Errorf("VitalServer indexed-library endpoint is invalid for the selected configuration kind")
	}
	return endpoint.Scheme + "://" + net.JoinHostPort(endpoint.Host, strconv.Itoa(endpoint.Port)), nil
}

func validEndpoint(endpoint vitalServerIndexedLibraryEndpoint) bool {
	return (endpoint.Scheme == "http" || endpoint.Scheme == "https") && endpoint.Host != "" && !strings.ContainsAny(endpoint.Host, "/?#@") && endpoint.Port > 0 && endpoint.Port <= 65535
}

func validHTTPObservationEndpoint(endpoint vitalServerHTTPObservationEndpoint) bool {
	if !validEndpoint(vitalServerIndexedLibraryEndpoint{Scheme: endpoint.Scheme, Host: endpoint.Host, Port: endpoint.Port}) || len(endpoint.Path) == 0 || len(endpoint.Path) > 2048 || endpoint.Path[0] != '/' || strings.ContainsAny(endpoint.Path, "?#") || len(endpoint.AcceptedStatusCodes) == 0 {
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

func validGuestLoopbackEndpoint(endpoint vitalServerIndexedLibraryEndpoint) bool {
	return validEndpoint(endpoint) && endpoint.Scheme == "http" && endpoint.Host == "127.0.0.1"
}

func validGuestLoopbackHTTPObservationEndpoint(endpoint vitalServerHTTPObservationEndpoint) bool {
	return validHTTPObservationEndpoint(endpoint) && endpoint.Scheme == "http" && endpoint.Host == "127.0.0.1"
}

func isLoopbackHost(host string) bool {
	return host == "127.0.0.1" || host == "::1" || host == "localhost"
}

func validAbsolutePath(value string) bool {
	if !filepath.IsAbs(value) || strings.Contains(value, "\\") {
		return false
	}
	for _, component := range strings.Split(filepath.Clean(value), string(os.PathSeparator)) {
		if component == ".." {
			return false
		}
	}
	return true
}

func validIdentifier(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for index, character := range value {
		if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || (index > 0 && (character == '.' || character == '_' || character == '-')) {
			continue
		}
		return false
	}
	return true
}
