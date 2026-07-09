import Contracts

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

public struct RuntimeVMLifecycleRead {
    public let document: RuntimeVMLifecycleDocument?
    public let issue: RuntimeStatusReadIssue?

    public init(
        document: RuntimeVMLifecycleDocument?,
        issue: RuntimeStatusReadIssue?
    ) {
        self.document = document
        self.issue = issue
    }
}

public struct RuntimeVersionRead {
    public let version: String?
    public let issue: RuntimeStatusReadIssue?

    public init(version: String?, issue: RuntimeStatusReadIssue?) {
        self.version = version
        self.issue = issue
    }
}

public struct RuntimeLatestBackupRead {
    public let path: String?
    public let issue: RuntimeStatusReadIssue?

    public init(path: String?, issue: RuntimeStatusReadIssue?) {
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

public enum RuntimeGuestServicesRead: Equatable, Sendable {
    case unavailable
    case loaded(
        services: [String],
        statuses: [RuntimeGuestControlServiceStatus],
        resources: [RuntimeGuestServiceResource] = [],
        resourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = [],
        probeErrors: [GuestRuntimeProbeError] = [],
        cpuUsagePercent: Double?,
        memory: ResourceUsage?,
        systemDisk: ResourceUsage?
    )
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
        } else {
            apply(reads.guestHTTP, to: \.guestHTTP, in: &next)
        }

        guard status.proxyPort != nil else {
            next.hostProxyHTTP = RuntimeHTTPStatusText.missingProxyPort
            next.redisUIHTTP = RuntimeHTTPStatusText.missingProxyPort
            next.swaggerUIHTTP = RuntimeHTTPStatusText.missingProxyPort
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
        redisRelayStatusRead: RuntimeRedisRelayStatusRead = RuntimeRedisRelayStatusRead(
            document: nil,
            error: nil,
            issue: nil
        ),
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        runtimeVersionRead: RuntimeVersionRead = RuntimeVersionRead(version: nil, issue: nil),
        latestBackupRead: RuntimeLatestBackupRead = RuntimeLatestBackupRead(path: nil, issue: nil),
        currentHealthRead: RuntimeCurrentHealthRead? = nil,
        guestServicesRead: RuntimeGuestServicesRead = .unavailable,
        guestAddressRead: RuntimeGuestAddressReadResult = .notReported,
        vmLifecycleRead: RuntimeVMLifecycleRead = RuntimeVMLifecycleRead(document: nil, issue: nil),
        liveDiagnostics: RuntimeLiveDiagnostics
    ) -> RuntimeStatus {
        let readIssues = liveDiagnostics.readIssues
            + [liveDiagnostics.runtimeInstallationIssue].compactMap { $0 }
            + [redisRelayStatusRead.issue].compactMap { $0 }
            + [vmLifecycleRead.issue].compactMap { $0 }
            + [runtimeVersionRead.issue, latestBackupRead.issue].compactMap { $0 }
        let currentHealth = currentHealthRead ?? makeCurrentHealthRead(
            liveDiagnostics: liveDiagnostics,
            guestServicesRead: guestServicesRead,
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
            runtimeState: currentHealth.runtimeState,
            readIssues: readIssues,
            runtimeVersion: runtimeVersionRead.version,
            latestBackup: latestBackupRead.path,
            vmState: vmState(from: vmLifecycleRead.document),
            vmErrors: vmLifecycleRead.document?.reportedVMErrors,
            vmIP: guestAddressRead.loadedAddress,
            guestHTTP: nil,
            hostProxyHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            guestServicesReadState: guestServicesRead.state,
            guestServices: guestServicesRead.services,
            guestServiceStatuses: guestServicesRead.statuses,
            guestServiceResources: guestServicesRead.resources,
            guestServiceResourceReadIssues: guestServicesRead.resourceReadIssues,
            guestStackProbeErrors: guestServicesRead.probeErrors,
            guestServicesReadError: guestServicesRead.error,
            cpuUsagePercent: guestServicesRead.cpuUsagePercent,
            memory: guestServicesRead.memory,
            vitalServerMemory: guestServicesRead.memory(for: "app"),
            recorderIngressMemory: guestServicesRead.memory(for: "recorder-ingress"),
            redisMemory: guestServicesRead.memory(for: "redis"),
            systemDisk: guestServicesRead.systemDisk,
            dataStorage: nil,
            proxyPort: proxyPortReadState?.port,
            proxyPortReadState: proxyPortReadState,
            failureReasons: currentHealth.failureReasons,
            redisRelayStatus: redisRelayStatusRead.document
        )
    }

    private static func makeCurrentHealthRead(
        liveDiagnostics: RuntimeLiveDiagnostics,
        guestServicesRead: RuntimeGuestServicesRead,
        guestAddressRead: RuntimeGuestAddressReadResult,
        vmLifecycleRead: RuntimeVMLifecycleRead,
        proxyPortReadState: RuntimeProxyPortReadState?,
        readIssues: [RuntimeStatusReadIssue]
    ) -> RuntimeCurrentHealthRead {
        let failureReasons = currentFailureReasons(
            liveDiagnostics: liveDiagnostics,
            guestServicesRead: guestServicesRead,
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
        readIssues: [RuntimeStatusReadIssue]
    ) -> RuntimeState? {
        if failureReasons.contains(where: { $0.domainSeverity == .critical }) {
            return .critical
        }
        if !failureReasons.isEmpty || readIssues.contains(where: isCurrentRuntimeStateReadIssue) {
            return .degraded
        }
        return .healthy
    }

    private static func isCurrentRuntimeStateReadIssue(_ issue: RuntimeStatusReadIssue) -> Bool {
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
        guestServicesRead: RuntimeGuestServicesRead,
        guestAddressRead: RuntimeGuestAddressReadResult,
        vmLifecycleRead: RuntimeVMLifecycleRead,
        proxyPortReadState: RuntimeProxyPortReadState?
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        appendServiceReason(.vmService(liveDiagnostics.vmService.state.rawValue), ifNotLoaded: liveDiagnostics.vmService, to: &reasons)
        appendServiceReason(.proxyService(liveDiagnostics.proxyService.state.rawValue), ifNotLoaded: liveDiagnostics.proxyService, to: &reasons)
        appendServiceReason(.watchdogService(liveDiagnostics.watchdogService.state.rawValue), ifNotLoaded: liveDiagnostics.watchdogService, to: &reasons)
        reasons.append(contentsOf: vmLifecycleRead.document?.reportedVMErrors.map(RuntimeFailureReason.init(vmError:)) ?? [])
        if let error = guestServicesRead.error {
            reasons.append(.guestServiceObservationReadFailed(error))
        }
        reasons.append(contentsOf: guestServiceFailureReasons(guestServicesRead))
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

    private static func guestServiceFailureReasons(
        _ read: RuntimeGuestServicesRead
    ) -> [RuntimeFailureReason] {
        let resourceByService = Dictionary(
            uniqueKeysWithValues: read.resources.map { ($0.service, $0) }
        )
        return read.statuses.compactMap { status in
            guestServiceFailureReason(
                status,
                resource: resourceByService[status.service]
            )
        }
    }

    private static func guestServiceFailureReason(
        _ status: RuntimeGuestControlServiceStatus,
        resource: RuntimeGuestServiceResource?
    ) -> RuntimeFailureReason? {
        if let desiredState = resource?.spec.desiredState,
           desiredState == "stopped",
           status.state == "stopped" {
            return nil
        }
        if status.state != "running" {
            return .guestService(service: status.service, state: status.state)
        }
        if status.health != "healthy" && status.health != "ready" {
            return .guestService(service: status.service, state: status.health)
        }
        return nil
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
        case .loaded(let services, _, _, _, _, _, _, _):
            return services
        case .unavailable, .failed:
            return nil
        }
    }

    var statuses: [RuntimeGuestControlServiceStatus] {
        switch self {
        case .loaded(_, let statuses, _, _, _, _, _, _):
            return statuses
        case .unavailable, .failed:
            return []
        }
    }

    var resources: [RuntimeGuestServiceResource] {
        switch self {
        case .loaded(_, _, let resources, _, _, _, _, _):
            return resources
        case .unavailable, .failed:
            return []
        }
    }

    var resourceReadIssues: [RuntimeGuestServiceResourceReadIssue] {
        switch self {
        case .loaded(_, _, _, let issues, _, _, _, _):
            return issues
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

    var cpuUsagePercent: Double? {
        switch self {
        case .loaded(_, _, _, _, _, let cpuUsagePercent, _, _):
            return cpuUsagePercent
        case .unavailable, .failed:
            return nil
        }
    }

    var memory: ResourceUsage? {
        switch self {
        case .loaded(_, _, _, _, _, _, let memory, _):
            return memory
        case .unavailable, .failed:
            return nil
        }
    }

    var systemDisk: ResourceUsage? {
        switch self {
        case .loaded(_, _, _, _, _, _, _, let systemDisk):
            return systemDisk
        case .unavailable, .failed:
            return nil
        }
    }

    var probeErrors: [GuestRuntimeProbeError] {
        switch self {
        case .loaded(_, _, _, _, let probeErrors, _, _, _):
            return probeErrors
        case .unavailable, .failed:
            return []
        }
    }

    func memory(for service: String) -> RuntimeContainerMemoryUsage? {
        switch self {
        case .loaded(_, let statuses, _, _, _, _, _, _):
            guard let memory = statuses.first(where: { $0.service == service })?.memory else {
                return nil
            }
            return RuntimeContainerMemoryUsage(
                usedBytes: memory.usedBytes,
                limitBytes: memory.totalBytes
            )
        case .unavailable, .failed:
            return nil
        }
    }
}
