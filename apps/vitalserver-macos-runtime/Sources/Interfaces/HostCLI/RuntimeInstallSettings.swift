import Application
import Contracts
import Foundation

public enum RuntimeInstallSettingsError: Error, Equatable {
    case missingArgument(String)
}

public struct RuntimeInstallSettingsDefaults: Equatable, Sendable {
    public let cpuCount: Int
    public let memoryGiB: Int
    public let diskGiB: Int
    public let networkMode: RuntimeNetworkMode
    public let proxyPort: Int
    public let adminPassword: String
    public let vmHostname: String
    public let publicPort: Int
    public let minimumCPUCount: Int
    public let maximumAllowedCPUCount: Int
    public let minimumMemoryGiB: Int
    public let maximumAllowedMemoryGiB: Int
    public let memoryStepGiB: Int
    public let minimumDiskGiB: Int
    public let maximumDiskGiB: Int
    public let diskStepGiB: Int

    public init(
        cpuCount: Int,
        memoryGiB: Int,
        diskGiB: Int,
        networkMode: RuntimeNetworkMode,
        proxyPort: Int,
        adminPassword: String,
        vmHostname: String,
        publicPort: Int,
        minimumCPUCount: Int,
        maximumAllowedCPUCount: Int,
        minimumMemoryGiB: Int,
        maximumAllowedMemoryGiB: Int,
        memoryStepGiB: Int,
        minimumDiskGiB: Int,
        maximumDiskGiB: Int,
        diskStepGiB: Int
    ) {
        self.cpuCount = cpuCount
        self.memoryGiB = memoryGiB
        self.diskGiB = diskGiB
        self.networkMode = networkMode
        self.proxyPort = proxyPort
        self.adminPassword = adminPassword
        self.vmHostname = vmHostname
        self.publicPort = publicPort
        self.minimumCPUCount = minimumCPUCount
        self.maximumAllowedCPUCount = maximumAllowedCPUCount
        self.minimumMemoryGiB = minimumMemoryGiB
        self.maximumAllowedMemoryGiB = maximumAllowedMemoryGiB
        self.memoryStepGiB = memoryStepGiB
        self.minimumDiskGiB = minimumDiskGiB
        self.maximumDiskGiB = maximumDiskGiB
        self.diskStepGiB = diskStepGiB
    }
}

public struct RuntimeInstallSettings: Equatable, Sendable {
    public var cpuCount: Int
    public var memoryGiB: Int
    public var diskGiB: Int
    public var networkMode: RuntimeNetworkMode
    public var proxyPort: Int
    public var vitalFilesDirectory: String
    public var adminPassword: String?
    public var vmHostname: String
    public var sshAuthorizedKeys: [String]
    public var vitalServerURL: String
    public var remoteConsoleURL: String
    public var publicHost: String
    public var publicPort: Int
    public var startAfterInstall: Bool
    public var startOnBoot: Bool
    public var preventSystemSleep: Bool

    public init(vitalFilesDirectory: String, defaults: RuntimeInstallSettingsDefaults) {
        self.cpuCount = defaults.cpuCount
        self.memoryGiB = defaults.memoryGiB
        self.diskGiB = defaults.diskGiB
        self.networkMode = defaults.networkMode
        self.proxyPort = defaults.proxyPort
        self.vitalFilesDirectory = vitalFilesDirectory
        self.adminPassword = defaults.adminPassword
        self.vmHostname = defaults.vmHostname
        self.sshAuthorizedKeys = []
        self.vitalServerURL = ""
        self.remoteConsoleURL = ""
        self.publicHost = ""
        self.publicPort = defaults.publicPort
        self.startAfterInstall = true
        self.startOnBoot = true
        self.preventSystemSleep = true
    }

