import Foundation

public enum UpdateHandoffJobState: String, Codable, Equatable, Sendable {
    case queued
    case launching
    case running
    case cancellationRequested = "cancellation-requested"
    case succeeded
    case failed
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .interrupted:
            true
        case .queued, .launching, .running, .cancellationRequested:
            false
        }
    }
}

public struct UpdateHandoffChildIdentity: Codable, Equatable, Sendable {
    public let launchId: String
    public let processId: Int32
    public let processGroupId: Int32
    public let startedAt: String

    public init(
        launchId: String,
        processId: Int32,
        processGroupId: Int32,
        startedAt: String
    ) {
        self.launchId = launchId
        self.processId = processId
        self.processGroupId = processGroupId
        self.startedAt = startedAt
    }
}

public enum UpdateHandoffCompletionOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case interrupted
}

public struct UpdateHandoffJobCompletion: Codable, Equatable, Sendable {
    public let outcome: UpdateHandoffCompletionOutcome
    public let exitCode: Int32?
    public let reason: String?
    public let finishedAt: String

    public init(
        outcome: UpdateHandoffCompletionOutcome,
        exitCode: Int32?,
        reason: String?,
        finishedAt: String
    ) {
        self.outcome = outcome
        self.exitCode = exitCode
        self.reason = reason
        self.finishedAt = finishedAt
    }
}

public struct UpdateHandoffJobDocument: Codable, Equatable, Sendable {
    public static let schemaVersion = "vitalserver.update-handoff-job/v1"

    public let schemaVersion: String
    public let jobId: String
    public let revision: Int
    public let updateId: String
    public let operationId: String
    public let invocationPath: String
    public let updaterPath: String
    public let launchId: String?
    public let state: UpdateHandoffJobState
    public let child: UpdateHandoffChildIdentity?
    public let completion: UpdateHandoffJobCompletion?
    public let createdAt: String
    public let updatedAt: String

    public init(
        schemaVersion: String = Self.schemaVersion,
        jobId: String,
        revision: Int,
        updateId: String,
        operationId: String,
        invocationPath: String,
        updaterPath: String,
        launchId: String?,
        state: UpdateHandoffJobState,
        child: UpdateHandoffChildIdentity?,
        completion: UpdateHandoffJobCompletion?,
        createdAt: String,
        updatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.revision = revision
        self.updateId = updateId
        self.operationId = operationId
        self.invocationPath = invocationPath
        self.updaterPath = updaterPath
        self.launchId = launchId
        self.state = state
        self.child = child
        self.completion = completion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct UpdateHandoffChildStartReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion = "vitalserver.update-handoff-child-start/v1"

    public let schemaVersion: String
    public let jobId: String
    public let child: UpdateHandoffChildIdentity

    public init(
        schemaVersion: String = Self.schemaVersion,
        jobId: String,
        child: UpdateHandoffChildIdentity
    ) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.child = child
    }
}

public struct UpdateHandoffChildCompletionReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion =
        "vitalserver.update-handoff-child-completion/v1"

    public let schemaVersion: String
    public let jobId: String
    public let launchId: String
    public let processId: Int32
    public let processGroupId: Int32
    public let exitCode: Int32?
    public let launchFailureReason: String?
    public let finishedAt: String

    public init(
        schemaVersion: String = Self.schemaVersion,
        jobId: String,
        launchId: String,
        processId: Int32,
        processGroupId: Int32,
        exitCode: Int32?,
        launchFailureReason: String?,
        finishedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.jobId = jobId
        self.launchId = launchId
        self.processId = processId
        self.processGroupId = processGroupId
        self.exitCode = exitCode
        self.launchFailureReason = launchFailureReason
        self.finishedAt = finishedAt
    }
}

public enum UpdateHandoffReceiptReadResult<Value: Equatable & Sendable>:
    Equatable, Sendable {
    case loaded(Value)
    case missing(path: String)
    case failed(path: String, reason: String)
}

public enum UpdateHandoffChildObservation: Equatable, Sendable {
    case running(UpdateHandoffChildIdentity)
    case notRunning(UpdateHandoffChildIdentity)
    case failed(UpdateHandoffChildIdentity, reason: String)
}

public enum UpdateHandoffProcessTreeTerminationResult: Equatable, Sendable {
    case terminated(UpdateHandoffChildIdentity)
    case failed(UpdateHandoffChildIdentity, reason: String)
}
