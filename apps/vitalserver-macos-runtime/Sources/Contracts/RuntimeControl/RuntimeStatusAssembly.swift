import Contracts

public struct RuntimeVMLifecycleRead {
    public let document: RuntimeVMLifecycleDocument?
    public let issue: PlatformStateReadIssue?

    public init(
        document: RuntimeVMLifecycleDocument?,
        issue: PlatformStateReadIssue?
    ) {
        self.document = document
        self.issue = issue
    }
}

public struct RuntimeVersionRead {
    public let version: String?
    public let issue: PlatformStateReadIssue?

    public init(version: String?, issue: PlatformStateReadIssue?) {
        self.version = version
        self.issue = issue
    }
}

public struct RuntimeLatestBackupRead {
    public let path: String?
    public let issue: PlatformStateReadIssue?

    public init(path: String?, issue: PlatformStateReadIssue?) {
        self.path = path
        self.issue = issue
    }
}

public struct RuntimeCurrentHealthRead {
    public let runtimeState: RuntimeState?
    public let failureReasons: [RuntimeFailureReason]

    public init(
        runtimeState: RuntimeState?,
        failureReasons: [RuntimeFailureReason]
    ) {
        self.runtimeState = runtimeState
        self.failureReasons = failureReasons
    }
}

public struct RuntimeHTTPStatusRead: Equatable, Sendable {
    public let status: String?
    public let issue: PlatformStateReadIssue?

    public init(status: String?, issue: PlatformStateReadIssue?) {
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
    public let runtimeInstallationIssue: PlatformStateReadIssue?
    public let vmService: RuntimeServiceStateRead
    public let proxyService: RuntimeServiceStateRead
    public let guestLogSyncService: RuntimeServiceStateRead
    public let sleepPreventionService: RuntimeServiceStateRead
    public let watchdogService: RuntimeServiceStateRead
    public let readIssues: [PlatformStateReadIssue]

    public init(
        runtimeInstalled: Bool,
        runtimeInstallationState: RuntimeFileState,
        runtimeInstallationIssue: PlatformStateReadIssue?,
        vmService: RuntimeServiceStateRead,
        proxyService: RuntimeServiceStateRead,
        guestLogSyncService: RuntimeServiceStateRead,
        sleepPreventionService: RuntimeServiceStateRead,
        watchdogService: RuntimeServiceStateRead,
        readIssues: [PlatformStateReadIssue]
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

    public init(state: RuntimeServiceState) {
        self.state = state
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
        liveServiceStates: RuntimeLiveServiceStateReads
    ) -> RuntimeLiveDiagnostics {
        let vmService = liveServiceState(liveServiceStates.vm)
        let proxyService = liveServiceState(liveServiceStates.proxy)
        let guestLogSyncService = liveServiceState(liveServiceStates.guestLogSync)
        let sleepPreventionService = liveServiceState(liveServiceStates.sleepPrevention)
        let watchdogService = liveServiceState(liveServiceStates.watchdog)

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

    private static func liveServiceState(_ state: RuntimeServiceState) -> RuntimeServiceStateRead {
        RuntimeServiceStateRead(state: state)
    }

    private static func serviceReadIssues(_ states: [(String, RuntimeServiceStateRead)]) -> [PlatformStateReadIssue] {
        states.compactMap { source, read in
            switch read.state {
            case .readFailed(let message), .permissionDenied(let message):
                PlatformStateReadIssue(source: source, message: message)
            case .unknown(let value):
                PlatformStateReadIssue(source: source, message: "unknown service state: \(value)")
            case .loaded, .notLoaded:
                nil
            }
        }
    }

    private static func runtimeInstallationIssue(
        state: RuntimeFileState,
        path: String
    ) -> PlatformStateReadIssue? {
        switch state {
        case .executable, .missing:
            nil
        case .present:
            PlatformStateReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher is present but not executable path=\(path)"
            )
        case .inspectFailed(let reason):
            PlatformStateReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher inspection failed path=\(path) reason=\(reason)"
            )
        case .unknown(let value):
            PlatformStateReadIssue(
                source: "runtimeInstallation",
                message: "runtime launcher inspection returned unknown state path=\(path) state=\(value)"
            )
        }
    }
}

public enum RuntimeHealthStatusAssembler {
    public static func applyingHealthProbeReads(
        to status: PlatformState,
        reads: RuntimeHealthProbeReads
    ) -> PlatformState {
        var next = status
        if status.runtimeEndpoint == nil {
            next.runtimeControllerHTTP = RuntimeHTTPStatusText.missingVMIP
        } else {
            apply(reads.guestHTTP, to: \.runtimeControllerHTTP, in: &next)
        }

        guard status.publicProxyPort != nil else {
            next.publicProxyHTTP = RuntimeHTTPStatusText.missingProxyPort
            return next
        }

        apply(reads.hostProxyHTTP, to: \.publicProxyHTTP, in: &next)
        return next
    }