    public static func load(
        path: String,
        defaultVitalFilesDirectory: String,
        fileStore: RuntimeFileReading,
        defaults: RuntimeInstallSettingsDefaults
    ) throws -> RuntimeInstallSettings {
        var settings = RuntimeInstallSettings(
            vitalFilesDirectory: defaultVitalFilesDirectory,
            defaults: defaults
        )
        let url = URL(fileURLWithPath: path)
        guard fileStore.fileExists(url) else {
            return settings
        }
        let data = try fileStore.readData(url)
        let document = try JSONDecoder().decode(RuntimeInstallSettingsDocument.self, from: data)
        try settings.apply(document: document, defaults: defaults)
        return settings
    }

    private mutating func apply(
        document: RuntimeInstallSettingsDocument,
        defaults: RuntimeInstallSettingsDefaults
    ) throws {
        if let requestedCPUCount = document.cpuCount,
           requestedCPUCount >= defaults.minimumCPUCount,
           requestedCPUCount <= defaults.maximumAllowedCPUCount {
            cpuCount = requestedCPUCount
        }
        if let requestedMemoryGiB = document.memoryGiB,
           stride(
            from: defaults.minimumMemoryGiB,
            through: defaults.maximumAllowedMemoryGiB,
            by: defaults.memoryStepGiB
           ).contains(requestedMemoryGiB) {
            memoryGiB = requestedMemoryGiB
        }
        if let requestedDiskGiB = document.diskGiB,
           stride(
            from: defaults.minimumDiskGiB,
            through: defaults.maximumDiskGiB,
            by: defaults.diskStepGiB
           ).contains(requestedDiskGiB) {
            diskGiB = requestedDiskGiB
        }
        if let requestedNetworkMode = document.networkMode,
           let mode = RuntimeNetworkMode(rawValue: requestedNetworkMode) {
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
        if let requestedSSHAuthorizedKeys = document.sshAuthorizedKeys {
            sshAuthorizedKeys = try normalizedSSHAuthorizedKeys(requestedSSHAuthorizedKeys)
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
            applyVitalServerURLCompatibilityFields(requestedVitalServerURL, defaultPublicPort: defaults.publicPort)
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

    private mutating func applyVitalServerURLCompatibilityFields(_ value: String, defaultPublicPort: Int) {
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
            publicPort = defaultPublicPort
        }
    }

    private func normalizedSSHAuthorizedKeys(_ values: [String]) throws -> [String] {
        try values.enumerated().map { index, value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidSSHPublicKey(normalized) else {
                throw RuntimeInstallSettingsError.missingArgument(
                    "install settings sshAuthorizedKeys[\(index)] must be an OpenSSH public key"
                )
            }
            return normalized
        }
    }

    private func isValidSSHPublicKey(_ value: String) -> Bool {
        guard isLineSafe(value) else {
            return false
        }
        let parts = value.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return false
        }
        let keyType = String(parts[0])
        guard isSupportedSSHPublicKeyType(keyType) else {
            return false
        }
        let keyMaterial = String(parts[1])
        guard !keyMaterial.isEmpty else {
            return false
        }
        let allowedKeyMaterial = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        return keyMaterial.unicodeScalars.allSatisfy { allowedKeyMaterial.contains($0) }
    }

    private func isSupportedSSHPublicKeyType(_ value: String) -> Bool {
        value == "ssh-ed25519"
            || value == "ssh-rsa"
            || value == "ecdsa-sha2-nistp256"
            || value == "ecdsa-sha2-nistp384"
            || value == "ecdsa-sha2-nistp521"
            || value == "sk-ssh-ed25519@openssh.com"
            || value == "sk-ecdsa-sha2-nistp256@openssh.com"
    }
}

private struct RuntimeInstallSettingsDocument: Decodable {
    let cpuCount: Int?
    let memoryGiB: Int?
    let diskGiB: Int?
    let networkMode: String?
    let proxyPort: Int?
    let vitalFilesDirectory: String?
    let adminPassword: String?
    let vmHostname: String?
    let sshAuthorizedKeys: [String]?
    let vitalServerURL: String?
    let remoteConsoleURL: String?
    let publicHost: String?
    let publicPort: Int?
    let startAfterInstall: Bool?
    let startOnBoot: Bool?
    let preventSystemSleep: Bool?
}
