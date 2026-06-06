import Foundation
import RuntimeControl
import Application
import Contracts
import Domain
import Errors

protocol RuntimeStatusReading: Sendable {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

struct SystemRuntimeStatusReader: RuntimeStatusReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let fileStore: RuntimeFileStore
    private let storageUsageProvider: RuntimeStorageUsageProviding
    private let runCommand: @Sendable (String, [String]) async -> RuntimeCommandResult
    private let runSyncCommand: @Sendable (String, [String]) -> RuntimeCommandResult

    init(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        storageUsageProvider: RuntimeStorageUsageProviding? = nil,
        runCommand: @escaping @Sendable (String, [String]) async -> RuntimeCommandResult = { command, arguments in
            await ProcessRunner.run(command, arguments: arguments)
        },
        runSyncCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult = ProcessRunner.runSync
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.storageUsageProvider = storageUsageProvider ?? SystemRuntimeStorageUsageProvider(fileStore: fileStore)
        self.runCommand = runCommand
        self.runSyncCommand = runSyncCommand
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        withDataDirectoryMetrics(loadBaseStatus(configuredProxyPort: settings.proxyPort), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        var next = loadBaseStatus(configuredProxyPort: settings.proxyPort)

        if let vmIP = next.vmIP {
            let read = await httpStatus(
                source: "guestHTTP",
                url: RuntimeAdapterConstants.Product.guestHealthURL(vmIP: vmIP)
            )
            next.guestHTTP = read.status
            next.appendStatusReadIssue(read.issue)
        }
        let hostProxyRead = await httpStatus(
            source: "hostProxyHTTP",
            url: RuntimeAdapterConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort)
        )
        next.hostProxyHTTP = hostProxyRead.status
        next.appendStatusReadIssue(hostProxyRead.issue)

        let redisRead = await httpStatus(
            source: "redisUIHTTP",
            url: RuntimeAdapterConstants.Product.redisUIURL(proxyPort: next.proxyPort)
        )
        next.redisUIHTTP = redisRead.status
        next.appendStatusReadIssue(redisRead.issue)

        let swaggerRead = await httpStatus(
            source: "swaggerUIHTTP",
            url: RuntimeAdapterConstants.Product.swaggerURL(proxyPort: next.proxyPort)
        )
        next.swaggerUIHTTP = swaggerRead.status
        next.appendStatusReadIssue(swaggerRead.issue)

        return withDataDirectoryMetrics(next, settings: settings)
    }

    func loadBaseStatus(configuredProxyPort: Int = RuntimeAdapterConstants.Product.defaultProxyPort) -> RuntimeStatus {
        let statusRead = RuntimeStatusDocumentReader(
            url: URL(fileURLWithPath: paths.runtimeStatus)
        ).load()
        let guestStateRead = GuestRuntimeStateDocumentReader(
            path: paths.runtimeState,
            fileStore: fileStore
        ).load()
        let liveDiagnostics = RuntimeLiveDiagnosticsReader(
            paths: paths,
            isExecutableFile: { fileStore.isExecutableFile(atPath: $0) },
            launchdServiceState: launchdServiceState
        ).load(statusDocument: statusRead.document)

        return RuntimeBaseStatusAssembler.makeStatus(
            configuredProxyPort: configuredProxyPort,
            statusRead: statusRead,
            guestStateRead: guestStateRead,
            liveDiagnostics: liveDiagnostics
        )
    }

    private func httpStatus(source: String, url: String) async -> RuntimeHTTPStatusRead {
        let result = await runCommand(
            RuntimeAdapterConstants.Commands.curl,
            ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            return RuntimeHTTPStatusRead(
                status: nil,
                issue: RuntimeStatusReadIssue(source: source, message: commandFailureMessage(result))
            )
        }
        guard !code.isEmpty else {
            return RuntimeHTTPStatusRead(
                status: nil,
                issue: RuntimeStatusReadIssue(source: source, message: "empty HTTP status")
            )
        }
        return RuntimeHTTPStatusRead(status: code, issue: nil)
    }

    private func withDataDirectoryMetrics(_ status: RuntimeStatus, settings: RuntimeSettings) -> RuntimeStatus {
        var next = status
        switch storageUsageProvider.storageUsage(for: settings.vitalFilesDirectory) {
        case .loaded(let usage):
            next.dataStorage = usage
            next.dataStorageError = nil
        case .unavailable:
            next.dataStorageError = nil
        case .failed(let message):
            next.dataStorageError = message
        }
        do {
            next.dataDirectoryStats = try dataDirectoryStats(for: settings.vitalFilesDirectory)
            next.dataDirectoryStatsError = nil
        } catch {
            next.dataDirectoryStats = nil
            next.dataDirectoryStatsError = error.localizedDescription
        }
        return next
    }

