import Foundation
import Contracts

public struct RuntimeControlCapabilities: Codable, Equatable, Sendable {
    public var canInstallRuntime: Bool
    public var canUninstallRuntime: Bool
    public var canApplyBundle: Bool
    public var canRollback: Bool
    public var canEditVMResources: Bool
    public var canEditNetworkExposure: Bool
    public var canResetAdminPassword: Bool
    public var canOpenLocalFiles: Bool
    public var canStreamLogs: Bool
    public var canControlRuntimeServices: Bool
    public var canExportLogs: Bool
    public var canViewReleaseMetadata: Bool

    public init(
        canInstallRuntime: Bool = true,
        canUninstallRuntime: Bool = true,
        canApplyBundle: Bool = true,
        canRollback: Bool = true,
        canEditVMResources: Bool = true,
        canEditNetworkExposure: Bool = true,
        canResetAdminPassword: Bool = true,
        canOpenLocalFiles: Bool = true,
        canStreamLogs: Bool = true,
        canControlRuntimeServices: Bool = true,
        canExportLogs: Bool = true,
        canViewReleaseMetadata: Bool = true
    ) {
        self.canInstallRuntime = canInstallRuntime
        self.canUninstallRuntime = canUninstallRuntime
        self.canApplyBundle = canApplyBundle
        self.canRollback = canRollback
        self.canEditVMResources = canEditVMResources
        self.canEditNetworkExposure = canEditNetworkExposure
        self.canResetAdminPassword = canResetAdminPassword
        self.canOpenLocalFiles = canOpenLocalFiles
        self.canStreamLogs = canStreamLogs
        self.canControlRuntimeServices = canControlRuntimeServices
        self.canExportLogs = canExportLogs
        self.canViewReleaseMetadata = canViewReleaseMetadata
    }
}

public enum RuntimeNetworkMode: String, Codable, Equatable, Sendable {
    case shared
    case bridged
}

public enum RuntimeState: Codable, Equatable, Sendable {
    case installing
    case updating
    case recovering
    case healthy
    case degraded
    case critical
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "installing":
            self = .installing
        case "updating":
            self = .updating
        case "recovering":
            self = .recovering
        case "healthy":
            self = .healthy
        case "degraded":
            self = .degraded
        case "critical":
            self = .critical
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .installing:
            return "installing"
        case .updating:
            return "updating"
        case .recovering:
            return "recovering"
        case .healthy:
            return "healthy"
        case .degraded:
            return "degraded"
        case .critical:
            return "critical"
        case .unknown(let value):
            return value
        }
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

public struct RuntimeSettings: Codable, Equatable, Sendable {
    public var cpuCount: Int
    public var memoryGiB: Int
    public var diskGiB: Int
    public var minimumDiskGiB: Int
    public var networkMode: RuntimeNetworkMode
    public var bridgedInterface: String
    public var proxyPort: Int
    public var vitalFilesDirectory: String
    public var publicHost: String
    public var publicPort: Int
    public var adminPassword: String
    public var changeAdminPassword: Bool
    public var startOnBoot: Bool
    public var startOnBootConfigurable: Bool
    public var autoRecoveryEnabled: Bool
    public var preventSystemSleep: Bool
    public var redisBackupRetentionCount: Int
    public var restartAfterSave: Bool

    public init(
        cpuCount: Int = 8,
        memoryGiB: Int = 8,
        diskGiB: Int = 32,
        minimumDiskGiB: Int = 4,
        networkMode: RuntimeNetworkMode = .shared,
        bridgedInterface: String = "",
        proxyPort: Int = 80,
        vitalFilesDirectory: String = "/Users/Shared/TiroshVitalServer/vital-files",
        publicHost: String = "",
        publicPort: Int = 80,
        adminPassword: String = "",
        changeAdminPassword: Bool = false,
        startOnBoot: Bool = true,
        startOnBootConfigurable: Bool = true,
        autoRecoveryEnabled: Bool = true,
        preventSystemSleep: Bool = true,
        redisBackupRetentionCount: Int = 30,
        restartAfterSave: Bool = true
    ) {
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.minimumDiskGiB = minimumDiskGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.proxyPort = proxyPort
        self.vitalFilesDirectory = vitalFilesDirectory
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.adminPassword = adminPassword
        self.changeAdminPassword = changeAdminPassword
        self.startOnBoot = startOnBoot
        self.startOnBootConfigurable = startOnBootConfigurable
        self.autoRecoveryEnabled = autoRecoveryEnabled
        self.preventSystemSleep = preventSystemSleep
        self.redisBackupRetentionCount = redisBackupRetentionCount
        self.restartAfterSave = restartAfterSave
    }
}

