import Foundation
import Contracts
import Errors

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
    public var canUseTestTools: Bool

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
        canViewReleaseMetadata: Bool = true,
        canUseTestTools: Bool = false
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
        self.canUseTestTools = canUseTestTools
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
    private enum CodingKeys: String, CodingKey {
        case readIssues
        case cpuCount
        case memoryGiB
        case diskGiB
        case minimumDiskGiB
        case networkMode
        case bridgedInterface
        case proxyPort
        case runtimeControlPort
        case vitalFilesDirectory
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case adminPassword
        case changeAdminPassword
        case startOnBoot
        case startOnBootConfigurable
        case autoRecoveryEnabled
        case preventSystemSleep
        case redisBackupRetentionCount
        case restartAfterSave
    }

    public var readIssues: [RuntimeSettingsReadIssue]
    public var cpuCount: Int
    public var memoryGiB: Int
    public var diskGiB: Int
    public var minimumDiskGiB: Int
    public var networkMode: RuntimeNetworkMode
    public var bridgedInterface: String?
    public var proxyPort: Int
    public var runtimeControlPort: Int
    public var vitalFilesDirectory: String
    public var vitalServerURL: String
    public var remoteConsoleURL: String
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
        readIssues: [RuntimeSettingsReadIssue] = [],
        cpuCount: Int = 8,
        memoryGiB: Int = 8,
        diskGiB: Int = 32,
        minimumDiskGiB: Int = 4,
        networkMode: RuntimeNetworkMode = .shared,
        bridgedInterface: String? = nil,
        proxyPort: Int = 80,
        runtimeControlPort: Int = 18_321,
        vitalFilesDirectory: String = "/Users/Shared/VitalServerHelper/vital-files",
        vitalServerURL: String = "",
        remoteConsoleURL: String = "",
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
        self.readIssues = readIssues
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.minimumDiskGiB = minimumDiskGiB
        self.networkMode = networkMode
        self.bridgedInterface = bridgedInterface
        self.proxyPort = proxyPort
        self.runtimeControlPort = runtimeControlPort
        self.vitalFilesDirectory = vitalFilesDirectory
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.bridgedInterface) else {
            throw DecodingError.keyNotFound(
                CodingKeys.bridgedInterface,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "RuntimeSettings.bridgedInterface is required and may be null only when no bridged interface is configured"
                )
            )
        }
        let bridgedInterface: String?
        if try container.decodeNil(forKey: .bridgedInterface) {
            bridgedInterface = nil
        } else {
            bridgedInterface = try container.decode(String.self, forKey: .bridgedInterface)
        }

        self.init(
            readIssues: try container.decode([RuntimeSettingsReadIssue].self, forKey: .readIssues),
            cpuCount: try container.decode(Int.self, forKey: .cpuCount),
            memoryGiB: try container.decode(Int.self, forKey: .memoryGiB),
            diskGiB: try container.decode(Int.self, forKey: .diskGiB),
            minimumDiskGiB: try container.decode(Int.self, forKey: .minimumDiskGiB),
            networkMode: try container.decode(RuntimeNetworkMode.self, forKey: .networkMode),
            bridgedInterface: bridgedInterface,
            proxyPort: try container.decode(Int.self, forKey: .proxyPort),
            runtimeControlPort: try container.decode(Int.self, forKey: .runtimeControlPort),
            vitalFilesDirectory: try container.decode(String.self, forKey: .vitalFilesDirectory),
            vitalServerURL: try container.decode(String.self, forKey: .vitalServerURL),
            remoteConsoleURL: try container.decode(String.self, forKey: .remoteConsoleURL),
            publicHost: try container.decode(String.self, forKey: .publicHost),
            publicPort: try container.decode(Int.self, forKey: .publicPort),
            adminPassword: try container.decode(String.self, forKey: .adminPassword),
            changeAdminPassword: try container.decode(Bool.self, forKey: .changeAdminPassword),
            startOnBoot: try container.decode(Bool.self, forKey: .startOnBoot),
            startOnBootConfigurable: try container.decode(Bool.self, forKey: .startOnBootConfigurable),
            autoRecoveryEnabled: try container.decode(Bool.self, forKey: .autoRecoveryEnabled),
            preventSystemSleep: try container.decode(Bool.self, forKey: .preventSystemSleep),
            redisBackupRetentionCount: try container.decode(Int.self, forKey: .redisBackupRetentionCount),
            restartAfterSave: try container.decode(Bool.self, forKey: .restartAfterSave)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readIssues, forKey: .readIssues)
        try container.encode(cpuCount, forKey: .cpuCount)
        try container.encode(memoryGiB, forKey: .memoryGiB)
        try container.encode(diskGiB, forKey: .diskGiB)
        try container.encode(minimumDiskGiB, forKey: .minimumDiskGiB)
        try container.encode(networkMode, forKey: .networkMode)
        if let bridgedInterface {
            try container.encode(bridgedInterface, forKey: .bridgedInterface)
        } else {
            try container.encodeNil(forKey: .bridgedInterface)
        }
        try container.encode(proxyPort, forKey: .proxyPort)
        try container.encode(runtimeControlPort, forKey: .runtimeControlPort)
        try container.encode(vitalFilesDirectory, forKey: .vitalFilesDirectory)
        try container.encode(vitalServerURL, forKey: .vitalServerURL)
        try container.encode(remoteConsoleURL, forKey: .remoteConsoleURL)
        try container.encode(publicHost, forKey: .publicHost)
        try container.encode(publicPort, forKey: .publicPort)
        try container.encode(adminPassword, forKey: .adminPassword)
        try container.encode(changeAdminPassword, forKey: .changeAdminPassword)
        try container.encode(startOnBoot, forKey: .startOnBoot)
        try container.encode(startOnBootConfigurable, forKey: .startOnBootConfigurable)
        try container.encode(autoRecoveryEnabled, forKey: .autoRecoveryEnabled)
        try container.encode(preventSystemSleep, forKey: .preventSystemSleep)
        try container.encode(redisBackupRetentionCount, forKey: .redisBackupRetentionCount)
        try container.encode(restartAfterSave, forKey: .restartAfterSave)
    }
}

