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
        self.redisUiPort = try container.decode(Int.self, forKey: .redisUiPort)
        self.swaggerUiPort = try container.decode(Int.self, forKey: .swaggerUiPort)
        self.testkitEnabled = try container.decode(
            Bool.self,
            forKey: .testkitEnabled
        )
    }
}

public struct GuestRuntimeSettingsDocument: Codable, Equatable, Sendable {
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode
    public var automaticBackupEnabled: Bool
    public var backupScheduleTimes: [String]
    public var backupRetentionCount: Int

    enum CodingKeys: String, CodingKey {
        case vitalServerURL
        case remoteConsoleURL
        case publicHost
        case publicPort
        case recorderIngressSendDataMode
        case automaticBackupEnabled
        case backupScheduleTimes
        case backupRetentionCount
    }

    public init(
        vitalServerURL: String,
        remoteConsoleURL: String,
        publicHost: String,
        publicPort: Int,
        recorderIngressSendDataMode: RuntimeRecorderIngressSendDataMode = RuntimeRecorderIngressDefaults.sendDataMode,
        automaticBackupEnabled: Bool = RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled,
        backupScheduleTimes: [String] = RuntimeSettingsInitialBackupDefaults.backupScheduleTimes,
        backupRetentionCount: Int = RuntimeSettingsInitialBackupDefaults.backupRetentionCount
    ) {
        self.vitalServerURL = vitalServerURL
        self.remoteConsoleURL = remoteConsoleURL
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.recorderIngressSendDataMode = recorderIngressSendDataMode
        self.automaticBackupEnabled = automaticBackupEnabled
        self.backupScheduleTimes = backupScheduleTimes
        self.backupRetentionCount = backupRetentionCount
    }

    public init(runtimeConfig: GuestRuntimeConfigDocument) {
        self.init(
            vitalServerURL: runtimeConfig.vitalServerURL,
            remoteConsoleURL: runtimeConfig.remoteConsoleURL,
            publicHost: runtimeConfig.publicHost,
            publicPort: runtimeConfig.publicPort
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vitalServerURL: try container.decode(String.self, forKey: .vitalServerURL),
            remoteConsoleURL: try container.decode(String.self, forKey: .remoteConsoleURL),
            publicHost: try container.decode(String.self, forKey: .publicHost),
            publicPort: try container.decode(Int.self, forKey: .publicPort),
            recorderIngressSendDataMode: try container.decodeIfPresent(
                RuntimeRecorderIngressSendDataMode.self,
                forKey: .recorderIngressSendDataMode
            ) ?? RuntimeRecorderIngressDefaults.sendDataMode,
            automaticBackupEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticBackupEnabled
            ) ?? RuntimeSettingsInitialBackupDefaults.automaticBackupEnabled,
            backupScheduleTimes: try container.decodeIfPresent(
                [String].self,
                forKey: .backupScheduleTimes
            ) ?? RuntimeSettingsInitialBackupDefaults.backupScheduleTimes,
            backupRetentionCount: try container.decodeIfPresent(
                Int.self,
                forKey: .backupRetentionCount
            ) ?? RuntimeSettingsInitialBackupDefaults.backupRetentionCount
        )
    }
}

public enum RuntimeRecorderIngressSendDataMode: String, Codable, CaseIterable, Equatable, Sendable {
    case passthrough
    case mirrorSpool = "mirror_spool"
    case spoolOnly = "spool_only"
    case spoolAndReplay = "spool_and_replay"
}

public enum RuntimeRecorderIngressDefaults {
    public static let sendDataMode = RuntimeRecorderIngressSendDataMode.spoolAndReplay
}

public enum RuntimeSettingsInitialBackupDefaults {
    public static let automaticBackupEnabled = true
    public static let backupScheduleTimes = ["03:15"]
    public static let backupRetentionCount = 30
}
