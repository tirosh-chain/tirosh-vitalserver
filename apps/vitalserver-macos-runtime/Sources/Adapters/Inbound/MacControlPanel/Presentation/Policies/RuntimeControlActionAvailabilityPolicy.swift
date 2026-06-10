import RuntimeControl
import Errors

public struct RuntimeControlActionAvailabilityPolicy {
    public init() {}

    public func isRuntimeExecutable(_ status: RuntimeStatus) -> Bool {
        status.effectiveRuntimeInstallationState.isExecutable
    }

    public func canApplyUpdate(
        status: RuntimeStatus,
        capabilities: RuntimeControlCapabilities,
        updateInProgress: Bool,
        hasSelectedBundle: Bool,
        selectedBundleVerified: Bool
    ) -> Bool {
        !updateInProgress
            && hasSelectedBundle
            && selectedBundleVerified
            && capabilities.canApplyBundle
            && isRuntimeExecutable(status)
    }

    public func canApplySettings(
        status: RuntimeStatus,
        isBusy: Bool,
        canApplyForCurrentConnection: Bool
    ) -> Bool {
        !isBusy
            && canApplyForCurrentConnection
            && isRuntimeExecutable(status)
    }

    public func canCreateRedisBackup(
        status: RuntimeStatus,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canManageRuntimeDataBackup(
        status: RuntimeStatus,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canRepairRuntime(status: RuntimeStatus, isBusy: Bool) -> Bool {
        !isBusy && isRuntimeExecutable(status)
    }

    public func canControlRuntimeServices(
        status: RuntimeStatus,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canControlRuntimeServices
            && isRuntimeExecutable(status)
    }

    public func canUninstallRuntime(
        status: RuntimeStatus,
        capabilities: RuntimeControlCapabilities,
        isBusy: Bool
    ) -> Bool {
        !isBusy
            && capabilities.canUninstallRuntime
            && isRuntimeExecutable(status)
    }
}
