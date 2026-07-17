package hostagentdomain

// Platform provider kinds are product selections, not a host-OS probe.  The
// deployment configuration names one provider explicitly and Host persists
// that choice on its GuestRuntimeControlEndpoint. An unavailable selected provider must not
// cause Host to try another kind.
const (
	MacOSVirtualizationProviderKind    = "macos-virtualization"
	WindowsHyperVSCMProviderKind       = "windows-hyperv-scm"
	LinuxKVMlibvirtSystemdProviderKind = "linux-kvm-libvirt-systemd"
)

func ValidPlatformProviderKind(kind string) bool {
	switch kind {
	case MacOSVirtualizationProviderKind, WindowsHyperVSCMProviderKind, LinuxKVMlibvirtSystemdProviderKind:
		return true
	default:
		return false
	}
}

// PlatformProviderLifecycleInvocation is the Host-to-Platform-Provider C21
// envelope around C10. Host owns request-id/revision idempotency in its durable
// operation ledger; the provider receives those exact values and must validate them
// rather than invent a lifecycle revision of its own.
type PlatformProviderLifecycleInvocation struct {
	SchemaVersion                               string                   `json:"schemaVersion"`
	ProviderKind                                string                   `json:"providerKind"`
	RequestID                                   string                   `json:"requestId"`
	ExpectedGuestRuntimeControlEndpointRevision int                      `json:"expectedGuestRuntimeControlEndpointRevision"`
	Lifecycle                                   ProviderLifecycleRequest `json:"lifecycle"`
}

func NewPlatformProviderLifecycleInvocation(providerKind string, command GuestLifecycleCommand, providerID string) PlatformProviderLifecycleInvocation {
	return PlatformProviderLifecycleInvocation{
		SchemaVersion: SchemaVersion,
		ProviderKind:  providerKind,
		RequestID:     command.RequestID,
		ExpectedGuestRuntimeControlEndpointRevision: command.ExpectedResourceRevision,
		Lifecycle: ProviderLifecycleRequest{
			SchemaVersion: SchemaVersion,
			RequestID:     command.RequestID,
			ProviderID:    providerID,
			Action:        command.Action,
		},
	}
}

func ValidatePlatformProviderLifecycleInvocation(invocation PlatformProviderLifecycleInvocation) *Issue {
	if invocation.SchemaVersion != SchemaVersion {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "Platform Provider lifecycle invocation schemaVersion must be v1"}
	}
	if !ValidPlatformProviderKind(invocation.ProviderKind) {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "Platform Provider lifecycle invocation providerKind is unsupported"}
	}
	if !ValidIdentifier(invocation.RequestID) || invocation.ExpectedGuestRuntimeControlEndpointRevision < 1 {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "Platform Provider lifecycle invocation requestId and expected Guest Runtime Control endpoint revision are required"}
	}
	if invocation.Lifecycle.SchemaVersion != SchemaVersion || invocation.Lifecycle.RequestID != invocation.RequestID || !ValidIdentifier(invocation.Lifecycle.ProviderID) || invocation.Lifecycle.Action == "" {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "Platform Provider lifecycle invocation lifecycle must match its requestId"}
	}
	if invocation.Lifecycle.Action != "start" && invocation.Lifecycle.Action != "stop" && invocation.Lifecycle.Action != "reboot" {
		return &Issue{Code: "platform-provider-invocation-invalid", Message: "Platform Provider lifecycle invocation lifecycle action is unsupported"}
	}
	return nil
}