    private func dataDirectoryStats(for path: String) throws -> RuntimeDataDirectoryStats? {
        let root = URL(fileURLWithPath: path)
        guard fileStore.directoryExists(root) else {
            return nil
        }
        let stats = try directoryStats(root)
        return RuntimeDataDirectoryStats(fileCount: stats.fileCount, sizeBytes: Int64(stats.sizeBytes))
    }

    private func directoryStats(_ directory: URL) throws -> (fileCount: Int, sizeBytes: UInt64) {
        let contents = try fileStore.contentsOfDirectory(at: directory, skipsHiddenFiles: true)

        var fileCount = 0
        var sizeBytes: UInt64 = 0
        for url in contents {
            if fileStore.directoryExists(url) {
                let nested = try directoryStats(url)
                fileCount += nested.fileCount
                sizeBytes += nested.sizeBytes
            } else if fileStore.fileExists(url) {
                fileCount += 1
                sizeBytes += try fileStore.fileSize(url)
            }
        }
        return (fileCount, sizeBytes)
    }

    private func launchdServiceState(_ service: RuntimeManagedService) -> RuntimeServiceState {
        let result = runSyncCommand(
            RuntimeAdapterConstants.Commands.launchctl,
            ["print", "system/\(service.label)"]
        )
        guard result.exitCode != 0 else {
            return .loaded
        }
        let message = commandFailureMessage(result)
        let lowercased = message.lowercased()
        if lowercased.contains("could not find service")
            || lowercased.contains("no such process")
            || lowercased.contains("not found")
        {
            return .notLoaded
        }
        if lowercased.contains("permission denied")
            || lowercased.contains("operation not permitted")
        {
            return .permissionDenied(message)
        }
        return .readFailed(message)
    }

    private func commandFailureMessage(_ result: RuntimeCommandResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        if !result.outputIssues.isEmpty {
            return "exitCode=\(result.exitCode) outputIssues=\(result.outputIssues.commandSummary)"
        }
        return "exitCode=\(result.exitCode)"
    }

}

private extension Array where Element == RuntimeCommandOutputIssue {
    var commandSummary: String {
        map { "\($0.stream.rawValue): \($0.message)" }
            .joined(separator: "; ")
    }
}

private extension RuntimeStatus {
    mutating func appendStatusReadIssue(_ issue: RuntimeStatusReadIssue?) {
        guard let issue else {
            return
        }
        readIssues.append(issue)
    }
}

private struct RuntimeHTTPStatusRead {
    let status: String?
    let issue: RuntimeStatusReadIssue?
}

private struct RuntimeStatusDocumentRead {
    let document: RuntimeStatusDocument?
    let error: String?
}

private struct GuestRuntimeStateRead {
    let document: GuestRuntimeStateDocument?
    let error: String?
}

private struct RuntimeLiveDiagnostics {
    let runtimeInstalled: Bool
    let vmServiceState: RuntimeServiceState
    let proxyServiceState: RuntimeServiceState
    let guestLogSyncServiceState: RuntimeServiceState
    let sleepPreventionServiceState: RuntimeServiceState
    let watchdogServiceState: RuntimeServiceState
    let readIssues: [RuntimeStatusReadIssue]
}

private struct RuntimeStatusDocumentReader {
    let url: URL

    func load() -> RuntimeStatusDocumentRead {
        switch JSONFileRuntimeStatusRepository(url: url).loadResult() {
        case .loaded(let document):
            RuntimeStatusDocumentRead(document: document, error: nil)
        case .missing:
            RuntimeStatusDocumentRead(document: nil, error: nil)
        case .failed(let message):
            RuntimeStatusDocumentRead(document: nil, error: message)
        }
    }
}

private struct GuestRuntimeStateDocumentReader {
    let path: String
    let fileStore: RuntimeFileStore

    func load() -> GuestRuntimeStateRead {
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return GuestRuntimeStateRead(document: nil, error: nil)
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
            return GuestRuntimeStateRead(document: document, error: nil)
        } catch {
            return GuestRuntimeStateRead(document: nil, error: error.localizedDescription)
        }
    }
}

private struct RuntimeLiveDiagnosticsReader {
    let paths: RuntimePaths
    let isExecutableFile: (String) -> Bool
    let launchdServiceState: (RuntimeManagedService) -> RuntimeServiceState

