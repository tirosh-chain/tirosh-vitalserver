import Foundation
import RuntimeCore

public struct RuntimeClientCapabilities: Equatable, Sendable {
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

public struct RuntimeSettings: Codable, Equatable, Sendable {
    public var cpuCount: Int
    public var memoryGiB: Int
    public var diskGiB: Int
    public var minimumDiskGiB: Int
    public var networkMode: String
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
    public var restartAfterSave: Bool

    public init(
        cpuCount: Int = 8,
        memoryGiB: Int = 8,
        diskGiB: Int = 32,
        minimumDiskGiB: Int = 4,
        networkMode: String = "shared",
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
        self.restartAfterSave = restartAfterSave
    }

    public func configureArguments(adminPasswordFile: String? = nil) -> [String] {
        var arguments = [
            RuntimeControlDefaults.runtime,
            RuntimeControlDefaults.configure,
            RuntimeControlDefaults.optionCPU,
            String(cpuCount),
            RuntimeControlDefaults.optionMemoryGiB,
            String(memoryGiB),
            RuntimeControlDefaults.optionDiskGiB,
            String(diskGiB),
            RuntimeControlDefaults.optionNetwork,
            networkMode,
            RuntimeControlDefaults.optionProxyPort,
            String(proxyPort),
            RuntimeControlDefaults.optionVitalFilesDirectory,
            vitalFilesDirectory,
            RuntimeControlDefaults.optionPublicHost,
            publicHost,
            RuntimeControlDefaults.optionPublicPort,
            String(publicPort),
        ]
        if startOnBootConfigurable {
            arguments += [
                RuntimeControlDefaults.optionStartOnBoot,
                startOnBoot ? RuntimeControlDefaults.boolTrue : RuntimeControlDefaults.boolFalse,
            ]
        }
        arguments += [
            RuntimeControlDefaults.optionAutoRecovery,
            autoRecoveryEnabled ? RuntimeControlDefaults.boolTrue : RuntimeControlDefaults.boolFalse,
        ]
        if networkMode == RuntimeControlDefaults.networkBridged, !bridgedInterface.isEmpty {
            arguments += [RuntimeControlDefaults.optionBridgedInterface, bridgedInterface]
        }
        if let adminPasswordFile {
            arguments += [RuntimeControlDefaults.optionAdminPasswordFile, adminPasswordFile]
        }
        if restartAfterSave {
            arguments.append(RuntimeControlDefaults.optionRestart)
        }
        return arguments
    }
}

public struct RuntimeStatus {
    public var runtimeInstalled: Bool
    public var vmServiceLoaded: Bool
    public var proxyServiceLoaded: Bool
    public var watchdogServiceLoaded: Bool
    public var runtimeState: String?
    public var operation: String?
    public var statusMessage: String?
    public var updatedAt: String?
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

    public init(
        runtimeInstalled: Bool = false,
        vmServiceLoaded: Bool = false,
        proxyServiceLoaded: Bool = false,
        watchdogServiceLoaded: Bool = false,
        runtimeState: String? = nil,
        operation: String? = nil,
        statusMessage: String? = nil,
        updatedAt: String? = nil,
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
        progress: RuntimeProgressDocument? = nil
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.vmServiceLoaded = vmServiceLoaded
        self.proxyServiceLoaded = proxyServiceLoaded
        self.watchdogServiceLoaded = watchdogServiceLoaded
        self.runtimeState = runtimeState
        self.operation = operation
        self.statusMessage = statusMessage
        self.updatedAt = updatedAt
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
    }

    public var isReady: Bool {
        runtimeInstalled
            && vmServiceLoaded
            && proxyServiceLoaded
            && watchdogServiceLoaded
            && runtimeState == RuntimeControlDefaults.stateHealthy
            && vmIP != nil
            && isSuccessfulHTTPStatus(guestHTTP)
            && isSuccessfulHTTPStatus(hostProxyHTTP)
    }

