import Foundation

public struct RuntimeDataBackupStorePaths {
    public var backupsDirectory: URL
    public var runtimeHome: URL
    public var runtimeVersion: URL
    public var vmConfig: URL
    public var guestRuntimeConfig: URL
    public var guestRuntimeSettings: URL
    public var proxyLaunchDaemon: URL
    public var runtimeStatus: URL
    public var runtimeEvents: URL
    public var runtimeObservabilityDatabase: URL

    public init(
        backupsDirectory: URL,
        runtimeHome: URL,
        runtimeVersion: URL,
        vmConfig: URL,
        guestRuntimeConfig: URL,
        guestRuntimeSettings: URL,
        proxyLaunchDaemon: URL,
        runtimeStatus: URL,
        runtimeEvents: URL,
        runtimeObservabilityDatabase: URL
    ) {
        self.backupsDirectory = backupsDirectory
        self.runtimeHome = runtimeHome
        self.runtimeVersion = runtimeVersion
        self.vmConfig = vmConfig
        self.guestRuntimeConfig = guestRuntimeConfig
        self.guestRuntimeSettings = guestRuntimeSettings
        self.proxyLaunchDaemon = proxyLaunchDaemon
        self.runtimeStatus = runtimeStatus
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDatabase = runtimeObservabilityDatabase
    }
}

public struct RuntimeDataBackupStoreMetadata {
    public var productIdentifier: String
    public var manifestName: String
    public var redisVolumeName: String

    public init(
        productIdentifier: String,
        manifestName: String,
        redisVolumeName: String
    ) {
        self.productIdentifier = productIdentifier
        self.manifestName = manifestName
        self.redisVolumeName = redisVolumeName
    }
}
