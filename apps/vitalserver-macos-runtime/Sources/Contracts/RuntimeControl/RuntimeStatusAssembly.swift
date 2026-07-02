import Contracts

public struct RuntimeStatusDocumentRead {
    public let document: RuntimeStatusDocument?
    public let error: String?
    public let issue: RuntimeStatusReadIssue?

    public init(
        document: RuntimeStatusDocument?,
        error: String?,
        issue: RuntimeStatusReadIssue?
    ) {
        self.document = document
        self.error = error
        self.issue = issue
    }
}

public struct RuntimeInstallStateRead {
    public let document: RuntimeInstallStateDocument?
    public let error: String?
    public let issue: RuntimeStatusReadIssue?

    public init(
        document: RuntimeInstallStateDocument?,
        error: String?,
        issue: RuntimeStatusReadIssue?
    ) {
        self.document = document
        self.error = error
        self.issue = issue
    }
}

public struct RuntimeRedisRelayStatusRead {
    public let document: RuntimeRedisRelayStatus?
    public let error: String?
    public let issue: RuntimeStatusReadIssue?

    public init(
        document: RuntimeRedisRelayStatus?,
        error: String?,
        issue: RuntimeStatusReadIssue?
    ) {
        self.document = document
        self.error = error
        self.issue = issue
    }
}

public enum RuntimeGuestServicesRead: Equatable, Sendable {
    case unavailable
    case loaded(services: [String], statuses: [RuntimeGuestControlServiceStatus])
    case failed(String)
}

public struct RuntimeHTTPStatusRead: Equatable, Sendable {
    public let status: String?
    public let issue: RuntimeStatusReadIssue?

    public init(status: String?, issue: RuntimeStatusReadIssue?) {
        self.status = status
        self.issue = issue
    }
}

public struct RuntimeHealthProbeReads: Equatable, Sendable {
    public let guestHTTP: RuntimeHTTPStatusRead?
    public let hostProxyHTTP: RuntimeHTTPStatusRead?
    public let redisUIHTTP: RuntimeHTTPStatusRead?
    public let swaggerUIHTTP: RuntimeHTTPStatusRead?

    public init(
        guestHTTP: RuntimeHTTPStatusRead?,
        hostProxyHTTP: RuntimeHTTPStatusRead?,
        redisUIHTTP: RuntimeHTTPStatusRead?,
        swaggerUIHTTP: RuntimeHTTPStatusRead?
    ) {
        self.guestHTTP = guestHTTP
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
    }
}

public struct RuntimeControlLocalAPIStatusRead: Equatable, Sendable {
    public let http: String?
    public let startedAt: String?

    public init(http: String?, startedAt: String?) {
        self.http = http
        self.startedAt = startedAt
    }

    public static func reachable(startedAt: String) -> RuntimeControlLocalAPIStatusRead {
        RuntimeControlLocalAPIStatusRead(http: "200", startedAt: startedAt)
    }

    public static func failed() -> RuntimeControlLocalAPIStatusRead {
        RuntimeControlLocalAPIStatusRead(http: RuntimeHTTPStatusText.failed, startedAt: nil)
    }
}

public enum RuntimeDataStorageUsageRead: Equatable, Sendable {
    case loaded(ResourceUsage)
    case unavailable
    case failed(String)
}

public enum RuntimeDataDirectoryStatsRead: Equatable, Sendable {
    case loaded(RuntimeDataDirectoryStats)
    case missing(path: String)
    case unavailable
    case failed(String)
}

public struct RuntimeDataDirectoryMetricReads: Equatable, Sendable {
    public let storageUsage: RuntimeDataStorageUsageRead
    public let directoryStats: RuntimeDataDirectoryStatsRead

    public init(
        storageUsage: RuntimeDataStorageUsageRead,
        directoryStats: RuntimeDataDirectoryStatsRead
    ) {
        self.storageUsage = storageUsage
        self.directoryStats = directoryStats
    }
}

public struct RuntimeLiveDiagnostics: Equatable, Sendable {
    public let runtimeInstalled: Bool
    public let runtimeInstallationState: RuntimeFileState
    public let runtimeInstallationIssue: RuntimeStatusReadIssue?
    public let vmService: RuntimeServiceStateRead
    public let proxyService: RuntimeServiceStateRead
    public let guestLogSyncService: RuntimeServiceStateRead
    public let sleepPreventionService: RuntimeServiceStateRead
    public let watchdogService: RuntimeServiceStateRead
    public let readIssues: [RuntimeStatusReadIssue]

