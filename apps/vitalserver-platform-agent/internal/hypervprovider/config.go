package hypervprovider

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	SchemaVersion           int    `json:"schemaVersion"`
	PowerShellExecutable    string `json:"powerShellExecutable"`
	VMName                  string `json:"vmName"`
	RuntimeReadyURL         string `json:"runtimeReadyURL"`
	RuntimeEndpointAddress  string `json:"runtimeEndpointAddress"`
	RuntimeEndpointDocument string `json:"runtimeEndpointDocument"`
	RuntimeProviderDocument string `json:"runtimeProviderDocument"`
	StartupTimeoutSeconds   int    `json:"startupTimeoutSeconds"`
	ShutdownTimeoutSeconds  int    `json:"shutdownTimeoutSeconds"`
}

func LoadConfig(path string) (Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("Hyper-V provider config read failed path=%s: %w", path, err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var config Config
	if err := decoder.Decode(&config); err != nil {
		return Config{}, fmt.Errorf("Hyper-V provider config decode failed path=%s: %w", path, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			err = fmt.Errorf("multiple JSON values are not allowed")
		}
		return Config{}, fmt.Errorf("Hyper-V provider config decode failed path=%s: %w", path, err)
	}
	if config.SchemaVersion != 1 {
		return Config{}, fmt.Errorf("unsupported Hyper-V provider config schemaVersion=%d", config.SchemaVersion)
	}
	for name, value := range map[string]string{
		"powerShellExecutable":    config.PowerShellExecutable,
		"vmName":                  config.VMName,
		"runtimeReadyURL":         config.RuntimeReadyURL,
		"runtimeEndpointAddress":  config.RuntimeEndpointAddress,
		"runtimeEndpointDocument": config.RuntimeEndpointDocument,
		"runtimeProviderDocument": config.RuntimeProviderDocument,
	} {
		if value == "" {
			return Config{}, fmt.Errorf("Hyper-V provider config field is required: %s", name)
		}
	}
	if net.ParseIP(config.RuntimeEndpointAddress) == nil {
		return Config{}, fmt.Errorf("Hyper-V provider runtimeEndpointAddress must be an IP address: %s", config.RuntimeEndpointAddress)
	}
	readyURL, err := url.Parse(config.RuntimeReadyURL)
	if err != nil || readyURL.Scheme != "http" || readyURL.Hostname() != config.RuntimeEndpointAddress || readyURL.Port() == "" || readyURL.Path != "/ready" {
		return Config{}, fmt.Errorf(
			"Hyper-V provider runtimeReadyURL must be the explicit Runtime Controller /ready endpoint for runtimeEndpointAddress: %s",
			config.RuntimeReadyURL,
		)
	}
	if config.StartupTimeoutSeconds < 1 || config.ShutdownTimeoutSeconds < 1 {
		return Config{}, fmt.Errorf("Hyper-V provider timeouts must be positive")
	}
	base := filepath.Dir(path)
	config.PowerShellExecutable = resolvePath(base, config.PowerShellExecutable)
	config.RuntimeEndpointDocument = resolvePath(base, config.RuntimeEndpointDocument)
	config.RuntimeProviderDocument = resolvePath(base, config.RuntimeProviderDocument)
	return config, nil
}

func (c Config) StartupTimeout() time.Duration {
	return time.Duration(c.StartupTimeoutSeconds) * time.Second
}

func (c Config) ShutdownTimeout() time.Duration {
	return time.Duration(c.ShutdownTimeoutSeconds) * time.Second
}

func resolvePath(base, value string) string {
	if filepath.IsAbs(value) || isWindowsAbsolute(value) {
		return value
	}
	return filepath.Join(base, value)
}

func isWindowsAbsolute(value string) bool {
	return len(value) >= 3 && ((value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= 'a' && value[0] <= 'z')) && value[1] == ':' && (value[2] == '\\' || value[2] == '/')
}
