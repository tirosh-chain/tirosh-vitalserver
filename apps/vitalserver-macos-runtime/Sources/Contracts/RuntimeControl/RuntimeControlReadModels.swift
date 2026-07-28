import Contracts
import Foundation
import Errors

public struct RuntimeBackup: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let sizeBytes: UInt64?

    public init(path: String, sizeBytes: UInt64?) {
        self.path = path
        self.sizeBytes = sizeBytes
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public enum RuntimeLogSource: String, Codable, Hashable, Sendable {
    case helperMessage
    case install
    case command
    case launcher
    case vmLaunchOutput
    case vmLaunchError
    case proxyOutput
    case proxyError
    case watchdog
    case updateActivation
    case updateShutdown
    case containers
}

public struct RuntimeLogSourceOption: Codable, Identifiable, Sendable {
    public let id: RuntimeLogSource
    public let title: String

    public init(id: RuntimeLogSource, title: String) {
        self.id = id
        self.title = title
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeExplicitOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

public struct VitalFilesFolder: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum RuntimeOperationResourceReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
    case stale
}

public enum RuntimeHostResourceReadState: String, Codable, Equatable, Sendable {
    case loaded
    case missing
    case unavailable
    case failed
}

public struct RuntimeTimeAuthorityResourceRead: Codable, Equatable, Sendable {
    public let state: RuntimeHostResourceReadState
    public let document: RuntimeTimeAuthorityDocument?
    public let readError: String?

    public init(
        state: RuntimeHostResourceReadState,
        document: RuntimeTimeAuthorityDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.document = document
        self.readError = readError
    }
}

public struct RuntimeVMLifecycleResourceState: Codable, Equatable, Sendable {
    public let state: RuntimeHostResourceReadState
    public let document: RuntimeVMLifecycleDocument?
    public let readError: String?

    public init(
        state: RuntimeHostResourceReadState,
        document: RuntimeVMLifecycleDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.document = document
        self.readError = readError
    }

    public static func loaded(_ document: RuntimeVMLifecycleDocument) -> Self {
        Self(state: .loaded, document: document)
    }

    public static func missing(readError: String? = nil) -> Self {
        Self(state: .missing, readError: readError)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case document
        case readError
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeExplicitOptional(document, forKey: .document)
        try container.encodeExplicitOptional(readError, forKey: .readError)
    }
}

public enum RuntimeProviderCommandAction: String, Codable, Equatable, Sendable {
    case start
    case stop
    case restart
}

public enum RuntimeProviderCommandState: String, Codable, Equatable, Sendable {
    case completed
    case failed
}

public struct PlatformCommandFailure: Codable, Equatable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct RuntimeProviderCommandResponse: Codable, Equatable, Sendable {
    public let operationId: String
    public let action: RuntimeProviderCommandAction
    public let state: RuntimeProviderCommandState
    public let provider: RuntimeVMLifecycleResourceState
    public let failure: PlatformCommandFailure?

    public init(
        operationId: String,
        action: RuntimeProviderCommandAction,
        state: RuntimeProviderCommandState,
        provider: RuntimeVMLifecycleResourceState,
        failure: PlatformCommandFailure?
    ) {
        self.operationId = operationId
        self.action = action
        self.state = state
        self.provider = provider
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case operationId
        case action
        case state
        case provider
        case failure
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(action, forKey: .action)
        try container.encode(state, forKey: .state)
        try container.encode(provider, forKey: .provider)
        try container.encodeExplicitOptional(failure, forKey: .failure)
    }
}

public struct RuntimeGuestAddressResourceState: Codable, Equatable, Sendable {
    public let state: RuntimeHostResourceReadState
    public let read: RuntimeGuestAddressReadResult?
    public let readError: String?

    public init(
        state: RuntimeHostResourceReadState,
        read: RuntimeGuestAddressReadResult? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.read = read
        self.readError = readError
    }

    public static func loaded(_ read: RuntimeGuestAddressReadResult) -> Self {
        Self(state: .loaded, read: read)
    }

    public static func missing(readError: String? = nil) -> Self {
        Self(state: .missing, readError: readError)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }
}

public struct RuntimeInstallStateRead: Equatable, Sendable {
    public let state: RuntimeOperationResourceReadState
    public let document: RuntimeInstallStateDocument?
    public let error: String?

    private init(
        state: RuntimeOperationResourceReadState,
        document: RuntimeInstallStateDocument? = nil,
        error: String? = nil
    ) {
        self.state = state
        self.document = document
        self.error = error
    }

    public static func loaded(_ document: RuntimeInstallStateDocument) -> Self {
        Self(state: .loaded, document: document)
    }

    public static func unavailable() -> Self {
        Self(state: .unavailable)
    }

    public static func failed(_ error: String) -> Self {
        Self(state: .failed, error: error)
    }
}

public struct RuntimeInstallOperationState: Codable, Equatable, Sendable {
    public let state: RuntimeOperationResourceReadState
    public let document: RuntimeInstallStateDocument?
    public let readError: String?

    public init(
        state: RuntimeOperationResourceReadState,
        document: RuntimeInstallStateDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.document = document
        self.readError = readError
    }

    public static func loaded(_ document: RuntimeInstallStateDocument) -> Self {
        Self(state: .loaded, document: document)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }

    public static func fromInstallStateRead(_ read: RuntimeInstallStateRead) -> Self {
        switch read.state {
        case .loaded:
            guard let document = read.document else {
                return .failed(readError: "runtime install state read is loaded without a document")
            }
            return .loaded(document)
        case .failed:
            return .failed(readError: read.error ?? "runtime install state read failed")
        case .unavailable:
            return .unavailable()
        case .stale:
            return .failed(readError: "runtime install state read cannot be stale")
        }
    }

    enum CodingKeys: String, CodingKey {
        case state
        case document
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decode(RuntimeOperationResourceReadState.self, forKey: .state)
        self.document = try container.decodeRequiredNullable(RuntimeInstallStateDocument.self, forKey: .document)
        self.readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        try Self.validateDecoded(state: state, document: document, readError: readError, codingPath: decoder.codingPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let document {
            try container.encode(document, forKey: .document)
        } else {
            try container.encodeNil(forKey: .document)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func validateDecoded(
        state: RuntimeOperationResourceReadState,
        document: RuntimeInstallStateDocument?,
        readError: String?,
        codingPath: [CodingKey]
    ) throws {
        if state == .loaded && document == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "loaded install operation state must include document"
                )
            )
        }
        if state == .failed && readError.isBlankOrMissing {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "failed install operation state must include readError"
                )
            )
        }
    }
}

public struct RuntimeOperationLeaseState: Codable, Equatable, Sendable {
    public let state: RuntimeOperationResourceReadState
    public let document: RuntimeOperationLeaseDocument?
    public let readError: String?
    public let staleReason: String?

    public init(
        state: RuntimeOperationResourceReadState,
        document: RuntimeOperationLeaseDocument? = nil,
        readError: String? = nil,
        staleReason: String? = nil
    ) {
        self.state = state
        self.document = document
        self.readError = readError
        self.staleReason = staleReason
    }

    public static func loaded(_ document: RuntimeOperationLeaseDocument) -> Self {
        Self(state: .loaded, document: document)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }

    public static func stale(_ document: RuntimeOperationLeaseDocument, staleReason: String) -> Self {
        Self(state: .stale, document: document, staleReason: staleReason)
    }

    enum CodingKeys: String, CodingKey {
        case state
        case document
        case readError
        case staleReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decode(RuntimeOperationResourceReadState.self, forKey: .state)
        self.document = try container.decodeRequiredNullable(RuntimeOperationLeaseDocument.self, forKey: .document)
        self.readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        self.staleReason = try container.decodeRequiredNullable(String.self, forKey: .staleReason)
        try Self.validateDecoded(
            state: state,
            document: document,
            readError: readError,
            staleReason: staleReason,
            codingPath: decoder.codingPath
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let document {
            try container.encode(document, forKey: .document)
        } else {
            try container.encodeNil(forKey: .document)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
        if let staleReason {
            try container.encode(staleReason, forKey: .staleReason)
        } else {
            try container.encodeNil(forKey: .staleReason)
        }
    }

    private static func validateDecoded(
        state: RuntimeOperationResourceReadState,
        document: RuntimeOperationLeaseDocument?,
        readError: String?,
        staleReason: String?,
        codingPath: [CodingKey]
    ) throws {
        if (state == .loaded || state == .stale) && document == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "\(state.rawValue) operation lease state must include document"
                )
            )
        }
        if state == .failed && readError.isBlankOrMissing {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "failed operation lease state must include readError"
                )
            )
        }
        if state == .stale && staleReason.isBlankOrMissing {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "stale operation lease state must include staleReason"
                )
            )
        }
    }
}

public enum RuntimeOperationLeaseMutationState: String, Codable, Equatable, Sendable {
    case acquired
    case heartbeatRecorded
    case released
}

public struct RuntimeOperationLeaseMutationResponse: Codable, Equatable, Sendable {
    public let operationId: String
    public let state: RuntimeOperationLeaseMutationState

    public init(operationId: String, state: RuntimeOperationLeaseMutationState) {
        self.operationId = operationId
        self.state = state
    }
}

public struct RuntimeWorkflowOperationStateDocument: Codable, Equatable, Sendable {
    public let operationID: String
    public let operation: RuntimeOperation
    public let phase: RuntimeProgressPhase
    public let currentStep: RuntimeWorkflowStep?
    public let stepStatus: RuntimeProgressStepStatus?
    public let message: String
    public let reasonCodes: [String]
    public let startedAt: String
    public let updatedAt: String
    public let completedAt: String?
    public let revision: Int