public struct RuntimeSettingsReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct RuntimeDataDirectoryStats: Codable, Equatable, Sendable {
    public let fileCount: Int
    public let sizeBytes: Int64

    public init(fileCount: Int, sizeBytes: Int64) {
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
    }
}

public struct RuntimeStatusReadIssue: Codable, Equatable, Sendable {
    public var source: String
    public var message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public enum RuntimeServiceStateSource: String, Codable, Equatable, Sendable {
    case statusDocument = "status-document"
    case liveLaunchd = "live-launchd"
}

public struct RuntimeStatus: Codable, Equatable, Sendable {
    public var runtimeInstalled: Bool
    public var runtimeInstallationState: RuntimeFileState?
    public var vmServiceLoaded: Bool
    public var proxyServiceLoaded: Bool
    public var guestLogSyncServiceLoaded: Bool
    public var sleepPreventionServiceLoaded: Bool?
    public var watchdogServiceLoaded: Bool
    public var vmServiceState: RuntimeServiceState?
    public var proxyServiceState: RuntimeServiceState?
    public var guestLogSyncServiceState: RuntimeServiceState?
    public var sleepPreventionServiceState: RuntimeServiceState?
    public var watchdogServiceState: RuntimeServiceState?
    public var vmServiceStateSource: RuntimeServiceStateSource?
    public var proxyServiceStateSource: RuntimeServiceStateSource?
    public var guestLogSyncServiceStateSource: RuntimeServiceStateSource?
    public var sleepPreventionServiceStateSource: RuntimeServiceStateSource?
    public var watchdogServiceStateSource: RuntimeServiceStateSource?
    public var runtimeState: RuntimeState?
    public var operation: RuntimeOperation?
    public var statusMessage: String?
    public var statusDocumentError: String?
    public var installStateDocument: RuntimeInstallStateDocument?
    public var installStateDocumentError: String?
    public var readIssues: [RuntimeStatusReadIssue]
    public var updatedAt: String?
    public var startedAt: String?
    public var runtimeVersion: String?
    public var latestBackup: String?
    public var vmState: RuntimeVMState?
    public var vmErrors: [RuntimeVMError]?
    public var vmIP: String?
    public var guestHTTP: String?
    public var hostProxyHTTP: String?
    public var runtimeControlHTTP: String?
    public var runtimeControlStartedAt: String?
    public var redisUIHTTP: String?
    public var swaggerUIHTTP: String?
    public var cpuUsagePercent: Double?
    public var memory: ResourceUsage?
    public var systemDisk: ResourceUsage?
    public var dataStorage: ResourceUsage?
    public var dataStorageError: String?
    public var guestRuntimeStateError: String?
    public var dataDirectoryStats: RuntimeDataDirectoryStats?
    public var dataDirectoryStatsError: String?
    public var proxyPort: Int?
    public var proxyPortReadState: RuntimeProxyPortReadState?
    public var failureReasons: [RuntimeFailureReason]
    public var progress: RuntimeProgressDocument?
    public var containerObservation: RuntimeContainerObservation?
    public var vitalDBObservation: VitalDBObservationDocument?

