import MacPlatformAgent
import Foundation

@main
@MainActor
struct MacPlatformAgentServiceMain {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty {
            try MacPlatformAgentService.live().run()
        }
        let configuration = try RuntimeSmokeLaunchConfiguration.parse(arguments)
        try MacPlatformAgentService.runtimeSmoke(
            runtimeHome: URL(fileURLWithPath: configuration.runtimeHome),
            runtimeControlPort: configuration.runtimeControlPort,
            automationToken: configuration.automationToken,
            ntpServerPort: configuration.ntpServerPort
        ).run()
    }
}

private struct RuntimeSmokeLaunchConfiguration {
    let runtimeHome: String
    let runtimeControlPort: Int
    let automationToken: String
    let ntpServerPort: UInt16

    static func parse(_ arguments: [String]) throws -> Self {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard [
                "--runtime-home",
                "--runtime-control-port",
                "--automation-token",
                "--ntp-port",
            ].contains(option) else {
                throw RuntimeSmokeLaunchError.invalidArgument(option)
            }
            guard values[option] == nil else {
                throw RuntimeSmokeLaunchError.duplicateArgument(option)
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw RuntimeSmokeLaunchError.missingValue(option)
            }
            values[option] = arguments[valueIndex]
            index += 2
        }

        let runtimeHome = try requiredValue("--runtime-home", values: values)
        let automationToken = try requiredValue(
            "--automation-token",
            values: values
        )
        guard !runtimeHome.isEmpty else {
            throw RuntimeSmokeLaunchError.invalidValue("--runtime-home")
        }
        guard !automationToken.isEmpty else {
            throw RuntimeSmokeLaunchError.invalidValue("--automation-token")
        }
        let runtimeControlPort = try integerValue(
            "--runtime-control-port",
            values: values,
            range: 0...65_535
        )
        let ntpPort = try integerValue(
            "--ntp-port",
            values: values,
            range: 1...65_535
        )
        guard let ntpServerPort = UInt16(exactly: ntpPort) else {
            throw RuntimeSmokeLaunchError.invalidValue("--ntp-port")
        }
        return Self(
            runtimeHome: runtimeHome,
            runtimeControlPort: runtimeControlPort,
            automationToken: automationToken,
            ntpServerPort: ntpServerPort
        )
    }

    private static func requiredValue(
        _ option: String,
        values: [String: String]
    ) throws -> String {
        guard let value = values[option] else {
            throw RuntimeSmokeLaunchError.missingArgument(option)
        }
        return value
    }

    private static func integerValue(
        _ option: String,
        values: [String: String],
        range: ClosedRange<Int>
    ) throws -> Int {
        let value = try requiredValue(option, values: values)
        guard let integer = Int(value), range.contains(integer) else {
            throw RuntimeSmokeLaunchError.invalidValue(option)
        }
        return integer
    }
}

private enum RuntimeSmokeLaunchError: Error {
    case invalidArgument(String)
    case duplicateArgument(String)
    case missingArgument(String)
    case missingValue(String)
    case invalidValue(String)
}
