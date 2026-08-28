/// Host-owned Guest Control HTTP endpoint. Consumers receive this contract
/// explicitly; they must not infer scheme or port from reachability or from
/// URL defaults.
public enum RuntimeGuestControlEndpointContract {
    public static let scheme = "http"
    public static let port = 18330

    public static func baseURL(host: String) -> String {
        "\(scheme)://\(host):\(port)"
    }
}

public struct RuntimeGuestControlReadiness: Codable, Equatable, Sendable {
    public let status: String
    public let dependencies: [RuntimeGuestControlReadinessDependency]

    public init(
        status: String,
        dependencies: [RuntimeGuestControlReadinessDependency] = []
    ) {
        self.status = status
        self.dependencies = dependencies
    }

    public var failureSummary: String? {
        let failures = dependencies.filter { $0.state != "ready" }
        guard !failures.isEmpty else {
            return nil
        }
        return failures.map { dependency in
            [
                dependency.name,
                dependency.state,
                dependency.kind ?? "",
                dependency.message ?? "",
            ]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        }
        .joined(separator: ",")
    }
}

public struct RuntimeGuestControlReadinessDependency: Codable, Equatable, Sendable {
    public let name: String
    public let role: String
    public let state: String
    public let kind: String?
    public let message: String?

    public init(
        name: String,
        role: String,
        state: String,
        kind: String? = nil,
        message: String? = nil
    ) {
        self.name = name
        self.role = role
        self.state = state
        self.kind = kind
        self.message = message
    }
}

public struct RuntimeGuestControlCapabilities: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capabilities: [String]

    public init(schemaVersion: Int, capabilities: [String]) {
        self.schemaVersion = schemaVersion
        self.capabilities = capabilities
    }
}

public enum RuntimeGuestControlServiceCommand: String, CaseIterable, Codable, Equatable, Sendable {
    case start
    case stop
    case restart
    case reconcile
    case labCreateSession = "lab-create-session"
    case labStartSession = "lab-start-session"
    case labStopSession = "lab-stop-session"
    case labFinishSession = "lab-finish-session"
    case labReplayVitalFile = "lab-replay-vital-file"
    case labUploadVitalFile = "lab-upload-vital-file"
    case labCreateBeds = "lab-create-beds"
    case labDeleteBeds = "lab-delete-beds"
    case labResetBeds = "lab-reset-beds"
    case labCreateRecorders = "lab-create-recorders"
    case labDeleteRecorders = "lab-delete-recorders"
    case labResetRecorders = "lab-reset-recorders"
    case postgresBackup = "postgres-backup"
    case postgresRestore = "postgres-restore"
    case redisBackup = "redis-backup"
    case redisRestore = "redis-restore"
    case repairDatastore = "repair-datastore"
    case updateActivation = "activate-update"
    case updateShutdown = "prepare-update-shutdown"
    case requestGuestPoweroff = "request-guest-poweroff"
    case applySettings = "apply-settings"
    case applyAdminPassword = "apply-admin-password"
    case applyRedisRelaySettings = "apply-redis-relay-settings"
}

public enum RuntimeGuestControlOperationState: String, CaseIterable, Codable, Equatable, Sendable {
    case accepted
    case running
    case completed
    case failed
    case cancelled
    case interrupted
}

public struct RuntimeGuestControlServiceStatus: Codable, Equatable, Sendable {
    public let service: String
    public let state: String
    public let health: String
    public let observedAt: String
    public let container: String?
    public let exitCode: Int?
    public let memory: ResourceUsage?

    public init(
        service: String,
        state: String,
        health: String,
        observedAt: String,
        container: String? = nil,
        exitCode: Int? = nil,
        memory: ResourceUsage? = nil
    ) {
        self.service = service
        self.state = state
        self.health = health
        self.observedAt = observedAt
        self.container = container
        self.exitCode = exitCode
        self.memory = memory
    }
}

public struct RuntimeGuestServiceSpec: Codable, Equatable, Sendable {
    public let state: String
    public let desiredState: String?
    public let updatedAt: String?

    public init(
        state: String,
        desiredState: String? = nil,
        updatedAt: String? = nil
    ) {
        self.state = state
        self.desiredState = desiredState
        self.updatedAt = updatedAt
    }
}