    public init(
        operationID: String,
        operation: RuntimeOperation,
        phase: RuntimeProgressPhase,
        currentStep: RuntimeWorkflowStep?,
        stepStatus: RuntimeProgressStepStatus?,
        message: String,
        reasonCodes: [String],
        startedAt: String,
        updatedAt: String,
        completedAt: String?,
        revision: Int
    ) {
        self.operationID = operationID
        self.operation = operation
        self.phase = phase
        self.currentStep = currentStep
        self.stepStatus = stepStatus
        self.message = message
        self.reasonCodes = reasonCodes
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.revision = revision
    }
}

public struct RuntimeWorkflowOperationStateResource: Codable, Equatable, Sendable {
    public let state: RuntimeOperationResourceReadState
    public let document: RuntimeWorkflowOperationStateDocument?
    public let readError: String?

    public init(
        state: RuntimeOperationResourceReadState,
        document: RuntimeWorkflowOperationStateDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.document = document
        self.readError = readError
    }

    public static func loaded(_ document: RuntimeWorkflowOperationStateDocument) -> Self {
        Self(state: .loaded, document: document)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }

    enum CodingKeys: String, CodingKey {
        case state
        case document
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeOperationResourceReadState.self, forKey: .state)
        document = try container.decodeRequiredNullable(
            RuntimeWorkflowOperationStateDocument.self,
            forKey: .document
        )
        readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        if state == .loaded && document == nil {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "loaded workflow operation state must include document"
            ))
        }
        if state == .failed && readError.isBlankOrMissing {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "failed workflow operation state must include readError"
            ))
        }
        if state == .stale {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "workflow operation state cannot be stale"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let document {
            try container.encode(document, forKey: .document)
        } else {
            try container.encodeNil(forKey: .document)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public struct PlatformOperationState: Codable, Equatable, Sendable {
    public let activeOperation: RuntimeOperation?
    public let install: RuntimeInstallOperationState
    public let lease: RuntimeOperationLeaseState
    public let workflow: RuntimeWorkflowOperationStateResource

    public init(
        activeOperation: RuntimeOperation?,
        install: RuntimeInstallOperationState,
        lease: RuntimeOperationLeaseState = .unavailable(),
        workflow: RuntimeWorkflowOperationStateResource = .unavailable()
    ) {
        self.activeOperation = activeOperation ?? Self.resolvedActiveOperation(
            lease: lease,
            workflow: workflow
        )
        self.install = install
        self.lease = lease
        self.workflow = workflow
    }

    public var operationForPresentation: RuntimeOperation? {
        activeOperation
    }

    public var hasActiveOperation: Bool {
        activeOperation != nil
    }

    private static func resolvedActiveOperation(
        lease: RuntimeOperationLeaseState,
        workflow: RuntimeWorkflowOperationStateResource
    ) -> RuntimeOperation? {
        if lease.state == .loaded {
            return lease.document?.operation
        }
        guard workflow.state == .loaded, let document = workflow.document else {
            return nil
        }
        switch document.phase {
        case .completed, .failed, .cancelled:
            return nil
        case .preparing, .waitingForPrivilege, .running, .waiting, .recovering, .unknown:
            return document.operation
        }
    }

    enum CodingKeys: String, CodingKey {
        case activeOperation
        case install
        case lease
        case workflow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let activeOperation = try container.decodeRequiredNullable(RuntimeOperation.self, forKey: .activeOperation)
        let install = try container.decode(RuntimeInstallOperationState.self, forKey: .install)
        let lease = try container.decode(RuntimeOperationLeaseState.self, forKey: .lease)
        let workflow = try container.decode(RuntimeWorkflowOperationStateResource.self, forKey: .workflow)
        self.init(
            activeOperation: activeOperation,
            install: install,
            lease: lease,
            workflow: workflow
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let activeOperation {
            try container.encode(activeOperation, forKey: .activeOperation)
        } else {
            try container.encodeNil(forKey: .activeOperation)
        }
        try container.encode(install, forKey: .install)
        try container.encode(lease, forKey: .lease)
        try container.encode(workflow, forKey: .workflow)
    }
}

public struct RuntimeCommandResult: Codable, Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let outputIssues: [RuntimeCommandOutputIssue]
    public let executionIssue: RuntimeProcessExecutionIssue?

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputIssues: [RuntimeCommandOutputIssue] = [],
        executionIssue: RuntimeProcessExecutionIssue? = nil
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.outputIssues = outputIssues
        self.executionIssue = executionIssue
    }

    private enum CodingKeys: String, CodingKey {
        case exitCode
        case stdout
        case stderr
        case outputIssues
        case executionIssue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exitCode = try container.decode(Int32.self, forKey: .exitCode)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
        outputIssues = try container.decode([RuntimeCommandOutputIssue].self, forKey: .outputIssues)
        executionIssue = try container.decodeRequiredNullable(
            RuntimeProcessExecutionIssue.self,
            forKey: .executionIssue
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exitCode, forKey: .exitCode)
        try container.encode(stdout, forKey: .stdout)
        try container.encode(stderr, forKey: .stderr)
        try container.encode(outputIssues, forKey: .outputIssues)
        if let executionIssue {
            try container.encode(executionIssue, forKey: .executionIssue)
        } else {
            try container.encodeNil(forKey: .executionIssue)
        }
    }
}

public struct RuntimeLogExportResult: Codable, Equatable, Sendable {
    public let destination: URL
    public let cleanupIssue: String?

    public init(destination: URL, cleanupIssue: String? = nil) {
        self.destination = destination
        self.cleanupIssue = cleanupIssue
    }
}

public struct RuntimeReleaseInfo: Codable, Equatable, Sendable {
    public let helperVersion: String
    public let minimumUpdaterVersion: String
    public let vitalServerVersion: String
    public let services: [RuntimeBundledServiceInfo]

    public init(
        helperVersion: String,
        minimumUpdaterVersion: String,
        vitalServerVersion: String,
        services: [RuntimeBundledServiceInfo]
    ) {
        self.helperVersion = helperVersion
        self.minimumUpdaterVersion = minimumUpdaterVersion
        self.vitalServerVersion = vitalServerVersion
        self.services = services
    }
}

public struct RuntimeBundledServiceInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let image: String
    public let version: String

    public init(name: String, image: String, version: String) {
        self.name = name
        self.image = image
        self.version = version
    }
}

public struct RuntimeInstallInfo: Codable, Equatable, Sendable {
    public let appBundlePath: String?
    public let packageIdentifier: String?
    public let runtimeHomePath: String?
    public let backupsPath: String?
    public let redisBackupsPath: String?
    public let runtimeDataBackupsPath: String?

    public init(
        appBundlePath: String? = nil,
        packageIdentifier: String? = nil,
        runtimeHomePath: String? = nil,
        backupsPath: String? = nil,
        redisBackupsPath: String? = nil,
        runtimeDataBackupsPath: String? = nil
    ) {
        self.appBundlePath = appBundlePath
        self.packageIdentifier = packageIdentifier
        self.runtimeHomePath = runtimeHomePath
        self.backupsPath = backupsPath
        self.redisBackupsPath = redisBackupsPath
        self.runtimeDataBackupsPath = runtimeDataBackupsPath
    }
}

public struct RuntimeEventHistory: Codable, Equatable, Sendable {
    public let state: RuntimeEventPageState
    public let events: [RuntimeEventDocument]
    public let nextCursor: String?
    public let matchingCount: Int?
    public let readError: String?

    public init(
        events: [RuntimeEventDocument],
        nextCursor: String? = nil,
        matchingCount: Int? = nil,
        state: RuntimeEventPageState? = nil,
        readError: String? = nil
    ) {
        self.state = state ?? Self.defaultState(events: events, readError: readError)
        self.events = events
        self.nextCursor = nextCursor
        self.matchingCount = matchingCount
        self.readError = readError
    }

    public static func failed(readError: String) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [], state: .readFailed, readError: readError)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case events
        case nextCursor
        case matchingCount
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([RuntimeEventDocument].self, forKey: .events)
        nextCursor = try container.decodeRequiredNullable(String.self, forKey: .nextCursor)
        matchingCount = try container.decodeRequiredNullable(Int.self, forKey: .matchingCount)
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
        state = try container.decodeIfPresent(RuntimeEventPageState.self, forKey: .state)
            ?? Self.defaultState(events: events, readError: readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(events, forKey: .events)
        if let nextCursor {
            try container.encode(nextCursor, forKey: .nextCursor)
        } else {
            try container.encodeNil(forKey: .nextCursor)
        }
        if let matchingCount {
            try container.encode(matchingCount, forKey: .matchingCount)
        } else {
            try container.encodeNil(forKey: .matchingCount)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func defaultState(
        events: [RuntimeEventDocument],
        readError: String?
    ) -> RuntimeEventPageState {
        guard readError != nil else {
            return .loaded
        }
        return events.isEmpty ? .readFailed : .partiallyLoaded
    }
}

public enum RuntimeVitalRecorderSummarySource: String, Codable, Equatable, Sendable {
    case vitalDBObservation
    case unavailable
}

public struct RuntimeVitalRecorderReference: Codable, Equatable, Sendable {
    public let vrcode: String
    public let ip: String?
    public let lastSeenAt: String?
    public let source: RuntimeVitalRecorderSummarySource

    public init(
        vrcode: String,
        ip: String?,
        lastSeenAt: String?,
        source: RuntimeVitalRecorderSummarySource
    ) {
        self.vrcode = vrcode
        self.ip = ip
        self.lastSeenAt = lastSeenAt
        self.source = source
    }
}

public enum RuntimeVitalRecorderStatus: String, Codable, Equatable, Sendable {
    case online
    case stale
    case offline
    case notObserved
    case unknown
}

public struct RuntimeVitalRecorderActivityPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String { observedAt }
    public let observedAt: String
    public let windowSeconds: Int
    public let messageCount: Int
    public let byteCount: Int
    public let roomCount: Int
    public let messagesPerSecond: Double
    public let bytesPerSecond: Double
    public let buckets: [VitalDBRecorderActivityBucket]

    public init(
        observedAt: String,
        windowSeconds: Int,
        messageCount: Int,
        byteCount: Int,
        roomCount: Int,
        messagesPerSecond: Double,
        bytesPerSecond: Double,
        buckets: [VitalDBRecorderActivityBucket] = []
    ) {
        self.observedAt = observedAt
        self.windowSeconds = windowSeconds
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.roomCount = roomCount
        self.messagesPerSecond = messagesPerSecond
        self.bytesPerSecond = bytesPerSecond
        self.buckets = buckets
    }

    private enum CodingKeys: String, CodingKey {
        case observedAt
        case windowSeconds
        case messageCount
        case byteCount
        case roomCount
        case messagesPerSecond
        case bytesPerSecond
        case buckets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observedAt = try container.decode(String.self, forKey: .observedAt)
        windowSeconds = try container.decode(Int.self, forKey: .windowSeconds)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        roomCount = try container.decode(Int.self, forKey: .roomCount)
        messagesPerSecond = try container.decode(Double.self, forKey: .messagesPerSecond)
        bytesPerSecond = try container.decode(Double.self, forKey: .bytesPerSecond)
        buckets = try container.decode([VitalDBRecorderActivityBucket].self, forKey: .buckets)
    }
}

