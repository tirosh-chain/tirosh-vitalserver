import Foundation
import RuntimeControl
import Errors

public struct RuntimeSettingsValidator {
    private let vitalFilesDirectoryPolicy: RuntimeVitalFilesDirectoryPolicy
    private let redisBackupRetentionRange: ClosedRange<Int>

    public init(
        vitalFilesDirectoryPolicy: RuntimeVitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy(),
        redisBackupRetentionRange: ClosedRange<Int> = 1...30
    ) {
        self.vitalFilesDirectoryPolicy = vitalFilesDirectoryPolicy
        self.redisBackupRetentionRange = redisBackupRetentionRange
    }

    public func validate(
        _ settings: RuntimeSettings,
        installedSettings: RuntimeSettings
    ) -> RuntimeSettingsValidationResult {
        if settings.networkMode == RuntimeNetworkMode.bridged {
            return .invalid("Bridged mode is not available in this build.")
        }
        if settings.diskGiB < installedSettings.diskGiB {
            return .invalid("Disk size can only be increased.")
        }
        if !(1...65_535).contains(settings.proxyPort)
            || !(1...65_535).contains(settings.publicPort)
            || !(1...65_535).contains(settings.runtimeControlPort) {
            return .invalid("Port must be between 1 and 65535.")
        }
        if !isValidAdvertisedURL(settings.vitalServerURL)
            || !isValidAdvertisedURL(settings.remoteConsoleURL) {
            return .invalid("Advertised URLs must be absolute http/https URLs.")
        }
        if !redisBackupRetentionRange.contains(settings.redisBackupRetentionCount) {
            return .invalid("VitalServer Helper backups must be between 1 and 30 archives.")
        }
        if let message = vitalFilesDirectoryPolicy.validationMessage(for: settings.vitalFilesDirectory) {
            return .invalid(message)
        }
        if settings.changeAdminPassword, settings.adminPassword.isEmpty {
            return .invalid("Admin password reset value must not be empty.")
        }
        if settings.changeAdminPassword, !isLineSafe(settings.adminPassword) {
            return .invalid("Admin password reset value must not contain newlines.")
        }
        return .valid
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func isValidAdvertisedURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == value,
              isLineSafe(value),
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
}

public enum RuntimeSettingsValidationResult: Equatable {
    case valid
    case invalid(String)

    public var isValid: Bool {
        self == .valid
    }
}
