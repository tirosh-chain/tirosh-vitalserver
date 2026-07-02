import Contracts

public enum RuntimeVitalDBReadAction: Equatable, Sendable {
    case observation
    case recorders
    case recorderActivity(String)
    case beds
    case relationships
}

public struct RuntimeVitalDBReadCommand: Equatable, Sendable {
    public static let defaultGuestControlBaseURL = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL

    public let action: RuntimeVitalDBReadAction
    public let guestControlBaseURL: String

    public init(
        action: RuntimeVitalDBReadAction,
        guestControlBaseURL: String = RuntimeVitalDBReadCommand.defaultGuestControlBaseURL
    ) {
        self.action = action
        self.guestControlBaseURL = guestControlBaseURL
    }
}

extension RuntimeVitalDBReadCommand {
    public static func parseObservationCommand(_ arguments: [String]) throws -> RuntimeVitalDBReadCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime vitaldb-observation [--guest-control-url <url>]"
        )
        return RuntimeVitalDBReadCommand(action: .observation, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseRecordersCommand(_ arguments: [String]) throws -> RuntimeVitalDBReadCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime vitaldb-recorders [--guest-control-url <url>]"
        )
        return RuntimeVitalDBReadCommand(action: .recorders, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseRecorderActivityCommand(_ arguments: [String]) throws -> RuntimeVitalDBReadCommand {
        var remaining = Array(arguments)
        guard let vrcode = remaining.first, !vrcode.isEmpty else {
            throw RuntimeLifecycleCommandParseError.missingArgument(
                "usage: vitalserver-vm runtime vitaldb-recorder-activity <vrcode> [--guest-control-url <url>]"
            )
        }
        remaining.removeFirst()
        let guestControlBaseURL = try parseGuestControlBaseURL(
            remaining,
            usage: "usage: vitalserver-vm runtime vitaldb-recorder-activity <vrcode> [--guest-control-url <url>]"
        )
        return RuntimeVitalDBReadCommand(
            action: .recorderActivity(vrcode),
            guestControlBaseURL: guestControlBaseURL
        )
    }

    public static func parseBedsCommand(_ arguments: [String]) throws -> RuntimeVitalDBReadCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime vitaldb-beds [--guest-control-url <url>]"
        )
        return RuntimeVitalDBReadCommand(action: .beds, guestControlBaseURL: guestControlBaseURL)
    }

    public static func parseRelationshipsCommand(_ arguments: [String]) throws -> RuntimeVitalDBReadCommand {
        let guestControlBaseURL = try parseGuestControlBaseURL(
            Array(arguments),
            usage: "usage: vitalserver-vm runtime vitaldb-relationships [--guest-control-url <url>]"
        )
        return RuntimeVitalDBReadCommand(action: .relationships, guestControlBaseURL: guestControlBaseURL)
    }

    private static func parseGuestControlBaseURL(
        _ arguments: [String],
        usage: String
    ) throws -> String {
        var remaining = arguments
        var guestControlBaseURL = RuntimeVitalDBReadCommand.defaultGuestControlBaseURL
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
