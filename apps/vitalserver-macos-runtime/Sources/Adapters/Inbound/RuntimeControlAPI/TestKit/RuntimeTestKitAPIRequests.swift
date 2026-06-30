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
    public let bedroomName: String?

    public init(sessionID: String, bedroomName: String?) {
        self.sessionID = sessionID
        self.bedroomName = bedroomName
    }
}

public struct RuntimeTestKitRecorderDeletionRequest: Codable, Equatable, Sendable {
    public let vrcode: String

    public init(vrcode: String) {
        self.vrcode = vrcode
    }
}
