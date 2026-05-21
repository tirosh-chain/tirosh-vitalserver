import Foundation

struct UpdateBundleManifest: Decodable {
    let schemaVersion: Int
    let product: String
    let version: String
    let runtimeVersion: String
    let createdAt: String
    let artifacts: [UpdateBundleArtifact]
    let migrations: [UpdateBundleMigration]
}

struct UpdateBundleArtifact: Decodable {
    let name: String
    let type: String
    let sha256: String
    let size: Int
}

struct UpdateBundleMigration: Decodable {
    let name: String
    let sha256: String
    let size: Int
}

struct RuntimeProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct RuntimeHealthSnapshot {
    let vmExecutable: Bool
    let proxyExecutable: Bool
    let rootfsBase: String
    let vmDisk: String
    let vmService: String
    let proxyService: String
    let watchdogService: String
    let vmIP: String?
    let proxyPort: Int
    let hostProxyHTTP: String
    let guestHTTP: String
    let redisUIHTTP: String
    let swaggerUIHTTP: String
    let failureReasons: [String]

    var isHealthy: Bool {
        failureReasons.isEmpty
    }
}

struct GuestRuntimeStateDocument: Decodable {
    let vmIP: String
    let updatedAt: String?
    let bootID: String?
    let guestHTTP: String?
    let redisUIHTTP: String?
    let swaggerUIHTTP: String?

    static func load(from url: URL) -> GuestRuntimeStateDocument? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
    }
}

enum RuntimeStatusLevel: String, Encodable {
    case installing
    case updating
    case recovering
    case healthy
    case degraded
    case critical
}

struct RuntimeStatusDocument: Encodable {
    let product: String
    let status: String
    let operation: String
    let message: String
    let updatedAt: String
    let productRoot: String
    let runtimeHome: String
    let runtimeVersion: String
    let vmService: String
    let proxyService: String
    let watchdogService: String
    let vmIP: String?
    let proxyPort: Int
    let hostProxyHTTP: String
    let guestHTTP: String
    let redisUIHTTP: String
    let swaggerUIHTTP: String
    let rootfsBase: String
    let vmDisk: String
    let failureReasons: [String]
    let latestBackup: String?
}

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
    var publicHost: String
    var publicPort: Int
    var adminPassword: String
    var vitalFilesDirectory: String
    var redisUiPort: Int
    var swaggerUiPort: Int

    static func load(from url: URL) throws -> GuestRuntimeConfigDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GuestRuntimeConfigDocument.default
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
    }

    static var `default`: GuestRuntimeConfigDocument {
        GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            publicHost: "",
            publicPort: Constants.Guest.publicPort,
            adminPassword: Constants.Guest.defaultAdminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort
        )
    }
}

struct BackupManifest: Encodable {
    let product: String
    let createdAt: String
    let reason: String
    let rootfsBase: String
    let vmDisk: String
    let vmDiskPreserved: Bool
}

struct InstallSettings {
    static let defaultSettingsPath = Constants.InstallPaths.settingsPath
    static let defaultProxyPort = Constants.Guest.publicPort

    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = 64
    var networkMode = NetworkMode.shared
    var proxyPort = defaultProxyPort
    var vitalFilesDirectory: String
    var adminPassword: String?
    var vmHostname = Constants.Guest.hostname
    var publicHost = ""
    var publicPort = Constants.Guest.publicPort
    var startAfterInstall = true
    var startOnBoot = true

    static func load(
        path: String = defaultSettingsPath,
        defaultVitalFilesDirectory: String
    ) throws -> InstallSettings {
        var settings = InstallSettings(
            vitalFilesDirectory: defaultVitalFilesDirectory
        )
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return settings
        }
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(InstallSettingsDocument.self, from: data)
        settings.apply(document: document)
        return settings
    }

    private mutating func apply(document: InstallSettingsDocument) {
        if let requestedCPUCount = document.cpuCount,
           requestedCPUCount >= Constants.Defaults.minimumCPUCount,
           requestedCPUCount <= Constants.Defaults.maximumCPUCount {
            cpuCount = requestedCPUCount
        }
        if let requestedMemoryGiB = document.memoryGiB,
           stride(from: 4, through: 64, by: 4).contains(requestedMemoryGiB) {
            memoryGiB = requestedMemoryGiB
        }
        if let requestedDiskGiB = document.diskGiB,
           stride(from: 32, through: 512, by: 16).contains(requestedDiskGiB) {
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
           !requestedAdminPassword.isEmpty {
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
        if let requestedStartAfterInstall = document.startAfterInstall {
            startAfterInstall = requestedStartAfterInstall
        }
        if let requestedStartOnBoot = document.startOnBoot {
            startOnBoot = requestedStartOnBoot
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
    let publicHost: String?
    let publicPort: Int?
    let startAfterInstall: Bool?
    let startOnBoot: Bool?
}