    public var displayMessage: String? {
        var lines: [String] = []
        if let statusMessage, !statusMessage.isEmpty {
            lines.append(statusMessage)
        }
        if !failureReasons.isEmpty {
            lines.append("\(RuntimeControlDefaults.failureReasonsLabel): \(failureReasonText)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public var failureReasonText: String {
        failureReasons.map(\.rawValue).joined(separator: ", ")
    }

    public var progressDisplayMessage: String? {
        guard let progress else {
            return nil
        }
        if let step = progress.step,
           let stepStatus = progress.stepStatus {
            return "\(stepStatusDisplayName(stepStatus)): \(humanizeStepName(step))"
        }
        return progress.message.isEmpty ? nil : progress.message
    }

    private func stepStatusDisplayName(_ status: RuntimeProgressStepStatus) -> String {
        switch status {
        case .pending:
            return RuntimeControlDefaults.waiting
        case .started:
            return RuntimeControlDefaults.running
        case .completed:
            return RuntimeControlDefaults.done
        case .failed:
            return RuntimeControlDefaults.failed.capitalized
        case .skipped:
            return "Skipped"
        case .unknown(let value):
            return value.capitalized
        }
    }

    private func humanizeStepName(_ step: String) -> String {
        step
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func humanizeStepName(_ step: RuntimeWorkflowStep) -> String {
        humanizeStepName(step.rawValue)
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}

public struct RuntimeBackup: Identifiable, Hashable, Sendable {
    public let url: URL
    public let sizeBytes: UInt64?

    public init(url: URL, sizeBytes: UInt64?) {
        self.url = url
        self.sizeBytes = sizeBytes
    }

    public var id: String { path }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }
    public var sizeText: String {
        guard let sizeBytes else {
            return RuntimeControlDefaults.unknown
        }
        return Self.formatBytes(sizeBytes)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}

public enum LogSourceID: String, Hashable, Sendable {
    case helperMessage
    case install
    case command
    case launcher
    case proxyOutput
    case proxyError
    case updateActivation
    case containers
}

public struct LogSourceOption: Identifiable, Sendable {
    public let id: LogSourceID
    public let title: String

    public init(id: LogSourceID, title: String) {
        self.id = id
        self.title = title
    }
}

public struct VitalFileFolder: Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var summary: String {
        let output = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return exitCode == 0
                ? RuntimeControlDefaults.done
                : RuntimeControlDefaults.commandFailed(exitCode: exitCode)
        }
        return output
    }
}

public struct RuntimeLogExportResult: Equatable, Sendable {
    public let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }
}

public struct RuntimeReleaseInfo: Equatable, Sendable {
    public let helperVersion: String
    public let minimumUpdaterVersion: String
    public let vitalServerVersion: String
    public let services: [RuntimeBundledServiceInfo]

    public init(
        helperVersion: String,
        minimumUpdaterVersion: String,
        vitalServerVersion: String,
        services: [RuntimeBundledServiceInfo]
    ) {
        self.helperVersion = helperVersion
        self.minimumUpdaterVersion = minimumUpdaterVersion
        self.vitalServerVersion = vitalServerVersion
        self.services = services
    }
}

public struct RuntimeBundledServiceInfo: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let image: String
    public let version: String

    public init(name: String, image: String, version: String) {
        self.name = name
        self.image = image
        self.version = version
    }
}

public struct RuntimeInstallationInfo: Equatable, Sendable {
    public let runtimeHomePath: String
    public let backupsPath: String

    public init(runtimeHomePath: String = "", backupsPath: String = "") {
        self.runtimeHomePath = runtimeHomePath
        self.backupsPath = backupsPath
    }
}

@MainActor
public protocol RuntimeClient {
    var capabilities: RuntimeClientCapabilities { get }

    func loadSettings() -> RuntimeSettings
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup]
    func updateBundleSummary(url: URL) -> String
    func logText(sourceID: LogSourceID, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFileFolder]
    func legacyCommandProgressLine() -> String?
    func createDirectory(at url: URL)
    func verifyUpdateBundle(url: URL) async throws -> ProcessResult
    func uninstallRuntime(clean: Bool) async throws -> ProcessResult
    func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult
    func applyUpdateBundle(url: URL) async throws -> ProcessResult
    func rollbackRuntime(backupURL: URL) async throws -> ProcessResult
    func deleteBackup(url: URL) async throws -> ProcessResult
    func repairProxy(proxyPort: Int) async throws -> ProcessResult
    func repairDatastore() async throws -> ProcessResult
    func startRuntimeServices() async throws -> ProcessResult
    func stopRuntimeServices() async throws -> ProcessResult
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallationInfo() -> RuntimeInstallationInfo
}

private enum RuntimeControlDefaults {
    static let defaultProxyPort = 80
    static let defaultDiskGiB = 32
    static let minimumDiskGiB = 4
    static let vitalFilesDirectory = "/Users/Shared/TiroshVitalServer/vital-files"
    static let networkShared = "shared"
    static let networkBridged = "bridged"
    static let stateHealthy = "healthy"
    static let boolTrue = "true"
    static let boolFalse = "false"
    static let runtime = "runtime"
    static let configure = "configure"
    static let optionCPU = "--cpu"
    static let optionMemoryGiB = "--memory-gib"
    static let optionDiskGiB = "--disk-gib"
    static let optionNetwork = "--network"
    static let optionProxyPort = "--proxy-port"
    static let optionVitalFilesDirectory = "--vital-files-dir"
    static let optionPublicHost = "--public-host"
    static let optionPublicPort = "--public-port"
    static let optionStartOnBoot = "--start-on-boot"
    static let optionAutoRecovery = "--auto-recovery"
    static let optionBridgedInterface = "--bridged-interface"
    static let optionAdminPasswordFile = "--admin-password-file"
    static let optionRestart = "--restart"
    static let failureReasonsLabel = "Failure reasons"
    static let waiting = "Waiting"
    static let running = "Running"
    static let done = "Done"
    static let failed = "failed"
    static let unknown = "Unknown"

    static func commandFailed(exitCode: Int32) -> String {
        "Command failed with exit code \(exitCode)."
    }
}
