import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

public protocol PlatformStateReading: Sendable {
    func loadPlatformState(settings: RuntimeSettings) -> PlatformState
    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState
}

struct SystemPlatformStateReader: PlatformStateReading, @unchecked Sendable {
    private let fileStore: RuntimeFileStore
    private let storageUsageProvider: RuntimeStorageUsageProviding
    private let guestAddressProvider: any RuntimeGuestAddressProvider
    private let liveDiagnosticsReader: any RuntimeLiveDiagnosticsReading
    private let proxyPortReader: any RuntimeProxyPortReading
    private let runtimeVersionReader: any RuntimeVersionReading
    private let latestBackupReader: any RuntimeLatestBackupReading
    private let vmLifecycleReader: any RuntimeVMLifecycleReading
    private let guestControlGateway: @Sendable (String) throws -> any RuntimeGuestControlGateway
    private let runCommand: @Sendable (String, [String]) async -> RuntimeCommandResult
    private let timeAuthorityReader: any RuntimeTimeAuthorityReading

    init(
        runtimeLauncherPath: String = RuntimeControlClientConstants.Paths.launcher,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        storageUsageProvider: RuntimeStorageUsageProviding? = nil,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
        runtimeExecutableState: ((String) -> RuntimeFileState)? = nil,
        runtimeVersionFile: URL = InstalledRuntimePaths.defaultInstalled.runtimeDirectory
            .appendingPathComponent(RuntimePackageArtifactFileNames.runtimeVersion),
        backupsDirectory: URL = InstalledRuntimePaths.defaultInstalled.backupsDirectory,
        vmLifecycleResourceReader: (any RuntimeVMLifecycleResourceReading)? = nil,
        installedProductReleaseReader: (any InstalledProductReleaseReading)? = nil,
        liveDiagnosticsReader: (any RuntimeLiveDiagnosticsReading)? = nil,
        proxyPortReader: (any RuntimeProxyPortReading)? = nil,
        runtimeVersionReader: (any RuntimeVersionReading)? = nil,
        latestBackupReader: (any RuntimeLatestBackupReading)? = nil,
        vmLifecycleReader: (any RuntimeVMLifecycleReading)? = nil,
        timeAuthorityReader: (any RuntimeTimeAuthorityReading)? = nil,
        guestControlGateway: (@Sendable () throws -> any RuntimeGuestControlGateway)? = nil,
        guestControlGatewayForBaseURL: (@Sendable (String) throws -> any RuntimeGuestControlGateway)? = nil,
        runCommand: @escaping @Sendable (String, [String]) async -> RuntimeCommandResult = { command, arguments in
            await ProcessRunner.run(command, arguments: arguments)
        },
        runSyncCommand: @escaping @Sendable (String, [String]) -> RuntimeCommandResult = ProcessRunner.runSync
    ) {
        let resolvedRuntimeExecutableState = runtimeExecutableState ?? { path in
            fileStore.fileState(atPath: path)
        }
        let ownerReaders = RuntimeHostStatusOwnerReaderBundle.live(
            runtimeLauncherPath: runtimeLauncherPath,
            fileStore: fileStore,
            guestAddressProvider: guestAddressProvider,
            installedProductReleaseReader: installedProductReleaseReader,
            runtimeVersionFile: runtimeVersionFile,
            backupsDirectory: backupsDirectory,
            vmLifecycleResourceReader: vmLifecycleResourceReader,
            runtimeExecutableState: resolvedRuntimeExecutableState,
            runSyncCommand: runSyncCommand
        )
        self.fileStore = fileStore
        self.storageUsageProvider = storageUsageProvider ?? SystemRuntimeStorageUsageProvider(fileStore: fileStore)
        self.guestAddressProvider = guestAddressProvider ?? ownerReaders.guestAddressProvider
        self.liveDiagnosticsReader = liveDiagnosticsReader ?? ownerReaders.liveDiagnosticsReader
        self.proxyPortReader = proxyPortReader ?? ownerReaders.proxyPortReader
        self.runtimeVersionReader = runtimeVersionReader ?? ownerReaders.runtimeVersionReader
        self.latestBackupReader = latestBackupReader ?? ownerReaders.latestBackupReader
        self.vmLifecycleReader = vmLifecycleReader ?? ownerReaders.vmLifecycleReader
        self.guestControlGateway = guestControlGatewayForBaseURL ?? { baseURL in
            if let guestControlGateway {
                return try guestControlGateway()
            }
            return try HTTPRuntimeGuestControlGateway(
                baseURL: baseURL,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIStackStatusTimeoutSeconds
            )
        }
        self.runCommand = runCommand
        self.timeAuthorityReader = timeAuthorityReader ?? SystemRuntimeTimeAuthorityReader()
    }

    func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        withDataDirectoryMetrics(loadBaseStatus(), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        let status = loadBaseStatus()
        let reads = RuntimeHealthProbeReads(
            guestHTTP: await guestHTTPRead(vmIP: status.runtimeEndpoint),
            hostProxyHTTP: await hostProxyHTTPRead(proxyPort: status.publicProxyPort),
            redisUIHTTP: nil,
            swaggerUIHTTP: nil
        )
        return withDataDirectoryMetrics(
            RuntimeHealthStatusAssembler.applyingHealthProbeReads(to: status, reads: reads),
            settings: settings
        )
    }

    private func guestHTTPRead(vmIP: String?) async -> RuntimeHTTPStatusRead? {
        guard let vmIP, !vmIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let baseURL = RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
        do {
            let readiness = try guestControlGateway(baseURL).ready()
            if readiness.status == "ready" {
                return RuntimeHTTPStatusRead(status: "200", issue: nil)
            }
            let message = readiness.failureSummary.map {
                "\(readiness.status):\($0)"
            } ?? readiness.status
            return RuntimeHTTPStatusRead(
                status: readiness.status,
                issue: PlatformStateReadIssue(
                    source: "guestHTTP",
                    message: "guest control readiness failed: \(message)"
                )
            )
        } catch {
            return RuntimeHTTPStatusRead(
                status: nil,
                issue: PlatformStateReadIssue(
                    source: "guestHTTP",
                    message: String(describing: error)
                )
            )
        }
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

    func loadBaseStatus() -> PlatformState {
        let liveDiagnostics = liveDiagnosticsReader.loadLiveDiagnostics()
        let guestAddressRead = guestAddressProvider.readGuestAddress()
        let vmLifecycleRead = vmLifecycleReader.loadVMLifecycleRead()

        var status = PlatformStateAssembler.makePlatformState(
            proxyPortReadState: proxyPortReader.loadProxyPortReadState(),
            runtimeVersionRead: runtimeVersionReader.loadRuntimeVersionRead(),
            latestBackupRead: latestBackupReader.loadLatestBackupRead(),
            guestAddressRead: guestAddressRead,
            vmLifecycleRead: vmLifecycleRead,
            liveDiagnostics: liveDiagnostics
        )
        status.timeAuthority = timeAuthorityReader.loadTimeAuthority()
        return status
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
                issue: PlatformStateReadIssue(
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
                issue: PlatformStateReadIssue(source: source, message: "empty HTTP status")
            )
        }
        return RuntimeHTTPStatusRead(status: code, issue: nil)
    }

    private func withDataDirectoryMetrics(_ status: PlatformState, settings: RuntimeSettings) -> PlatformState {
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

}