    public init(
        runtimeInstalled: Bool,
        runtimeInstallationState: RuntimeFileState,
        runtimeInstallationIssue: RuntimeStatusReadIssue?,
        vmService: RuntimeServiceStateRead,
        proxyService: RuntimeServiceStateRead,
        guestLogSyncService: RuntimeServiceStateRead,
        sleepPreventionService: RuntimeServiceStateRead,
        watchdogService: RuntimeServiceStateRead,
        readIssues: [RuntimeStatusReadIssue]
    ) {
        self.runtimeInstalled = runtimeInstalled
        self.runtimeInstallationState = runtimeInstallationState
        self.runtimeInstallationIssue = runtimeInstallationIssue
        self.vmService = vmService
        self.proxyService = proxyService
        self.guestLogSyncService = guestLogSyncService
        self.sleepPreventionService = sleepPreventionService
        self.watchdogService = watchdogService
        self.readIssues = readIssues
    }
}

public struct RuntimeServiceStateRead: Equatable, Sendable {
    public let state: RuntimeServiceState
    public let source: RuntimeServiceStateSource

    public init(state: RuntimeServiceState, source: RuntimeServiceStateSource) {
        self.state = state
        self.source = source
    }
}

public struct RuntimeLiveServiceStateReads: Equatable, Sendable {
    public let vm: RuntimeServiceState
    public let proxy: RuntimeServiceState
    public let guestLogSync: RuntimeServiceState
    public let sleepPrevention: RuntimeServiceState
    public let watchdog: RuntimeServiceState

    public init(
        vm: RuntimeServiceState,
        proxy: RuntimeServiceState,
        guestLogSync: RuntimeServiceState,
        sleepPrevention: RuntimeServiceState,
        watchdog: RuntimeServiceState
    ) {
        self.vm = vm
        self.proxy = proxy
        self.guestLogSync = guestLogSync
        self.sleepPrevention = sleepPrevention
        self.watchdog = watchdog
    }
}

public enum RuntimeLiveDiagnosticsAssembler {
    public static func makeDiagnostics(
        runtimeLauncherPath: String,
        runtimeExecutableState: RuntimeFileState,
        statusDocument document: RuntimeStatusDocument?,
        liveServiceStates: RuntimeLiveServiceStateReads
    ) -> RuntimeLiveDiagnostics {
        let vmService = serviceState(document?.vmService, liveState: liveServiceStates.vm)
        let proxyService = serviceState(document?.proxyService, liveState: liveServiceStates.proxy)
        let guestLogSyncService = liveServiceState(liveServiceStates.guestLogSync)
        let sleepPreventionService = liveServiceState(liveServiceStates.sleepPrevention)
        let watchdogService = serviceState(document?.watchdogService, liveState: liveServiceStates.watchdog)

        return RuntimeLiveDiagnostics(
            runtimeInstalled: runtimeExecutableState == .executable,
            runtimeInstallationState: runtimeExecutableState,
            runtimeInstallationIssue: runtimeInstallationIssue(
                state: runtimeExecutableState,
                path: runtimeLauncherPath
            ),
            vmService: vmService,
            proxyService: proxyService,
            guestLogSyncService: guestLogSyncService,
            sleepPreventionService: sleepPreventionService,
            watchdogService: watchdogService,
            readIssues: serviceReadIssues([
                ("vmService", vmService),
                ("proxyService", proxyService),
                ("guestLogSyncService", guestLogSyncService),
                ("sleepPreventionService", sleepPreventionService),
                ("watchdogService", watchdogService),
            ])
        )
    }

    private static func serviceState(
        _ statusDocumentState: RuntimeServiceState?,
        liveState: RuntimeServiceState
    ) -> RuntimeServiceStateRead {
        if let statusDocumentState {
            return RuntimeServiceStateRead(state: statusDocumentState, source: .statusDocument)
        }
        return liveServiceState(liveState)
    }

    private static func liveServiceState(_ state: RuntimeServiceState) -> RuntimeServiceStateRead {
        RuntimeServiceStateRead(state: state, source: .liveLaunchd)
    }

    private static func serviceReadIssues(_ states: [(String, RuntimeServiceStateRead)]) -> [RuntimeStatusReadIssue] {
        states.compactMap { source, read in
            switch read.state {
            case .readFailed(let message), .permissionDenied(let message):
                RuntimeStatusReadIssue(source: source, message: message)
            case .unknown(let value):
                RuntimeStatusReadIssue(source: source, message: "unknown service state: \(value)")
            case .loaded, .notLoaded:
                nil
            }
        }
    }

