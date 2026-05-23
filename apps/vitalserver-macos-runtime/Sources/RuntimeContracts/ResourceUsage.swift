import Foundation

public struct ResourceUsage: Codable, Equatable {
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(usedBytes: Int64, totalBytes: Int64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var percent: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return min(max((Double(usedBytes) / Double(totalBytes)) * 100.0, 0), 100)
    }
}