public struct RuntimeStatus: Codable, Equatable, Sendable {
    public var runtimeInstalled: Bool
    public var vmServiceLoaded: Bool
    public var proxyServiceLoaded: Bool
    public var guestLogSyncServiceLoaded: Bool
    public var sleepPreventionServiceLoaded: Bool?
    public var watchdogServiceLoaded: Bool
    public var runtimeState: RuntimeState?
    public var operation: RuntimeOperation?
    public var statusMessage: String?
    public var updatedAt: String?
    public var startedAt: String?
    public var runtimeVersion: String?
    public var latestBackup: String?
    public var vmIP: String?
    public var guestHTTP: String?
    public var hostProxyHTTP: String?
    public var redisUIHTTP: String?
    public var swaggerUIHTTP: String?
    public var cpuUsagePercent: Double?
    public var memory: ResourceUsage?
    public var systemDisk: ResourceUsage?
    public var dataStorage: ResourceUsage?
    public var proxyPort: Int
    public var failureReasons: [RuntimeFailureReason]
    public var progress: RuntimeProgressDocument?
    public var containerObservation: RuntimeContainerObservation?
    public var vitalDBObservation: VitalDBObservationDocument?

    public init(
        runtimeInstalled: Bool = false,
        vmServiceLoaded: Bool = false,
        proxyServiceLoaded: Bool = false,
        guestLogSyncServiceLoaded: Bool = false,
        sleepPreventionServiceLoaded: Bool? = nil,
        watchdogServiceLoaded: Bool = false,
        runtimeState: RuntimeState? = nil,
        operation: RuntimeOperation? = nil,
        statusMessage: String? = nil,
        updatedAt: String? = nil,
        startedAt: String? = nil,
        runtimeVersion: String? = nil,
        latestBackup: String? = nil,
        vmIP: String? = nil,
        guestHTTP: String? = nil,
        hostProxyHTTP: String? = nil,
        redisUIHTTP: String? = nil,
        swaggerUIHTTP: String? = nil,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil,
        dataStorage: ResourceUsage? = nil,
        proxyPort: Int = 80,
        failureReasons: [RuntimeFailureReason] = [],
        progress: RuntimeProgressDocument? = nil,
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.vmServiceLoaded = vmServiceLoaded
        self.proxyServiceLoaded = proxyServiceLoaded
        self.guestLogSyncServiceLoaded = guestLogSyncServiceLoaded
        self.sleepPreventionServiceLoaded = sleepPreventionServiceLoaded
        self.watchdogServiceLoaded = watchdogServiceLoaded
        self.runtimeState = runtimeState
        self.operation = operation
        self.statusMessage = statusMessage
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.runtimeVersion = runtimeVersion
        self.latestBackup = latestBackup
        self.vmIP = vmIP
        self.guestHTTP = guestHTTP
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.systemDisk = systemDisk
        self.dataStorage = dataStorage
        self.proxyPort = proxyPort
        self.failureReasons = failureReasons
        self.progress = progress
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
    }

    public var isReady: Bool {
        runtimeInstalled
            && vmServiceLoaded
            && proxyServiceLoaded
            && watchdogServiceLoaded
            && runtimeState == .healthy
            && vmIP != nil
            && isSuccessfulHTTPStatus(guestHTTP)
            && isSuccessfulHTTPStatus(hostProxyHTTP)
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
