public enum RuntimeWorkflowStep: Codable, Equatable, Sendable {
    case loadInstallSettings
    case prepareInstallDirectories
    case prepareHostStateStore
    case rotateRuntimeLogs
    case configureGuestRuntimeConfig
    case prepareInstalledExecutables
    case provisionVMDisk
    case configureVMRuntime
    case createCloudInitSeed
    case writeInstallRuntimeVersion
    case configureInstalledPermissions
    case startInstalledServices
    case applyStartOnBootPolicy
    case waitInstallRuntimeHealth
    case cleanupInstallSettings
    case uninstallCreateRedisBackup
    case uninstallStopRuntimeServices
    case uninstallRemoveFiles
    case uninstallForgetPackageReceipts
    case stopRuntimeServices
    case replaceRootfsBase
    case replaceUpdateArtifacts
    case runMigrations
    case refreshCloudInitSeed
    case writeRuntimeVersion
    case startRuntimeServices
    case activateGuestUpdate
    case waitRuntimeHealth
    case rollbackStopRuntimeServices
    case rollbackRestoreRootfsBase
    case rollbackRestoreRuntimeVersion
    case rollbackRestoreUpdateArtifacts
    case rollbackStartRuntimeServices
    case rollbackWaitRuntimeHealth
    case restoreRuntimeDataBackup
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "load-install-settings":
            self = .loadInstallSettings
        case "prepare-install-directories":
            self = .prepareInstallDirectories
        case "prepare-host-state-store":
            self = .prepareHostStateStore
        case "rotate-runtime-logs":
            self = .rotateRuntimeLogs
        case "configure-guest-runtime-config":
            self = .configureGuestRuntimeConfig
        case "prepare-installed-executables":
            self = .prepareInstalledExecutables
        case "provision-vm-disk":
            self = .provisionVMDisk
        case "configure-vm-runtime":
            self = .configureVMRuntime
        case "create-cloud-init-seed":
            self = .createCloudInitSeed
        case "write-install-runtime-version":
            self = .writeInstallRuntimeVersion
        case "configure-installed-permissions":
            self = .configureInstalledPermissions
        case "start-installed-services":
            self = .startInstalledServices
        case "apply-start-on-boot-policy":
            self = .applyStartOnBootPolicy
        case "wait-install-runtime-health":
            self = .waitInstallRuntimeHealth
        case "cleanup-install-settings":
            self = .cleanupInstallSettings
        case "uninstall-create-redis-backup":
            self = .uninstallCreateRedisBackup
        case "uninstall-stop-runtime-services":
            self = .uninstallStopRuntimeServices
        case "uninstall-remove-files":
            self = .uninstallRemoveFiles
        case "uninstall-forget-package-receipts":
            self = .uninstallForgetPackageReceipts
        case "stop-runtime-services":
            self = .stopRuntimeServices
        case "replace-rootfs-base":
            self = .replaceRootfsBase
        case "replace-update-artifacts":
            self = .replaceUpdateArtifacts
        case "run-migrations":
            self = .runMigrations
        case "refresh-cloud-init-seed":
            self = .refreshCloudInitSeed
        case "write-runtime-version":
            self = .writeRuntimeVersion
        case "start-runtime-services":
            self = .startRuntimeServices
        case "activate-guest-update":
            self = .activateGuestUpdate
        case "wait-runtime-health":
            self = .waitRuntimeHealth
        case "rollback-stop-runtime-services":
            self = .rollbackStopRuntimeServices
        case "rollback-restore-rootfs-base":
            self = .rollbackRestoreRootfsBase
        case "rollback-restore-runtime-version":
            self = .rollbackRestoreRuntimeVersion
        case "rollback-restore-update-artifacts":
            self = .rollbackRestoreUpdateArtifacts
        case "rollback-start-runtime-services":
            self = .rollbackStartRuntimeServices
        case "rollback-wait-runtime-health":
            self = .rollbackWaitRuntimeHealth
        case "restore-runtime-data-backup":
            self = .restoreRuntimeDataBackup
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .loadInstallSettings:
            return "load-install-settings"
        case .prepareInstallDirectories:
            return "prepare-install-directories"
        case .prepareHostStateStore:
            return "prepare-host-state-store"
        case .rotateRuntimeLogs:
            return "rotate-runtime-logs"
        case .configureGuestRuntimeConfig:
            return "configure-guest-runtime-config"
        case .prepareInstalledExecutables:
            return "prepare-installed-executables"
        case .provisionVMDisk:
            return "provision-vm-disk"
        case .configureVMRuntime:
            return "configure-vm-runtime"
        case .createCloudInitSeed:
            return "create-cloud-init-seed"
        case .writeInstallRuntimeVersion:
            return "write-install-runtime-version"
        case .configureInstalledPermissions:
            return "configure-installed-permissions"
        case .startInstalledServices:
            return "start-installed-services"
        case .applyStartOnBootPolicy:
            return "apply-start-on-boot-policy"
        case .waitInstallRuntimeHealth:
            return "wait-install-runtime-health"
        case .cleanupInstallSettings:
            return "cleanup-install-settings"
        case .uninstallCreateRedisBackup:
            return "uninstall-create-redis-backup"
        case .uninstallStopRuntimeServices:
            return "uninstall-stop-runtime-services"
        case .uninstallRemoveFiles:
            return "uninstall-remove-files"
        case .uninstallForgetPackageReceipts:
            return "uninstall-forget-package-receipts"
        case .stopRuntimeServices:
            return "stop-runtime-services"
        case .replaceRootfsBase:
            return "replace-rootfs-base"
        case .replaceUpdateArtifacts:
            return "replace-update-artifacts"
        case .runMigrations:
            return "run-migrations"
        case .refreshCloudInitSeed:
            return "refresh-cloud-init-seed"
        case .writeRuntimeVersion:
            return "write-runtime-version"
        case .startRuntimeServices:
            return "start-runtime-services"
        case .activateGuestUpdate:
            return "activate-guest-update"
        case .waitRuntimeHealth:
            return "wait-runtime-health"
        case .rollbackStopRuntimeServices:
            return "rollback-stop-runtime-services"
        case .rollbackRestoreRootfsBase:
            return "rollback-restore-rootfs-base"
        case .rollbackRestoreRuntimeVersion:
            return "rollback-restore-runtime-version"
        case .rollbackRestoreUpdateArtifacts:
            return "rollback-restore-update-artifacts"
        case .rollbackStartRuntimeServices:
            return "rollback-start-runtime-services"
        case .rollbackWaitRuntimeHealth:
            return "rollback-wait-runtime-health"
        case .restoreRuntimeDataBackup:
            return "restore-runtime-data-backup"
        case .unknown(let value):
            return value
        }
    }

    public var operation: RuntimeOperation? {
        switch self {
        case .loadInstallSettings,
             .prepareInstallDirectories,
             .prepareHostStateStore,
             .rotateRuntimeLogs,
             .configureGuestRuntimeConfig,
             .prepareInstalledExecutables,
             .provisionVMDisk,
             .configureVMRuntime,
             .createCloudInitSeed,
             .writeInstallRuntimeVersion,
             .configureInstalledPermissions,
             .startInstalledServices,
             .applyStartOnBootPolicy,
             .waitInstallRuntimeHealth,
             .cleanupInstallSettings:
            return .install
        case .uninstallCreateRedisBackup,
             .uninstallStopRuntimeServices,
             .uninstallRemoveFiles,
             .uninstallForgetPackageReceipts:
            return .uninstall
        case .stopRuntimeServices,
             .replaceRootfsBase,
             .replaceUpdateArtifacts,
             .runMigrations,
             .refreshCloudInitSeed,
             .writeRuntimeVersion,
             .startRuntimeServices,
             .activateGuestUpdate,
             .waitRuntimeHealth:
            return .applyBundle
        case .rollbackStopRuntimeServices,
             .rollbackRestoreRootfsBase,
             .rollbackRestoreRuntimeVersion,
             .rollbackRestoreUpdateArtifacts,
             .rollbackStartRuntimeServices,
             .rollbackWaitRuntimeHealth:
            return .rollback
        case .restoreRuntimeDataBackup:
            return .runtimeDataRestore
        case .unknown:
            return nil
        }
    }

    public func belongs(to operation: RuntimeOperation) -> Bool {
        self.operation == operation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