    private static func runtimeInstallationIssue(
        state: RuntimeFileState,
        path: String
    ) -> RuntimeStatusReadIssue? {
        switch state {
        case .executable, .missing:
            nil
        case .present:
            RuntimeStatusReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher is present but not executable path=\(path)"
            )
        case .inspectFailed(let reason):
            RuntimeStatusReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher inspection failed path=\(path) reason=\(reason)"
            )
        case .unknown(let value):
            RuntimeStatusReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher inspection returned unknown state path=\(path) state=\(value)"
            )
        }
    }
}

public enum RuntimeHealthStatusAssembler {
    public static func applyingHealthProbeReads(
        to status: RuntimeStatus,
        reads: RuntimeHealthProbeReads
    ) -> RuntimeStatus {
        var next = status
        if status.vmIP == nil {
            next.guestHTTP = RuntimeHTTPStatusText.missingVMIP
            appendUnique(RuntimeStatusReadIssue(
                source: "vmIP",
                message: "vm ip is missing from runtime status document"
            ), to: &next)
        } else {
            apply(reads.guestHTTP, to: \.guestHTTP, in: &next)
        }

        guard status.proxyPort != nil else {
            next.hostProxyHTTP = RuntimeHTTPStatusText.missingProxyPort
            next.redisUIHTTP = RuntimeHTTPStatusText.missingProxyPort
            next.swaggerUIHTTP = RuntimeHTTPStatusText.missingProxyPort
            appendUnique(RuntimeStatusReadIssue(
                source: "proxyPort",
                message: "proxy port is missing from runtime status document"
            ), to: &next)
            return next
        }

        apply(reads.hostProxyHTTP, to: \.hostProxyHTTP, in: &next)
        apply(reads.redisUIHTTP, to: \.redisUIHTTP, in: &next)
        apply(reads.swaggerUIHTTP, to: \.swaggerUIHTTP, in: &next)
        return next
    }

    private static func apply(
        _ read: RuntimeHTTPStatusRead?,
        to keyPath: WritableKeyPath<RuntimeStatus, String?>,
        in status: inout RuntimeStatus
    ) {
        guard let read else {
            return
        }
        status[keyPath: keyPath] = read.status
        append(read.issue, to: &status)
    }

    private static func append(
        _ issue: RuntimeStatusReadIssue?,
        to status: inout RuntimeStatus
    ) {
        guard let issue else {
            return
        }
        status.readIssues.append(issue)
    }

    private static func appendUnique(
        _ issue: RuntimeStatusReadIssue,
        to status: inout RuntimeStatus
    ) {
        guard !status.readIssues.contains(issue) else {
            return
        }
        status.readIssues.append(issue)
    }
}

public enum RuntimeControlLocalAPIStatusAssembler {
    public static func applyingLocalAPIStatus(
        to status: RuntimeStatus,
        read: RuntimeControlLocalAPIStatusRead
    ) -> RuntimeStatus {
        var next = status
        next.runtimeControlHTTP = read.http
        next.runtimeControlStartedAt = read.startedAt
        return next
    }
}

public enum RuntimeDataDirectoryMetricsAssembler {
    public static func applyingMetricReads(
        to status: RuntimeStatus,
        reads: RuntimeDataDirectoryMetricReads
    ) -> RuntimeStatus {
        var next = status
        switch reads.storageUsage {
        case .loaded(let usage):
            next.dataStorage = usage
            next.dataStorageError = nil
        case .unavailable:
            next.dataStorageError = nil
        case .failed(let message):
            next.dataStorage = nil
            next.dataStorageError = message
        }

        switch reads.directoryStats {
        case .loaded(let stats):
            next.dataDirectoryStats = stats
            next.dataDirectoryStatsError = nil
        case .missing(let path):
            next.dataDirectoryStats = nil
            next.dataDirectoryStatsError = "data directory missing path=\(path)"
        case .unavailable:
            next.dataDirectoryStats = nil
            next.dataDirectoryStatsError = nil
        case .failed(let message):
            next.dataDirectoryStats = nil
            next.dataDirectoryStatsError = message
        }
        return next
    }
}

