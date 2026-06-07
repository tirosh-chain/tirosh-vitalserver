import Foundation
import Application
import Contracts
import Errors

public struct RuntimeHealthCheckerContext {
    public let installedPaths: InstalledRuntimePaths
    public let vmExecutablePath: String
    public let proxyExecutablePath: String
    public let rootfsBaseURL: URL
    public let vmDiskURL: URL
    public let plistBuddyPath: String
    public let lsofPath: String
    public let curlPath: String
    public let proxyLaunchDaemonPlist: String
    public let runtimeStateStaleAfterSeconds: TimeInterval
    public let watchdogManagedOperationGraceSeconds: TimeInterval
    public let proxyHealthURL: (Int) -> String
    public let redisUIHealthURL: (Int) -> String
    public let swaggerUIHealthURL: (Int) -> String
    public let auditProxyStatusURL: (Int) -> String

    public init(
        installedPaths: InstalledRuntimePaths,
        vmExecutablePath: String,
        proxyExecutablePath: String,
        rootfsBaseURL: URL,
        vmDiskURL: URL,
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String,
        proxyLaunchDaemonPlist: String,
        runtimeStateStaleAfterSeconds: TimeInterval,
        watchdogManagedOperationGraceSeconds: TimeInterval,
        proxyHealthURL: @escaping (Int) -> String,
        redisUIHealthURL: @escaping (Int) -> String,
        swaggerUIHealthURL: @escaping (Int) -> String,
        auditProxyStatusURL: @escaping (Int) -> String
    ) {
        self.installedPaths = installedPaths
        self.vmExecutablePath = vmExecutablePath
        self.proxyExecutablePath = proxyExecutablePath
        self.rootfsBaseURL = rootfsBaseURL
        self.vmDiskURL = vmDiskURL
        self.plistBuddyPath = plistBuddyPath
        self.lsofPath = lsofPath
        self.curlPath = curlPath
        self.proxyLaunchDaemonPlist = proxyLaunchDaemonPlist
        self.runtimeStateStaleAfterSeconds = runtimeStateStaleAfterSeconds
        self.watchdogManagedOperationGraceSeconds = watchdogManagedOperationGraceSeconds
        self.proxyHealthURL = proxyHealthURL
        self.redisUIHealthURL = redisUIHealthURL
        self.swaggerUIHealthURL = swaggerUIHealthURL
        self.auditProxyStatusURL = auditProxyStatusURL
    }
}

public struct RuntimeHealthChecker {
    private let context: RuntimeHealthCheckerContext
    private let fileStore: RuntimeFileStore
    private let serviceManager: RuntimeServiceManager
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let guestGateway: RuntimeGuestGateway
    private let now: @Sendable () -> Date

    public init(
        context: RuntimeHealthCheckerContext,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestGateway: RuntimeGuestGateway,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.context = context
        self.fileStore = fileStore
        self.serviceManager = serviceManager
        self.commandRunner = commandRunner
        self.httpProber = httpProber
        self.guestGateway = guestGateway
        self.now = now
    }

    public func observationReads() -> RuntimeHealthObservationReads {
        let observedAt = now()
        let guestRuntimeState = guestRuntimeStateObservationReader().read()
        let proxyPortRead = installedProxyPortRead()
        let proxyPort = proxyPortRead.port
        let hostProxyHTTP = proxyPort.map { httpProber.statusRead(url: context.proxyHealthURL($0)) }
        let redisUIHTTP = proxyPort.map { httpProber.statusRead(url: context.redisUIHealthURL($0)) }
        let swaggerUIHTTP = proxyPort.map { httpProber.statusRead(url: context.swaggerUIHealthURL($0)) }

        return RuntimeHealthObservationReads(
            vmExecutable: fileState(path: context.vmExecutablePath),
            proxyExecutable: fileState(path: context.proxyExecutablePath),
            rootfsBase: fileState(url: context.rootfsBaseURL),
            vmDisk: fileState(url: context.vmDiskURL),
            vmService: launchdState(.vm),
            proxyService: launchdState(.proxy),
            watchdogService: launchdState(.watchdog),
            vmLifecycleLoadResult: vmLifecycleLoadResult(),
            guestRuntimeState: guestRuntimeState,
            proxyPortReadState: proxyPortRead.state,
            hostProxyHTTP: hostProxyHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            auditProxyStatus: proxyPort.map(auditProxyStatus(port:)),
            runtimeStateFileModifiedAt: runtimeStateFileModifiedAt(guestRuntimeState),
            containerLogsMetadata: containerLogsMetadata(),
            proxyListenerObservation: proxyPort.map(proxyListenerObservation(port:)),
            guestBootstrapResult: guestGateway.loadBootstrapResultDocument(),
            observedAt: observedAt,
            guestBootstrapFreshnessGraceSeconds: context.watchdogManagedOperationGraceSeconds
        )
    }