public enum RuntimeRecorderObservabilitySupportState: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unknown
}

public enum RuntimeRecorderObservabilityReportState: String, Codable, Equatable, Sendable {
    case notEvaluated
    case awaitingFirstReport
    case current
    case stale
    case missing
    case readFailed
}

public struct RuntimeRecorderObservability: Codable, Equatable, Sendable {
    public let state: String
    public let vrcode: String
    public let supportState: RuntimeRecorderObservabilitySupportState
    public let supportSource: String?
    public let reportState: RuntimeRecorderObservabilityReportState
    public let profileState: String?
    public let collectionState: String?
    public let latestObservationReceivedAt: String?
    public let lastBootStartedAt: String?
    public let readIssueCount: Int?
    public let operationalHealthState: RuntimeRecorderOperationalHealthState?
    public let operationalIssueCount: Int?
    public let expectedSince: String?
    public let recorderVersion: String?
    public let producerVersion: String?
    public let protocolVersion: String?
    public let readError: String?
}

public struct RuntimeVitalRecorderRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { vrcode }
    public let vrcode: String
    public let status: RuntimeVitalRecorderStatus
    public let lastIP: String?
    public let version: String?
    public let bedID: String?
    public let bedName: String?
    public let patientConnected: Bool?
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let observationCount: Int
    public let duplicateObservationCount: Int
    public let currentAnomalyCount: Int
    public let latestAnomalyKind: VitalDBAnomalyKind?
    public let latestAnomalySeverity: VitalDBAnomalySeverity?
    public let latestAnomalyMessage: String?
    public let latestAnomalyObservedAt: String?
    public let presentInLatestObservation: Bool
    public let visibility: RuntimeVitalRecordVisibility
    public let activityTimeline: [RuntimeVitalRecorderActivityPoint]?
    public let redisIPSync: RuntimeRecorderRedisIPSyncObservation?
    public let observability: RuntimeRecorderObservability?

    public init(
        vrcode: String,
        status: RuntimeVitalRecorderStatus,
        lastIP: String?,
        version: String?,
        bedID: String?,
        bedName: String?,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        duplicateObservationCount: Int = 0,
        currentAnomalyCount: Int,
        latestAnomalyKind: VitalDBAnomalyKind? = nil,
        latestAnomalySeverity: VitalDBAnomalySeverity?,
        latestAnomalyMessage: String? = nil,
        latestAnomalyObservedAt: String? = nil,
        presentInLatestObservation: Bool = true,
        visibility: RuntimeVitalRecordVisibility = .visible,
        redisIPSync: RuntimeRecorderRedisIPSyncObservation? = nil,
        observability: RuntimeRecorderObservability? = nil
    ) {
        self.init(
            vrcode: vrcode,
            status: status,
            lastIP: lastIP,
            version: version,
            bedID: bedID,
            bedName: bedName,
            patientConnected: patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt,
            observationCount: observationCount,
            duplicateObservationCount: duplicateObservationCount,
            currentAnomalyCount: currentAnomalyCount,
            latestAnomalyKind: latestAnomalyKind,
            latestAnomalySeverity: latestAnomalySeverity,
            latestAnomalyMessage: latestAnomalyMessage,
            latestAnomalyObservedAt: latestAnomalyObservedAt,
            presentInLatestObservation: presentInLatestObservation,
            visibility: visibility,
            activityTimeline: nil,
            redisIPSync: redisIPSync,
            observability: observability
        )
    }

    public init(
        vrcode: String,
        status: RuntimeVitalRecorderStatus,
        lastIP: String?,
        version: String?,
        bedID: String?,
        bedName: String?,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        duplicateObservationCount: Int,
        currentAnomalyCount: Int,
        latestAnomalyKind: VitalDBAnomalyKind?,
        latestAnomalySeverity: VitalDBAnomalySeverity?,
        latestAnomalyMessage: String?,
        latestAnomalyObservedAt: String?,
        presentInLatestObservation: Bool,
        visibility: RuntimeVitalRecordVisibility = .visible,
        activityTimeline: [RuntimeVitalRecorderActivityPoint]?,
        redisIPSync: RuntimeRecorderRedisIPSyncObservation? = nil,
        observability: RuntimeRecorderObservability? = nil
    ) {
        self.vrcode = vrcode
        self.status = status
        self.lastIP = lastIP
        self.version = version
        self.bedID = bedID
        self.bedName = bedName
        self.patientConnected = patientConnected
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.observationCount = observationCount
        self.duplicateObservationCount = duplicateObservationCount
        self.currentAnomalyCount = currentAnomalyCount
        self.latestAnomalyKind = latestAnomalyKind
        self.latestAnomalySeverity = latestAnomalySeverity
        self.latestAnomalyMessage = latestAnomalyMessage
        self.latestAnomalyObservedAt = latestAnomalyObservedAt
        self.presentInLatestObservation = presentInLatestObservation
        self.visibility = visibility
        self.activityTimeline = activityTimeline
        self.redisIPSync = redisIPSync
        self.observability = observability
    }

    private enum CodingKeys: String, CodingKey {
        case vrcode
        case status
        case lastIP
        case version
        case bedID
        case bedName
        case patientConnected
        case firstSeenAt
        case lastSeenAt
        case observationCount
        case duplicateObservationCount
        case currentAnomalyCount
        case latestAnomalyKind
        case latestAnomalySeverity
        case latestAnomalyMessage
        case latestAnomalyObservedAt
        case presentInLatestObservation
        case visibility
        case activityTimeline
        case redisIPSync
        case observability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vrcode: try container.decode(String.self, forKey: .vrcode),
            status: try container.decode(RuntimeVitalRecorderStatus.self, forKey: .status),
            lastIP: try container.decodeIfPresent(String.self, forKey: .lastIP),
            version: try container.decodeIfPresent(String.self, forKey: .version),
            bedID: try container.decodeIfPresent(String.self, forKey: .bedID),
            bedName: try container.decodeIfPresent(String.self, forKey: .bedName),
            patientConnected: try container.decodeIfPresent(Bool.self, forKey: .patientConnected),
            firstSeenAt: try container.decodeIfPresent(String.self, forKey: .firstSeenAt),
            lastSeenAt: try container.decodeIfPresent(String.self, forKey: .lastSeenAt),
            observationCount: try container.decode(Int.self, forKey: .observationCount),
            duplicateObservationCount: try container.decode(Int.self, forKey: .duplicateObservationCount),
            currentAnomalyCount: try container.decode(Int.self, forKey: .currentAnomalyCount),
            latestAnomalyKind: try container.decodeIfPresent(VitalDBAnomalyKind.self, forKey: .latestAnomalyKind),
            latestAnomalySeverity: try container.decodeIfPresent(
                VitalDBAnomalySeverity.self,
                forKey: .latestAnomalySeverity
            ),
            latestAnomalyMessage: try container.decodeIfPresent(String.self, forKey: .latestAnomalyMessage),
            latestAnomalyObservedAt: try container.decodeIfPresent(String.self, forKey: .latestAnomalyObservedAt),
            presentInLatestObservation: try container.decode(Bool.self, forKey: .presentInLatestObservation),
            visibility: try container.decode(RuntimeVitalRecordVisibility.self, forKey: .visibility),
            activityTimeline: try container.decodeIfPresent(
                [RuntimeVitalRecorderActivityPoint].self,
                forKey: .activityTimeline
            ),
            redisIPSync: try container.decodeIfPresent(
                RuntimeRecorderRedisIPSyncObservation.self,
                forKey: .redisIPSync
            ),
            observability: try container.decodeIfPresent(
                RuntimeRecorderObservability.self,
                forKey: .observability
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vrcode, forKey: .vrcode)
        try container.encode(status, forKey: .status)
        try container.encodeExplicitOptional(lastIP, forKey: .lastIP)
        try container.encodeExplicitOptional(version, forKey: .version)
        try container.encodeExplicitOptional(bedID, forKey: .bedID)
        try container.encodeExplicitOptional(bedName, forKey: .bedName)
        try container.encodeExplicitOptional(patientConnected, forKey: .patientConnected)
        try container.encodeExplicitOptional(firstSeenAt, forKey: .firstSeenAt)
        try container.encodeExplicitOptional(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(observationCount, forKey: .observationCount)
        try container.encode(duplicateObservationCount, forKey: .duplicateObservationCount)
        try container.encode(currentAnomalyCount, forKey: .currentAnomalyCount)
        try container.encodeExplicitOptional(latestAnomalyKind, forKey: .latestAnomalyKind)
        try container.encodeExplicitOptional(latestAnomalySeverity, forKey: .latestAnomalySeverity)
        try container.encodeExplicitOptional(latestAnomalyMessage, forKey: .latestAnomalyMessage)
        try container.encodeExplicitOptional(latestAnomalyObservedAt, forKey: .latestAnomalyObservedAt)
        try container.encode(presentInLatestObservation, forKey: .presentInLatestObservation)
        try container.encode(visibility, forKey: .visibility)
        try container.encodeExplicitOptional(activityTimeline, forKey: .activityTimeline)
        try container.encodeExplicitOptional(redisIPSync, forKey: .redisIPSync)
        try container.encodeExplicitOptional(observability, forKey: .observability)
    }
}