public struct RuntimeGuestServiceStatusRead: Codable, Equatable, Sendable {
    public let state: String
    public let observedState: String?
    public let observedAt: String?
    public let serviceStatus: RuntimeGuestControlServiceStatus?
    public let readError: RuntimeGuestControlOperationFailure?

    public init(
        state: String,
        observedState: String? = nil,
        observedAt: String? = nil,
        serviceStatus: RuntimeGuestControlServiceStatus? = nil,
        readError: RuntimeGuestControlOperationFailure? = nil
    ) {
        self.state = state
        self.observedState = observedState
        self.observedAt = observedAt
        self.serviceStatus = serviceStatus
        self.readError = readError
    }
}

public struct RuntimeGuestServiceCondition: Codable, Equatable, Sendable {
    public let type: String
    public let status: String
    public let reason: String
    public let message: String
    public let observedAt: String

    public init(
        type: String,
        status: String,
        reason: String,
        message: String,
        observedAt: String
    ) {
        self.type = type
        self.status = status
        self.reason = reason
        self.message = message
        self.observedAt = observedAt
    }
}

public struct RuntimeGuestServiceResource: Codable, Equatable, Sendable {
    public let service: String
    public let spec: RuntimeGuestServiceSpec
    public let status: RuntimeGuestServiceStatusRead
    public let conditions: [RuntimeGuestServiceCondition]
    public let lastOperationId: String?

    public init(
        service: String,
        spec: RuntimeGuestServiceSpec,
        status: RuntimeGuestServiceStatusRead,
        conditions: [RuntimeGuestServiceCondition],
        lastOperationId: String? = nil
    ) {
        self.service = service
        self.spec = spec
        self.status = status
        self.conditions = conditions
        self.lastOperationId = lastOperationId
    }
}

public struct RuntimeGuestServiceResourceReadIssue: Codable, Equatable, Sendable {
    public let service: String
    public let message: String

    public init(service: String, message: String) {
        self.service = service
        self.message = message
    }
}

public struct RuntimeGuestControlStackStatus: Codable, Equatable, Sendable {
    public let state: String
    public let observedAt: String
    public let services: [RuntimeGuestControlServiceStatus]
    public let cpuUsagePercent: Double?
    public let memory: ResourceUsage?
    public let systemDisk: ResourceUsage?
    public let vitalFilesDisk: ResourceUsage?
    public let clockQuality: RuntimeClockQualityDocument?
    public let probeErrors: [GuestRuntimeProbeError]

    public init(
        state: String,
        observedAt: String,
        services: [RuntimeGuestControlServiceStatus],
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil,
        vitalFilesDisk: ResourceUsage? = nil,
        clockQuality: RuntimeClockQualityDocument? = nil,
        probeErrors: [GuestRuntimeProbeError] = []
    ) {
        self.state = state
        self.observedAt = observedAt
        self.services = services
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.systemDisk = systemDisk
        self.vitalFilesDisk = vitalFilesDisk
        self.clockQuality = clockQuality
        self.probeErrors = probeErrors
    }
}

public struct RuntimeGuestControlOperationFailure: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String
    public let evidencePath: String?

    public init(kind: String, message: String, evidencePath: String? = nil) {
        self.kind = kind
        self.message = message
        self.evidencePath = evidencePath
    }
}

public struct RuntimeGuestControlServiceOperation: Codable, Equatable, Sendable {
    public let operationId: String
    public let service: String
    public let command: RuntimeGuestControlServiceCommand
    public let state: RuntimeGuestControlOperationState
    public let createdAt: String
    public let updatedAt: String
    public let failure: RuntimeGuestControlOperationFailure?
    public let result: RuntimeGuestControlOperationResult?

    public init(
        operationId: String,
        service: String,
        command: RuntimeGuestControlServiceCommand,
        state: RuntimeGuestControlOperationState,
        createdAt: String,
        updatedAt: String,
        failure: RuntimeGuestControlOperationFailure? = nil,
        result: RuntimeGuestControlOperationResult? = nil
    ) {
        self.operationId = operationId
        self.service = service
        self.command = command
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failure = failure
        self.result = result
    }
}

