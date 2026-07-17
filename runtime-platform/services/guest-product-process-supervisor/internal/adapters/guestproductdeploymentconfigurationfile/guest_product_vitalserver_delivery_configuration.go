package guestproductdeploymentconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

// GuestProductVitalServerTopologyDeploymentUnavailableError keeps a missing or
// unreadable C44 desired topology distinct from an invalid topology document.
type GuestProductVitalServerTopologyDeploymentUnavailableError struct{ reason string }

func (failure GuestProductVitalServerTopologyDeploymentUnavailableError) Error() string {
	return "Guest Product VitalServer topology deployment is unavailable: " + failure.reason
}

type GuestProductVitalServerTopologyDeploymentInvalidError struct{ reason string }

func (failure GuestProductVitalServerTopologyDeploymentInvalidError) Error() string {
	return "Guest Product VitalServer topology deployment is invalid: " + failure.reason
}

// ExternalVitalServerDeliveryConfigurationUnavailableError preserves the
// configuration-required condition for an external topology. It never lets the
// Supervisor fall back to a bundled loopback target.
type ExternalVitalServerDeliveryConfigurationUnavailableError struct{ reason string }

func (failure ExternalVitalServerDeliveryConfigurationUnavailableError) Error() string {
	return "External VitalServer delivery configuration is unavailable: " + failure.reason
}

type ExternalVitalServerDeliveryConfigurationInvalidError struct{ reason string }

func (failure ExternalVitalServerDeliveryConfigurationInvalidError) Error() string {
	return "External VitalServer delivery configuration is invalid: " + failure.reason
}

func LoadGuestProductVitalServerTopologyDeployment(path string) (guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment, error) {
	if !isSafeGuestProductProcessDeploymentConfigurationPath(path) {
		return guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment{}, GuestProductVitalServerTopologyDeploymentInvalidError{reason: "C44 path must be an absolute path without traversal"}
	}
	contents, err := readGuestProductConfigurationDocument(path)
	if err != nil {
		return guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment{}, GuestProductVitalServerTopologyDeploymentUnavailableError{reason: err.Error()}
	}
	var topology guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment
	if err := decodeOneGuestProductConfigurationDocument(contents, &topology); err != nil {
		return guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment{}, GuestProductVitalServerTopologyDeploymentInvalidError{reason: err.Error()}
	}
	if err := guestproductprocesssupervisordomain.ValidateGuestProductVitalServerTopologyDeployment(topology); err != nil {
		return guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment{}, GuestProductVitalServerTopologyDeploymentInvalidError{reason: err.Error()}
	}
	return topology, nil
}

func LoadExternalVitalServerDeliveryConfiguration(path string) (guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration, error) {
	if !isSafeGuestProductProcessDeploymentConfigurationPath(path) {
		return guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{}, ExternalVitalServerDeliveryConfigurationInvalidError{reason: "C46 path must be an absolute path without traversal"}
	}
	contents, err := readGuestProductConfigurationDocument(path)
	if err != nil {
		return guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{}, ExternalVitalServerDeliveryConfigurationUnavailableError{reason: err.Error()}
	}
	var configuration guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration
	if err := decodeOneGuestProductConfigurationDocument(contents, &configuration); err != nil {
		return guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{}, ExternalVitalServerDeliveryConfigurationInvalidError{reason: err.Error()}
	}
	if err := guestproductprocesssupervisordomain.ValidateExternalVitalServerDeliveryConfiguration(configuration); err != nil {
		return guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration{}, ExternalVitalServerDeliveryConfigurationInvalidError{reason: err.Error()}
	}
	return configuration, nil
}

func readGuestProductConfigurationDocument(path string) ([]byte, error) {
	contents, err := os.ReadFile(path)
	if err == nil {
		return contents, nil
	}
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
		return nil, fmt.Errorf("configuration file cannot be read")
	}
	return nil, fmt.Errorf("configuration file read failed")
}

func decodeOneGuestProductConfigurationDocument(contents []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("configuration JSON cannot be decoded")
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("configuration contains multiple JSON values")
	}
	return nil
}
