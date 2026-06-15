import Foundation

public struct RuntimeVersionDocument: Codable, Equatable, Sendable {
    public let product: String
    public let runtimeVersion: String
    public let appliedAt: String
    public let bundle: String
    public let rootfsBase: String
    public let vmDisk: String

    public init(
        product: String,
        runtimeVersion: String,
        appliedAt: String,
        bundle: String,
        rootfsBase: String,
        vmDisk: String
    ) {
        self.product = product
        self.runtimeVersion = runtimeVersion
        self.appliedAt = appliedAt
        self.bundle = bundle
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}

public struct InstalledRuntimeVersionDocument: Codable, Equatable, Sendable {
    public let product: String
    public let runtimeVersion: String
    public let installedAt: String
    public let rootfsBase: String
    public let vmDisk: String

    public init(
        product: String,
        runtimeVersion: String,
        installedAt: String,
        rootfsBase: String,
        vmDisk: String
    ) {
        self.product = product
        self.runtimeVersion = runtimeVersion
        self.installedAt = installedAt
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}
