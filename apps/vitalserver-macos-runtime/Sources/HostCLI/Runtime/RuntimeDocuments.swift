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

extension GuestRuntimeConfigDocument {
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
