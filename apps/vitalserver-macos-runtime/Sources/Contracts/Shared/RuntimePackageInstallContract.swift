public enum RuntimePackageInstallMode: String, Codable, Equatable, Sendable {
    case fresh
    case reinstall
}

public struct RuntimePackageInstallContract: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let packageIdentifier: String
    public let mode: RuntimePackageInstallMode

    public init(
        schemaVersion: Int = RuntimePackageInstallContract.currentSchemaVersion,
        packageIdentifier: String,
        mode: RuntimePackageInstallMode
    ) {
        self.schemaVersion = schemaVersion
        self.packageIdentifier = packageIdentifier
        self.mode = mode
    }
}