public struct RuntimeGuestControlOperationResult: Codable, Equatable, Sendable {
    public let archive: String?
    public let restoredArchive: String?
    public let requestId: String?
    public let version: String?
    public let shutdownPhase: String?
    public let redisBackupPath: String?
    public let postgresBackupPath: String?
    public let alembicRevision: String?
    public let runtimeRestarted: Bool?

    public init(
        archive: String? = nil,
        restoredArchive: String? = nil,
        requestId: String? = nil,
        version: String? = nil,
        shutdownPhase: String? = nil,
        redisBackupPath: String? = nil,
        postgresBackupPath: String? = nil,
        alembicRevision: String? = nil,
        runtimeRestarted: Bool? = nil
    ) {
        self.archive = archive
        self.restoredArchive = restoredArchive
        self.requestId = requestId
        self.version = version
        self.shutdownPhase = shutdownPhase
        self.redisBackupPath = redisBackupPath
        self.postgresBackupPath = postgresBackupPath
        self.alembicRevision = alembicRevision
        self.runtimeRestarted = runtimeRestarted
    }
}

public struct RuntimeGuestControlServiceList: Codable, Equatable, Sendable {
    public let services: [String]

    public init(services: [String]) {
        self.services = services
    }
}

public enum RuntimeGuestControlReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public struct RuntimeGuestControlVitalDBObservationRead: Codable, Equatable, Sendable {
    public let state: RuntimeGuestControlReadState
    public let observation: VitalDBObservationDocument?
    public let readError: String?

    public init(
        state: RuntimeGuestControlReadState,
        observation: VitalDBObservationDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.observation = observation
        self.readError = readError
    }
}

public struct RuntimeVitalDBRecorderVisibilityRequest: Codable, Equatable, Sendable {
    public let vrcodes: [String]

    public init(vrcodes: [String]) {
        self.vrcodes = vrcodes
    }
}

public struct RuntimeGuestControlVitalDBRecorderActivityRead: Codable, Equatable, Sendable {
    public let state: RuntimeGuestControlReadState
    public let vrcode: String?
    public let buckets: [VitalDBRecorderActivityBucketRecord]
    public let readError: String?

    public init(
        state: RuntimeGuestControlReadState,
        vrcode: String? = nil,
        buckets: [VitalDBRecorderActivityBucketRecord] = [],
        readError: String? = nil
    ) {
        self.state = state
        self.vrcode = vrcode
        self.buckets = buckets
        self.readError = readError
    }
}

public enum RuntimeVitalRecorderVitalFileHistoryState: String, Codable, Equatable, Sendable {
    case loaded
    case partiallyLoaded
    case readFailed
}

public enum RuntimeVitalRecorderVitalFileOrigin: String, Codable, Equatable, Sendable {
    case nativeRecorderUpload
    case coldPathRecovery
}

public enum RuntimeVitalRecorderVitalFileStatus: String, Codable, Equatable, Sendable {
    case receiving
    case reconciling
    case indexed
    case failed
    case notRequested
    case publishRequested
    case publishing
    case published
    case unknownLegacy
}

public enum RuntimeVitalRecorderVitalFileAttributionState: String, Codable, Equatable, Sendable {
    case recorderDeclared
    case bedAssignmentResolved
    case recoveryReceipt
}

public struct RuntimeVitalRecorderVitalFileAttribution: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case state
        case assignmentID
        case resolvedAt
        case readError
    }

    public let state: RuntimeVitalRecorderVitalFileAttributionState
    public let assignmentID: String?
    public let resolvedAt: String
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderVitalFileAttributionState,
        assignmentID: String?,
        resolvedAt: String,
        readError: String?
    ) {
        self.state = state
        self.assignmentID = assignmentID
        self.resolvedAt = resolvedAt
        self.readError = readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderVitalFileAttributionState.self, forKey: .state)
        assignmentID = try container.decode(String?.self, forKey: .assignmentID)
        resolvedAt = try container.decode(String.self, forKey: .resolvedAt)
        readError = try container.decode(String?.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(assignmentID, forKey: .assignmentID)
        try container.encode(resolvedAt, forKey: .resolvedAt)
        try container.encode(readError, forKey: .readError)
    }
}

