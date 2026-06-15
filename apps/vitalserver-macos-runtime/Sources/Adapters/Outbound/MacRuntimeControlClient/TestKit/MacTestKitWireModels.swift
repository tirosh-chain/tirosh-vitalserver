import Foundation
import RuntimeControl
import Errors

struct TestKitSessionsResponse: Decodable {
    let sessions: [RuntimeTestKitSession]
}

struct TestKitBedsResponse: Decodable {
    let beds: [RuntimeTestKitBed]
}

struct TestKitStartSessionRequest: Encodable {
    let targetURL: String
    let recorders: Int
    let bedRoomNames: [String]
    let vrcode: String?
    let version: String
    let intervalSeconds: Double
    let durationSeconds: Double?
    let maxMessages: Int?
    let shiftTime: Bool
    let generateFrames: Bool
    let scenario: String
    let defaultScenario: String

    init(
        runtimeRequest: RuntimeTestKitVirtualRecorderStartRequest,
        targetURL: String
    ) {
        self.targetURL = targetURL
        recorders = runtimeRequest.recorders
        bedRoomNames = runtimeRequest.bedRoomNames
        vrcode = runtimeRequest.vrcode
        version = runtimeRequest.version
        intervalSeconds = runtimeRequest.intervalSeconds
        durationSeconds = runtimeRequest.durationSeconds
        maxMessages = runtimeRequest.maxMessages
        shiftTime = runtimeRequest.shiftTime
        generateFrames = runtimeRequest.generateFrames
        scenario = runtimeRequest.scenario.rawValue
        defaultScenario = runtimeRequest.signalProfile.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case recorders
        case bedRoomNames
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case scenario
        case defaultScenario
    }
}

struct TestKitDeleteRecorderRequest: Encodable {
    let targetURL: String
    let vrcode: String

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case vrcode
    }
}

struct TestKitDeleteBedsRequest: Encodable {
    let targetURL: String
    let roomNames: [String]

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case roomNames
    }
}

struct TestKitRestartSessionRequest: Encodable {
    let bedRoomNames: [String]
}