public struct RuntimeVitalBedRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bedID }
    public let bedID: String
    public let name: String?
    public let vrcode: String?
    public let linkedRecorderStatus: RuntimeVitalRecorderStatus?
    public let linkedRecorderIP: String?
    public let linkedRecorderVersion: String?
    public let linkedRecorderLastSeenAt: String?
    public let status: RuntimeVitalBedStatus
    public let patientConnected: Bool?
    public let firstSeenAt: String?
    public let lastSeenAt: String?
    public let observationCount: Int
    public let duplicateObservationCount: Int
    public let currentAnomalyCount: Int
    public let latestAnomalyKind: VitalDBAnomalyKind?
    public let latestAnomalySeverity: VitalDBAnomalySeverity?
    public let latestAnomalyMessage: String?
    public let latestAnomalyObservedAt: String?
    public let visibility: RuntimeVitalRecordVisibility

    public init(
        bedID: String,
        name: String?,
        vrcode: String?,
        linkedRecorderStatus: RuntimeVitalRecorderStatus? = nil,
        linkedRecorderIP: String? = nil,
        linkedRecorderVersion: String? = nil,
        linkedRecorderLastSeenAt: String? = nil,
        status: RuntimeVitalBedStatus,
        patientConnected: Bool?,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observationCount: Int,
        duplicateObservationCount: Int = 0,
        currentAnomalyCount: Int,
        latestAnomalyKind: VitalDBAnomalyKind? = nil,
        latestAnomalySeverity: VitalDBAnomalySeverity?,
        latestAnomalyMessage: String? = nil,
        latestAnomalyObservedAt: String? = nil,
        visibility: RuntimeVitalRecordVisibility = .visible
    ) {
        self.bedID = bedID
        self.name = name
        self.vrcode = vrcode
        self.linkedRecorderStatus = linkedRecorderStatus
        self.linkedRecorderIP = linkedRecorderIP
        self.linkedRecorderVersion = linkedRecorderVersion
        self.linkedRecorderLastSeenAt = linkedRecorderLastSeenAt
        self.status = status
        self.patientConnected = patientConnected
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.observationCount = observationCount
        self.duplicateObservationCount = duplicateObservationCount
        self.currentAnomalyCount = currentAnomalyCount
        self.latestAnomalyKind = latestAnomalyKind
        self.latestAnomalySeverity = latestAnomalySeverity
        self.latestAnomalyMessage = latestAnomalyMessage
        self.latestAnomalyObservedAt = latestAnomalyObservedAt
        self.visibility = visibility
    }

    private enum CodingKeys: String, CodingKey {
        case bedID
        case name
        case vrcode
        case linkedRecorderStatus
        case linkedRecorderIP
        case linkedRecorderVersion
        case linkedRecorderLastSeenAt
        case status
        case patientConnected
        case firstSeenAt
        case lastSeenAt
        case observationCount
        case duplicateObservationCount
        case currentAnomalyCount
        case latestAnomalyKind
        case latestAnomalySeverity
        case latestAnomalyMessage
        case latestAnomalyObservedAt
        case visibility
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bedID: try container.decode(String.self, forKey: .bedID),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            vrcode: try container.decodeIfPresent(String.self, forKey: .vrcode),
            linkedRecorderStatus: try container.decodeIfPresent(
                RuntimeVitalRecorderStatus.self,
                forKey: .linkedRecorderStatus
            ),
            linkedRecorderIP: try container.decodeIfPresent(String.self, forKey: .linkedRecorderIP),
            linkedRecorderVersion: try container.decodeIfPresent(String.self, forKey: .linkedRecorderVersion),
            linkedRecorderLastSeenAt: try container.decodeIfPresent(String.self, forKey: .linkedRecorderLastSeenAt),
            status: try container.decode(RuntimeVitalBedStatus.self, forKey: .status),
            patientConnected: try container.decodeIfPresent(Bool.self, forKey: .patientConnected),
            firstSeenAt: try container.decodeIfPresent(String.self, forKey: .firstSeenAt),
            lastSeenAt: try container.decodeIfPresent(String.self, forKey: .lastSeenAt),
            observationCount: try container.decode(Int.self, forKey: .observationCount),
            duplicateObservationCount: try container.decode(Int.self, forKey: .duplicateObservationCount),
            currentAnomalyCount: try container.decode(Int.self, forKey: .currentAnomalyCount),
            latestAnomalyKind: try container.decodeIfPresent(VitalDBAnomalyKind.self, forKey: .latestAnomalyKind),
            latestAnomalySeverity: try container.decodeIfPresent(
                VitalDBAnomalySeverity.self,
                forKey: .latestAnomalySeverity
            ),
            latestAnomalyMessage: try container.decodeIfPresent(String.self, forKey: .latestAnomalyMessage),
            latestAnomalyObservedAt: try container.decodeIfPresent(String.self, forKey: .latestAnomalyObservedAt),
            visibility: try container.decode(RuntimeVitalRecordVisibility.self, forKey: .visibility)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bedID, forKey: .bedID)
        try container.encodeExplicitOptional(name, forKey: .name)
        try container.encodeExplicitOptional(vrcode, forKey: .vrcode)
        try container.encodeExplicitOptional(linkedRecorderStatus, forKey: .linkedRecorderStatus)
        try container.encodeExplicitOptional(linkedRecorderIP, forKey: .linkedRecorderIP)
        try container.encodeExplicitOptional(linkedRecorderVersion, forKey: .linkedRecorderVersion)
        try container.encodeExplicitOptional(linkedRecorderLastSeenAt, forKey: .linkedRecorderLastSeenAt)
        try container.encode(status, forKey: .status)
        try container.encodeExplicitOptional(patientConnected, forKey: .patientConnected)
        try container.encodeExplicitOptional(firstSeenAt, forKey: .firstSeenAt)
        try container.encodeExplicitOptional(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(observationCount, forKey: .observationCount)
        try container.encode(duplicateObservationCount, forKey: .duplicateObservationCount)
        try container.encode(currentAnomalyCount, forKey: .currentAnomalyCount)
        try container.encodeExplicitOptional(latestAnomalyKind, forKey: .latestAnomalyKind)
        try container.encodeExplicitOptional(latestAnomalySeverity, forKey: .latestAnomalySeverity)
        try container.encodeExplicitOptional(latestAnomalyMessage, forKey: .latestAnomalyMessage)
        try container.encodeExplicitOptional(latestAnomalyObservedAt, forKey: .latestAnomalyObservedAt)
        try container.encode(visibility, forKey: .visibility)
    }
}

public enum RuntimeVitalRecorderHistoryState: String, Codable, Equatable, Sendable {
    case loaded
    case partiallyLoaded
    case readFailed
}

public struct RuntimeVitalBedHistory: Codable, Equatable, Sendable {
    public let state: RuntimeVitalRecorderHistoryState
    public let updatedAt: String?
    public let beds: [RuntimeVitalBedRecord]
    public let summary: RuntimeVitalBedHistorySummary
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderHistoryState? = nil,
        updatedAt: String? = nil,
        beds: [RuntimeVitalBedRecord] = [],
        summary: RuntimeVitalBedHistorySummary? = nil,
        readError: String? = nil
    ) {
        self.state = state ?? Self.defaultState(beds: beds, readError: readError)
        self.updatedAt = updatedAt
        self.beds = beds
        self.summary = summary ?? RuntimeVitalBedHistorySummary(beds: beds)
        self.readError = readError
    }

    public static func failed(readError: String) -> RuntimeVitalBedHistory {
        RuntimeVitalBedHistory(state: .readFailed, readError: readError)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case updatedAt
        case beds
        case summary
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderHistoryState.self, forKey: .state)
        updatedAt = try container.decodeRequiredNullable(String.self, forKey: .updatedAt)
        beds = try container.decode([RuntimeVitalBedRecord].self, forKey: .beds)
        summary = try container.decode(RuntimeVitalBedHistorySummary.self, forKey: .summary)
        readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let updatedAt {
            try container.encode(updatedAt, forKey: .updatedAt)
        } else {
            try container.encodeNil(forKey: .updatedAt)
        }
        try container.encode(beds, forKey: .beds)
        try container.encode(summary, forKey: .summary)
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func defaultState(
        beds: [RuntimeVitalBedRecord],
        readError: String?
    ) -> RuntimeVitalRecorderHistoryState {
        guard readError != nil else {
            return .loaded
        }
        return beds.isEmpty ? .readFailed : .partiallyLoaded
    }
}

