package contract

import "encoding/json"

var PlatformServiceRoles = [...]string{
	"runtime-provider",
	"public-proxy",
	"log-sync",
	"sleep-prevention",
	"watchdog",
}

type PlatformServiceStatus struct {
	Role      string  `json:"role"`
	State     string  `json:"state"`
	ReadError *string `json:"readError"`
}

type ReadIssue struct {
	Source  string `json:"source"`
	Message string `json:"message"`
}

type PlatformState struct {
	RuntimeInstallationState string                  `json:"runtimeInstallationState"`
	Services                 []PlatformServiceStatus `json:"services"`
	PlatformHealth           *string                 `json:"platformHealth"`
	ReadIssues               []ReadIssue             `json:"readIssues"`
	InstalledVersion         *string                 `json:"installedVersion"`
	RuntimeProviderState     *string                 `json:"runtimeProviderState"`
	RuntimeEndpoint          *string                 `json:"runtimeEndpoint"`
	PlatformAPIHTTP          *string                 `json:"platformAPIHTTP"`
	PlatformAPIStartedAt     *string                 `json:"platformAPIStartedAt"`
	HealthIssues             []string                `json:"healthIssues"`
}

type PlatformCapabilities struct {
	CanInstallRuntime               bool `json:"canInstallRuntime"`
	CanUninstallRuntime             bool `json:"canUninstallRuntime"`
	CanApplyBundle                  bool `json:"canApplyBundle"`
	CanRollback                     bool `json:"canRollback"`
	CanRollbackRelease              bool `json:"canRollbackRelease"`
	CanEditRuntimeProviderResources bool `json:"canEditRuntimeProviderResources"`
	CanEditNetworkExposure          bool `json:"canEditNetworkExposure"`
	CanResetAdminPassword           bool `json:"canResetAdminPassword"`
	CanOpenLocalFiles               bool `json:"canOpenLocalFiles"`
	CanStreamLogs                   bool `json:"canStreamLogs"`
	CanControlRuntimeServices       bool `json:"canControlRuntimeServices"`
	CanExportLogs                   bool `json:"canExportLogs"`
	CanViewReleaseMetadata          bool `json:"canViewReleaseMetadata"`
}

type DocumentResource struct {
	State     string          `json:"state"`
	Document  json.RawMessage `json:"document"`
	ReadError *string         `json:"readError"`
}

type EndpointRead struct {
	State   string  `json:"state"`
	Address *string `json:"address"`
	Source  *string `json:"source"`
	Reason  *string `json:"reason"`
}

type EndpointResource struct {
	State     string        `json:"state"`
	Read      *EndpointRead `json:"read"`
	ReadError *string       `json:"readError"`
}

type OperationResource struct {
	State       string          `json:"state"`
	Document    json.RawMessage `json:"document"`
	ReadError   *string         `json:"readError"`
	StaleReason *string         `json:"staleReason"`
}

type PlatformOperations struct {
	ActiveOperation *string           `json:"activeOperation"`
	Install         OperationResource `json:"install"`
	Lease           OperationResource `json:"lease"`
}

type ErrorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type PlatformCommandFailure struct {
	Kind    string `json:"kind"`
	Message string `json:"message"`
}

type RuntimeProviderCommandResponse struct {
	OperationID string                  `json:"operationId"`
	Action      string                  `json:"action"`
	State       string                  `json:"state"`
	Provider    DocumentResource        `json:"provider"`
	Failure     *PlatformCommandFailure `json:"failure"`
}

type PlatformWorkflowRelease struct {
	PlatformVersion      string `json:"platformVersion"`
	RuntimeBundleVersion string `json:"runtimeBundleVersion"`
}

type PlatformWorkflowArtifact struct {
	Path      string `json:"path"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
}

type PlatformWorkflowOperation struct {
	SchemaVersion int                       `json:"schemaVersion"`
	OperationID   string                    `json:"operationId"`
	Kind          string                    `json:"kind"`
	State         string                    `json:"state"`
	StartedAt     string                    `json:"startedAt"`
	UpdatedAt     string                    `json:"updatedAt"`
	Release       *PlatformWorkflowRelease  `json:"release"`
	Artifact      *PlatformWorkflowArtifact `json:"artifact"`
	Failure       *PlatformCommandFailure   `json:"failure"`
}

type PlatformWorkflowResource struct {
	State     string                     `json:"state"`
	Operation *PlatformWorkflowOperation `json:"operation"`
	ReadError *string                    `json:"readError"`
}
