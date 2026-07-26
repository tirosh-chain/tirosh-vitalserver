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
