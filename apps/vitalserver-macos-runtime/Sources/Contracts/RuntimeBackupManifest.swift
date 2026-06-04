import Foundation

public struct BackupManifest: Codable, Equatable {
    public let product: String
    public let createdAt: String
    public let reason: String
    public let rootfsBase: String?
    public let vmDisk: String
    public let vmDiskPreserved: Bool

    public init(
        product: String,
        createdAt: String,
        reason: String,
        rootfsBase: String?,
        vmDisk: String,
        vmDiskPreserved: Bool
    ) {
        self.product = product
        self.createdAt = createdAt
        self.reason = reason
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmDiskPreserved = vmDiskPreserved
    }
}
