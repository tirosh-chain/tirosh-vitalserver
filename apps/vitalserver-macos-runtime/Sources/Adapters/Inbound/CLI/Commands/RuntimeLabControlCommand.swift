import Contracts
import Errors
import RuntimeControl

public enum RuntimeLabControlAction: Equatable, Sendable {
    case scenarios
    case beds
    case recorders
    case createSession(RuntimeLabSessionCreateRequest)
    case getSession(String)
    case startSession(String)
    case stopSession(String)
    case replayVitalFile(RuntimeLabVitalFileReplayRequest)
}

public struct RuntimeLabControlCommand: Equatable, Sendable {
    public static let defaultGuestControlBaseURL = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL

    public let action: RuntimeLabControlAction
    public let guestControlBaseURL: String

    public init(
        action: RuntimeLabControlAction,
        guestControlBaseURL: String = RuntimeLabControlCommand.defaultGuestControlBaseURL
    ) {
        self.action = action
        self.guestControlBaseURL = guestControlBaseURL
    }
}

extension RuntimeLabControlCommand {
    public static func parseScenariosCommand(_ arguments: [String]) throws -> RuntimeLabControlCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime lab-scenarios [--guest-control-url <url>]"
        )
        return RuntimeLabControlCommand(action: .scenarios, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseBedsCommand(_ arguments: [String]) throws -> RuntimeLabControlCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime lab-beds [--guest-control-url <url>]"
        )
        return RuntimeLabControlCommand(action: .beds, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseRecordersCommand(_ arguments: [String]) throws -> RuntimeLabControlCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime lab-recorders [--guest-control-url <url>]"
        )
        return RuntimeLabControlCommand(action: .recorders, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseSessionCreateCommand(_ arguments: [String]) throws -> RuntimeLabControlCommand {
        let usage = "usage: vitalserver-vm runtime lab-session-create <scenario-id> [--name <name>] [--recorder-count <count>] [--target-url <url>] [--guest-control-url <url>]"
        guard let scenarioId = arguments.first, !scenarioId.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        var remaining = Array(arguments.dropFirst())
        var guestControlBaseURL = RuntimeLabControlCommand.defaultGuestControlBaseURL
        var name: String?
        var recorderCount = 1
        var targetURL: String?
        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            switch key {
            case "--guest-control-url":
                guestControlBaseURL = try requiredOptionValue(&remaining, option: key)
            case "--name":
                name = try requiredOptionValue(&remaining, option: key)
            case "--recorder-count":
                let value = try requiredOptionValue(&remaining, option: key)
                guard let count = Int(value), count > 0 else {
                    throw RuntimeLifecycleCommandParseError.missingArgument("--recorder-count must be a positive integer")
                }
                recorderCount = count
            case "--target-url":
                targetURL = try requiredOptionValue(&remaining, option: key)
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
        }
        return RuntimeLabControlCommand(
            action: .createSession(RuntimeLabSessionCreateRequest(
                scenarioId: scenarioId,
                name: name,
                recorderCount: recorderCount,
                targetURL: targetURL
            )),
            guestControlBaseURL: guestControlBaseURL
        )
    }

    public static func parseSessionIDCommand(
        _ arguments: [String],
        action: (String) -> RuntimeLabControlAction,
        usage: String
    ) throws -> RuntimeLabControlCommand {
        guard let sessionId = arguments.first, !sessionId.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        let guestControlBaseURL = try parseGuestControlBaseURL(Array(arguments.dropFirst()), usage: usage)
        return RuntimeLabControlCommand(action: action(sessionId), guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseVitalReplayCommand(_ arguments: [String]) throws -> RuntimeLabControlCommand {
        let usage = "usage: vitalserver-vm runtime lab-vital-replay <vital-file-relative-path> [--session-name <name>] [--target-url <url>] [--guest-control-url <url>]"
        guard let vitalFileRelativePath = arguments.first, !vitalFileRelativePath.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(usage)
        }
        var remaining = Array(arguments.dropFirst())
        var guestControlBaseURL = RuntimeLabControlCommand.defaultGuestControlBaseURL
        var sessionName: String?
        var targetURL: String?
        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            switch key {
            case "--guest-control-url":
                guestControlBaseURL = try requiredOptionValue(&remaining, option: key)
            case "--session-name":
                sessionName = try requiredOptionValue(&remaining, option: key)
            case "--target-url":
                targetURL = try requiredOptionValue(&remaining, option: key)
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
        }
        return RuntimeLabControlCommand(
            action: .replayVitalFile(RuntimeLabVitalFileReplayRequest(
                vitalFileRelativePath: vitalFileRelativePath,
                sessionName: sessionName,
                targetURL: targetURL,
                resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
                repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
            )),
            guestControlBaseURL: guestControlBaseURL
        )
    }

    private static func parseGuestControlBaseURL(
        _ arguments: [String],
        usage: String
    ) throws -> String {
        var remaining = arguments
        var guestControlBaseURL = RuntimeLabControlCommand.defaultGuestControlBaseURL
        while !remaining.isEmpty {
            let key = remaining.removeFirst()
            switch key {
            case "--guest-control-url":
                guestControlBaseURL = try requiredOptionValue(&remaining, option: key)
            default:
                throw RuntimeLifecycleCommandParseError.missingArgument(usage)
            }
        }
        return guestControlBaseURL
    }

    private static func requiredOptionValue(
        _ remaining: inout [String],
        option: String
    ) throws -> String {
        guard let value = remaining.first, !value.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument("missing value for \(option)")
        }
        remaining.removeFirst()
        return value
    }
}
