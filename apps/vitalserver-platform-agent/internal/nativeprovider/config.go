package nativeprovider

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"time"
)

var composeProjectNamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)

type Config struct {
	SchemaVersion                int    `json:"schemaVersion"`
	ComposeExecutable            string `json:"composeExecutable"`
	ComposeFile                  string `json:"composeFile"`
	ComposeEnvironmentFile       string `json:"composeEnvironmentFile"`
	ComposeProjectName           string `json:"composeProjectName"`
	ProjectDirectory             string `json:"projectDirectory"`
	RuntimeReadyURL              string `json:"runtimeReadyURL"`
	RuntimeEndpointAddress       string `json:"runtimeEndpointAddress"`
	RuntimeEndpointDocument      string `json:"runtimeEndpointDocument"`
	RuntimeProviderDocument      string `json:"runtimeProviderDocument"`
	ReadinessProbeTimeoutSeconds int    `json:"readinessProbeTimeoutSeconds"`
	StartupTimeoutSeconds        int    `json:"startupTimeoutSeconds"`
	ShutdownTimeoutSeconds       int    `json:"shutdownTimeoutSeconds"`
}

func LoadConfig(path string) (Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("native provider config read failed path=%s: %w", path, err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var config Config
	if err := decoder.Decode(&config); err != nil {
		return Config{}, fmt.Errorf("native provider config decode failed path=%s: %w", path, err)
	}
	if err := requireJSONEOF(decoder); err != nil {
		return Config{}, fmt.Errorf("native provider config decode failed path=%s: %w", path, err)
	}
	if config.SchemaVersion != 1 {
		return Config{}, fmt.Errorf("unsupported native provider config schemaVersion=%d", config.SchemaVersion)
	}
	for name, value := range map[string]string{
		"composeExecutable":       config.ComposeExecutable,
		"composeFile":             config.ComposeFile,
		"composeEnvironmentFile":  config.ComposeEnvironmentFile,
		"composeProjectName":      config.ComposeProjectName,
		"projectDirectory":        config.ProjectDirectory,
		"runtimeReadyURL":         config.RuntimeReadyURL,
		"runtimeEndpointAddress":  config.RuntimeEndpointAddress,
		"runtimeEndpointDocument": config.RuntimeEndpointDocument,
		"runtimeProviderDocument": config.RuntimeProviderDocument,
	} {
		if value == "" {
			return Config{}, fmt.Errorf("native provider config field is required: %s", name)
		}
	}
	if !composeProjectNamePattern.MatchString(config.ComposeProjectName) {
		return Config{}, fmt.Errorf(
			"native provider composeProjectName must match %s: %s",
			composeProjectNamePattern.String(),
			config.ComposeProjectName,
		)
	}
	if net.ParseIP(config.RuntimeEndpointAddress) == nil {
		return Config{}, fmt.Errorf("native provider runtimeEndpointAddress must be an IP address: %s", config.RuntimeEndpointAddress)
	}
	readyURL, err := url.Parse(config.RuntimeReadyURL)
	if err != nil || readyURL.Scheme != "http" || readyURL.Hostname() != config.RuntimeEndpointAddress || readyURL.Port() == "" || readyURL.Path != "/ready" {
		return Config{}, fmt.Errorf(
			"native provider runtimeReadyURL must be the explicit Runtime Controller /ready endpoint for runtimeEndpointAddress: %s",
			config.RuntimeReadyURL,
		)
	}
	if config.ReadinessProbeTimeoutSeconds < 1 || config.StartupTimeoutSeconds < 1 || config.ShutdownTimeoutSeconds < 1 {
		return Config{}, fmt.Errorf("native provider timeouts must be positive")
	}
	base := filepath.Dir(path)
	config.ComposeExecutable = resolvePath(base, config.ComposeExecutable)
	config.ComposeFile = resolvePath(base, config.ComposeFile)
	config.ComposeEnvironmentFile = resolvePath(base, config.ComposeEnvironmentFile)
	config.ProjectDirectory = resolvePath(base, config.ProjectDirectory)
	config.RuntimeEndpointDocument = resolvePath(base, config.RuntimeEndpointDocument)
	config.RuntimeProviderDocument = resolvePath(base, config.RuntimeProviderDocument)
	return config, nil
}

func (c Config) StartupTimeout() time.Duration {
	return time.Duration(c.StartupTimeoutSeconds) * time.Second
}

func (c Config) ReadinessProbeTimeout() time.Duration {
	return time.Duration(c.ReadinessProbeTimeoutSeconds) * time.Second
}

func (c Config) ShutdownTimeout() time.Duration {
	return time.Duration(c.ShutdownTimeoutSeconds) * time.Second
}

func resolvePath(base, value string) string {
	if filepath.IsAbs(value) {
		return value
	}
	return filepath.Join(base, value)
}

func requireJSONEOF(decoder *json.Decoder) error {
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return fmt.Errorf("multiple JSON values are not allowed")
		}
		return err
	}
	return nil
}