public struct RuntimeVitalRecorderHistory: Codable, Equatable, Sendable {
    public let state: RuntimeVitalRecorderHistoryState
    public let updatedAt: String?
    public let recorders: [RuntimeVitalRecorderRecord]
    public let beds: [RuntimeVitalBedRecord]
    public let summary: RuntimeVitalRecorderHistorySummary
    public let activityHistory: RuntimeVitalRecorderActivityHistory
    public let recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderHistoryState? = nil,
        updatedAt: String? = nil,
        recorders: [RuntimeVitalRecorderRecord] = [],
        beds: [RuntimeVitalBedRecord] = [],
        summary: RuntimeVitalRecorderHistorySummary? = nil,
        activityHistory: RuntimeVitalRecorderActivityHistory = .notProvided(),
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult? = nil,
        readError: String? = nil
    ) {
        self.state = state ?? Self.defaultState(
            recorders: recorders,
            beds: beds,
            readError: readError
        )
        self.updatedAt = updatedAt
        self.recorders = recorders
        self.beds = beds
        self.summary = summary ?? RuntimeVitalRecorderHistorySummary(
            recorders: recorders,
            beds: beds
        )
        self.activityHistory = activityHistory
        self.recorderIngressStatusRead = recorderIngressStatusRead
        self.readError = readError
    }

    public static func failed(readError: String) -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory(state: .readFailed, readError: readError)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case updatedAt
        case recorders
        case beds
        case summary
        case activityHistory
        case recorderIngressStatusRead
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderHistoryState.self, forKey: .state)
        updatedAt = try container.decodeRequiredNullable(String.self, forKey: .updatedAt)
        recorders = try container.decode([RuntimeVitalRecorderRecord].self, forKey: .recorders)
        beds = try container.decode([RuntimeVitalBedRecord].self, forKey: .beds)
        summary = try container.decode(RuntimeVitalRecorderHistorySummary.self, forKey: .summary)
        activityHistory = try container.decode(
            RuntimeVitalRecorderActivityHistory.self,
            forKey: .activityHistory
        )
        recorderIngressStatusRead = try container.decodeRequiredNullable(
            RuntimeRecorderIngressStatusReadResult.self,
            forKey: .recorderIngressStatusRead
        )
        readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let updatedAt {
            try container.encode(updatedAt, forKey: .updatedAt)
        } else {
            try container.encodeNil(forKey: .updatedAt)
        }
        try container.encode(recorders, forKey: .recorders)
        try container.encode(beds, forKey: .beds)
        try container.encode(summary, forKey: .summary)
        try container.encode(activityHistory, forKey: .activityHistory)
        if let recorderIngressStatusRead {
            try container.encode(recorderIngressStatusRead, forKey: .recorderIngressStatusRead)
        } else {
            try container.encodeNil(forKey: .recorderIngressStatusRead)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func defaultState(
        recorders: [RuntimeVitalRecorderRecord],
        beds: [RuntimeVitalBedRecord],
        readError: String?
    ) -> RuntimeVitalRecorderHistoryState {
        guard readError != nil else {
            return .loaded
        }
        return recorders.isEmpty && beds.isEmpty ? .readFailed : .partiallyLoaded
    }

    public init(
        observations: [VitalDBObservationDocument],
        statusEvaluationTime: String? = nil
    ) {
        self.init(
            observations: observations,
            projectedActivityBuckets: nil,
            statusEvaluationTime: statusEvaluationTime
        )
    }

    public init(
        observations: [VitalDBObservationDocument],
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?,
        statusEvaluationTime: String? = nil
    ) {
        self.init(
            observations: observations,
            projectedActivityBuckets: nil,
            recorderIngressStatusRead: recorderIngressStatusRead,
            statusEvaluationTime: statusEvaluationTime
        )
    }

    public init(
        observations: [VitalDBObservationDocument],
        activityBuckets: [VitalDBRecorderActivityBucketRecord],
        activityHistory: RuntimeVitalRecorderActivityHistory? = nil,
        readError: String? = nil,
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult? = nil,
        statusEvaluationTime: String? = nil
    ) {
        self.init(
            observations: observations,
            projectedActivityBuckets: activityBuckets,
            activityHistory: activityHistory,
            readError: readError,
            recorderIngressStatusRead: recorderIngressStatusRead,
            statusEvaluationTime: statusEvaluationTime
        )
    }

    private init(
        observations: [VitalDBObservationDocument],
        projectedActivityBuckets activityBuckets: [VitalDBRecorderActivityBucketRecord]?,
        activityHistory: RuntimeVitalRecorderActivityHistory? = nil,
        readError: String? = nil,
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult? = nil,
        statusEvaluationTime: String? = nil
    ) {
        let ordered = observations.sorted { $0.observedAt < $1.observedAt }
        guard let latestObservation = ordered.last else {
            self.init(
                activityHistory: activityHistory ?? .notProvided(readError: readError),
                recorderIngressStatusRead: recorderIngressStatusRead,
                readError: readError
            )
            return
        }
        let recorderStatusEvaluationTime = statusEvaluationTime ?? latestObservation.observedAt

        var builders: [String: RecorderBuilder] = [:]
        var bedBuilders: [String: BedBuilder] = [:]
        var recorderDuplicateObservationCounts: [String: Int] = [:]
        var bedDuplicateObservationCounts: [String: Int] = [:]
        for observation in ordered {
            recorderDuplicateObservationCounts.merge(
                duplicateRecorderObservationCounts(observation.recorders),
                uniquingKeysWith: +
            )
            bedDuplicateObservationCounts.merge(
                duplicateBedObservationCounts(observation.beds),
                uniquingKeysWith: +
            )
            let bedsByRecorder = Dictionary(
                observation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
                uniquingKeysWith: { _, latest in latest }
            )
            for recorder in uniqueRecordersByVrcode(observation.recorders) {
                var builder = builders[recorder.vrcode] ?? RecorderBuilder(vrcode: recorder.vrcode)
                builder.observe(
                    recorder: recorder,
                    bed: bedsByRecorder[recorder.vrcode],
                    observedAt: observation.observedAt
                )
                builders[recorder.vrcode] = builder
            }
            for bed in uniqueBedsByID(observation.beds) {
                var builder = bedBuilders[bed.bedID] ?? BedBuilder(bedID: bed.bedID)
                builder.observe(bed: bed, observedAt: observation.observedAt)
                bedBuilders[bed.bedID] = builder
            }
        }

        let latestRecorders = Dictionary(
            uniqueRecordersByVrcode(latestObservation.recorders).map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestBedsByRecorder = Dictionary(
            latestObservation.beds.compactMap { bed in bed.vrcode.map { ($0, bed) } },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestBeds = Dictionary(
            uniqueBedsByID(latestObservation.beds).map { ($0.bedID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let latestAnomaliesBySubject = Dictionary(grouping: latestObservation.anomalies, by: \.subject)
        let projectedActivityByVrcode = activityBuckets.map(projectedActivityTimelineByVrcode)
        let redisIPSyncByVrcode = recorderRedisIPSyncByVrcode(recorderIngressStatusRead)

        let unsortedRecords: [RuntimeVitalRecorderRecord] = builders.values.map { builder in
            let latestRecorder = latestRecorders[builder.vrcode]
            let latestBed = latestBedsByRecorder[builder.vrcode]
            let anomalies = latestAnomaliesBySubject[builder.vrcode] ?? []
            return builder.record(
                latestRecorder: latestRecorder,
                latestBed: latestBed,
                latestObservationObservedAt: recorderStatusEvaluationTime,
                recorderOnlineThresholdSeconds: latestObservation.recorderOnlineThresholdSeconds,
                currentAnomalies: anomalies,
                duplicateObservationCount: recorderDuplicateObservationCounts[builder.vrcode, default: 0],
                activityTimeline: projectedActivityByVrcode?[builder.vrcode],
                redisIPSync: redisIPSyncByVrcode[builder.vrcode] ?? defaultRecorderRedisIPSync(
                    vrcode: builder.vrcode,
                    recorderIngressStatusRead: recorderIngressStatusRead
                )
            )
        }

        let records = unsortedRecords.sorted { lhs, rhs in
            switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
            case .orderedDescending:
                return true
            case .orderedAscending:
                return false
            case .orderedSame:
                return lhs.vrcode < rhs.vrcode
            }
        }
        let recorderRecordsByVrcode = Dictionary(
            records.map { ($0.vrcode, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let beds = bedBuilders.values.map { builder in
            let latestBed = latestBeds[builder.bedID]
            let anomalies = latestAnomaliesBySubject[builder.bedID] ?? []
            let linkedRecorder = (latestBed?.vrcode ?? builder.vrcode)
                .flatMap { recorderRecordsByVrcode[$0] }
            return builder.record(
                latestBed: latestBed,
                linkedRecorder: linkedRecorder,
                currentAnomalies: anomalies,
                duplicateObservationCount: bedDuplicateObservationCounts[builder.bedID, default: 0]
            )
        }
        .sorted { lhs, rhs in
            switch compareReportedTimestamp(lhs.lastSeenAt, rhs.lastSeenAt) {
            case .orderedDescending:
                return true
            case .orderedAscending:
                return false
            case .orderedSame:
                return lhs.bedID < rhs.bedID
            }
        }

        self.init(
            updatedAt: latestObservation.observedAt,
            recorders: records,
            beds: beds,
            summary: RuntimeVitalRecorderHistorySummary(
                recorders: records,
                beds: beds
            ),
            activityHistory: activityHistory
                ?? activityBuckets.map { RuntimeVitalRecorderActivityHistory.fromProjection($0) }
                ?? .notProvided(),
            recorderIngressStatusRead: recorderIngressStatusRead,
            readError: readError
        )
    }
}

public struct RuntimeVitalRecorderHistorySummary: Codable, Equatable, Sendable {
    public let knownRecorders: Int
    public let currentRecorders: Int
    public let onlineRecorders: Int
    public let staleRecorders: Int
    public let recorderAnomalies: Int
    public let knownBeds: Int
    public let onlineBeds: Int
    public let staleBeds: Int
    public let bedAssignments: Int
    public let bedAnomalies: Int

    public init(
        knownRecorders: Int = 0,
        currentRecorders: Int = 0,
        onlineRecorders: Int = 0,
        staleRecorders: Int = 0,
        recorderAnomalies: Int = 0,
        knownBeds: Int = 0,
        onlineBeds: Int = 0,
        staleBeds: Int = 0,
        bedAssignments: Int = 0,
        bedAnomalies: Int = 0
    ) {
        self.knownRecorders = knownRecorders
        self.currentRecorders = currentRecorders
        self.onlineRecorders = onlineRecorders
        self.staleRecorders = staleRecorders
        self.recorderAnomalies = recorderAnomalies
        self.knownBeds = knownBeds
        self.onlineBeds = onlineBeds
        self.staleBeds = staleBeds
        self.bedAssignments = bedAssignments
        self.bedAnomalies = bedAnomalies
    }

    public init(
        recorders: [RuntimeVitalRecorderRecord],
        beds: [RuntimeVitalBedRecord]
    ) {
        let currentRecorders = recorders.filter(\.presentInLatestObservation)
        let currentBeds = beds.filter { $0.status != .notObserved }
        self.init(
            knownRecorders: recorders.count,
            currentRecorders: currentRecorders.count,
            onlineRecorders: currentRecorders.filter { $0.status == .online }.count,
            staleRecorders: currentRecorders.filter { $0.status == .stale }.count,
            recorderAnomalies: currentRecorders.reduce(0) { $0 + $1.currentAnomalyCount },
            knownBeds: beds.count,
            onlineBeds: currentBeds.filter { $0.status == .online }.count,
            staleBeds: currentBeds.filter { $0.status == .stale }.count,
            bedAssignments: currentBeds.filter { $0.vrcode?.isEmpty == false }.count,
            bedAnomalies: currentBeds.reduce(0) { $0 + $1.currentAnomalyCount }
        )
    }
}

public struct RuntimeVitalBedHistorySummary: Codable, Equatable, Sendable {
    public let knownBeds: Int
    public let onlineBeds: Int
    public let staleBeds: Int
    public let bedAssignments: Int
    public let bedAnomalies: Int

    public init(
        knownBeds: Int = 0,
        onlineBeds: Int = 0,
        staleBeds: Int = 0,
        bedAssignments: Int = 0,
        bedAnomalies: Int = 0
    ) {
        self.knownBeds = knownBeds
        self.onlineBeds = onlineBeds
        self.staleBeds = staleBeds
        self.bedAssignments = bedAssignments
        self.bedAnomalies = bedAnomalies
    }

    public init(beds: [RuntimeVitalBedRecord]) {
        let currentBeds = beds.filter { $0.status != .notObserved }
        self.init(
            knownBeds: beds.count,
            onlineBeds: currentBeds.filter { $0.status == .online }.count,
            staleBeds: currentBeds.filter { $0.status == .stale }.count,
            bedAssignments: currentBeds.filter { $0.vrcode?.isEmpty == false }.count,
            bedAnomalies: currentBeds.reduce(0) { $0 + $1.currentAnomalyCount }
        )
    }

    public init(recorderSummary: RuntimeVitalRecorderHistorySummary) {
        self.init(
            knownBeds: recorderSummary.knownBeds,
            onlineBeds: recorderSummary.onlineBeds,
            staleBeds: recorderSummary.staleBeds,
            bedAssignments: recorderSummary.bedAssignments,
            bedAnomalies: recorderSummary.bedAnomalies
        )
    }
}

public struct RuntimeVitalRecorderActivityHistory: Codable, Equatable, Sendable {
    public let source: RuntimeVitalRecorderActivityHistorySource
    public let bucketCount: Int
    public let earliestBucketStartedAt: String?
    public let latestBucketStartedAt: String?
    public let readError: String?

    public init(
        source: RuntimeVitalRecorderActivityHistorySource,
        bucketCount: Int,
        earliestBucketStartedAt: String? = nil,
        latestBucketStartedAt: String? = nil,
        readError: String? = nil
    ) {
        self.source = source
        self.bucketCount = bucketCount
        self.earliestBucketStartedAt = earliestBucketStartedAt
        self.latestBucketStartedAt = latestBucketStartedAt
        self.readError = readError
    }

    public static func fromProjection(
        _ buckets: [VitalDBRecorderActivityBucketRecord],
        readError: String? = nil
    ) -> RuntimeVitalRecorderActivityHistory {
        RuntimeVitalRecorderActivityHistory(
            source: .readModelProjection,
            bucketCount: buckets.count,
            earliestBucketStartedAt: buckets.map(\.bucketStartedAt).min(),
            latestBucketStartedAt: buckets.map(\.bucketStartedAt).max(),
            readError: readError
        )
    }

    public static func unavailable(readError: String? = nil) -> RuntimeVitalRecorderActivityHistory {
        RuntimeVitalRecorderActivityHistory(
            source: .unavailable,
            bucketCount: 0,
            readError: readError
        )
    }

    public static func notProvided(readError: String? = nil) -> RuntimeVitalRecorderActivityHistory {
        RuntimeVitalRecorderActivityHistory(
            source: .notProvided,
            bucketCount: 0,
            readError: readError
        )
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case bucketCount
        case earliestBucketStartedAt
        case latestBucketStartedAt
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(RuntimeVitalRecorderActivityHistorySource.self, forKey: .source)
        bucketCount = try container.decode(Int.self, forKey: .bucketCount)
        earliestBucketStartedAt = try container.decodeRequiredNullable(
            String.self,
            forKey: .earliestBucketStartedAt
        )
        latestBucketStartedAt = try container.decodeRequiredNullable(
            String.self,
            forKey: .latestBucketStartedAt
        )
        readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(bucketCount, forKey: .bucketCount)
        if let earliestBucketStartedAt {
            try container.encode(earliestBucketStartedAt, forKey: .earliestBucketStartedAt)
        } else {
            try container.encodeNil(forKey: .earliestBucketStartedAt)
        }
        if let latestBucketStartedAt {
            try container.encode(latestBucketStartedAt, forKey: .latestBucketStartedAt)
        } else {
            try container.encodeNil(forKey: .latestBucketStartedAt)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public enum RuntimeVitalRecorderActivityHistorySource: String, Codable, Equatable, Sendable {
    case readModelProjection
    case unavailable
    case notProvided
}

public enum RuntimeVitalRecorderActivityWindowState: String, Codable, Equatable, Sendable {
    case loaded
    case empty
    case invalidRequest
    case readFailed
}

public enum RuntimeVitalRecorderActivityWindowPeriod: String, Codable, CaseIterable, Equatable, Sendable {
    case lastHour
    case last4Hours
    case last8Hours
    case last12Hours
    case all

    public var intervalSeconds: Int? {
        switch self {
        case .lastHour:
            return 60 * 60
        case .last4Hours:
            return 4 * 60 * 60
        case .last8Hours:
            return 8 * 60 * 60
        case .last12Hours:
            return 12 * 60 * 60
        case .all:
            return nil
        }
    }
}

public struct RuntimeVitalRecorderActivityWindowQuery: Codable, Equatable, Sendable {
    public static let oneMinuteBucketSeconds = 60
    public static let fiveMinuteBucketSeconds = 300
    public static let allWindowSeconds = 12 * 60 * 60
    public static let allWindowStepSeconds = 4 * 60 * 60

    public let vrcode: String
    public let bucketSeconds: Int
    public let period: RuntimeVitalRecorderActivityWindowPeriod
    public let pageIndex: Int?

    public init(
        vrcode: String,
        bucketSeconds: Int = oneMinuteBucketSeconds,
        period: RuntimeVitalRecorderActivityWindowPeriod = .lastHour,
        pageIndex: Int? = nil
    ) {
        self.vrcode = vrcode
        self.bucketSeconds = bucketSeconds
        self.period = period
        self.pageIndex = pageIndex
    }

    public var validationError: String? {
        if vrcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "vrcode is required"
        }
        if bucketSeconds != Self.oneMinuteBucketSeconds && bucketSeconds != Self.fiveMinuteBucketSeconds {
            return "bucketSeconds must be 60 or 300"
        }
        if let pageIndex, pageIndex < 0 {
            return "pageIndex must be non-negative"
        }
        return nil
    }
}

public struct RuntimeVitalRecorderActivityWindowPage: Codable, Equatable, Sendable {
    public let index: Int
    public let count: Int
    public let windowSeconds: Int
    public let windowStartedAt: String?
    public let windowEndedAt: String?
    public let firstBucketStartedAt: String?
    public let latestBucketStartedAt: String?

    public init(
        index: Int,
        count: Int,
        windowSeconds: Int,
        windowStartedAt: String?,
        windowEndedAt: String?,
        firstBucketStartedAt: String?,
        latestBucketStartedAt: String?
    ) {
        self.index = index
        self.count = count
        self.windowSeconds = windowSeconds
        self.windowStartedAt = windowStartedAt
        self.windowEndedAt = windowEndedAt
        self.firstBucketStartedAt = firstBucketStartedAt
        self.latestBucketStartedAt = latestBucketStartedAt
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case count
        case windowSeconds
        case windowStartedAt
        case windowEndedAt
        case firstBucketStartedAt
        case latestBucketStartedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        count = try container.decode(Int.self, forKey: .count)
        windowSeconds = try container.decode(Int.self, forKey: .windowSeconds)
        windowStartedAt = try container.decodeIfPresent(String.self, forKey: .windowStartedAt)
        windowEndedAt = try container.decodeIfPresent(String.self, forKey: .windowEndedAt)
        firstBucketStartedAt = try container.decodeIfPresent(String.self, forKey: .firstBucketStartedAt)
        latestBucketStartedAt = try container.decodeIfPresent(String.self, forKey: .latestBucketStartedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(count, forKey: .count)
        try container.encode(windowSeconds, forKey: .windowSeconds)
        if let windowStartedAt {
            try container.encode(windowStartedAt, forKey: .windowStartedAt)
        } else {
            try container.encodeNil(forKey: .windowStartedAt)
        }
        if let windowEndedAt {
            try container.encode(windowEndedAt, forKey: .windowEndedAt)
        } else {
            try container.encodeNil(forKey: .windowEndedAt)
        }
        if let firstBucketStartedAt {
            try container.encode(firstBucketStartedAt, forKey: .firstBucketStartedAt)
        } else {
            try container.encodeNil(forKey: .firstBucketStartedAt)
        }
        if let latestBucketStartedAt {
            try container.encode(latestBucketStartedAt, forKey: .latestBucketStartedAt)
        } else {
            try container.encodeNil(forKey: .latestBucketStartedAt)
        }
    }
}

public struct RuntimeVitalRecorderActivityWindow: Codable, Equatable, Sendable {
    public let state: RuntimeVitalRecorderActivityWindowState
    public let query: RuntimeVitalRecorderActivityWindowQuery
    public let page: RuntimeVitalRecorderActivityWindowPage
    public let buckets: [VitalDBRecorderActivityBucket]
    public let latestSampleAt: String?
    public let readError: String?

    public init(
        state: RuntimeVitalRecorderActivityWindowState,
        query: RuntimeVitalRecorderActivityWindowQuery,
        page: RuntimeVitalRecorderActivityWindowPage,
        buckets: [VitalDBRecorderActivityBucket],
        latestSampleAt: String?,
        readError: String? = nil
    ) {
        self.state = state
        self.query = query
        self.page = page
        self.buckets = buckets
        self.latestSampleAt = latestSampleAt
        self.readError = readError
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case query
        case page
        case buckets
        case latestSampleAt
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeVitalRecorderActivityWindowState.self, forKey: .state)
        query = try container.decode(RuntimeVitalRecorderActivityWindowQuery.self, forKey: .query)
        page = try container.decode(RuntimeVitalRecorderActivityWindowPage.self, forKey: .page)
        buckets = try container.decode([VitalDBRecorderActivityBucket].self, forKey: .buckets)
        latestSampleAt = try container.decodeIfPresent(String.self, forKey: .latestSampleAt)
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(query, forKey: .query)
        try container.encode(page, forKey: .page)
        try container.encode(buckets, forKey: .buckets)
        if let latestSampleAt {
            try container.encode(latestSampleAt, forKey: .latestSampleAt)
        } else {
            try container.encodeNil(forKey: .latestSampleAt)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public struct RuntimeVitalRecorderSummary: Codable, Equatable, Sendable {
    public let source: RuntimeVitalRecorderSummarySource
    public let activeConnections: Int?
    public let knownRecorders: Int?
    public let onlineRecorders: Int?
    public let staleRecorders: Int?
    public let knownBeds: Int?
    public let recorderAnomalies: Int?
    public let observedAt: String?
    public let latestRecorder: RuntimeVitalRecorderReference?

    public init(
        source: RuntimeVitalRecorderSummarySource,
        activeConnections: Int?,
        knownRecorders: Int?,
        onlineRecorders: Int?,
        staleRecorders: Int?,
        knownBeds: Int?,
        recorderAnomalies: Int?,
        observedAt: String?,
        latestRecorder: RuntimeVitalRecorderReference?
    ) {
        self.source = source
        self.activeConnections = activeConnections
        self.knownRecorders = knownRecorders
        self.onlineRecorders = onlineRecorders
        self.staleRecorders = staleRecorders
        self.knownBeds = knownBeds
        self.recorderAnomalies = recorderAnomalies
        self.observedAt = observedAt
        self.latestRecorder = latestRecorder
    }

    public init(
        recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?,
        vitalDBObservation: VitalDBObservationDocument?,
        statusEvaluationTime: String? = nil
    ) {
        let observation = vitalDBObservation
        let activeConnections = recorderIngressStatusRead?.document?.activeRecorderConnections

        if let observation {
            let history = RuntimeVitalRecorderHistory(
                observations: [observation],
                recorderIngressStatusRead: recorderIngressStatusRead,
                statusEvaluationTime: statusEvaluationTime
            )
            let latest = history.recorders
                .sorted { compareReportedTimestamp($0.lastSeenAt, $1.lastSeenAt) == .orderedDescending }
                .first
            self.init(
                source: .vitalDBObservation,
                activeConnections: activeConnections,
                knownRecorders: history.summary.knownRecorders,
                onlineRecorders: history.summary.onlineRecorders,
                staleRecorders: history.summary.staleRecorders,
                knownBeds: observation.beds.count,
                recorderAnomalies: observation.anomalies.count,
                observedAt: observation.observedAt,
                latestRecorder: latest.map {
                    RuntimeVitalRecorderReference(
                        vrcode: $0.vrcode,
                        ip: $0.lastIP,
                        lastSeenAt: $0.lastSeenAt,
                        source: .vitalDBObservation
                    )
                }
            )
            return
        }

        self.init(
            source: .unavailable,
            activeConnections: activeConnections,
            knownRecorders: nil,
            onlineRecorders: nil,
            staleRecorders: nil,
            knownBeds: nil,
            recorderAnomalies: nil,
            observedAt: nil,
            latestRecorder: nil
        )
    }
}

private func duplicateRecorderObservationCounts(
    _ recorders: [VitalDBRecorderObservation]
) -> [String: Int] {
    let grouped = Dictionary(grouping: recorders, by: \.vrcode)
    return grouped.compactMapValues { observations in
        observations.count > 1 ? observations.count - 1 : nil
    }
}

private func duplicateBedObservationCounts(_ beds: [VitalDBBedObservation]) -> [String: Int] {
    let grouped = Dictionary(grouping: beds, by: \.bedID)
    return grouped.compactMapValues { observations in
        observations.count > 1 ? observations.count - 1 : nil
    }
}

private func uniqueRecordersByVrcode(_ recorders: [VitalDBRecorderObservation]) -> [VitalDBRecorderObservation] {
    Dictionary(
        recorders.map { ($0.vrcode, $0) },
        uniquingKeysWith: preferredRecorder
    )
    .values
    .sorted { $0.vrcode < $1.vrcode }
}

private func uniqueBedsByID(_ beds: [VitalDBBedObservation]) -> [VitalDBBedObservation] {
    Dictionary(
        beds.map { ($0.bedID, $0) },
        uniquingKeysWith: preferredBed
    )
    .values
    .sorted { $0.bedID < $1.bedID }
}

private func preferredRecorder(
    _ current: VitalDBRecorderObservation,
    _ candidate: VitalDBRecorderObservation
) -> VitalDBRecorderObservation {
    let timestampOrder = compareReportedTimestamp(candidate.lastSeenAt, current.lastSeenAt)
    if timestampOrder != .orderedSame {
        return timestampOrder == .orderedDescending ? candidate : current
    }
    if candidate.stale != current.stale {
        return candidate.stale ? candidate : current
    }
    if candidate.online != current.online {
        return candidate.online ? candidate : current
    }
    return candidate
}

private func preferredBed(
    _ current: VitalDBBedObservation,
    _ candidate: VitalDBBedObservation
) -> VitalDBBedObservation {
    let timestampOrder = compareReportedTimestamp(candidate.lastSeenAt, current.lastSeenAt)
    if timestampOrder != .orderedSame {
        return timestampOrder == .orderedDescending ? candidate : current
    }
    if candidate.online != current.online {
        return candidate.online ? candidate : current
    }
    return candidate
}

private func compareReportedTimestamp(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    let lhsDate = reportedTimestampDate(lhs)
    let rhsDate = reportedTimestampDate(rhs)
    if let lhsDate, let rhsDate {
        if lhsDate == rhsDate {
            return .orderedSame
        }
        return lhsDate > rhsDate ? .orderedDescending : .orderedAscending
    }
    if lhsDate != nil {
        return .orderedDescending
    }
    if rhsDate != nil {
        return .orderedAscending
    }
    switch (lhs, rhs) {
    case let (lhs?, rhs?) where lhs != rhs:
        return lhs > rhs ? .orderedDescending : .orderedAscending
    case (.some, .some):
        return .orderedSame
    case (.some, nil):
        return .orderedDescending
    case (nil, .some):
        return .orderedAscending
    case (nil, nil):
        return .orderedSame
    }
}

private func reportedTimestampDate(_ value: String?) -> Date? {
    guard let value else {
        return nil
    }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

private func projectedActivityTimelineByVrcode(
    _ records: [VitalDBRecorderActivityBucketRecord]
) -> [String: [RuntimeVitalRecorderActivityPoint]] {
    let grouped = Dictionary(grouping: records, by: \.vrcode)
    return grouped.mapValues { records in
        records
            .sorted { $0.bucketStartedAt < $1.bucketStartedAt }
            .map { record in
                RuntimeVitalRecorderActivityPoint(
                    observedAt: record.lastObservedAt,
                    windowSeconds: record.bucketSeconds,
                    messageCount: record.messageCount,
                    byteCount: record.byteCount,
                    roomCount: record.roomCount,
                    messagesPerSecond: Double(record.messageCount) / Double(max(record.bucketSeconds, 1)),
                    bytesPerSecond: Double(record.byteCount) / Double(max(record.bucketSeconds, 1)),
                    buckets: [record.bucket]
                )
            }
    }
}

private func recorderRedisIPSyncByVrcode(
    _ recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?
) -> [String: RuntimeRecorderRedisIPSyncObservation] {
    guard let ingressRecorders = recorderIngressStatusRead?.document?.recorders else {
        return [:]
    }
    return Dictionary(
        ingressRecorders.compactMap { recorder in
            guard let sync = recorder.redisIpSync else {
                return nil
            }
            return (recorder.vrcode, sync)
        },
        uniquingKeysWith: { _, latest in latest }
    )
}

private func defaultRecorderRedisIPSync(
    vrcode: String,
    recorderIngressStatusRead: RuntimeRecorderIngressStatusReadResult?
) -> RuntimeRecorderRedisIPSyncObservation? {
    guard let recorderIngressStatusRead else {
        return nil
    }
    guard recorderIngressStatusRead.readState == .loaded else {
        return RuntimeRecorderRedisIPSyncObservation(
            status: .unavailable,
            redisKey: "ip_\(vrcode)",
            lastFailure: recorderIngressStatusRead.readError
                ?? "recorder ingress status \(recorderIngressStatusRead.readState.rawValue)"
        )
    }
    return RuntimeRecorderRedisIPSyncObservation(
        status: .unknown,
        redisKey: "ip_\(vrcode)"
    )
}

private struct RecorderBuilder {
    let vrcode: String
    var lastIP: String?
    var version: String?
    var bedID: String?
    var bedName: String?
    var patientConnected: Bool?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var observationCount = 0

    mutating func observe(
        recorder: VitalDBRecorderObservation,
        bed: VitalDBBedObservation?,
        observedAt _: String
    ) {
        observationCount += 1
        if let seenAt = recorder.lastSeenAt {
            firstSeenAt = minTimestamp(firstSeenAt, seenAt)
            lastSeenAt = maxTimestamp(lastSeenAt, seenAt)
        }
        lastIP = recorder.ip ?? lastIP
        version = recorder.version ?? version
        bedID = bed?.bedID ?? bedID
        bedName = bed?.name ?? bedName
        patientConnected = bed?.patientConnected ?? patientConnected
    }

    func record(
        latestRecorder: VitalDBRecorderObservation?,
        latestBed: VitalDBBedObservation?,
        latestObservationObservedAt: String,
        recorderOnlineThresholdSeconds: Int,
        currentAnomalies: [VitalDBAnomalyObservation],
        duplicateObservationCount: Int,
        activityTimeline projectedActivityTimeline: [RuntimeVitalRecorderActivityPoint]? = nil,
        redisIPSync: RuntimeRecorderRedisIPSyncObservation? = nil
    ) -> RuntimeVitalRecorderRecord {
        let presentInLatestObservation = latestRecorder != nil
        let latestAnomaly = latestAnomaly(in: currentAnomalies)
        return RuntimeVitalRecorderRecord(
            vrcode: vrcode,
            status: status(
                latestRecorder,
                observedAt: latestObservationObservedAt,
                onlineThresholdSeconds: recorderOnlineThresholdSeconds
            ),
            lastIP: presentInLatestObservation ? latestRecorder?.ip : lastIP,
            version: presentInLatestObservation ? latestRecorder?.version : version,
            bedID: presentInLatestObservation ? latestBed?.bedID : bedID,
            bedName: presentInLatestObservation ? latestBed?.name : bedName,
            patientConnected: presentInLatestObservation ? latestBed?.patientConnected : patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: presentInLatestObservation ? latestRecorder?.lastSeenAt : lastSeenAt,
            observationCount: observationCount,
            duplicateObservationCount: duplicateObservationCount,
            currentAnomalyCount: currentAnomalies.count,
            latestAnomalyKind: latestAnomaly?.kind,
            latestAnomalySeverity: latestAnomaly?.severity,
            latestAnomalyMessage: latestAnomaly?.message,
            latestAnomalyObservedAt: latestAnomaly?.observedAt,
            presentInLatestObservation: presentInLatestObservation,
            visibility: latestRecorder?.visibility ?? .visible,
            activityTimeline: projectedActivityTimeline,
            redisIPSync: redisIPSync
        )
    }

    private func status(
        _ recorder: VitalDBRecorderObservation?,
        observedAt: String,
        onlineThresholdSeconds: Int
    ) -> RuntimeVitalRecorderStatus {
        guard let recorder else {
            return .notObserved
        }
        if recorder.stale {
            return .stale
        }
        guard recorder.online else {
            return .offline
        }
        guard let lastSeenAt = recorder.lastSeenAt,
              let lastSeenDate = iso8601Date(lastSeenAt),
              let observedDate = iso8601Date(observedAt) else {
            return .online
        }
        if observedDate.timeIntervalSince(lastSeenDate) > Double(max(onlineThresholdSeconds, 0)) {
            return .stale
        }
        return .online
    }

    private func minTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.min(current, next)
    }

    private func maxTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.max(current, next)
    }

    private func maxOptionalTimestamp(_ current: String?, _ next: String?) -> String? {
        guard let next else {
            return current
        }
        return maxTimestamp(current, next)
    }
}

private func iso8601Date(_ timestamp: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: timestamp) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: timestamp)
}

private struct BedBuilder {
    let bedID: String
    var name: String?
    var vrcode: String?
    var patientConnected: Bool?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var observationCount = 0

    mutating func observe(bed: VitalDBBedObservation, observedAt _: String) {
        observationCount += 1
        if let seenAt = bed.lastSeenAt {
            firstSeenAt = minTimestamp(firstSeenAt, seenAt)
            lastSeenAt = maxTimestamp(lastSeenAt, seenAt)
        }
        name = bed.name ?? name
        vrcode = bed.vrcode ?? vrcode
        patientConnected = bed.patientConnected ?? patientConnected
    }

    func record(
        latestBed: VitalDBBedObservation?,
        linkedRecorder: RuntimeVitalRecorderRecord?,
        currentAnomalies: [VitalDBAnomalyObservation],
        duplicateObservationCount: Int
    ) -> RuntimeVitalBedRecord {
        let presentInLatestObservation = latestBed != nil
        let latestAnomaly = latestAnomaly(in: currentAnomalies)
        return RuntimeVitalBedRecord(
            bedID: bedID,
            name: presentInLatestObservation ? latestBed?.name : name,
            vrcode: presentInLatestObservation ? latestBed?.vrcode : vrcode,
            linkedRecorderStatus: linkedRecorder?.status,
            linkedRecorderIP: linkedRecorder?.lastIP,
            linkedRecorderVersion: linkedRecorder?.version,
            linkedRecorderLastSeenAt: linkedRecorder?.lastSeenAt,
            status: status(latestBed),
            patientConnected: presentInLatestObservation ? latestBed?.patientConnected : patientConnected,
            firstSeenAt: firstSeenAt,
            lastSeenAt: presentInLatestObservation ? latestBed?.lastSeenAt : lastSeenAt,
            observationCount: observationCount,
            duplicateObservationCount: duplicateObservationCount,
            currentAnomalyCount: currentAnomalies.count,
            latestAnomalyKind: latestAnomaly?.kind,
            latestAnomalySeverity: latestAnomaly?.severity,
            latestAnomalyMessage: latestAnomaly?.message,
            latestAnomalyObservedAt: latestAnomaly?.observedAt,
            visibility: latestBed?.visibility ?? .visible
        )
    }

    private func status(_ bed: VitalDBBedObservation?) -> RuntimeVitalBedStatus {
        guard let bed else {
            return .notObserved
        }
        return bed.online ? .online : .offline
    }

    private func minTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.min(current, next)
    }

    private func maxTimestamp(_ current: String?, _ next: String) -> String {
        guard let current else {
            return next
        }
        return Swift.max(current, next)
    }
}

private func latestAnomaly(in anomalies: [VitalDBAnomalyObservation]) -> VitalDBAnomalyObservation? {
    anomalies.sorted { left, right in
        if left.observedAt == right.observedAt {
            return left.id < right.id
        }
        return left.observedAt > right.observedAt
    }.first
}

public enum RuntimeVitalDBObservationReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public struct RuntimeVitalDBObservationSnapshot: Codable, Equatable, Sendable {
    public let state: RuntimeVitalDBObservationReadState
    public let observation: VitalDBObservationDocument?
    public let readError: String?

    public init(
        state: RuntimeVitalDBObservationReadState,
        observation: VitalDBObservationDocument? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.observation = observation
        self.readError = readError
    }

    public static func loaded(_ observation: VitalDBObservationDocument) -> Self {
        Self(state: .loaded, observation: observation)
    }

    public static func unavailable(readError: String? = nil) -> Self {
        Self(state: .unavailable, readError: readError)
    }

    public static func failed(readError: String) -> Self {
        Self(state: .failed, readError: readError)
    }

    public static func fromOptional(
        _ observation: VitalDBObservationDocument?,
        readError: String? = nil
    ) -> Self {
        if let observation {
            return Self(state: .loaded, observation: observation, readError: readError)
        }
        if let readError {
            return failed(readError: readError)
        }
        return unavailable()
    }

    enum CodingKeys: String, CodingKey {
        case state
        case observation
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decode(RuntimeVitalDBObservationReadState.self, forKey: .state)
        self.observation = try container.decodeRequiredNullable(
            VitalDBObservationDocument.self,
            forKey: .observation
        )
        self.readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        try Self.validateDecoded(
            state: state,
            observation: observation,
            readError: readError
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let observation {
            try container.encode(observation, forKey: .observation)
        } else {
            try container.encodeNil(forKey: .observation)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func validateDecoded(
        state: RuntimeVitalDBObservationReadState,
        observation: VitalDBObservationDocument?,
        readError: String?
    ) throws {
        switch state {
        case .loaded:
            if observation == nil {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.observation],
                        debugDescription: "loaded VitalDB observation snapshots must include observation"
                    )
                )
            }
        case .failed:
            if readError.isBlankOrMissing {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.readError],
                        debugDescription: "failed VitalDB observation snapshots must include readError"
                    )
                )
            }
        case .unavailable:
            break
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Missing required nullable key \(key.stringValue)"
                )
            )
        }
        return try decodeIfPresent(T.self, forKey: key)
    }
}

private extension Optional where Wrapped == String {
    var isBlankOrMissing: Bool {
        guard let value = self else {
            return true
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
