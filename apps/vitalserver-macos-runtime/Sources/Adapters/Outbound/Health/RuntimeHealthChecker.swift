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
    public let watchdogManagedOperationGraceSeconds: TimeInterval
    public let proxyHealthURL: (Int) -> String
    public let redisUIHealthURL: (Int) -> String
    public let swaggerUIHealthURL: (Int) -> String

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
        watchdogManagedOperationGraceSeconds: TimeInterval,
        proxyHealthURL: @escaping (Int) -> String,
        redisUIHealthURL: @escaping (Int) -> String,
        swaggerUIHealthURL: @escaping (Int) -> String
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
        self.watchdogManagedOperationGraceSeconds = watchdogManagedOperationGraceSeconds
        self.proxyHealthURL = proxyHealthURL
        self.redisUIHealthURL = redisUIHealthURL
        self.swaggerUIHealthURL = swaggerUIHealthURL
    }
}

public struct RuntimeHealthChecker {
    private let context: RuntimeHealthCheckerContext
    private let fileStore: RuntimeFileStore
    private let serviceManager: RuntimeServiceManager
    private let commandRunner: RuntimeCommandRunner
    private let httpProber: RuntimeHTTPProber
    private let guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader
    private let guestControlGateway: (@Sendable (String) throws -> any RuntimeGuestControlGateway)?
    private let now: @Sendable () -> Date

    public init(
        context: RuntimeHealthCheckerContext,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader,
        guestControlGateway: (@Sendable () throws -> any RuntimeGuestControlGateway)? = nil,
        guestControlGatewayForBaseURL: (@Sendable (String) throws -> any RuntimeGuestControlGateway)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.context = context
        self.fileStore = fileStore
        self.serviceManager = serviceManager
        self.commandRunner = commandRunner
        self.httpProber = httpProber
        self.guestBootstrapResultReader = guestBootstrapResultReader
        if let guestControlGatewayForBaseURL {
            self.guestControlGateway = guestControlGatewayForBaseURL
        } else if let guestControlGateway {
            self.guestControlGateway = { _ in
                return try guestControlGateway()
            }
        } else {
            self.guestControlGateway = nil
        }
        self.now = now
    }

    public func observationReads() -> RuntimeHealthObservationReads {
        let observedAt = now()
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
            guestControlReadiness: guestControlReadiness(),
            proxyPortReadState: proxyPortRead.state,
            hostProxyHTTP: hostProxyHTTP,
            redisUIHTTP: redisUIHTTP,
            swaggerUIHTTP: swaggerUIHTTP,
            recorderIngressStatus: recorderIngressStatus(),
            vitalDBObservation: vitalDBObservation(),
            containerLogsMetadata: containerLogsMetadata(),
            proxyListenerObservation: proxyPort.map(proxyListenerObservation(port:)),
            guestBootstrapResult: guestBootstrapResultReader.loadBootstrapResultDocument(),
            guestServiceStatuses: guestServiceStatuses(),
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

    private func guestServiceStatuses() -> RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> {
        guard let guestControlGateway else {
            return .notReported
        }
        guard let baseURL = guestControlBaseURL() else {
            return .readFailed(RuntimeHTTPStatusText.missingVMIP)
        }
        do {
            let gateway = try guestControlGateway(baseURL)
            return .loaded(try gateway.stackStatus().services)
        } catch {
            return .readFailed(String(describing: error))
        }
    }

    private func vitalDBObservation() -> RuntimeObservationInput<VitalDBObservationDocument> {
        guard let guestControlGateway else {
            return .notReported
        }
        guard let baseURL = guestControlBaseURL() else {
            return .readFailed(RuntimeHTTPStatusText.missingVMIP)
        }
        do {
            let read = try guestControlGateway(baseURL).latestVitalDBObservation()
            switch read.state {
            case .loaded:
                guard let observation = read.observation else {
                    return .readFailed("guestControl=loadedObservationMissing")
                }
                return .loaded(observation)
            case .unavailable:
                return .missing
            case .failed:
                return .readFailed(read.readError ?? "guestControl=failed")
            }
        } catch {
            return .readFailed("guestControl=\(error)")
        }
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

    private func guestControlReadiness() -> RuntimeGuestControlReadinessRead {
        guard let guestControlGateway else {
            return .notReported
        }
        let vmIP = readVMIP()
        guard let baseURL = guestControlBaseURL(vmIP: vmIP) else {
            return .failed(vmIP: nil, message: RuntimeHTTPStatusText.missingVMIP)
        }
        do {
            return .loaded(vmIP: vmIP, readiness: try guestControlGateway(baseURL).ready())
        } catch {
            return .failed(vmIP: vmIP, message: String(describing: error))
        }
    }

    private func guestControlBaseURL() -> String? {
        guestControlBaseURL(vmIP: readVMIP())
    }

    private func guestControlBaseURL(vmIP: String?) -> String? {
        guard let vmIP else {
            return nil
        }
        return RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)
    }

    private func readVMIP() -> String? {
        readVMIPFromRuntimeState() ?? readVMIPFile()
    }

    private func readVMIPFromRuntimeState() -> String? {
        let url = context.installedPaths.runtimeState
        guard fileStore.pathState(at: url) == .file else {
            return nil
        }
        do {
            let document = try JSONDecoder().decode(
                GuestRuntimeStateDocument.self,
                from: try fileStore.readData(url)
            )
            return nonEmpty(document.vmIP)
        } catch {
            return nil
        }
    }

    private func readVMIPFile() -> String? {
        let url = context.installedPaths.vmIPFile
        guard fileStore.pathState(at: url) == .file else {
            return nil
        }
        do {
            return nonEmpty(String(decoding: try fileStore.readData(url), as: UTF8.self))
        } catch {
            return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
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

    private func recorderIngressStatus() -> RuntimeRecorderIngressStatusReadResult {
        guard let guestControlGateway else {
            return RuntimeRecorderIngressStatusReadResult(
                readState: .readFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "guestControl=unavailable"
            )
        }
        guard let baseURL = guestControlBaseURL() else {
            return RuntimeRecorderIngressStatusReadResult(
                readState: .readFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "guestControl=\(RuntimeHTTPStatusText.missingVMIP)"
            )
        }
        do {
            return try guestControlGateway(baseURL).recorderIngressStatus()
        } catch {
            return RuntimeRecorderIngressStatusReadResult(
                readState: .readFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "guestControl=\(error)"
            )
        }
    }
}

private struct RuntimeProxyPortReadResult {
    let state: RuntimeProxyPortReadState

    var port: Int? {
        state.port
    }
}