    public init(
        runtimeInstalled: Bool = false,
        runtimeInstallationState: RuntimeFileState? = nil,
        vmServiceLoaded: Bool = false,
        proxyServiceLoaded: Bool = false,
        guestLogSyncServiceLoaded: Bool = false,
        sleepPreventionServiceLoaded: Bool? = nil,
        watchdogServiceLoaded: Bool = false,
        vmServiceState: RuntimeServiceState? = nil,
        proxyServiceState: RuntimeServiceState? = nil,
        guestLogSyncServiceState: RuntimeServiceState? = nil,
        sleepPreventionServiceState: RuntimeServiceState? = nil,
        watchdogServiceState: RuntimeServiceState? = nil,
        vmServiceStateSource: RuntimeServiceStateSource? = nil,
        proxyServiceStateSource: RuntimeServiceStateSource? = nil,
        guestLogSyncServiceStateSource: RuntimeServiceStateSource? = nil,
        sleepPreventionServiceStateSource: RuntimeServiceStateSource? = nil,
        watchdogServiceStateSource: RuntimeServiceStateSource? = nil,
        runtimeState: RuntimeState? = nil,
        operation: RuntimeOperation? = nil,
        statusMessage: String? = nil,
        statusDocumentError: String? = nil,
        installStateDocument: RuntimeInstallStateDocument? = nil,
        installStateDocumentError: String? = nil,
        readIssues: [RuntimeStatusReadIssue] = [],
        updatedAt: String? = nil,
        startedAt: String? = nil,
        runtimeVersion: String? = nil,
        latestBackup: String? = nil,
        vmState: RuntimeVMState? = nil,
        vmErrors: [RuntimeVMError]? = nil,
        vmIP: String? = nil,
        guestHTTP: String? = nil,
        hostProxyHTTP: String? = nil,
        runtimeControlHTTP: String? = nil,
        runtimeControlStartedAt: String? = nil,
        redisUIHTTP: String? = nil,
        swaggerUIHTTP: String? = nil,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil,
        dataStorage: ResourceUsage? = nil,
        dataStorageError: String? = nil,
        guestRuntimeStateError: String? = nil,
        dataDirectoryStats: RuntimeDataDirectoryStats? = nil,
        dataDirectoryStatsError: String? = nil,
        proxyPort: Int? = nil,
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        failureReasons: [RuntimeFailureReason] = [],
        progress: RuntimeProgressDocument? = nil,
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.runtimeInstallationState = runtimeInstallationState
        self.vmServiceLoaded = vmServiceLoaded
        self.proxyServiceLoaded = proxyServiceLoaded
        self.guestLogSyncServiceLoaded = guestLogSyncServiceLoaded
        self.sleepPreventionServiceLoaded = sleepPreventionServiceLoaded
        self.watchdogServiceLoaded = watchdogServiceLoaded
        self.vmServiceState = vmServiceState
        self.proxyServiceState = proxyServiceState
        self.guestLogSyncServiceState = guestLogSyncServiceState
        self.sleepPreventionServiceState = sleepPreventionServiceState
        self.watchdogServiceState = watchdogServiceState
        self.vmServiceStateSource = vmServiceStateSource
        self.proxyServiceStateSource = proxyServiceStateSource
        self.guestLogSyncServiceStateSource = guestLogSyncServiceStateSource
        self.sleepPreventionServiceStateSource = sleepPreventionServiceStateSource
        self.watchdogServiceStateSource = watchdogServiceStateSource
        self.runtimeState = runtimeState
        self.operation = operation
        self.statusMessage = statusMessage
        self.statusDocumentError = statusDocumentError
        self.installStateDocument = installStateDocument
        self.installStateDocumentError = installStateDocumentError
        self.readIssues = readIssues
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.runtimeVersion = runtimeVersion
        self.latestBackup = latestBackup
        self.vmState = vmState
        self.vmErrors = vmErrors
        self.vmIP = vmIP
        self.guestHTTP = guestHTTP
        self.hostProxyHTTP = hostProxyHTTP
        self.runtimeControlHTTP = runtimeControlHTTP
        self.runtimeControlStartedAt = runtimeControlStartedAt
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.systemDisk = systemDisk
        self.dataStorage = dataStorage
        self.dataStorageError = dataStorageError
        self.guestRuntimeStateError = guestRuntimeStateError
        self.dataDirectoryStats = dataDirectoryStats
        self.dataDirectoryStatsError = dataDirectoryStatsError
        self.proxyPort = proxyPort
        self.proxyPortReadState = proxyPortReadState
        self.failureReasons = failureReasons
        self.progress = progress
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
    }

    public var effectiveRuntimeInstallationState: RuntimeFileState {
        runtimeInstallationState ?? (runtimeInstalled ? .executable : .missing)
    }

}
