package hostinstallationmanagerdomain

import "testing"

func TestHostMutationRequiresAvailableIdentityMatchedIdleUpdateOwnership(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	idle := HostUpdateOperationOwnershipObservation{
		SchemaVersion: "v1",
		ReadState:     HostUpdateOwnershipReadAvailable,
		ObservedAt:    "2026-07-27T01:00:00Z",
		Ownership: &HostUpdateOperationOwnership{
			SchemaVersion: "v1", InstallationID: manifest.InstallationID, InstallationRevision: 4, State: "idle",
		},
	}
	if decision := DecideHostMutationAgainstUpdateOwnership(manifest, idle, "active-host-update-blocks-installation"); decision.State != "admitted" {
		t.Fatalf("idle decision=%+v", decision)
	}

	active := idle
	active.Ownership = &HostUpdateOperationOwnership{
		SchemaVersion: "v1", InstallationID: manifest.InstallationID, InstallationRevision: 4, State: "active",
		UpdateID: "update-1", OperationID: "operation-1", RequestID: "request-1", UpdateState: "applying", JournalRevision: 5,
	}
	decision := DecideHostMutationAgainstUpdateOwnership(manifest, active, "active-host-update-blocks-installation")
	if decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "active-host-update-blocks-installation" {
		t.Fatalf("active decision=%+v", decision)
	}
}

func TestHostMutationDoesNotConvertNonAvailableOwnershipToIdle(t *testing.T) {
	manifest := declaredHostProductInstallationManifest()
	for _, state := range []string{
		HostUpdateOwnershipReadMissing,
		HostUpdateOwnershipReadInvalid,
		HostUpdateOwnershipReadFailed,
		HostUpdateOwnershipReadUnavailable,
		HostUpdateOwnershipReadStale,
		HostUpdateOwnershipReadUnsupported,
	} {
		t.Run(state, func(t *testing.T) {
			observation := HostUpdateOperationOwnershipObservation{
				SchemaVersion: "v1",
				ReadState:     state,
				ObservedAt:    "2026-07-27T01:00:00Z",
				Issue:         &HostInstallationIssue{Code: "owner-read-" + state, Message: "explicit provider result"},
			}
			decision := DecideHostMutationAgainstUpdateOwnership(manifest, observation, "active-host-update-blocks-removal")
			if decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "host-update-ownership-"+state {
				t.Fatalf("%s decision=%+v", state, decision)
			}
		})
	}
	empty := HostUpdateOperationOwnershipObservation{
		SchemaVersion: "v1",
		ReadState:     HostUpdateOwnershipReadEmpty,
		ObservedAt:    "2026-07-27T01:00:00Z",
	}
	decision := DecideHostMutationAgainstUpdateOwnership(manifest, empty, "active-host-update-blocks-removal")
	if decision.State != "blocked" || decision.Issue == nil || decision.Issue.Code != "host-update-ownership-empty" {
		t.Fatalf("empty decision=%+v", decision)
	}
}

func TestOnlyExistingInstallationPreflightModesRequireUpdateOwnershipGuard(t *testing.T) {
	for _, mode := range []string{"clean-install", "package-unpacked-install", "windows-msi-payload-install", "clean-install-migrate-blocked-preflight-receipt", "clean-install-retry"} {
		if HostInstallationDecisionRequiresUpdateIdle(HostInstallationDecision{State: "admitted", Mode: mode}) {
			t.Fatalf("%s unexpectedly requires an installed Host owner", mode)
		}
	}
	for _, mode := range []string{"same-release-reinstall", "same-release-repair"} {
		if !HostInstallationDecisionRequiresUpdateIdle(HostInstallationDecision{State: "admitted", Mode: mode}) {
			t.Fatalf("%s must guard against an active update", mode)
		}
	}
}
