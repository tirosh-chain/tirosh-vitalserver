import Foundation

public enum RuntimeLabReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public enum RuntimeLabSessionState: String, Codable, Equatable, Sendable {
    case accepted
    case running
    case stopping
    case stopped
    case finished
    case failed
    case unavailable
}

public enum RuntimeLabSessionFailureStage: String, Codable, Equatable, Sendable {
    case fileValidation
    case replayFrame
}

public enum RuntimeLabSessionFailureCode: String, Codable, Equatable, Sendable {
    case sourceUnavailable
    case readerUnavailable
    case decodeFailed
    case nonPositiveDuration
    case invalidWaveformSampleRate
    case unsupportedTrackType
    case trackReadFailed
    case noReplayableTracks
    case offsetOutsideSourceDuration
    case noFiniteRecords
}

public struct RuntimeLabSessionFailure: Codable, Equatable, Sendable {
    public let stage: RuntimeLabSessionFailureStage
    public let code: RuntimeLabSessionFailureCode
    public let message: String
    public let failedAt: String

    public init(
        stage: RuntimeLabSessionFailureStage,
        code: RuntimeLabSessionFailureCode,
        message: String,
        failedAt: String
    ) {
        self.stage = stage
        self.code = code
        self.message = message
        self.failedAt = failedAt
    }
}

public enum RuntimeLabArchiveFinalizationState: String, Codable, Equatable, Sendable {
    case queued
    case processing
    case retrying
    case exported
    case published
    case failed
    case partial
    case missing
    case unavailable
}

public struct RuntimeLabArchiveFinalization: Codable, Equatable, Sendable {
    public let state: RuntimeLabArchiveFinalizationState
    public let updatedAt: String?
    public let readError: String?

    private enum CodingKeys: String, CodingKey {
        case state
        case updatedAt
        case readError
    }

    public init(
        state: RuntimeLabArchiveFinalizationState,
        updatedAt: String? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.updatedAt = updatedAt
        self.readError = readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(RuntimeLabArchiveFinalizationState.self, forKey: .state)
        guard container.contains(.updatedAt) else {
            throw DecodingError.keyNotFound(
                CodingKeys.updatedAt,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Runtime Lab archive finalization requires updatedAt."
                )
            )
        }
        guard container.contains(.readError) else {
            throw DecodingError.keyNotFound(
                CodingKeys.readError,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Runtime Lab archive finalization requires readError."
                )
            )
        }
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let updatedAt {
            try container.encode(updatedAt, forKey: .updatedAt)
        } else {
            try container.encodeNil(forKey: .updatedAt)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public enum RuntimeLabRecorderSendState: String, Codable, Equatable, Sendable {
    case notAttempted
    case skipped
    case sent
    case failed
}

public struct RuntimeLabScenario: Codable, Equatable, Sendable {
    public let scenarioId: String
    public let name: String
    public let category: String
    public let description: String?

    public init(
        scenarioId: String,
        name: String,
        category: String,
        description: String? = nil
    ) {
        self.scenarioId = scenarioId
        self.name = name
        self.category = category
        self.description = description
    }
}

public struct RuntimeLabScenarioList: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let scenarios: [RuntimeLabScenario]
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        scenarios: [RuntimeLabScenario],
        readError: String? = nil
    ) {
        self.state = state
        self.scenarios = scenarios
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabScenarioList {
        RuntimeLabScenarioList(state: .unavailable, scenarios: [], readError: readError)
    }
}

public struct RuntimeLabVitalFile: Codable, Equatable, Sendable {
    public let displayName: String
    public let relativePath: String
    public let guestPath: String
    public let sizeBytes: Int
    public let modifiedAt: String?

