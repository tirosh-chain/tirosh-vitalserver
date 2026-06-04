import Foundation
import Core
import Contracts

struct RuntimeVersionDocument: Encodable {
    let product: String
    let runtimeVersion: String
    let appliedAt: String
    let bundle: String
    let rootfsBase: String
    let vmDisk: String
}

struct InstalledRuntimeVersionDocument: Encodable {
    let product: String
    let runtimeVersion: String
    let installedAt: String
    let rootfsBase: String
    let vmDisk: String
}

struct GuestRuntimeConfigDocument: Codable {
    var vitalserverHttpPort: Int
    var redisHost: String
    var redisPort: Int
    var trustProxy: Bool
    var vitalServerURL: String
    var remoteConsoleURL: String
    var publicHost: String
    var publicPort: Int
    var adminPassword: String
    var vitalFilesDirectory: String
    var redisBackupRetentionCount: Int
    var redisUiPort: Int
    var swaggerUiPort: Int
    var testkitEnabled: Bool

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

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vitalserverHttpPort = try container.decode(Int.self, forKey: .vitalserverHttpPort)
        self.redisHost = try container.decode(String.self, forKey: .redisHost)
        self.redisPort = try container.decode(Int.self, forKey: .redisPort)
        self.trustProxy = try container.decode(Bool.self, forKey: .trustProxy)
        let publicHost = try container.decode(String.self, forKey: .publicHost)
        let publicPort = try container.decode(Int.self, forKey: .publicPort)
        self.publicHost = publicHost
        self.publicPort = publicPort
        self.vitalServerURL = try container.decodeIfPresent(String.self, forKey: .vitalServerURL)
            ?? Self.legacyVitalServerURL(publicHost: publicHost, publicPort: publicPort)
        self.remoteConsoleURL = try container.decodeIfPresent(String.self, forKey: .remoteConsoleURL) ?? ""
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

    static func load(from url: URL, fileStore: RuntimeFileReading) throws -> GuestRuntimeConfigDocument {
        guard fileStore.fileExists(url) else {
            throw LauncherError.missingFile(url.path)
        }
        let data = try fileStore.readData(url)
        return try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
    }

    static var `default`: GuestRuntimeConfigDocument {
        GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            vitalServerURL: "",
            remoteConsoleURL: "",
            publicHost: "",
            publicPort: Constants.Guest.publicPort,
            adminPassword: Constants.Guest.defaultAdminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisBackupRetentionCount: Constants.Defaults.redisBackupRetentionCount,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort,
            testkitEnabled: Constants.testkitContainerIncluded
        )
    }

    private static func legacyVitalServerURL(publicHost: String, publicPort: Int) -> String {
        guard !publicHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return "http://\(publicHost):\(publicPort)/"
    }
}

struct GuestRuntimeSettingsDocument: Codable, Equatable {
    var vitalServerURL: String
    var remoteConsoleURL: String
    var publicHost: String
    var publicPort: Int
    var redisBackupRetentionCount: Int

    init(
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

    init(runtimeConfig: GuestRuntimeConfigDocument) {
        self.init(
            vitalServerURL: runtimeConfig.vitalServerURL,
            remoteConsoleURL: runtimeConfig.remoteConsoleURL,
            publicHost: runtimeConfig.publicHost,
            publicPort: runtimeConfig.publicPort,
            redisBackupRetentionCount: runtimeConfig.redisBackupRetentionCount
        )
    }
}

struct BackupManifest: Codable, Equatable {
    let product: String
    let createdAt: String
    let reason: String
    let rootfsBase: String?
    let vmDisk: String
    let vmDiskPreserved: Bool
}

struct InstallSettings {
    static let defaultSettingsPath = Constants.InstallPaths.settingsPath
    static let defaultProxyPort = Constants.Guest.publicPort

    var cpuCount = 8
    var memoryGiB = Constants.Defaults.defaultMemoryGiB
    var diskGiB = Constants.Defaults.defaultDiskGiB
    var networkMode = NetworkMode.shared
    var proxyPort = defaultProxyPort
    var vitalFilesDirectory: String
    var adminPassword: String? = Constants.Guest.defaultAdminPassword
    var vmHostname = Constants.Guest.hostname
    var vitalServerURL = ""
    var remoteConsoleURL = ""
    var publicHost = ""
    var publicPort = Constants.Guest.publicPort
    var startAfterInstall = true
    var startOnBoot = true
    var preventSystemSleep = true