    func load(statusDocument document: RuntimeStatusDocument?) -> RuntimeLiveDiagnostics {
        let vmServiceState = serviceState(document?.vmService) ?? launchdServiceState(.vm)
        let proxyServiceState = serviceState(document?.proxyService) ?? launchdServiceState(.proxy)
        let guestLogSyncServiceState = launchdServiceState(.guestLogSync)
        let sleepPreventionServiceState = launchdServiceState(.sleepPrevention)
        let watchdogServiceState = serviceState(document?.watchdogService) ?? launchdServiceState(.watchdog)

        return RuntimeLiveDiagnostics(
            runtimeInstalled: isExecutableFile(paths.launcher),
            vmServiceState: vmServiceState,
            proxyServiceState: proxyServiceState,
            guestLogSyncServiceState: guestLogSyncServiceState,
            sleepPreventionServiceState: sleepPreventionServiceState,
            watchdogServiceState: watchdogServiceState,
            readIssues: serviceReadIssues([
                ("vmService", vmServiceState),
                ("proxyService", proxyServiceState),
                ("guestLogSyncService", guestLogSyncServiceState),
                ("sleepPreventionService", sleepPreventionServiceState),
                ("watchdogService", watchdogServiceState),
            ])
        )
    }

    private func serviceState(_ value: RuntimeServiceState?) -> RuntimeServiceState? {
        value
    }

    private func serviceReadIssues(_ states: [(String, RuntimeServiceState)]) -> [RuntimeStatusReadIssue] {
        states.compactMap { source, state in
            switch state {
            case .readFailed(let message), .permissionDenied(let message):
                RuntimeStatusReadIssue(source: source, message: message)
            case .unknown(let value):
                RuntimeStatusReadIssue(source: source, message: "unknown service state: \(value)")
            case .loaded, .notLoaded:
                nil
            }
        }
    }
}

private enum RuntimeBaseStatusAssembler {
    static func makeStatus(
        configuredProxyPort: Int,
        statusRead: RuntimeStatusDocumentRead,
        guestStateRead: GuestRuntimeStateRead,
        liveDiagnostics: RuntimeLiveDiagnostics
    ) -> RuntimeStatus {
        let document = statusRead.document
        let guestState = guestStateRead.document
        let containerObservation = document?.containerObservation
        let startedAt = containerObservation?.composeServices.first { $0.service == "app" }?.startedAt

        return RuntimeStatus(
            runtimeInstalled: liveDiagnostics.runtimeInstalled,
            vmServiceLoaded: liveDiagnostics.vmServiceState.isLoaded,
            proxyServiceLoaded: liveDiagnostics.proxyServiceState.isLoaded,
            guestLogSyncServiceLoaded: liveDiagnostics.guestLogSyncServiceState.isLoaded,
            sleepPreventionServiceLoaded: liveDiagnostics.sleepPreventionServiceState.isLoaded,
            watchdogServiceLoaded: liveDiagnostics.watchdogServiceState.isLoaded,
            vmServiceState: liveDiagnostics.vmServiceState,
            proxyServiceState: liveDiagnostics.proxyServiceState,
            guestLogSyncServiceState: liveDiagnostics.guestLogSyncServiceState,
            sleepPreventionServiceState: liveDiagnostics.sleepPreventionServiceState,
            watchdogServiceState: liveDiagnostics.watchdogServiceState,
            runtimeState: document.map { RuntimeState(rawValue: $0.status.rawValue) },
            operation: document?.operation,
            statusMessage: document?.message,
            statusDocumentError: statusRead.error,
            readIssues: liveDiagnostics.readIssues,
            updatedAt: document?.updatedAt,
            startedAt: startedAt,
            runtimeVersion: document?.runtimeVersion,
            latestBackup: document?.latestBackup,
            vmState: document?.vmState,
            vmErrors: document?.vmErrors,
            vmIP: document?.vmIP,
            guestHTTP: document?.guestHTTP,
            hostProxyHTTP: document?.hostProxyHTTP,
            redisUIHTTP: document?.redisUIHTTP,
            swaggerUIHTTP: document?.swaggerUIHTTP,
            cpuUsagePercent: guestState?.cpuUsagePercent,
            memory: guestState?.memory,
            systemDisk: guestState?.systemDisk,
            dataStorage: guestState?.vitalFilesDisk,
            guestRuntimeStateError: guestStateRead.error,
            proxyPort: document?.proxyPort ?? configuredProxyPort,
            failureReasons: document?.failureReasons ?? [],
            progress: document?.progress,
            containerObservation: containerObservation,
            vitalDBObservation: document?.vitalDBObservation
        )
    }
}