public struct RuntimeVitalRecorderVitalFileFailure: Codable, Equatable, Sendable {
    public let stage: String
    public let code: String
    public let message: String
    public let failedAt: String

    public init(
        stage: String,
        code: String,
        message: String,
        failedAt: String
    ) {
        self.stage = stage
        self.code = code
        self.message = message
        self.failedAt = failedAt
    }
}

public struct RuntimeVitalRecorderVitalFile: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case fileID
        case origin
        case vrcode
        case bedName
        case filename
        case sizeBytes
        case status
        case receivedAt
        case recordingStartedAt
        case recordingEndedAt
        case uploadedAt
        case attribution
        case failure
    }

    public var id: String { fileID }

    public let fileID: String
    public let origin: RuntimeVitalRecorderVitalFileOrigin
    public let vrcode: String
    public let bedName: String?
    public let filename: String
    public let sizeBytes: Int
    public let status: RuntimeVitalRecorderVitalFileStatus
    public let receivedAt: String
    public let recordingStartedAt: String?
    public let recordingEndedAt: String?
    public let uploadedAt: String?
    public let attribution: RuntimeVitalRecorderVitalFileAttribution
    public let failure: RuntimeVitalRecorderVitalFileFailure?

    public init(
        fileID: String,
        origin: RuntimeVitalRecorderVitalFileOrigin,
        vrcode: String,
        bedName: String?,
        filename: String,
        sizeBytes: Int,
        status: RuntimeVitalRecorderVitalFileStatus,
        receivedAt: String,
        recordingStartedAt: String?,
        recordingEndedAt: String?,
        uploadedAt: String?,
        attribution: RuntimeVitalRecorderVitalFileAttribution,
        failure: RuntimeVitalRecorderVitalFileFailure?
    ) {
        self.fileID = fileID
        self.origin = origin
        self.vrcode = vrcode
        self.bedName = bedName
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.status = status
        self.receivedAt = receivedAt
        self.recordingStartedAt = recordingStartedAt
        self.recordingEndedAt = recordingEndedAt
        self.uploadedAt = uploadedAt
        self.attribution = attribution
        self.failure = failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileID = try container.decode(String.self, forKey: .fileID)
        origin = try container.decode(RuntimeVitalRecorderVitalFileOrigin.self, forKey: .origin)
        vrcode = try container.decode(String.self, forKey: .vrcode)
        bedName = try container.decode(String?.self, forKey: .bedName)
        filename = try container.decode(String.self, forKey: .filename)
        sizeBytes = try container.decode(Int.self, forKey: .sizeBytes)
        status = try container.decode(RuntimeVitalRecorderVitalFileStatus.self, forKey: .status)
        receivedAt = try container.decode(String.self, forKey: .receivedAt)
        recordingStartedAt = try container.decode(String?.self, forKey: .recordingStartedAt)
        recordingEndedAt = try container.decode(String?.self, forKey: .recordingEndedAt)
        uploadedAt = try container.decode(String?.self, forKey: .uploadedAt)
        attribution = try container.decode(RuntimeVitalRecorderVitalFileAttribution.self, forKey: .attribution)
        failure = try container.decode(RuntimeVitalRecorderVitalFileFailure?.self, forKey: .failure)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileID, forKey: .fileID)
        try container.encode(origin, forKey: .origin)
        try container.encode(vrcode, forKey: .vrcode)
        try container.encode(bedName, forKey: .bedName)
        try container.encode(filename, forKey: .filename)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(status, forKey: .status)
        try container.encode(receivedAt, forKey: .receivedAt)
        try container.encode(recordingStartedAt, forKey: .recordingStartedAt)
        try container.encode(recordingEndedAt, forKey: .recordingEndedAt)
        try container.encode(uploadedAt, forKey: .uploadedAt)
        try container.encode(attribution, forKey: .attribution)
        try container.encode(failure, forKey: .failure)
    }
}

public struct RuntimeVitalRecorderVitalFileSourceRead: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case state
        case readError
    }

    public let state: RuntimeVitalRecorderVitalFileHistoryState
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderVitalFileHistoryState,
        readError: String?
    ) {
        self.state = state
        self.readError = readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderVitalFileHistoryState.self, forKey: .state)
        readError = try container.decode(String?.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(readError, forKey: .readError)
    }
}