    static func load(
        path: String = defaultSettingsPath,
        defaultVitalFilesDirectory: String,
        fileStore: RuntimeFileReading
    ) throws -> InstallSettings {
        var settings = InstallSettings(
            vitalFilesDirectory: defaultVitalFilesDirectory
        )
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return settings
        }
        let data = try fileStore.readData(url)
        let document = try JSONDecoder().decode(InstallSettingsDocument.self, from: data)
        settings.apply(document: document)
        return settings
    }

    private mutating func apply(document: InstallSettingsDocument) {
        if let requestedCPUCount = document.cpuCount,
           requestedCPUCount >= Constants.Defaults.minimumCPUCount,
           requestedCPUCount <= Constants.Defaults.maximumAllowedCPUCount {
            cpuCount = requestedCPUCount
        }
        if let requestedMemoryGiB = document.memoryGiB,
           stride(
            from: Constants.Defaults.minimumMemoryGiB,
            through: Constants.Defaults.maximumAllowedMemoryGiB,
            by: Constants.Defaults.memoryStepGiB
           ).contains(requestedMemoryGiB) {
            memoryGiB = requestedMemoryGiB
        }
        if let requestedDiskGiB = document.diskGiB,
           stride(
            from: Constants.Defaults.minimumDiskGiB,
            through: Constants.Defaults.maximumDiskGiB,
            by: Constants.Defaults.diskStepGiB
           ).contains(requestedDiskGiB) {
            diskGiB = requestedDiskGiB
        }
        if let requestedNetworkMode = document.networkMode,
           let mode = NetworkMode(rawValue: requestedNetworkMode) {
            networkMode = mode
        }
        if let requestedProxyPort = document.proxyPort,
           requestedProxyPort >= 1,
           requestedProxyPort <= 65_535 {
            proxyPort = requestedProxyPort
        }
        if let requestedVitalFilesDirectory = document.vitalFilesDirectory,
           requestedVitalFilesDirectory.hasPrefix("/") {
            vitalFilesDirectory = requestedVitalFilesDirectory
        }
        if let requestedAdminPassword = document.adminPassword,
           !requestedAdminPassword.isEmpty,
           isLineSafe(requestedAdminPassword) {
            adminPassword = requestedAdminPassword
        }
        if let requestedVMHostname = document.vmHostname,
           isValidHostname(requestedVMHostname) {
            vmHostname = requestedVMHostname
        }
        if let requestedPublicHost = document.publicHost,
           isLineSafe(requestedPublicHost) {
            publicHost = requestedPublicHost
        }
        if let requestedPublicPort = document.publicPort,
           requestedPublicPort >= 1,
           requestedPublicPort <= 65_535 {
            publicPort = requestedPublicPort
        }
        if let requestedVitalServerURL = document.vitalServerURL,
           isValidAdvertisedURL(requestedVitalServerURL) {
            vitalServerURL = requestedVitalServerURL
            applyVitalServerURLCompatibilityFields(requestedVitalServerURL)
        }
        if let requestedRemoteConsoleURL = document.remoteConsoleURL,
           isValidAdvertisedURL(requestedRemoteConsoleURL) {
            remoteConsoleURL = requestedRemoteConsoleURL
        }
        if let requestedStartAfterInstall = document.startAfterInstall {
            startAfterInstall = requestedStartAfterInstall
        }
        if let requestedStartOnBoot = document.startOnBoot {
            startOnBoot = requestedStartOnBoot
        }
        if let requestedPreventSystemSleep = document.preventSystemSleep {
            preventSystemSleep = requestedPreventSystemSleep
        }
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 63 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let alphanumeric = CharacterSet.alphanumerics
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && value.unicodeScalars.first.map { alphanumeric.contains($0) } == true
    }

    private func isValidAdvertisedURL(_ value: String) -> Bool {
        if value.isEmpty {
            return true
        }
        guard isLineSafe(value),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return false
        }
        return true
    }

    private mutating func applyVitalServerURLCompatibilityFields(_ value: String) {
        guard let components = URLComponents(string: value),
              let host = components.host else {
            return
        }
        publicHost = host
        if let port = components.port {
            publicPort = port
        } else if components.scheme?.lowercased() == "https" {
            publicPort = 443
        } else {
            publicPort = Constants.Guest.publicPort
        }
    }
}

private struct InstallSettingsDocument: Decodable {
    let cpuCount: Int?
    let memoryGiB: Int?
    let diskGiB: Int?
    let networkMode: String?
    let proxyPort: Int?
    let vitalFilesDirectory: String?
    let adminPassword: String?
    let vmHostname: String?
    let vitalServerURL: String?
    let remoteConsoleURL: String?
    let publicHost: String?
    let publicPort: Int?
    let startAfterInstall: Bool?
    let startOnBoot: Bool?
    let preventSystemSleep: Bool?
}
