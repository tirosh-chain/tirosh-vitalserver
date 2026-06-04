import Foundation

public struct GuestRuntimeConfigDocument: Codable, Equatable, Sendable {
    public var vitalserverHttpPort: Int
    public var redisHost: String
    public var redisPort: Int
    public var trustProxy: Bool
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var adminPassword: String
    public var vitalFilesDirectory: String
    public var redisBackupRetentionCount: Int
    public var redisUiPort: Int
    public var swaggerUiPort: Int
    public var testkitEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case vitalserverHttpPort
        case redisHost
        case redisPort
        case trustProxy
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case adminPassword
        case vitalFilesDirectory
        case redisBackupRetentionCount
        case redisUiPort
        case swaggerUiPort
        case testkitEnabled
    }

    public init(
        vitalserverHttpPort: Int,
        redisHost: String,
        redisPort: Int,
        trustProxy: Bool,
        vitalServerURL: String = "",
        remoteConsoleURL: String = "",
        publicHost: String,
        publicPort: Int,
        adminPassword: String,
        vitalFilesDirectory: String,
        redisBackupRetentionCount: Int,
        redisUiPort: Int,
        swaggerUiPort: Int,
        testkitEnabled: Bool
    ) {
        self.vitalserverHttpPort = vitalserverHttpPort
        self.redisHost = redisHost
        self.redisPort = redisPort
        self.trustProxy = trustProxy
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.adminPassword = adminPassword
        self.vitalFilesDirectory = vitalFilesDirectory
        self.redisBackupRetentionCount = redisBackupRetentionCount
        self.redisUiPort = redisUiPort
        self.swaggerUiPort = swaggerUiPort
        self.testkitEnabled = testkitEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vitalserverHttpPort = try container.decode(Int.self, forKey: .vitalserverHttpPort)
        self.redisHost = try container.decode(String.self, forKey: .redisHost)
        self.redisPort = try container.decode(Int.self, forKey: .redisPort)
        self.trustProxy = try container.decode(Bool.self, forKey: .trustProxy)
        let publicHost = try container.decode(String.self, forKey: .publicHost)
        let publicPort = try container.decode(Int.self, forKey: .publicPort)
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.vitalServerURL = try container.decode(String.self, forKey: .vitalServerURL)
        self.remoteConsoleURL = try container.decode(String.self, forKey: .remoteConsoleURL)
        self.adminPassword = try container.decode(String.self, forKey: .adminPassword)
        self.vitalFilesDirectory = try container.decode(String.self, forKey: .vitalFilesDirectory)
        self.redisBackupRetentionCount = try container.decode(
            Int.self,
            forKey: .redisBackupRetentionCount
        )
        self.redisUiPort = try container.decode(Int.self, forKey: .redisUiPort)
        self.swaggerUiPort = try container.decode(Int.self, forKey: .swaggerUiPort)
        self.testkitEnabled = try container.decode(
            Bool.self,
            forKey: .testkitEnabled
        )
    }
}

public enum GuestRuntimeConfigDocumentMigration {
    public static func decodeCurrentOrLegacy(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> GuestRuntimeConfigDocument {
        do {
            return try decoder.decode(GuestRuntimeConfigDocument.self, from: data)
        } catch {
            return try decoder.decode(LegacyGuestRuntimeConfigDocument.self, from: data).migrated()
        }
    }
}

private struct LegacyGuestRuntimeConfigDocument: Decodable {
    let vitalserverHttpPort: Int
    let redisHost: String
    let redisPort: Int
    let trustProxy: Bool
    let vitalServerURL: String?
    let remoteConsoleURL: String?
    let publicHost: String
    let publicPort: Int
    let adminPassword: String
    let vitalFilesDirectory: String
    let redisBackupRetentionCount: Int
    let redisUiPort: Int
    let swaggerUiPort: Int
    let testkitEnabled: Bool

    func migrated() -> GuestRuntimeConfigDocument {
        GuestRuntimeConfigDocument(
            vitalserverHttpPort: vitalserverHttpPort,
            redisHost: redisHost,
            redisPort: redisPort,
            trustProxy: trustProxy,
            vitalServerURL: vitalServerURL ?? legacyVitalServerURL(publicHost: publicHost, publicPort: publicPort),
            remoteConsoleURL: remoteConsoleURL ?? "",
            publicHost: publicHost,
            publicPort: publicPort,
            adminPassword: adminPassword,
            vitalFilesDirectory: vitalFilesDirectory,
            redisBackupRetentionCount: redisBackupRetentionCount,
            redisUiPort: redisUiPort,
            swaggerUiPort: swaggerUiPort,
            testkitEnabled: testkitEnabled
        )
    }

    private func legacyVitalServerURL(publicHost: String, publicPort: Int) -> String {
        guard !publicHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return "http://\(publicHost):\(publicPort)/"
    }
}

public struct GuestRuntimeSettingsDocument: Codable, Equatable, Sendable {
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var redisBackupRetentionCount: Int

    public init(
        vitalServerURL: String,
        remoteConsoleURL: String,
        publicHost: String,
        publicPort: Int,
        redisBackupRetentionCount: Int
    ) {
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.redisBackupRetentionCount = redisBackupRetentionCount
    }

    public init(runtimeConfig: GuestRuntimeConfigDocument) {
        self.init(
            vitalServerURL: runtimeConfig.vitalServerURL,
            remoteConsoleURL: runtimeConfig.remoteConsoleURL,
            publicHost: runtimeConfig.publicHost,
            publicPort: runtimeConfig.publicPort,
            redisBackupRetentionCount: runtimeConfig.redisBackupRetentionCount
        )
    }
}