public struct RuntimeVitalRecorderVitalFileSources: Codable, Equatable, Sendable {
    public let nativeUpload: RuntimeVitalRecorderVitalFileSourceRead
    public let coldPathRecovery: RuntimeVitalRecorderVitalFileSourceRead

    public init(
        nativeUpload: RuntimeVitalRecorderVitalFileSourceRead,
        coldPathRecovery: RuntimeVitalRecorderVitalFileSourceRead
    ) {
        self.nativeUpload = nativeUpload
        self.coldPathRecovery = coldPathRecovery
    }
}

public struct RuntimeVitalRecorderVitalFileHistory: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case state
        case vrcode
        case files
        case unattributedCount
        case sources
        case readError
    }

    public let state: RuntimeVitalRecorderVitalFileHistoryState
    public let vrcode: String
    public let files: [RuntimeVitalRecorderVitalFile]
    public let unattributedCount: Int
    public let sources: RuntimeVitalRecorderVitalFileSources
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderVitalFileHistoryState,
        vrcode: String,
        files: [RuntimeVitalRecorderVitalFile] = [],
        unattributedCount: Int = 0,
        sources: RuntimeVitalRecorderVitalFileSources,
        readError: String?
    ) {
        self.state = state
        self.vrcode = vrcode
        self.files = files
        self.unattributedCount = unattributedCount
        self.sources = sources
        self.readError = readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderVitalFileHistoryState.self, forKey: .state)
        vrcode = try container.decode(String.self, forKey: .vrcode)
        files = try container.decode([RuntimeVitalRecorderVitalFile].self, forKey: .files)
        unattributedCount = try container.decode(Int.self, forKey: .unattributedCount)
        sources = try container.decode(RuntimeVitalRecorderVitalFileSources.self, forKey: .sources)
        readError = try container.decode(String?.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(vrcode, forKey: .vrcode)
        try container.encode(files, forKey: .files)
        try container.encode(unattributedCount, forKey: .unattributedCount)
        try container.encode(sources, forKey: .sources)
        try container.encode(readError, forKey: .readError)
    }

    public static func failed(vrcode: String, readError: String) -> Self {
        let failedSource = RuntimeVitalRecorderVitalFileSourceRead(
            state: .readFailed,
            readError: readError
        )
        return Self(
            state: .readFailed,
            vrcode: vrcode,
            sources: RuntimeVitalRecorderVitalFileSources(
                nativeUpload: failedSource,
                coldPathRecovery: failedSource
            ),
            readError: readError
        )
    }
}

public struct RuntimeVitalDBBedVisibilityRequest: Codable, Equatable, Sendable {
    public let bedIDs: [String]

    public init(bedIDs: [String]) {
        self.bedIDs = bedIDs
    }
}

public enum RuntimeGuestControlVitalDBRelationshipReadState: String, Codable, Equatable, Sendable {
    case loaded
    case partiallyLoaded
    case readFailed
    case unavailable
    case failed
}

public struct RuntimeGuestControlVitalDBRelationshipRead: Codable, Equatable, Sendable {
    public let state: RuntimeGuestControlVitalDBRelationshipReadState
    public let assignments: [RuntimeVitalBedAssignmentRecord]
    public let events: [RuntimeVitalRelationshipEventRecord]
    public let eventTotalCount: Int
    public let eventLimit: Int
    public let readError: String?

    public init(
        state: RuntimeGuestControlVitalDBRelationshipReadState,
        assignments: [RuntimeVitalBedAssignmentRecord] = [],
        events: [RuntimeVitalRelationshipEventRecord] = [],
        eventTotalCount: Int? = nil,
        eventLimit: Int? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.assignments = assignments
        self.events = events
        self.eventTotalCount = eventTotalCount ?? events.count
        self.eventLimit = eventLimit ?? max(events.count, 100)
        self.readError = readError
    }
}

public struct RuntimeGuestControlErrorDocument: Codable, Equatable, Sendable {
    public let detail: String
    public let code: String
    public let availableServices: [String]?

    public init(detail: String, code: String, availableServices: [String]? = nil) {
        self.detail = detail
        self.code = code
        self.availableServices = availableServices
    }
}