    public init(
        displayName: String,
        relativePath: String,
        guestPath: String,
        sizeBytes: Int,
        modifiedAt: String? = nil
    ) {
        self.displayName = displayName
        self.relativePath = relativePath
        self.guestPath = guestPath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

public struct RuntimeLabVitalFileList: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let vitalFiles: [RuntimeLabVitalFile]
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        vitalFiles: [RuntimeLabVitalFile],
        readError: String? = nil
    ) {
        self.state = state
        self.vitalFiles = vitalFiles
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabVitalFileList {
        RuntimeLabVitalFileList(state: .unavailable, vitalFiles: [], readError: readError)
    }
}

public struct RuntimeLabSession: Codable, Equatable, Sendable {
    public let sessionId: String
    public let state: RuntimeLabSessionState
    public let scenarioId: String
    public let name: String?
    public let recorderCount: Int
    public let targetURL: String?
    public let bedIds: [String]?
    public let recorderIds: [String]?
    public let vitalFileRelativePath: String?
    public let replayPolicy: RuntimeLabVitalFileReplayPolicy?
    public let failure: RuntimeLabSessionFailure?
    public let archiveFinalization: RuntimeLabArchiveFinalization?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        sessionId: String,
        state: RuntimeLabSessionState,
        scenarioId: String,
        name: String? = nil,
        recorderCount: Int,
        targetURL: String?,
        bedIds: [String]? = nil,
        recorderIds: [String]? = nil,
        vitalFileRelativePath: String? = nil,
        replayPolicy: RuntimeLabVitalFileReplayPolicy? = nil,
        failure: RuntimeLabSessionFailure? = nil,
        archiveFinalization: RuntimeLabArchiveFinalization? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.scenarioId = scenarioId
        self.name = name
        self.recorderCount = recorderCount
        self.targetURL = targetURL
        self.bedIds = bedIds
        self.recorderIds = recorderIds
        self.vitalFileRelativePath = vitalFileRelativePath
        self.replayPolicy = replayPolicy
        self.failure = failure
        self.archiveFinalization = archiveFinalization
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RuntimeLabBed: Codable, Equatable, Sendable {
    public let bedId: String
    public let sessionId: String
    public let name: String
    public let state: RuntimeLabSessionState
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        bedId: String,
        sessionId: String,
        name: String,
        state: RuntimeLabSessionState,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.bedId = bedId
        self.sessionId = sessionId
        self.name = name
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RuntimeLabBedList: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let beds: [RuntimeLabBed]
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        beds: [RuntimeLabBed],
        readError: String? = nil
    ) {
        self.state = state
        self.beds = beds
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabBedList {
        RuntimeLabBedList(state: .unavailable, beds: [], readError: readError)
    }
}

public struct RuntimeLabBedCreateRequest: Codable, Equatable, Sendable {
    public let count: Int?
    public let roomNames: [String]
    public let prefix: String?
    public let targetURL: String?

    public init(
        count: Int? = nil,
        roomNames: [String] = [],
        prefix: String? = nil,
        targetURL: String? = nil
    ) {
        self.count = count
        self.roomNames = roomNames
        self.prefix = prefix
        self.targetURL = targetURL
    }
}

public struct RuntimeLabBedDeleteRequest: Codable, Equatable, Sendable {
    public let bedIds: [String]
    public let roomNames: [String]
    public let sessionId: String?

    public init(
        bedIds: [String] = [],
        roomNames: [String] = [],
        sessionId: String? = nil
    ) {
        self.bedIds = bedIds
        self.roomNames = roomNames
        self.sessionId = sessionId
    }
}

public struct RuntimeLabRecorder: Codable, Equatable, Sendable {
    public let recorderId: String
    public let sessionId: String
    public let bedId: String
    public let vrcode: String
    public let state: RuntimeLabSessionState
    public let createdAt: String?
    public let updatedAt: String?
    public let messagesSent: Int
    public let lastSendState: RuntimeLabRecorderSendState
    public let lastSendAt: String?
    public let lastSendError: String?

