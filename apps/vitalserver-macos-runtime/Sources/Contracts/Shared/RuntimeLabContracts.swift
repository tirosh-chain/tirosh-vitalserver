import Foundation

public enum RuntimeLabReadState: String, Codable, Equatable, Sendable {
    case loaded
    case unavailable
    case failed
}

public enum RuntimeLabSessionState: String, Codable, Equatable, Sendable {
    case accepted
    case running
    case stopped
    case failed
    case unavailable
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
    public let vitalFilePath: String
    public let sessionName: String?
    public let targetURL: String?

    public init(
        vitalFilePath: String,
        sessionName: String? = nil,
        targetURL: String? = nil
    ) {
        self.vitalFilePath = vitalFilePath
        self.sessionName = sessionName
        self.targetURL = targetURL
    }
}

public struct RuntimeLabVitalFileUpload: Codable, Equatable, Sendable {
    public let filename: String
    public let endpoint: String
    public let targetURL: String
    public let statusCode: Int
    public let bytesSent: Int
    public let responseText: String
    public let ok: Bool

    public init(
        filename: String,
        endpoint: String,
        targetURL: String,
        statusCode: Int,
        bytesSent: Int,
        responseText: String,
        ok: Bool
    ) {
        self.filename = filename
        self.endpoint = endpoint
        self.targetURL = targetURL
        self.statusCode = statusCode
        self.bytesSent = bytesSent
        self.responseText = responseText
        self.ok = ok
    }
}

public struct RuntimeLabVitalFileUploadRequest: Codable, Equatable, Sendable {
    public let vitalFilePath: String
    public let targetURL: String
    public let endpoint: String?
    public let vrcode: String?

    public init(
        vitalFilePath: String,
        targetURL: String,
        endpoint: String? = nil,
        vrcode: String? = nil
    ) {
        self.vitalFilePath = vitalFilePath
        self.targetURL = targetURL
        self.endpoint = endpoint
        self.vrcode = vrcode
    }
}

public struct RuntimeLabVitalFileUploadResponse: Codable, Equatable, Sendable {
    public let state: RuntimeLabReadState
    public let upload: RuntimeLabVitalFileUpload?
    public let operationId: String?
    public let labOperationId: String?
    public let readError: String?

    public init(
        state: RuntimeLabReadState,
        upload: RuntimeLabVitalFileUpload?,
        operationId: String? = nil,
        labOperationId: String? = nil,
        readError: String? = nil
    ) {
        self.state = state
        self.upload = upload
        self.operationId = operationId
        self.labOperationId = labOperationId
        self.readError = readError
    }

    public static func unavailable(readError: String) -> RuntimeLabVitalFileUploadResponse {
        RuntimeLabVitalFileUploadResponse(
            state: .unavailable,
            upload: nil,
            operationId: nil,
            readError: readError
        )
    }
}
