public enum RuntimePackageInstallIntent: String, Codable, Equatable, Sendable {
    case fresh
    case sameVersionRepair = "same-version-repair"
    case upgrade
    case downgrade
}

public struct RuntimePackageInstallContract: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let packageIdentifier: String
    public let targetVersion: RuntimePackageVersion
    public let intent: RuntimePackageInstallIntent

    public init(
        schemaVersion: Int = RuntimePackageInstallContract.currentSchemaVersion,
        packageIdentifier: String,
        targetVersion: RuntimePackageVersion,
        intent: RuntimePackageInstallIntent
    ) {
        self.schemaVersion = schemaVersion
        self.packageIdentifier = packageIdentifier
        self.targetVersion = targetVersion
        self.intent = intent
    }
}