    public init(
        recorderId: String,
        sessionId: String,
        bedId: String,
        vrcode: String,
        state: RuntimeLabSessionState,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        messagesSent: Int = 0,
        lastSendState: RuntimeLabRecorderSendState = .notAttempted,
        lastSendAt: String? = nil,
        lastSendError: String? = nil
    ) {
        self.recorderId = recorderId
        self.sessionId = sessionId
        self.bedId = bedId
        self.vrcode = vrcode
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messagesSent = messagesSent
        self.lastSendState = lastSendState
        self.lastSendAt = lastSendAt
        self.lastSendError = lastSendError
    }
}

public struct RuntimeLabRecorderCreateRequest: Codable, Equatable, Sendable {
    public let bedIds: [String]
    public let sessionId: String?

    public init(
        bedIds: [String] = [],
        sessionId: String? = nil
    ) {
        self.bedIds = bedIds
        self.sessionId = sessionId
    }
}

public struct RuntimeLabRecorderDeleteRequest: Codable, Equatable, Sendable {
    public let recorderIds: [String]
    public let vrcodes: [String]
    public let sessionId: String?

    public init(
        recorderIds: [String] = [],
        vrcodes: [String] = [],
        sessionId: String? = nil
    ) {
        self.recorderIds = recorderIds
        self.vrcodes = vrcodes
        self.sessionId = sessionId
    }
}

public struct RuntimeLabRecorderList: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let recorders: [RuntimeLabRecorder]
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        recorders: [RuntimeLabRecorder],
        readError: String? = nil
    ) {
        self.state = state
        self.recorders = recorders
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabRecorderList {
        RuntimeLabRecorderList(state: .unavailable, recorders: [], readError: readError)
    }
}

public struct RuntimeLabRecorderResponse: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let recorder: RuntimeLabRecorder?
    public let operationId: String?
    public let labOperationId: String?
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        recorder: RuntimeLabRecorder?,
        operationId: String? = nil,
        labOperationId: String? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.recorder = recorder
        self.operationId = operationId
        self.labOperationId = labOperationId
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabRecorderResponse {
        RuntimeLabRecorderResponse(
            state: .unavailable,
            recorder: nil,
            operationId: nil,
            readError: readError
        )
    }
}

public struct RuntimeLabSessionList: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let sessions: [RuntimeLabSession]
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        sessions: [RuntimeLabSession],
        readError: String? = nil
    ) {
        self.state = state
        self.sessions = sessions
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabSessionList {
        RuntimeLabSessionList(state: .unavailable, sessions: [], readError: readError)
    }
}

public struct RuntimeLabSessionResponse: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let session: RuntimeLabSession?
    public let operationId: String?
    public let labOperationId: String?
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        session: RuntimeLabSession?,
        operationId: String? = nil,
        labOperationId: String? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.session = session
        self.operationId = operationId
        self.labOperationId = labOperationId
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse(
            state: .unavailable,
            session: nil,
            operationId: nil,
            readError: readError
        )
    }
}

public struct RuntimeLabSessionCreateRequest: Codable, Equatable, Sendable {
    public let scenarioId: String
    public let name: String?
    public let recorderCount: Int
    public let targetURL: String?
    public let bedIds: [String]?

    public init(
        scenarioId: String,
        name: String? = nil,
        recorderCount: Int = 1,
        targetURL: String? = nil,
        bedIds: [String]? = nil
    ) {
        self.scenarioId = scenarioId
        self.name = name
        self.recorderCount = recorderCount
        self.targetURL = targetURL
        self.bedIds = bedIds
    }
}

public struct RuntimeLabVitalFileReplayRequest: Codable, Equatable, Sendable {
    public let vitalFileRelativePath: String
    public let sessionName: String?
    public let targetURL: String?
    public let resourceSelection: RuntimeLabVitalFileReplayResourceSelection
    public let repeatPolicy: RuntimeLabVitalFileReplayPolicy

    public init(
        vitalFileRelativePath: String,
        sessionName: String? = nil,
        targetURL: String? = nil,
        resourceSelection: RuntimeLabVitalFileReplayResourceSelection,
        repeatPolicy: RuntimeLabVitalFileReplayPolicy
    ) {
        self.vitalFileRelativePath = vitalFileRelativePath
        self.sessionName = sessionName
        self.targetURL = targetURL
        self.resourceSelection = resourceSelection
        self.repeatPolicy = repeatPolicy
    }
}

