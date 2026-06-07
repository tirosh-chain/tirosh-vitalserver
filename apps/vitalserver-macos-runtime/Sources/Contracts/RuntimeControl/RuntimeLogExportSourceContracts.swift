import Contracts

public enum RuntimeLogExportSupplementalSourceID: String, CaseIterable, Sendable {
    case bootstrapLog
    case containerLog
    case updateActivationLog
    case updateShutdownLog
    case datastoreRepairLog
    case redisBackupLog
    case guestObservability
    case commandLog
    case helperMessageLog
    case runtimeStatus
    case runtimeOperationLease
    case runtimeEvents
    case runtimeObservabilityDB
    case runtimeObservabilityDBWAL
    case runtimeObservabilityDBSHM
    case runtimeState
    case vmLifecycle
    case vmIP
    case vmConfig
    case runtimeVersion
    case guestRuntimeConfig
    case proxyLaunchDaemon
    case proxyNginxConfig
    case proxyNginxPid
}

public struct RuntimeLogExportSupplementalDestinationContract: Equatable, Sendable {
    public let sourceID: RuntimeLogExportSupplementalSourceID
    public let relativeDestination: String

    public init(
        sourceID: RuntimeLogExportSupplementalSourceID,
        relativeDestination: String
    ) {
        self.sourceID = sourceID
        self.relativeDestination = relativeDestination
    }
}

public enum RuntimeLogExportRotatedSupplementalSourceID: String, CaseIterable, Sendable {
    case containerLogs
    case runtimeEvents
}

public struct RuntimeLogExportRotatedSupplementalDestinationContract: Equatable, Sendable {
    public let sourceID: RuntimeLogExportRotatedSupplementalSourceID
    public let sourceFilePrefix: String
    public let relativeDestinationDirectory: String
    public let destinationFilePrefix: String

    public init(
        sourceID: RuntimeLogExportRotatedSupplementalSourceID,
        sourceFilePrefix: String,
        relativeDestinationDirectory: String,
        destinationFilePrefix: String
    ) {
        self.sourceID = sourceID
        self.sourceFilePrefix = sourceFilePrefix
        self.relativeDestinationDirectory = relativeDestinationDirectory
        self.destinationFilePrefix = destinationFilePrefix
    }
}

public enum RuntimeLogExportSourceContract {
    public static func supplementalDestinations() -> [RuntimeLogExportSupplementalDestinationContract] {
        [
            .init(sourceID: .bootstrapLog, relativeDestination: "guest/\(RuntimeFileNames.bootstrapLog)"),
            .init(sourceID: .containerLog, relativeDestination: "guest/\(RuntimeFileNames.containerLogs)"),
            .init(sourceID: .updateActivationLog, relativeDestination: "guest/\(RuntimeFileNames.updateActivationLog)"),
            .init(sourceID: .updateShutdownLog, relativeDestination: "guest/\(RuntimeFileNames.updateShutdownLog)"),
            .init(sourceID: .datastoreRepairLog, relativeDestination: "guest/\(RuntimeFileNames.datastoreRepairLog)"),
            .init(sourceID: .redisBackupLog, relativeDestination: "guest/\(RuntimeFileNames.redisBackupLog)"),
            .init(sourceID: .guestObservability, relativeDestination: "guest/guest-observability"),
            .init(sourceID: .commandLog, relativeDestination: "command.log"),
            .init(sourceID: .helperMessageLog, relativeDestination: "helper-message.log"),
            .init(sourceID: .runtimeStatus, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeStatus)"),
            .init(sourceID: .runtimeOperationLease, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeOperationLease)"),
            .init(sourceID: .runtimeEvents, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeEvents)"),
            .init(sourceID: .runtimeObservabilityDB, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)"),
            .init(sourceID: .runtimeObservabilityDBWAL, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-wal"),
            .init(sourceID: .runtimeObservabilityDBSHM, relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-shm"),
            .init(sourceID: .runtimeState, relativeDestination: "diagnostics/guest/\(RuntimeFileNames.runtimeState)"),
            .init(sourceID: .vmLifecycle, relativeDestination: "diagnostics/runtime/\(RuntimeFileNames.vmLifecycle)"),
            .init(sourceID: .vmIP, relativeDestination: "diagnostics/guest/\(RuntimeFileNames.vmIP)"),
            .init(sourceID: .vmConfig, relativeDestination: "diagnostics/runtime/vm-config.json"),
            .init(sourceID: .runtimeVersion, relativeDestination: "diagnostics/runtime/runtime-version.json"),
            .init(sourceID: .guestRuntimeConfig, relativeDestination: "diagnostics/guest/runtime-config.json"),
            .init(sourceID: .proxyLaunchDaemon, relativeDestination: "diagnostics/host/ai.tirosh.vitalserver.helper.proxy.plist"),
            .init(sourceID: .proxyNginxConfig, relativeDestination: "diagnostics/host/vitalserver-nginx.conf"),
            .init(sourceID: .proxyNginxPid, relativeDestination: "diagnostics/host/nginx.pid"),
        ]
    }

    public static func rotatedSupplementalDestinations() -> [RuntimeLogExportRotatedSupplementalDestinationContract] {
        [
            .init(
                sourceID: .containerLogs,
                sourceFilePrefix: "\(RuntimeFileNames.containerLogs).",
                relativeDestinationDirectory: "guest",
                destinationFilePrefix: "\(RuntimeFileNames.containerLogs)."
            ),
            .init(
                sourceID: .runtimeEvents,
                sourceFilePrefix: "\(RuntimeFileNames.runtimeEvents).",
                relativeDestinationDirectory: "diagnostics/status",
                destinationFilePrefix: "\(RuntimeFileNames.runtimeEvents)."
            ),
        ]
    }
}
