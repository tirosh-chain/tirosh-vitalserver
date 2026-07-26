// Package guestproductdeploymentconfigurationfile is the file adapter for the explicit
// C37 Guest process deployment, C44 VitalServer topology, and C46 external
// VitalServer delivery configuration documents. It never manufactures a
// desired deployment input when one of those owner documents is unavailable.
package guestproductdeploymentconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

type GuestProductProcessDeploymentConfigurationUnavailableError struct{ reason string }

func (failure GuestProductProcessDeploymentConfigurationUnavailableError) Error() string {
	return "Guest Product process deployment configuration is unavailable: " + failure.reason
}

type GuestProductProcessDeploymentConfigurationInvalidError struct{ reason string }

func (failure GuestProductProcessDeploymentConfigurationInvalidError) Error() string {
	return "Guest Product process deployment configuration is invalid: " + failure.reason
}

// LoadGuestProductProcessDeploymentConfiguration reads exactly one C37
// document. It never creates desired input or substitutes process settings.
func LoadGuestProductProcessDeploymentConfiguration(configurationPath string) (guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration, error) {
	if !isSafeGuestProductProcessDeploymentConfigurationPath(configurationPath) {
		return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationInvalidError{reason: "configuration path must be an absolute path without traversal"}
	}
	encoded, err := os.ReadFile(configurationPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationUnavailableError{reason: "configuration file cannot be read"}
		}
		return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationUnavailableError{reason: "configuration file read failed"}
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var configuration guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration
	if err := decoder.Decode(&configuration); err != nil {
		return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationInvalidError{reason: "configuration JSON cannot be decoded"}
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationInvalidError{reason: "configuration contains multiple JSON values"}
	}
	if err := guestproductprocesssupervisordomain.ValidateGuestProductProcessDeploymentConfiguration(configuration); err != nil {
		return guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration{}, GuestProductProcessDeploymentConfigurationInvalidError{reason: err.Error()}
	}
	return configuration, nil
}

func GuestProductProcessDeploymentConfigurationPathDescription() string {
	return fmt.Sprintf("required absolute path to C37 GuestProductProcessDeploymentConfiguration JSON")
}

func isSafeGuestProductProcessDeploymentConfigurationPath(value string) bool {
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