public enum RuntimeLabVitalFileReplayRepeatMode: String, Codable, CaseIterable, Equatable, Sendable {
    case once
    case count
    case continuous
}

public struct RuntimeLabVitalFileReplayPolicy: Codable, Equatable, Sendable {
    public let mode: RuntimeLabVitalFileReplayRepeatMode
    public let count: Int?

    public init(mode: RuntimeLabVitalFileReplayRepeatMode, count: Int? = nil) {
        self.mode = mode
        self.count = count
    }
}

public enum RuntimeLabVitalFileReplayResourceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case existing
    case quickCreate
}

public struct RuntimeLabVitalFileReplayResourceSelection: Codable, Equatable, Sendable {
    public let mode: RuntimeLabVitalFileReplayResourceMode
    public let bedId: String?
    public let recorderId: String?

    public init(
        mode: RuntimeLabVitalFileReplayResourceMode,
        bedId: String? = nil,
        recorderId: String? = nil
    ) {
        self.mode = mode
        self.bedId = bedId
        self.recorderId = recorderId
    }
}

public enum RuntimeLabVitalFileAccessMode: Equatable, Sendable {
    case direct
    case securityScoped
}

public struct RuntimeLabVitalFileUploadFile: Equatable, Sendable {
    public let url: URL
    public let sizeBytes: Int64
    public let accessMode: RuntimeLabVitalFileAccessMode

    public init(
        url: URL,
        sizeBytes: Int64,
        accessMode: RuntimeLabVitalFileAccessMode
    ) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.accessMode = accessMode
    }
}

public enum RuntimeLabVitalFileUploadPayload: Equatable, Sendable {
    case bytes(Data)
    case file(RuntimeLabVitalFileUploadFile)
}

public struct RuntimeLabVitalFileUploadSource: Equatable, Sendable {
    public let fileName: String
    public let payload: RuntimeLabVitalFileUploadPayload

    public init(fileName: String, content: Data) {
        self.fileName = fileName
        self.payload = .bytes(content)
    }

    public init(
        fileName: String,
        fileURL: URL,
        sizeBytes: Int64,
        accessMode: RuntimeLabVitalFileAccessMode
    ) {
        self.fileName = fileName
        self.payload = .file(RuntimeLabVitalFileUploadFile(
            url: fileURL,
            sizeBytes: sizeBytes,
            accessMode: accessMode
        ))
    }

    public var sizeBytes: Int64 {
        switch payload {
        case .bytes(let content):
            return Int64(content.count)
        case .file(let file):
            return file.sizeBytes
        }
    }
}

public struct RuntimeLabVitalFileLibraryUploadItem: Codable, Equatable, Sendable {
    public let fileName: String
    public let relativePath: String
    public let sizeBytes: Int

    public init(fileName: String, relativePath: String, sizeBytes: Int) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
    }
}

public enum RuntimeLabVitalFileLibraryUploadState: String, Codable, Equatable, Sendable {
    case completed
    case partial
    case failed
}

public struct RuntimeLabVitalFileLibraryUploadFailure: Codable, Equatable, Sendable {
    public let fileName: String
    public let reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

public struct RuntimeLabVitalFileLibraryUploadResponse: Codable, Equatable, Sendable {
    public let state: RuntimeLabVitalFileLibraryUploadState
    public let files: [RuntimeLabVitalFileLibraryUploadItem]
    public let failedFiles: [RuntimeLabVitalFileLibraryUploadFailure]

    public init(
        state: RuntimeLabVitalFileLibraryUploadState = .completed,
        files: [RuntimeLabVitalFileLibraryUploadItem],
        failedFiles: [RuntimeLabVitalFileLibraryUploadFailure] = []
    ) {
        self.state = state
        self.files = files
        self.failedFiles = failedFiles
    }
}
