package agent

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh/vitalserver-platform-agent/internal/contract"
)

type Config struct {
	SchemaVersion           int                `json:"schemaVersion"`
	ListenAddress           string             `json:"listenAddress"`
	APIToken                string             `json:"apiToken"`
	RuntimeExecutable       string             `json:"runtimeExecutable"`
	RuntimeEndpointDocument string             `json:"runtimeEndpointDocument"`
	RuntimeProviderDocument string             `json:"runtimeProviderDocument"`
	OperationLeaseDocument  string             `json:"operationLeaseDocument"`
	InstallDocument         string             `json:"installDocument"`
	RuntimeControllerPort   int                `json:"runtimeControllerPort"`
	PWA                     string             `json:"pwaDirectory"`
	PlatformServices        map[string]*string `json:"platformServices"`
	Delivery                *DeliveryConfig    `json:"delivery"`
}

type DeliveryConfig struct {
	WorkflowDocument     string `json:"workflowDocument"`
	UpdateTool           string `json:"updateTool"`
	RollbackTool         string `json:"rollbackTool"`
	UninstallTool        string `json:"uninstallTool"`
	SupportExportTool    string `json:"supportExportTool"`
	SchedulerExecutable  string `json:"schedulerExecutable"`
	SchedulerKind        string `json:"schedulerKind"`
	SchedulerScript      string `json:"schedulerScript"`
	ApplyPolicy          string `json:"applyPolicy"`
	TrustedBundleDigests string `json:"trustedBundleDigests"`
}

const (
	DeliveryApplyPolicyVerifyOnly      = "verify-only"
	DeliveryApplyPolicySHA256Allowlist = "sha256-allowlist"
	DeliverySchedulerSystemdTransient  = "systemd-transient"
	DeliverySchedulerWindowsTask       = "windows-scheduled-task"
)

func LoadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, fmt.Errorf("platform agent config read failed path=%s: %w", path, err)
	}
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return Config{}, fmt.Errorf("platform agent config decode failed path=%s: %w", path, err)
	}
	if config.SchemaVersion != 1 {
		return Config{}, fmt.Errorf("unsupported platform agent config schemaVersion=%d", config.SchemaVersion)
	}
	if config.RuntimeControllerPort < 1 || config.RuntimeControllerPort > 65535 {
		return Config{}, fmt.Errorf(
			"platform agent config runtimeControllerPort must be between 1 and 65535: %d",
			config.RuntimeControllerPort,
		)
	}
	for name, value := range map[string]string{
		"listenAddress":           config.ListenAddress,
		"apiToken":                config.APIToken,
		"runtimeExecutable":       config.RuntimeExecutable,
		"runtimeEndpointDocument": config.RuntimeEndpointDocument,
		"runtimeProviderDocument": config.RuntimeProviderDocument,
		"operationLeaseDocument":  config.OperationLeaseDocument,
	} {
		if value == "" {
			return Config{}, fmt.Errorf("platform agent config field is required: %s", name)
		}
	}
	for _, role := range contract.PlatformServiceRoles {
		name, exists := config.PlatformServices[role]
		if !exists {
			return Config{}, fmt.Errorf("platform agent config must explicitly declare service role: %s", role)
		}
		if name != nil && *name == "" {
			return Config{}, fmt.Errorf("platform agent service binding must be null or non-empty: %s", role)
		}
	}
	knownRoles := make(map[string]struct{}, len(contract.PlatformServiceRoles))
	for _, role := range contract.PlatformServiceRoles {
		knownRoles[role] = struct{}{}
	}
	for role := range config.PlatformServices {
		if _, exists := knownRoles[role]; !exists {
			return Config{}, fmt.Errorf("unknown platform agent service role: %s", role)
		}
	}
	base := filepath.Dir(path)
	config.RuntimeExecutable = resolvePath(base, config.RuntimeExecutable)
	config.RuntimeEndpointDocument = resolvePath(base, config.RuntimeEndpointDocument)
	config.RuntimeProviderDocument = resolvePath(base, config.RuntimeProviderDocument)
	config.OperationLeaseDocument = resolvePath(base, config.OperationLeaseDocument)
	if config.InstallDocument != "" {
		config.InstallDocument = resolvePath(base, config.InstallDocument)
	}
	if config.PWA != "" {
		config.PWA = resolvePath(base, config.PWA)
	}
	if config.Delivery != nil {
		for name, value := range map[string]string{
			"workflowDocument":    config.Delivery.WorkflowDocument,
			"updateTool":          config.Delivery.UpdateTool,
			"rollbackTool":        config.Delivery.RollbackTool,
			"schedulerExecutable": config.Delivery.SchedulerExecutable,
			"schedulerKind":       config.Delivery.SchedulerKind,
			"applyPolicy":         config.Delivery.ApplyPolicy,
		} {
			if value == "" {
				return Config{}, fmt.Errorf("platform agent delivery field is required: %s", name)
			}
		}
		switch config.Delivery.SchedulerKind {
		case DeliverySchedulerSystemdTransient:
			if config.Delivery.SchedulerScript != "" {
				return Config{}, fmt.Errorf("platform agent delivery schedulerScript must be absent for schedulerKind=%s", DeliverySchedulerSystemdTransient)
			}
		case DeliverySchedulerWindowsTask:
			if config.Delivery.SchedulerScript == "" {
				return Config{}, fmt.Errorf("platform agent delivery schedulerScript is required for schedulerKind=%s", DeliverySchedulerWindowsTask)
			}
		default:
			return Config{}, fmt.Errorf("unsupported platform agent delivery schedulerKind=%q", config.Delivery.SchedulerKind)
		}
		switch config.Delivery.ApplyPolicy {
		case DeliveryApplyPolicyVerifyOnly:
			if config.Delivery.TrustedBundleDigests != "" {
				return Config{}, fmt.Errorf("platform agent delivery trustedBundleDigests must be absent for applyPolicy=%s", DeliveryApplyPolicyVerifyOnly)
			}
		case DeliveryApplyPolicySHA256Allowlist:
			if config.Delivery.TrustedBundleDigests == "" {
				return Config{}, fmt.Errorf("platform agent delivery trustedBundleDigests is required for applyPolicy=%s", DeliveryApplyPolicySHA256Allowlist)
			}
		default:
			return Config{}, fmt.Errorf(
				"unsupported platform agent delivery applyPolicy=%q",
				config.Delivery.ApplyPolicy,
			)
		}
		config.Delivery.WorkflowDocument = resolvePath(base, config.Delivery.WorkflowDocument)
		config.Delivery.UpdateTool = resolvePath(base, config.Delivery.UpdateTool)
		config.Delivery.RollbackTool = resolvePath(base, config.Delivery.RollbackTool)
		if config.Delivery.UninstallTool != "" {
			config.Delivery.UninstallTool = resolvePath(base, config.Delivery.UninstallTool)
		}
		if config.Delivery.SupportExportTool != "" {
			config.Delivery.SupportExportTool = resolvePath(base, config.Delivery.SupportExportTool)
		}
		config.Delivery.SchedulerExecutable = resolvePath(base, config.Delivery.SchedulerExecutable)
		if config.Delivery.SchedulerScript != "" {
			config.Delivery.SchedulerScript = resolvePath(base, config.Delivery.SchedulerScript)
		}
		if config.Delivery.TrustedBundleDigests != "" {
			config.Delivery.TrustedBundleDigests = resolvePath(base, config.Delivery.TrustedBundleDigests)
		}
	}
	return config, nil
}

func resolvePath(base, value string) string {
	if filepath.IsAbs(value) {
		return value
	}
	return filepath.Join(base, value)
}
