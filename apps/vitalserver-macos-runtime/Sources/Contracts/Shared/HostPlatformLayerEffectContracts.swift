public struct HostPlatformManagerEndpoint: Codable, Equatable, Sendable {
    public let executablePath: String
    public let databasePath: String
    public let installationRootPath: String
    public let launchctlExecutablePath: String
    public let exchangeRootPath: String

    public init(
        executablePath: String,
        databasePath: String,
        installationRootPath: String,
        launchctlExecutablePath: String,
        exchangeRootPath: String
    ) {
        self.executablePath = executablePath
        self.databasePath = databasePath
        self.installationRootPath = installationRootPath
        self.launchctlExecutablePath = launchctlExecutablePath
        self.exchangeRootPath = exchangeRootPath
    }
}

public struct HostPlatformLayerTransition: Codable, Equatable, Sendable {
    public let installationId: String
    public let expectedInstallationRevision: Int
    public let targetReleaseId: String
    public let targetReleaseVersion: String
    public let targetSlotRelativePath: String

    public init(
        installationId: String,
        expectedInstallationRevision: Int,
        targetReleaseId: String,
        targetReleaseVersion: String,
        targetSlotRelativePath: String
    ) {
        self.installationId = installationId
        self.expectedInstallationRevision = expectedInstallationRevision
        self.targetReleaseId = targetReleaseId
        self.targetReleaseVersion = targetReleaseVersion
        self.targetSlotRelativePath = targetSlotRelativePath
    }
}

public struct HostPlatformLayerEffectConfiguration:
    Codable, Equatable, Sendable
{
    public let schemaVersion: String
    public let effectExecutorId: String
    public let manager: HostPlatformManagerEndpoint
    public let apply: HostPlatformLayerTransition
    public let rollback: HostPlatformLayerTransition

    public init(
        schemaVersion: String,
        effectExecutorId: String,
        manager: HostPlatformManagerEndpoint,
        apply: HostPlatformLayerTransition,
        rollback: HostPlatformLayerTransition
    ) {
        self.schemaVersion = schemaVersion
        self.effectExecutorId = effectExecutorId
        self.manager = manager
        self.apply = apply
        self.rollback = rollback
    }
}
