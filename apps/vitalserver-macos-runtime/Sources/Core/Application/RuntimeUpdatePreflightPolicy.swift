import Contracts

public struct RuntimeUpdateStorageRequirement: Equatable, Sendable {
    public let requiredBytes: UInt64
    public let stagedBundleBytes: UInt64
    public let installedRootfsBytes: UInt64?
    public let incomingRootfsBytes: UInt64?

    public init(
        requiredBytes: UInt64,
        stagedBundleBytes: UInt64,
        installedRootfsBytes: UInt64?,
        incomingRootfsBytes: UInt64?
    ) {
        self.requiredBytes = requiredBytes
        self.stagedBundleBytes = stagedBundleBytes
        self.installedRootfsBytes = installedRootfsBytes
        self.incomingRootfsBytes = incomingRootfsBytes
    }
}

public enum RuntimeUpdatePreflightPolicy {
    public static func checkCompatibility(
        manifest: UpdateBundleManifest,
        currentUpdaterVersion: String,
        currentChannel: UpdateBundleChannel,
        currentPlatform: String?
    ) throws {
        try RuntimeUpdateCompatibilityChecker.check(
            manifest: manifest,
            currentUpdaterVersion: currentUpdaterVersion,
            currentChannel: currentChannel,
            currentPlatform: currentPlatform
        )
    }

    public static func storageRequirement(
        stagedBundleBytes: UInt64,
        installedRootfsBytes: UInt64?,
        incomingRootfsBytes: UInt64?,
        marginBytes: UInt64
    ) -> RuntimeUpdateStorageRequirement {
        let rootfsBytes = (installedRootfsBytes ?? 0) + (incomingRootfsBytes ?? 0)
        return RuntimeUpdateStorageRequirement(
            requiredBytes: marginBytes + stagedBundleBytes + rootfsBytes,
            stagedBundleBytes: stagedBundleBytes,
            installedRootfsBytes: installedRootfsBytes,
            incomingRootfsBytes: incomingRootfsBytes
        )
    }
}
