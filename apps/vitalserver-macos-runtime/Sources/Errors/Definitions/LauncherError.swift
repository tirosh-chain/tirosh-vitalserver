import Foundation

public enum LauncherError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unsupportedCommand(String)
    case missingConfig(URL)
    case missingFile(String)
    case bridgedInterfaceUnavailable(String)
    case noBridgedInterfaces
    case invalidMacAddress(String)
    case runtimeHealthFailed
    case runtimeOperationFailed(String)
    case bundleVerificationFailed(String)
    case insufficientFreeSpace(operation: String, required: UInt64, available: UInt64)

    public var description: String {
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
        case let .runtimeOperationFailed(message):
            return message
        case let .bundleVerificationFailed(message):
            return "bundle verification failed: \(message)"
        case let .insufficientFreeSpace(operation, required, available):
            return "insufficient free space for \(operation): required \(formatBytes(required)), available \(formatBytes(available))"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
