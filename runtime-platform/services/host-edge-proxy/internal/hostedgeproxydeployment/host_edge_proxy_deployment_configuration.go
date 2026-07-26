// Package hostedgeproxydeployment loads C36 Host Edge Proxy deployment input.
package hostedgeproxydeployment

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-edge-proxy/internal/hostedgeproxydomain"
)

type HostEdgeProxyDeploymentConfigurationUnavailableError struct{ reason string }

func (failure HostEdgeProxyDeploymentConfigurationUnavailableError) Error() string {
	return "Host Edge Proxy deployment configuration is unavailable: " + failure.reason
}

type HostEdgeProxyDeploymentConfigurationInvalidError struct{ reason string }

func (failure HostEdgeProxyDeploymentConfigurationInvalidError) Error() string {
	return "Host Edge Proxy deployment configuration is invalid: " + failure.reason
}

// LoadHostEdgeProxyDeploymentConfiguration reads exactly one C36 file. It does
// not create configuration or select a route when the file cannot be read.
func LoadHostEdgeProxyDeploymentConfiguration(configurationPath string) (hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration, error) {
	if !isSafeHostEdgeProxyDeploymentConfigurationPath(configurationPath) {
		return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationInvalidError{reason: "configuration path must be an absolute path without traversal"}
	}
	encoded, err := os.ReadFile(configurationPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationUnavailableError{reason: "configuration file cannot be read"}
		}
		return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationUnavailableError{reason: "configuration file read failed"}
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var configuration hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration
	if err := decoder.Decode(&configuration); err != nil {
		return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationInvalidError{reason: "configuration JSON cannot be decoded"}
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationInvalidError{reason: "configuration contains multiple JSON values"}
	}
	if err := hostedgeproxydomain.ValidateHostEdgeProxyDeploymentConfiguration(configuration); err != nil {
		return hostedgeproxydomain.HostEdgeProxyDeploymentConfiguration{}, HostEdgeProxyDeploymentConfigurationInvalidError{reason: err.Error()}
	}
	return configuration, nil
}

func isSafeHostEdgeProxyDeploymentConfigurationPath(configurationPath string) bool {
	if !filepath.IsAbs(configurationPath) || strings.Contains(configurationPath, "\\") {
		return false
	}
	for _, component := range strings.Split(filepath.Clean(configurationPath), string(os.PathSeparator)) {
		if component == ".." {
			return false
		}
	}
	return true
}

func HostEdgeProxyDeploymentConfigurationPathDescription() string {
	return fmt.Sprintf("required absolute path to C36 HostEdgeProxyDeploymentConfiguration JSON")
}