    public func isLaunchdLoaded(_ service: RuntimeManagedService) -> Bool {
        launchdState(service).isLoaded
    }

    public func fileState(path: String) -> RuntimeFileState {
        fileStore.fileState(atPath: path)
    }

    public func fileState(url: URL) -> RuntimeFileState {
        fileStore.fileState(at: url)
    }

    public func launchdState(_ service: RuntimeManagedService) -> RuntimeServiceState {
        serviceManager.state(service: service)
    }

    public func installedProxyPort() -> Int? {
        installedProxyPortRead().port
    }

    private func installedProxyPortRead() -> RuntimeProxyPortReadResult {
        RuntimeProxyPortReadResult(
            state: RuntimeInstalledProxyPortReader(
                plistBuddyPath: context.plistBuddyPath,
                proxyLaunchDaemonPlist: context.proxyLaunchDaemonPlist,
                fileStore: fileStore,
                commandRunner: commandRunner
            ).read()
        )
    }

    private func guestRuntimeStateObservationReader() -> RuntimeGuestRuntimeStateObservationReader {
        RuntimeGuestRuntimeStateObservationReader(
            guestGateway: guestGateway,
            fileStore: fileStore,
            runtimeStateURL: context.installedPaths.runtimeState,
            staleAfterSeconds: context.runtimeStateStaleAfterSeconds,
            now: now
        )
    }

    private func vmLifecycleLoadResult() -> RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument> {
        RuntimeVMLifecycleStore(
            url: context.installedPaths.vmLifecycle,
            fileStore: fileStore,
            now: now
        ).load()
    }

    private func proxyListenerObservation(port: Int) -> RuntimeHostProxyListenerObservation {
        RuntimeHostProxyListenerObservation(
            port: port,
            scanResult: RuntimeHostProxyListenerScanReader(
                lsofPath: context.lsofPath,
                fileStore: fileStore,
                commandRunner: commandRunner
            ).read(port: port),
            expectedNginxPID: readInstalledProxyNginxPID()
        )
    }

    public func readInstalledProxyNginxPID() -> RuntimeProxyNginxPIDReadResult {
        RuntimeProxyNginxPIDReader(
            url: context.installedPaths.proxyNginxPID,
            fileStore: fileStore
        ).read()
    }

    private func containerLogsMetadata() -> RuntimeContainerLogsMetadata {
        RuntimeContainerLogsMetadataReader(
            url: context.installedPaths.containerLogs,
            fileStore: fileStore
        ).read()
    }

    private func runtimeStateFileModifiedAt(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeFileModifiedAtReadResult {
        guard observation.isPresent else {
            return .notRead()
        }
        return RuntimeFileModifiedAtReader(
            url: context.installedPaths.runtimeState,
            fileStore: fileStore
        ).read()
    }

    private func auditProxyStatus(port: Int) -> RuntimeAuditProxyStatusReadResult {
        RuntimeAuditProxyStatusReader(
            curlPath: context.curlPath,
            commandRunner: commandRunner,
            statusURL: context.auditProxyStatusURL
        ).read(port: port)
    }
}

private struct RuntimeProxyPortReadResult {
    let state: RuntimeProxyPortReadState

    var port: Int? {
        state.port
    }
}
