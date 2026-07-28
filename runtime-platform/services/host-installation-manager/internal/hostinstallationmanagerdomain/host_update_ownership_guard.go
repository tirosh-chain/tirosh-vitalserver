package hostinstallationmanagerdomain

import "fmt"

const (
	HostUpdateOwnershipReadAvailable   = "available"
	HostUpdateOwnershipReadMissing     = "missing"
	HostUpdateOwnershipReadInvalid     = "invalid"
	HostUpdateOwnershipReadFailed      = "failed"
	HostUpdateOwnershipReadUnavailable = "unavailable"
	HostUpdateOwnershipReadEmpty       = "empty"
	HostUpdateOwnershipReadStale       = "stale"
	HostUpdateOwnershipReadUnsupported = "unsupported"
)

// HostUpdateOperationOwnershipObservation preserves the Host Agent-owned C80
// read result. Missing, invalid, failed, and unavailable are not idle.
type HostUpdateOperationOwnershipObservation struct {
	SchemaVersion string
	ReadState     string
	ObservedAt    string
	Ownership     *HostUpdateOperationOwnership
	Issue         *HostInstallationIssue
}

type HostUpdateOperationOwnership struct {
	SchemaVersion        string
	InstallationID       string
	InstallationRevision int
	State                string
	UpdateID             string
	OperationID          string
	RequestID            string
	UpdateState          string
	JournalRevision      int
}

// HostInstallationDecisionRequiresUpdateIdle reports whether an admitted C50
// preflight is mutating an already installed product. A C49-proven clean or
// package-unpacked first install has no Host Agent installation owner to ask.
func HostInstallationDecisionRequiresUpdateIdle(decision HostInstallationDecision) bool {
	if decision.State != "admitted" {
		return false
	}
	switch decision.Mode {
	case "same-release-reinstall", "same-release-repair":
		return true
	case "clean-install", "package-unpacked-install", "windows-msi-payload-install", "clean-install-migrate-blocked-preflight-receipt", "clean-install-retry":
		return false
	default:
		return true
	}
}

// DecideHostMutationAgainstUpdateOwnership is the pure fail-closed guard used
// before install or removal writes its durable intent. Only an available,
// identity-matched C80 idle value admits the mutation.
func DecideHostMutationAgainstUpdateOwnership(manifest HostProductInstallationManifest, observation HostUpdateOperationOwnershipObservation, activeIssueCode string) HostInstallationDecision {
	if observation.SchemaVersion != HostInstallationDocumentSchemaVersion || observation.ObservedAt == "" {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "Host update ownership observation identity is invalid"})
	}
	switch observation.ReadState {
	case HostUpdateOwnershipReadAvailable:
		if observation.Issue != nil || observation.Ownership == nil {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "available Host update ownership must contain a value and no issue"})
		}
	case HostUpdateOwnershipReadEmpty:
		if observation.Ownership != nil || observation.Issue != nil {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "empty Host update ownership must contain neither a value nor an issue"})
		}
		return blockedHostInstallationDecision(HostInstallationIssue{
			Code:    "host-update-ownership-empty",
			Message: "Host update ownership is empty and cannot prove that the current installation is idle",
		})
	case HostUpdateOwnershipReadMissing, HostUpdateOwnershipReadInvalid, HostUpdateOwnershipReadFailed, HostUpdateOwnershipReadUnavailable, HostUpdateOwnershipReadStale, HostUpdateOwnershipReadUnsupported:
		if observation.Ownership != nil || observation.Issue == nil || observation.Issue.Code == "" {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "non-available Host update ownership must contain one issue and no value"})
		}
		return blockedHostInstallationDecision(HostInstallationIssue{
			Code:    "host-update-ownership-" + observation.ReadState,
			Message: fmt.Sprintf("Host update ownership is %s: %s", observation.ReadState, observation.Issue.Message),
		})
	default:
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "Host update ownership read state is unsupported"})
	}

	ownership := observation.Ownership
	if ownership.SchemaVersion != HostInstallationDocumentSchemaVersion || ownership.InstallationID != manifest.InstallationID || ownership.InstallationRevision < 1 {
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-identity-mismatch", Message: "Host update ownership does not match the installation being mutated"})
	}
	switch ownership.State {
	case "idle":
		if ownership.UpdateID != "" || ownership.OperationID != "" || ownership.RequestID != "" || ownership.UpdateState != "" || ownership.JournalRevision != 0 {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "idle Host update ownership contains active owner fields"})
		}
		return HostInstallationDecision{State: "admitted", Mode: "host-update-owner-idle"}
	case "active":
		if ownership.UpdateID == "" || ownership.OperationID == "" || ownership.RequestID == "" || ownership.UpdateState == "" || ownership.JournalRevision < 1 {
			return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "active Host update ownership is incomplete"})
		}
		if activeIssueCode == "" {
			activeIssueCode = "active-host-update-blocks-mutation"
		}
		return blockedHostInstallationDecision(HostInstallationIssue{Code: activeIssueCode, Message: "an active Host update owns this installation"})
	default:
		return blockedHostInstallationDecision(HostInstallationIssue{Code: "host-update-ownership-observation-invalid", Message: "Host update ownership state is unsupported"})
	}
}
