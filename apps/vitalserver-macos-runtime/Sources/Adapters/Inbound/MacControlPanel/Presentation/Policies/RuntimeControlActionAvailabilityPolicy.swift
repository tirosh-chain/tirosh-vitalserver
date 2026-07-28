import RuntimeControl
import Errors

public struct RuntimeControlActionAvailabilityPolicy {
    public init() {}

    public func isRuntimeExecutable(_ status: PlatformState) -> Bool {
        status.runtimeInstallationState.isExecutable
    }

    public func canApplyUpdate(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        stableUpdate: RuntimeStableUpdateJournalResource,
        isBusy: Bool,
        hasSelectedBundle: Bool,
        selectedBundleVerified: Bool
    ) -> Bool {
        stableUpdateAllowsAdmission(stableUpdate)
            && !isBusy
            && hasSelectedBundle
            && selectedBundleVerified
            && capabilities.canApplyBundle
            && isRuntimeExecutable(status)
    }

    private func stableUpdateAllowsAdmission(
        _ resource: RuntimeStableUpdateJournalResource
    ) -> Bool {
        switch resource.state {
        case .missing:
            return true
        case .unavailable, .failed:
            return false
        case .loaded:
            guard let journal = resource.document else {
                return false
            }
            switch journal.state {
            case .admitted, .handoffPending, .running:
                return false
            case .succeeded, .failed, .interrupted:
                return true
            }
        }
    }

    public func canApplySettings(
        status: PlatformState,
        isBusy: Bool,
        canApplyForCurrentConnection: Bool
    ) -> Bool {
        !isBusy
            && canApplyForCurrentConnection
            && isRuntimeExecutable(status)
    }

    public func canCreateRedisBackup(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        canManageRedisBackup(
            status: status,
            capabilities: capabilities,
            isBusy: isBusy
        )
    }

    public func canManageRedisBackup(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canManageRuntimeDataBackup(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canRepairRuntime(status: PlatformState, isBusy: Bool) -> Bool {
        !isBusy && isRuntimeExecutable(status)
    }

    public func canControlRuntimeServices(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canUninstallRuntime(
        status: PlatformState,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canUninstallRuntime
            && isRuntimeExecutable(status)
    }
}
