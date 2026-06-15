import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeStatusReading: Sendable {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
}

struct SystemRuntimeStatusReader: RuntimeStatusReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let fileStore: RuntimeFileStore
    private let storageUsageProvider: RuntimeStorageUsageProviding
    private let runtimeExecutableState: (String) -> RuntimeFileState
    private let runCommand: @Sendable (String, [String]) async -> RuntimeCommandResult
    private let runSyncCommand: @Sendable (String, [String]) -> RuntimeCommandResult

    init(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        storageUsageProvider: RuntimeStorageUsageProviding? = nil,
        runtimeExecutableState: ((String) -> RuntimeFileState)? = nil,
        runCommand: @escaping @Sendable (String, [String]) async -> RuntimeCommandResult = { command, arguments in
            await ProcessRunner.run(command, arguments: arguments)
        },
        runSyncCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult = ProcessRunner.runSync
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.storageUsageProvider = storageUsageProvider ?? SystemRuntimeStorageUsageProvider(fileStore: fileStore)
        self.runtimeExecutableState = runtimeExecutableState ?? { path in
            fileStore.fileState(atPath: path)
        }
        self.runCommand = runCommand
        self.runSyncCommand = runSyncCommand
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        withDataDirectoryMetrics(loadBaseStatus(), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        let status = loadBaseStatus()
        let reads = RuntimeHealthProbeReads(
            guestHTTP: await guestHTTPRead(vmIP: status.vmIP),
            hostProxyHTTP: await hostProxyHTTPRead(proxyPort: status.proxyPort),
            redisUIHTTP: await redisUIHTTPRead(proxyPort: status.proxyPort),
            swaggerUIHTTP: await swaggerUIHTTPRead(proxyPort: status.proxyPort)
        )
        return withDataDirectoryMetrics(
            RuntimeHealthStatusAssembler.applyingHealthProbeReads(to: status, reads: reads),
            settings: settings
        )
    }

    private func guestHTTPRead(vmIP: String?) async -> RuntimeHTTPStatusRead? {
        guard let vmIP else {
            return nil
        }
        return await httpStatus(
            source: "guestHTTP",
            url: RuntimeControlClientConstants.Product.guestHealthURL(vmIP: vmIP)
        )
    }

    private func hostProxyHTTPRead(proxyPort: Int?) async -> RuntimeHTTPStatusRead? {
        guard let proxyPort else {
            return nil
        }
        return await httpStatus(
            source: "hostProxyHTTP",
            url: RuntimeControlClientConstants.Product.hostProxyHealthURL(proxyPort: proxyPort)
        )
    }

    private func redisUIHTTPRead(proxyPort: Int?) async -> RuntimeHTTPStatusRead? {
        guard let proxyPort else {
            return nil
        }
        return await httpStatus(
            source: "redisUIHTTP",
            url: RuntimeControlClientConstants.Product.redisUIURL(proxyPort: proxyPort)
        )
    }

    private func swaggerUIHTTPRead(proxyPort: Int?) async -> RuntimeHTTPStatusRead? {
        guard let proxyPort else {
            return nil
        }
        return await httpStatus(
            source: "swaggerUIHTTP",
            url: RuntimeControlClientConstants.Product.swaggerURL(proxyPort: proxyPort)
        )
    }

    func loadBaseStatus() -> RuntimeStatus {
        let statusRead = RuntimeStatusDocumentReader(
            url: URL(fileURLWithPath: paths.runtimeStatus),
            fileStore: fileStore
        ).load()
        let guestStateRead = GuestRuntimeStateDocumentReader(
            path: paths.runtimeState,
            fileStore: fileStore
        ).load()
        let installStateRead = RuntimeInstallStateDocumentReader(
            path: paths.runtimeInstallState,
            fileStore: fileStore
        ).load()
        let liveDiagnostics = RuntimeLiveDiagnosticsReader(
            paths: paths,
            runtimeExecutableState: runtimeExecutableState,
            launchdServiceState: launchdServiceState
        ).load(statusDocument: statusRead.document)

        return RuntimeControlStatusAssembler.makeStatus(
            statusRead: statusRead,
            guestStateRead: guestStateRead,
            installStateRead: installStateRead,
            liveDiagnostics: liveDiagnostics
        )
    }

    private func httpStatus(source: String, url: String) async -> RuntimeHTTPStatusRead {
        let result = await runCommand(
            RuntimeControlClientConstants.Commands.curl,
            ["-sS", "-L", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5", url]
        )
        let code = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            return RuntimeHTTPStatusRead(
                status: nil,
                issue: RuntimeStatusReadIssue(
                    source: source,
                    message: RuntimeProcessFailureMessageFormatter.message(
                        exitCode: result.exitCode,
                        stdout: result.stdout,
                        stderr: result.stderr,
                        outputIssues: result.outputIssues,
                        executionIssue: result.executionIssue
                    )
                )
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
        RuntimeDataDirectoryMetricsAssembler.applyingMetricReads(
            to: status,
            reads: dataDirectoryMetricReads(settings: settings)
        )
    }

    private func dataDirectoryMetricReads(settings: RuntimeSettings) -> RuntimeDataDirectoryMetricReads {
        let storageUsage: RuntimeDataStorageUsageRead
        switch storageUsageProvider.storageUsage(for: settings.vitalFilesDirectory) {
        case .loaded(let usage):
            storageUsage = .loaded(usage)
        case .unavailable:
            storageUsage = .unavailable
        case .failed(let message):
            storageUsage = .failed(message)
        }
        return RuntimeDataDirectoryMetricReads(
            storageUsage: storageUsage,
            directoryStats: RuntimeDataDirectoryStatsReader(fileStore: fileStore)
                .read(path: settings.vitalFilesDirectory)
        )
    }

    private func launchdServiceState(_ service: RuntimeManagedService) -> RuntimeServiceState {
        let result = runSyncCommand(
            RuntimeControlClientConstants.Commands.launchctl,
            ["print", "system/\(service.label)"]
        )
        return RuntimeLaunchdServiceStateMapper.state(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            outputIssues: result.outputIssues
        )
    }

}
