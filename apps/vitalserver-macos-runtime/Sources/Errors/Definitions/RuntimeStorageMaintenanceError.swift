import Foundation

public enum RuntimeStorageMaintenanceError: Error, CustomStringConvertible, Equatable {
    case freeSpaceUnavailable(path: String)
    case insufficientFreeSpace(operation: String, required: UInt64, available: UInt64)

    public var description: String {
        switch self {
        case .freeSpaceUnavailable(let path):
            return "could not determine free space for \(path)"
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
