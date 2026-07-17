// Package nativeproviderbridge implements the Windows/Linux C10/C21/C22
// adapter protocol without importing Host Agent source. JSON Schema in
// contracts/ remains the language-neutral authority at this process boundary.
package nativeproviderbridge

import "time"

const SchemaVersion = "v1"

const (
	WindowsHyperVSCMProviderKind       = "windows-hyperv-scm"
	LinuxKVMlibvirtSystemdProviderKind = "linux-kvm-libvirt-systemd"
)

type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency,omitempty"`
}

type ProviderLifecycleRequest struct {
	SchemaVersion string `json:"schemaVersion"`
	RequestID     string `json:"requestId"`
	ProviderID    string `json:"providerId"`
	Action        string `json:"action"`
}

type PlatformProviderLifecycleInvocation struct {
	SchemaVersion                 string                   `json:"schemaVersion"`
	ProviderKind                  string                   `json:"providerKind"`
	RequestID                     string                   `json:"requestId"`
	ExpectedGuestRuntimeControlEndpointRevision int                      `json:"expectedGuestRuntimeControlEndpointRevision"`
	Lifecycle                     ProviderLifecycleRequest `json:"lifecycle"`
}

type ProviderLifecycleResult struct {
	SchemaVersion string `json:"schemaVersion"`
	RequestID     string `json:"requestId"`
	ProviderID    string `json:"providerId"`
	ObservedState string `json:"observedState"`
	ObservedAt    string `json:"observedAt"`
	Issue         *Issue `json:"issue,omitempty"`
}

type InstallationObservation struct {
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type ComponentObservation struct {
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type ServiceObservation struct {
	Manager    string `json:"manager"`
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type CapabilityObservation struct {
	ID         string `json:"id"`
	State      string `json:"state"`
	ObservedAt string `json:"observedAt"`
	Issue      *Issue `json:"issue,omitempty"`
}

type ProviderInstallationEvidence struct {
	SchemaVersion  string                  `json:"schemaVersion"`
	ProviderKind   string                  `json:"providerKind"`
	ProviderID     string                  `json:"providerId"`
	HostPlatform   string                  `json:"hostPlatform"`
	ObservedAt     string                  `json:"observedAt"`
	Installation   InstallationObservation `json:"installation"`
	VirtualMachine ComponentObservation    `json:"virtualMachine"`
	Service        ServiceObservation      `json:"service"`
	Capabilities   []CapabilityObservation `json:"capabilities"`
}

type Config struct {
	ProviderID     string
	VirtualMachine string
	ServiceName    string
	HostPlatform   string
}

type Clock interface {
	Now() time.Time
}

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now().UTC() }

func timestamp(clock Clock) string { return clock.Now().UTC().Format(time.RFC3339Nano) }

func boolPointer(value bool) *bool { return &value }
