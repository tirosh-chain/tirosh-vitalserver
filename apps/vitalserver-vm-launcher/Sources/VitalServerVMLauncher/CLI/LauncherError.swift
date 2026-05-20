import Foundation

enum LauncherError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unsupportedCommand(String)
    case missingConfig(URL)
    case missingFile(String)
    case bridgedInterfaceUnavailable(String)
    case noBridgedInterfaces
    case invalidMacAddress(String)
    case runtimeHealthFailed
    case bundleVerificationFailed(String)

    var description: String {
        switch self {
        case let .missingArgument(message):
            return message
        case let .unsupportedCommand(command):
            return "unsupported command: \(command)"
        case let .missingConfig(url):
            return "missing config: \(url.path). Run `vitalserver-vm init` first."
        case let .missingFile(path):
            return "missing file: \(path)"
        case let .bridgedInterfaceUnavailable(identifier):
            return "bridged interface is not available: \(identifier)"
        case .noBridgedInterfaces:
            return "no bridged network interfaces are available"
        case let .invalidMacAddress(value):
            return "invalid MAC address: \(value)"
        case .runtimeHealthFailed:
            return "runtime health check failed"
        case let .bundleVerificationFailed(message):
            return "bundle verification failed: \(message)"
        }
    }
}
