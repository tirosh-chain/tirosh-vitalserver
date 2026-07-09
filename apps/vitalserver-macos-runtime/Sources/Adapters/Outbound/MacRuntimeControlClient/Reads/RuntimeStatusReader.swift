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
        liveDiagnosticsReader: (any RuntimeLiveDiagnosticsReading)? = nil,
        proxyPortReader: (any RuntimeProxyPortReading)? = nil,
        runtimeVersionReader: (any RuntimeVersionReading)? = nil,
        latestBackupReader: (any RuntimeLatestBackupReading)? = nil,
        vmLifecycleReader: (any RuntimeVMLifecycleReading)? = nil,
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
                issue: RuntimeStatusReadIssue(
                    source: "guestHTTP",
                    message: "guest control readiness failed: \(message)"
                )
            )
        } catch {
            return RuntimeHTTPStatusRead(
                status: nil,
                issue: RuntimeStatusReadIssue(
                    source: "guestHTTP",
                    message: runtimeStatusGuestServicesReadErrorDescription(error)
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
        let liveDiagnostics = liveDiagnosticsReader.loadLiveDiagnostics()
        let guestAddressRead = guestAddressProvider.readGuestAddress()
        let vmLifecycleRead = vmLifecycleReader.loadVMLifecycleRead()

        return RuntimeControlStatusAssembler.makeStatus(
            redisRelayStatusRead: redisRelayStatusRead(vmIP: guestAddressRead.loadedAddress),
            proxyPortReadState: proxyPortReader.loadProxyPortReadState(),
            runtimeVersionRead: runtimeVersionReader.loadRuntimeVersionRead(),
            latestBackupRead: latestBackupReader.loadLatestBackupRead(),
            guestServicesRead: guestServicesRead(
                vmIP: guestAddressRead.loadedAddress
            ),
            guestAddressRead: guestAddressRead,
            vmLifecycleRead: vmLifecycleRead,
            liveDiagnostics: liveDiagnostics
        )
    }

    private func guestServicesRead(vmIP: String?) -> RuntimeGuestServicesRead {
        guard let vmIP, !vmIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable
        }
        let baseURL = RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
        do {
            let gateway = try guestControlGateway(baseURL)
            let stackStatus = try gateway.stackStatus()
            let statuses = stackStatus.services
            let services = statuses.map(\.service)
            let resourceRead = guestServiceResourcesRead(
                services: services,
                gateway: gateway
            )
            return .loaded(
                services: services,
                statuses: statuses,
                resources: resourceRead.guestServiceResources,
                resourceReadIssues: resourceRead.guestServiceResourceReadIssues,
                probeErrors: stackStatus.probeErrors,
                cpuUsagePercent: stackStatus.cpuUsagePercent,
                memory: stackStatus.memory,
                systemDisk: stackStatus.systemDisk
            )
        } catch {
            return .failed(runtimeStatusGuestServicesReadErrorDescription(error))
        }
    }

    private func redisRelayStatusRead(vmIP: String?) -> RuntimeRedisRelayStatusRead {
        guard let vmIP, !vmIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RuntimeRedisRelayStatusRead(document: nil, error: nil, issue: nil)
        }
        let baseURL = RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
        do {
            let read = try guestControlGateway(baseURL).redisRelayStatus()
            switch read.readState {
            case .loaded:
                return RuntimeRedisRelayStatusRead(document: read.document, error: nil, issue: nil)
            case .notRead:
                return RuntimeRedisRelayStatusRead(document: nil, error: nil, issue: nil)
            case .invalidResponse, .readFailed:
                let message = read.readError ?? "redis relay status read failed state=\(read.readState.rawValue)"
                return RuntimeRedisRelayStatusRead(
                    document: nil,
                    error: message,
                    issue: RuntimeStatusReadIssue(source: "redisRelayStatus", message: message)
                )
            }
        } catch {
            let message = runtimeStatusGuestServicesReadErrorDescription(error)
            return RuntimeRedisRelayStatusRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "redisRelayStatus", message: message)
            )
        }
    }

    private func guestServiceResourcesRead(
        services: [String],
        gateway: RuntimeGuestControlGateway
    ) -> RuntimeGuestServiceResourcesRead {
        var guestServiceResources: [RuntimeGuestServiceResource] = []
        var guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = []
        for service in services {
            do {
                guestServiceResources.append(try gateway.serviceResource(service))
            } catch {
                guestServiceResourceReadIssues.append(RuntimeGuestServiceResourceReadIssue(
                    service: service,
                    message: runtimeStatusGuestServicesReadErrorDescription(error)
                ))
            }
        }
        return RuntimeGuestServiceResourcesRead(
            guestServiceResources: guestServiceResources,
            guestServiceResourceReadIssues: guestServiceResourceReadIssues
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

}

private struct RuntimeGuestServiceResourcesRead {
    let guestServiceResources: [RuntimeGuestServiceResource]
    let guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue]
}

private func runtimeStatusGuestServicesReadErrorDescription(_ error: Error) -> String {
    return String(describing: error)
}