    private static func apply(
        _ read: RuntimeHTTPStatusRead?,
        to keyPath: WritableKeyPath<PlatformState, String?>,
        in status: inout PlatformState
    ) {
        guard let read else {
            return
        }
        status[keyPath: keyPath] = read.status
        append(read.issue, to: &status)
    }

    private static func append(
        _ issue: PlatformStateReadIssue?,
        to status: inout PlatformState
    ) {
        guard let issue else {
            return
        }
        status.readIssues.append(issue)
    }

    private static func appendUnique(
        _ issue: PlatformStateReadIssue,
        to status: inout PlatformState
    ) {
        guard !status.readIssues.contains(issue) else {
            return
        }
        status.readIssues.append(issue)
    }
}

public enum RuntimeControlLocalAPIStatusAssembler {
    public static func applyingLocalAPIStatus(
        to status: PlatformState,
        read: RuntimeControlLocalAPIStatusRead
    ) -> PlatformState {
        var next = status
        next.platformAPIHTTP = read.http
        next.platformAPIStartedAt = read.startedAt
        return next
    }
}

public enum RuntimeDataDirectoryMetricsAssembler {
    public static func applyingMetricReads(
        to status: PlatformState,
        reads: RuntimeDataDirectoryMetricReads
    ) -> PlatformState {
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

public enum PlatformStateAssembler {
    public static func makePlatformState(
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        runtimeVersionRead: RuntimeVersionRead = RuntimeVersionRead(version: nil, issue: nil),
        latestBackupRead: RuntimeLatestBackupRead = RuntimeLatestBackupRead(path: nil, issue: nil),
        currentHealthRead: RuntimeCurrentHealthRead? = nil,
        guestAddressRead: RuntimeGuestAddressReadResult = .notReported,
        vmLifecycleRead: RuntimeVMLifecycleRead = RuntimeVMLifecycleRead(document: nil, issue: nil),
        liveDiagnostics: RuntimeLiveDiagnostics
    ) -> PlatformState {
        let readIssues = liveDiagnostics.readIssues
            + [liveDiagnostics.runtimeInstallationIssue].compactMap { $0 }
            + [vmLifecycleRead.issue].compactMap { $0 }
            + [runtimeVersionRead.issue, latestBackupRead.issue].compactMap { $0 }
        let currentHealth = currentHealthRead ?? makeCurrentHealthRead(
            liveDiagnostics: liveDiagnostics,
            guestAddressRead: guestAddressRead,
            vmLifecycleRead: vmLifecycleRead,
            proxyPortReadState: proxyPortReadState,
            readIssues: readIssues
        )
        let vmService = liveDiagnostics.vmService
        let proxyService = liveDiagnostics.proxyService
        let guestLogSyncService = liveDiagnostics.guestLogSyncService
        let sleepPreventionService = liveDiagnostics.sleepPreventionService
        let watchdogService = liveDiagnostics.watchdogService

        return PlatformState(
            runtimeInstallationState: liveDiagnostics.runtimeInstallationState,
            services: [
                PlatformServiceStatus(role: .runtimeProvider, state: vmService.state),
                PlatformServiceStatus(role: .publicProxy, state: proxyService.state),
                PlatformServiceStatus(role: .logSync, state: guestLogSyncService.state),
                PlatformServiceStatus(role: .sleepPrevention, state: sleepPreventionService.state),
                PlatformServiceStatus(role: .watchdog, state: watchdogService.state),
            ],
            platformHealth: currentHealth.runtimeState,
            readIssues: readIssues,
            installedVersion: runtimeVersionRead.version,
            latestBackup: latestBackupRead.path,
            runtimeProviderState: vmState(from: vmLifecycleRead.document),
            runtimeProviderErrors: vmLifecycleRead.document?.reportedVMErrors,
            runtimeEndpoint: guestAddressRead.loadedAddress,
            runtimeControllerHTTP: nil,
            publicProxyHTTP: nil,
            dataStorage: nil,
            publicProxyPort: proxyPortReadState?.port,
            publicProxyPortReadState: proxyPortReadState,
            healthIssues: currentHealth.failureReasons
        )
    }

    private static func makeCurrentHealthRead(
        liveDiagnostics: RuntimeLiveDiagnostics,
        guestAddressRead: RuntimeGuestAddressReadResult,
        vmLifecycleRead: RuntimeVMLifecycleRead,
        proxyPortReadState: RuntimeProxyPortReadState?,
        readIssues: [PlatformStateReadIssue]
    ) -> RuntimeCurrentHealthRead {
        let failureReasons = currentFailureReasons(
            liveDiagnostics: liveDiagnostics,
            guestAddressRead: guestAddressRead,
            vmLifecycleRead: vmLifecycleRead,
            proxyPortReadState: proxyPortReadState
        )
        return RuntimeCurrentHealthRead(
            runtimeState: currentRuntimeState(
                failureReasons: failureReasons,
                readIssues: readIssues
            ),
            failureReasons: failureReasons
        )
    }

    private static func currentRuntimeState(
        failureReasons: [RuntimeFailureReason],
        readIssues: [PlatformStateReadIssue]
    ) -> RuntimeState? {
        if failureReasons.contains(where: { $0.domainSeverity == .critical }) {
            return .critical
        }
        if !failureReasons.isEmpty || readIssues.contains(where: isCurrentRuntimeStateReadIssue) {
            return .degraded
        }
        return .healthy
    }

    private static func isCurrentRuntimeStateReadIssue(_ issue: PlatformStateReadIssue) -> Bool {
        [
            "runtimeInstallation",
            "vmService",
            "proxyService",
            "guestLogSyncService",
            "sleepPreventionService",
            "watchdogService",
            "vmLifecycle",
        ].contains(issue.source)
    }

    private static func currentFailureReasons(
        liveDiagnostics: RuntimeLiveDiagnostics,
        guestAddressRead: RuntimeGuestAddressReadResult,
        vmLifecycleRead: RuntimeVMLifecycleRead,
        proxyPortReadState: RuntimeProxyPortReadState?
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        appendServiceReason(.vmService(liveDiagnostics.vmService.state.rawValue), ifNotLoaded: liveDiagnostics.vmService, to: &reasons)
        appendServiceReason(.proxyService(liveDiagnostics.proxyService.state.rawValue), ifNotLoaded: liveDiagnostics.proxyService, to: &reasons)
        appendServiceReason(.watchdogService(liveDiagnostics.watchdogService.state.rawValue), ifNotLoaded: liveDiagnostics.watchdogService, to: &reasons)
        reasons.append(contentsOf: vmLifecycleRead.document?.reportedVMErrors.map(RuntimeFailureReason.init(vmError:)) ?? [])
        return reasons
    }

    private static func appendServiceReason(
        _ reason: RuntimeFailureReason,
        ifNotLoaded serviceRead: RuntimeServiceStateRead,
        to reasons: inout [RuntimeFailureReason]
    ) {
        guard serviceRead.state != .loaded else {
            return
        }
        reasons.append(reason)
    }

    private static func vmState(from lifecycle: RuntimeVMLifecycleDocument?) -> RuntimeVMState? {
        guard let lifecycle else {
            return nil
        }
        switch lifecycle.state {
        case .starting, .bootstrapping:
            return .starting
        case .running:
            return .running
        case .stopping, .stopped:
            return .stopped
        case .failed:
            return .failed
        case .unknown(let value):
            return .unknown(value)
        }
    }
}
