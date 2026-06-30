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
    let recorderCount: Int
    let bedroomName: String
    let window: RuntimeTestKitScenarioWindow?
    let output: RuntimeTestKitSessionOutput
    let vrcode: String?
    let version: String
    let intervalSeconds: Double
    let maxMessages: Int?
    let shiftTime: Bool
    let generateFrames: Bool
    let scenario: String

    init(
        runtimeRequest: RuntimeTestKitVirtualRecorderStartRequest,
        targetURL: String
    ) {
        self.targetURL = targetURL
        recorderCount = runtimeRequest.recorders
        bedroomName = runtimeRequest.bedroomName
        window = runtimeRequest.window
        output = runtimeRequest.output
        vrcode = runtimeRequest.vrcode
        version = runtimeRequest.version
        intervalSeconds = runtimeRequest.intervalSeconds
        maxMessages = runtimeRequest.maxMessages
        shiftTime = runtimeRequest.shiftTime
        generateFrames = runtimeRequest.generateFrames
        scenario = runtimeRequest.scenario.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case recorderCount
        case bedroomName
        case window
        case output
        case vrcode
        case version
        case intervalSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case scenario
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
    let bedroomName: String?
}