public enum RuntimeControlStatusAssembler {
    public static func makeStatus(
        statusRead: RuntimeStatusDocumentRead,
        installStateRead: RuntimeInstallStateRead = RuntimeInstallStateRead(document: nil, error: nil, issue: nil),
        redisRelayStatusRead: RuntimeRedisRelayStatusRead = RuntimeRedisRelayStatusRead(
            document: nil,
            error: nil,
            issue: nil
        ),
        guestServicesRead: RuntimeGuestServicesRead = .unavailable,
        liveDiagnostics: RuntimeLiveDiagnostics
    ) -> RuntimeStatus {
        let document = statusRead.document
        let proxyPortIssue = document.flatMap { document -> RuntimeStatusReadIssue? in
            document.proxyPort == nil
                ? RuntimeStatusReadIssue(
                    source: "proxyPort",
                    message: "proxy port is missing from runtime status document"
                )
                : nil
        }
        let readIssues = liveDiagnostics.readIssues
            + [liveDiagnostics.runtimeInstallationIssue].compactMap { $0 }
            + [statusRead.issue, installStateRead.issue, redisRelayStatusRead.issue]
                .compactMap { $0 }
            + [proxyPortIssue].compactMap { $0 }
        let vmService = liveDiagnostics.vmService
        let proxyService = liveDiagnostics.proxyService
        let guestLogSyncService = liveDiagnostics.guestLogSyncService
        let sleepPreventionService = liveDiagnostics.sleepPreventionService
        let watchdogService = liveDiagnostics.watchdogService

        return RuntimeStatus(
            runtimeInstalled: liveDiagnostics.runtimeInstalled,
            runtimeInstallationState: liveDiagnostics.runtimeInstallationState,
            vmServiceLoaded: vmService.state.isLoaded,
            proxyServiceLoaded: proxyService.state.isLoaded,
            guestLogSyncServiceLoaded: guestLogSyncService.state.isLoaded,
            sleepPreventionServiceLoaded: sleepPreventionService.state.isLoaded,
            watchdogServiceLoaded: watchdogService.state.isLoaded,
            vmServiceState: vmService.state,
            proxyServiceState: proxyService.state,
            guestLogSyncServiceState: guestLogSyncService.state,
            sleepPreventionServiceState: sleepPreventionService.state,
            watchdogServiceState: watchdogService.state,
            vmServiceStateSource: vmService.source,
            proxyServiceStateSource: proxyService.source,
            guestLogSyncServiceStateSource: guestLogSyncService.source,
            sleepPreventionServiceStateSource: sleepPreventionService.source,
            watchdogServiceStateSource: watchdogService.source,
            runtimeState: document.map { RuntimeState(rawValue: $0.status.rawValue) },
            operation: document?.operation,
            statusMessage: document?.message,
            statusDocumentError: statusRead.error,
            installStateDocument: installStateRead.document,
            installStateDocumentError: installStateRead.error,
            readIssues: readIssues,
            updatedAt: document?.updatedAt,
            startedAt: nil,
            runtimeVersion: document?.runtimeVersion,
            latestBackup: document?.latestBackup,
            vmState: document?.vmState,
            vmErrors: document?.vmErrors,
            vmIP: document?.vmIP,
            guestHTTP: document?.guestHTTP,
            hostProxyHTTP: document?.hostProxyHTTP,
            redisUIHTTP: document?.redisUIHTTP,
            swaggerUIHTTP: document?.swaggerUIHTTP,
            guestServicesReadState: guestServicesRead.state,
            guestServices: guestServicesRead.services,
            guestServiceStatuses: guestServicesRead.statuses,
            guestServicesReadError: guestServicesRead.error,
            cpuUsagePercent: nil,
            memory: nil,
            vitalServerMemory: nil,
            recorderIngressMemory: nil,
            redisMemory: nil,
            systemDisk: nil,
            dataStorage: nil,
            proxyPort: document?.proxyPort,
            proxyPortReadState: document?.proxyPortReadState,
            failureReasons: document?.failureReasons ?? [],
            progress: document?.progress,
            redisRelayStatus: redisRelayStatusRead.document
        )
    }
}

private extension RuntimeGuestServicesRead {
    var state: RuntimeGuestServicesReadState {
        switch self {
        case .unavailable:
            return .unavailable
        case .loaded:
            return .loaded
        case .failed:
            return .failed
        }
    }

    var services: [String]? {
        switch self {
        case .loaded(let services, _):
            return services
        case .unavailable, .failed:
            return nil
        }
    }

    var statuses: [RuntimeGuestControlServiceStatus] {
        switch self {
        case .loaded(_, let statuses):
            return statuses
        case .unavailable, .failed:
            return []
        }
    }

    var error: String? {
        switch self {
        case .failed(let message):
            return message
        case .unavailable, .loaded:
            return nil
        }
    }
}
