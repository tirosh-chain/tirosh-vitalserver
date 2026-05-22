import Foundation

enum RuntimeLifecycleCommand: Equatable {
    case install
    case status
    case health
    case watchdog
    case configure([String])
    case verifyBundle(URL)
    case stageBundle(URL)
    case applyBundle(URL)
    case rollback(URL?)
    case repairDatastore
    case startServices
    case stopServices
    case help

    static func parse(_ arguments: [String]) throws -> RuntimeLifecycleCommand {
        guard let command = arguments.first else {
            return .help
        }

        let remaining = Array(arguments.dropFirst())
        switch command {
        case "install":
            return .install
        case "status":
            return .status
        case "health":
            return .health
        case "watchdog":
            return .watchdog
        case "configure":
            return .configure(remaining)
        case "verify-bundle":
            return .verifyBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime verify-bundle <bundle.tar.gz>"
            ))
        case "stage-bundle":
            return .stageBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>"
            ))
        case "apply-bundle":
            return .applyBundle(try requiredBundleURL(
                in: remaining,
                usage: "usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz>"
            ))
        case "rollback":
            return .rollback(remaining.first.map { URL(fileURLWithPath: $0) })
        case "repair-datastore":
            return .repairDatastore
        case "start-services":
            return .startServices
        case "stop-services":
            return .stopServices
        case "-h", "--help", "help":
            return .help
        default:
            throw LauncherError.unsupportedCommand("runtime \(command)")
        }
    }

    static let usage = """
    Usage:
      vitalserver-vm runtime install
      vitalserver-vm runtime status
      vitalserver-vm runtime health
      vitalserver-vm runtime watchdog
      vitalserver-vm runtime configure [--cpu <count>] [--memory-gib <gib>] [--disk-gib <gib>] [--network shared|bridged] [--bridged-interface <id>] [--proxy-port <port>] [--vital-files-dir <path>] [--public-host <host>] [--public-port <port>] [--admin-password <password>] [--start-on-boot true|false] [--restart]
      vitalserver-vm runtime configure [--admin-password-file <path>] [--restart]
      vitalserver-vm runtime verify-bundle <bundle.tar.gz>
      vitalserver-vm runtime stage-bundle <bundle.tar.gz>
      vitalserver-vm runtime apply-bundle <bundle.tar.gz>
      vitalserver-vm runtime rollback [backup-dir]
      vitalserver-vm runtime repair-datastore
      vitalserver-vm runtime start-services
      vitalserver-vm runtime stop-services
    """

    private static func requiredBundleURL(in arguments: [String], usage: String) throws -> URL {
        guard let bundlePath = arguments.first else {
            throw LauncherError.missingArgument(usage)
        }
        return URL(fileURLWithPath: bundlePath)
    }
}
