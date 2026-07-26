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
    case hostRuntimeStateEvents
    case hostRuntimeStateSnapshot
    case hostRuntimeStateDatabase
    case hostRuntimeStateDatabaseWAL
    case hostRuntimeStateDatabaseSHM
    case runtimeEvents
    case runtimeObservabilityDB
    case runtimeObservabilityDBWAL
    case runtimeObservabilityDBSHM
    case runtimeObservation
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
            .init(sourceID: .bootstrapLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.bootstrapLog)"),
            .init(sourceID: .containerLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.containerLogs)"),
            .init(sourceID: .updateActivationLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.updateActivationLog)"),
            .init(sourceID: .updateShutdownLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.updateShutdownLog)"),
            .init(sourceID: .datastoreRepairLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.datastoreRepairLog)"),
            .init(sourceID: .redisBackupLog, relativeDestination: "guest/\(RuntimeLogArtifactFileNames.redisBackupLog)"),
            .init(sourceID: .guestObservability, relativeDestination: "guest/guest-observability"),
            .init(sourceID: .commandLog, relativeDestination: "command.log"),
            .init(sourceID: .helperMessageLog, relativeDestination: "helper-message.log"),
            .init(sourceID: .runtimeStatus, relativeDestination: "diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)"),
            .init(sourceID: .hostRuntimeStateEvents, relativeDestination: "diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeStateEvents)"),
            .init(sourceID: .hostRuntimeStateSnapshot, relativeDestination: "diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeState)"),
            .init(sourceID: .hostRuntimeStateDatabase, relativeDestination: "diagnostics/host/runtime-state.sqlite"),
            .init(sourceID: .hostRuntimeStateDatabaseWAL, relativeDestination: "diagnostics/host/runtime-state.sqlite-wal"),
            .init(sourceID: .hostRuntimeStateDatabaseSHM, relativeDestination: "diagnostics/host/runtime-state.sqlite-shm"),
            .init(sourceID: .runtimeEvents, relativeDestination: "diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)"),
            .init(sourceID: .runtimeObservabilityDB, relativeDestination: "diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)"),
            .init(sourceID: .runtimeObservabilityDBWAL, relativeDestination: "diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-wal"),
            .init(sourceID: .runtimeObservabilityDBSHM, relativeDestination: "diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-shm"),
            .init(sourceID: .runtimeObservation, relativeDestination: "diagnostics/guest/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservation)"),
            .init(sourceID: .vmIP, relativeDestination: "diagnostics/guest/\(RuntimeBootstrapEvidenceFileNames.vmIP)"),
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
                sourceFilePrefix: "\(RuntimeLogArtifactFileNames.containerLogs).",
                relativeDestinationDirectory: "guest",
                destinationFilePrefix: "\(RuntimeLogArtifactFileNames.containerLogs)."
            ),
            .init(
                sourceID: .runtimeEvents,
                sourceFilePrefix: "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents).",
                relativeDestinationDirectory: "diagnostics/status",
                destinationFilePrefix: "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)."
            ),
        ]
    }
}
