import Foundation
import Errors

public struct RuntimeTestKitStopRequest: Codable, Equatable, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct RuntimeTestKitDeleteRequest: Codable, Equatable, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct RuntimeTestKitRestartRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public let bedRoomNames: [String]

    public init(sessionID: String, bedRoomNames: [String]) {
        self.sessionID = sessionID
        self.bedRoomNames = bedRoomNames
    }
}

public struct RuntimeTestKitRecorderDeletionRequest: Codable, Equatable, Sendable {
    public let vrcode: String

    public init(vrcode: String) {
        self.vrcode = vrcode
    }
}
