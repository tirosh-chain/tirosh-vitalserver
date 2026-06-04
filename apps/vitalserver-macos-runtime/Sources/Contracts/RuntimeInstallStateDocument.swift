import Foundation

public enum RuntimeInstallMode: Codable, Equatable, Sendable {
    case full
    case provision
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "full":
            self = .full
        case "provision":
            self = .provision
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .full:
            return "full"
        case .provision:
            return "provision"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RuntimeInstallState: Codable, Equatable, Sendable {
    case started
    case settingsLoaded
    case preflightVerified
    case preflightBlocked
    case provisionPayloadVerified
    case provisionPayloadBlocked
    case stepStarted
    case stepCompleted
    case provisioned
    case completed
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "started":
            self = .started
        case "settings-loaded":
            self = .settingsLoaded
        case "preflight-verified":
            self = .preflightVerified
        case "preflight-blocked":
            self = .preflightBlocked
        case "provision-payload-verified":
            self = .provisionPayloadVerified
        case "provision-payload-blocked":
            self = .provisionPayloadBlocked
        case "step-started":
            self = .stepStarted
        case "step-completed":
            self = .stepCompleted
        case "provisioned":
            self = .provisioned
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .started:
            return "started"
        case .settingsLoaded:
            return "settings-loaded"
        case .preflightVerified:
            return "preflight-verified"
        case .preflightBlocked:
            return "preflight-blocked"
        case .provisionPayloadVerified:
            return "provision-payload-verified"
        case .provisionPayloadBlocked:
            return "provision-payload-blocked"
        case .stepStarted:
            return "step-started"
        case .stepCompleted:
            return "step-completed"
        case .provisioned:
            return "provisioned"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RuntimeInstallStateDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: RuntimeInstallState
    public let mode: RuntimeInstallMode
    public let currentStep: RuntimeWorkflowStep?
    public let updatedAt: String
    public let message: String?
    public let blockers: [String]

    public init(
        schemaVersion: Int = 1,
        state: RuntimeInstallState,
        mode: RuntimeInstallMode,
        currentStep: RuntimeWorkflowStep? = nil,
        updatedAt: String,
        message: String? = nil,
        blockers: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.mode = mode
        self.currentStep = currentStep
        self.updatedAt = updatedAt
        self.message = message
        self.blockers = blockers
    }
}
