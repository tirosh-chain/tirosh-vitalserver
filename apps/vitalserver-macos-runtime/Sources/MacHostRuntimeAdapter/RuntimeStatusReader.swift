import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

protocol RuntimeStatusReading: Sendable {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservation() -> VitalDBObservationDocument?
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
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
        withDataDirectoryMetrics(loadBaseStatus(), settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        var next = loadBaseStatus()

        if let vmIP = next.vmIP {
            next.guestHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.guestHealthURL(vmIP: vmIP))
        }
        next.hostProxyHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.hostProxyHealthURL(proxyPort: next.proxyPort))
        next.redisUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.redisUIURL(proxyPort: next.proxyPort))
        next.swaggerUIHTTP = await httpStatus(url: RuntimeAdapterConstants.Product.swaggerURL(proxyPort: next.proxyPort))

        return withDataDirectoryMetrics(next, settings: settings)
    }

    func loadBaseStatus() -> RuntimeStatus {
        let statusRepository = JSONFileRuntimeStatusRepository(url: URL(fileURLWithPath: paths.runtimeStatus))
        let document = statusRepository.load()
        let guestState = guestRuntimeStateDocument(paths.runtimeState)
        let containerObservation = document?.containerObservation
        let startedAt = containerObservation?.composeServices.first { $0.service == "app" }?.startedAt
            ?? guestState?.containerServices?.first { $0.service == "app" }?.startedAt
        let runtimeInstalled = fileStore.isExecutableFile(atPath: paths.launcher)
        let vmServiceLoaded = loaded(document?.vmService) ?? launchdLoaded(.vm)
        let vmIP = document?.vmIP ?? guestState?.vmIP
        let guestHTTP = document?.guestHTTP ?? guestState?.guestHTTP
        let vitalDBObservation = freshestVitalDBObservation(
            document?.vitalDBObservation,
            guestState?.vitalDBObservation
        )

        return RuntimeStatus(
            runtimeInstalled: runtimeInstalled,
            vmServiceLoaded: vmServiceLoaded,
            proxyServiceLoaded: loaded(document?.proxyService) ?? launchdLoaded(.proxy),
            guestLogSyncServiceLoaded: launchdLoaded(.guestLogSync),
            sleepPreventionServiceLoaded: launchdLoaded(.sleepPrevention),
            watchdogServiceLoaded: loaded(document?.watchdogService) ?? launchdLoaded(.watchdog),
            runtimeState: document.map { RuntimeState(rawValue: $0.status.rawValue) },
            operation: document?.operation,
            statusMessage: document?.message,
            updatedAt: document?.updatedAt,
            startedAt: startedAt,
            runtimeVersion: document?.runtimeVersion,
            latestBackup: document?.latestBackup,
            vmState: document?.vmState,
            vmErrors: document?.vmErrors,
            vmIP: vmIP,
            guestHTTP: guestHTTP,
            hostProxyHTTP: document?.hostProxyHTTP,
            redisUIHTTP: document?.redisUIHTTP ?? guestState?.redisUIHTTP,
            swaggerUIHTTP: document?.swaggerUIHTTP ?? guestState?.swaggerUIHTTP,
            cpuUsagePercent: guestState?.cpuUsagePercent,
            memory: guestState?.memory,
            systemDisk: guestState?.systemDisk,
            dataStorage: guestState?.vitalFilesDisk,
            proxyPort: document?.proxyPort ?? proxyPort(paths.proxyLaunchDaemon),
            failureReasons: document?.failureReasons ?? [],
            progress: document?.progress,
            containerObservation: containerObservation,
            vitalDBObservation: vitalDBObservation
        )
    }

    private func freshestVitalDBObservation(
        _ statusObservation: VitalDBObservationDocument?,
        _ guestObservation: VitalDBObservationDocument?
    ) -> VitalDBObservationDocument? {
        guard let statusObservation else {
            return guestObservation
        }
        guard let guestObservation else {
            return statusObservation
        }
        return guestObservation.observedAt > statusObservation.observedAt
            ? guestObservation
            : statusObservation
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        let repository = CompositeRuntimeEventRepository(
            primary: JSONLRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeEvents)),
            secondary: SQLiteRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
        )
        let page = repository.query(query)
        return RuntimeEventHistory(
            events: page.events,
            nextCursor: page.nextCursor.map(RuntimeEventCursorWireCodec.encode),
            matchingCount: page.matchingCount
        )
    }

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        SQLiteRuntimeObservabilityStore(
            url: URL(fileURLWithPath: paths.runtimeObservabilityDB)
        ).latestVitalDBObservation()
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        var observations = SQLiteRuntimeObservabilityStore(
            url: URL(fileURLWithPath: paths.runtimeObservabilityDB)
        ).vitalDBObservations()
        if let latestStatusObservation = loadBaseStatus().vitalDBObservation,
           !observations.contains(where: { $0.observedAt == latestStatusObservation.observedAt }) {
            observations.append(latestStatusObservation)
        }
        return RuntimeVitalRecorderHistory(observations: observations)
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        let store = SQLiteRuntimeObservabilityStore(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
        return RuntimeVitalRelationshipHistory(
            assignments: store.vitalDBBedAssignments().map(RuntimeVitalBedAssignmentRecord.init),
            events: store.vitalDBRelationshipEvents().map(RuntimeVitalRelationshipEventRecord.init)
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
        next.dataStorage = storageUsageProvider.storageUsage(for: settings.vitalFilesDirectory) ?? next.dataStorage
        next.dataDirectoryStats = dataDirectoryStats(for: settings.vitalFilesDirectory)
        return next
    }

    private func dataDirectoryStats(for path: String) -> RuntimeDataDirectoryStats? {
        let root = URL(fileURLWithPath: path)
        guard fileStore.directoryExists(root) else {
            return nil
        }
        let stats = directoryStats(root)
        return RuntimeDataDirectoryStats(fileCount: stats.fileCount, sizeBytes: Int64(stats.sizeBytes))
    }

    private func directoryStats(_ directory: URL) -> (fileCount: Int, sizeBytes: UInt64) {
        guard let contents = try? fileStore.contentsOfDirectory(at: directory, skipsHiddenFiles: true) else {
            return (0, 0)
        }

        var fileCount = 0
        var sizeBytes: UInt64 = 0
        for url in contents {
            if fileStore.directoryExists(url) {
                let nested = directoryStats(url)
                fileCount += nested.fileCount
                sizeBytes += nested.sizeBytes
            } else if fileStore.fileExists(url) {
                fileCount += 1
                sizeBytes += (try? fileStore.fileSize(url)) ?? 0
            }
        }
        return (fileCount, sizeBytes)
    }

    private func guestRuntimeStateDocument(_ path: String) -> GuestRuntimeStateDocument? {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
    }

    private func loaded(_ value: RuntimeServiceState?) -> Bool? {
        guard let value else {
            return nil
        }
        return value.isLoaded
    }

    private func launchdLoaded(_ service: RuntimeManagedService) -> Bool {
        ProcessRunner.runSync(
            RuntimeAdapterConstants.Commands.launchctl,
            arguments: ["print", "system/\(service.label)"]
        ).exitCode == 0
    }

    private func readTrimmed(_ path: String) -> String? {
        guard let value = try? fileStore.readUTF8Text(URL(fileURLWithPath: path))
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func proxyPort(_ plistPath: String) -> Int {
        guard let data = try? fileStore.readData(URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let document = plist as? [String: Any],
              let environment = document["EnvironmentVariables"] as? [String: Any],
              let rawPort = environment["VITALSERVER_PROXY_PORT"] as? String,
              let port = Int(rawPort),
              (1...65_535).contains(port)
        else {
            return RuntimeAdapterConstants.Product.defaultProxyPort
        }
        return port
    }

}

private extension RuntimeVitalBedAssignmentRecord {
    init(_ record: VitalDBBedAssignmentRecord) {
        self.init(
            assignmentID: record.id,
            bedID: record.bedID,
            bedName: record.bedName,
            vrcode: record.vrcode,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            lastSeenAt: record.lastSeenAt,
            lastObservedAt: record.lastObservedAt,
            status: RuntimeVitalBedStatus(rawValue: record.status) ?? .unknown,
            patientConnected: record.patientConnected,
            observationCount: record.observationCount
        )
    }
}

private extension RuntimeVitalRelationshipEventRecord {
    init(_ record: VitalDBRelationshipEventRecord) {
        self.init(
            eventID: record.id,
            observedAt: record.observedAt,
            eventType: RuntimeVitalRelationshipEventType(record.eventType),
            severity: RuntimeVitalRelationshipSeverity(record.severity),
            bedID: record.bedID,
            bedName: record.bedName,
            vrcode: record.vrcode,
            previousVrcode: record.previousVrcode,
            previousBedID: record.previousBedID,
            message: record.message
        )
    }
}

private extension RuntimeVitalRelationshipEventType {
    init(_ eventType: VitalDBRelationshipEventType) {
        switch eventType {
        case .handoff:
            self = .handoff
        case .duplicateAssignment:
            self = .duplicateAssignment
        case .unlinkedBed:
            self = .unlinkedBed
        case .unlinkedRecorder:
            self = .unlinkedRecorder
        case .staleLink:
            self = .staleLink
        }
    }
}

private extension RuntimeVitalRelationshipSeverity {
    init(_ severity: VitalDBRelationshipSeverity) {
        switch severity {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .critical:
            self = .critical
        }
    }
}
