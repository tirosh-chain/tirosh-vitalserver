import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

protocol RuntimeStatusReading: Sendable {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

struct SystemRuntimeStatusReader: RuntimeStatusReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let fileStore: RuntimeFileStore
    private let storageUsageProvider: RuntimeStorageUsageProviding

    init(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        storageUsageProvider: RuntimeStorageUsageProviding? = nil
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.storageUsageProvider = storageUsageProvider ?? SystemRuntimeStorageUsageProvider(fileStore: fileStore)
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        withDataDirectoryMetrics(loadBaseStatus(configuredProxyPort: settings.proxyPort), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        var next = loadBaseStatus(configuredProxyPort: settings.proxyPort)

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort))
        next.redisUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.redisUIURL(proxyPort: next.proxyPort))
        next.swaggerUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.swaggerURL(proxyPort: next.proxyPort))

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
            launchdLoaded: launchdLoaded
        ).load(statusDocument: statusRead.document)

        return RuntimeBaseStatusAssembler.makeStatus(
            configuredProxyPort: configuredProxyPort,
            statusRead: statusRead,
            guestStateRead: guestStateRead,
            liveDiagnostics: liveDiagnostics
        )
    }

    private func httpStatus(url: String) async -> String {
        let result = await ProcessRunner.run(
            RuntimeAdapterConstants.Commands.curl,
            arguments: ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !code.isEmpty ? code : RuntimeAdapterConstants.StatusText.failed
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

    private func launchdLoaded(_ service: RuntimeManagedService) -> Bool {
        ProcessRunner.runSync(
            RuntimeAdapterConstants.Commands.launchctl,
            arguments: ["print", "system/\(service.label)"]
        ).exitCode == 0
    }

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
    let vmServiceLoaded: Bool
    let proxyServiceLoaded: Bool
    let guestLogSyncServiceLoaded: Bool
    let sleepPreventionServiceLoaded: Bool
    let watchdogServiceLoaded: Bool
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
    let launchdLoaded: (RuntimeManagedService) -> Bool

    func load(statusDocument document: RuntimeStatusDocument?) -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnostics(
            runtimeInstalled: isExecutableFile(paths.launcher),
            vmServiceLoaded: serviceLoaded(document?.vmService) ?? launchdLoaded(.vm),
            proxyServiceLoaded: serviceLoaded(document?.proxyService) ?? launchdLoaded(.proxy),
            guestLogSyncServiceLoaded: launchdLoaded(.guestLogSync),
            sleepPreventionServiceLoaded: launchdLoaded(.sleepPrevention),
            watchdogServiceLoaded: serviceLoaded(document?.watchdogService) ?? launchdLoaded(.watchdog)
        )
    }

    private func serviceLoaded(_ value: RuntimeServiceState?) -> Bool? {
        value?.isLoaded
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
            vmServiceLoaded: liveDiagnostics.vmServiceLoaded,
            proxyServiceLoaded: liveDiagnostics.proxyServiceLoaded,
            guestLogSyncServiceLoaded: liveDiagnostics.guestLogSyncServiceLoaded,
            sleepPreventionServiceLoaded: liveDiagnostics.sleepPreventionServiceLoaded,
            watchdogServiceLoaded: liveDiagnostics.watchdogServiceLoaded,
            runtimeState: document.map { RuntimeState(rawValue: $0.status.rawValue) },
            operation: document?.operation,
            statusMessage: document?.message,
            statusDocumentError: statusRead.error,
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
