import Foundation
import RuntimeControl

struct RuntimeSettingsValidator {
    private let vitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy()

    func validate(_ settings: RuntimeSettings, installedSettings: RuntimeSettings) -> RuntimeSettingsValidationResult {
        if settings.networkMode == RuntimeNetworkMode.bridged {
            return .invalid(AppConstants.StatusText.bridgedModeUnavailable)
        }
        if settings.diskGiB < installedSettings.diskGiB {
            return .invalid(AppConstants.StatusText.diskDecreaseUnavailable)
        }
        if !(1...65_535).contains(settings.proxyPort)
            || !(1...65_535).contains(settings.publicPort)
            || !(1...65_535).contains(settings.runtimeControlPort) {
            return .invalid(AppConstants.StatusText.invalidPort)
        }
        if !isValidAdvertisedURL(settings.vitalServerURL)
            || !isValidAdvertisedURL(settings.remoteConsoleURL) {
            return .invalid(AppConstants.StatusText.invalidAdvertisedURL)
        }
        if !(AppConstants.SettingsLimits.minimumRedisBackupRetentionCount...AppConstants.SettingsLimits.maximumRedisBackupRetentionCount)
            .contains(settings.redisBackupRetentionCount) {
            return .invalid(AppConstants.StatusText.invalidRedisBackupRetention)
        }
        if let message = vitalFilesDirectoryPolicy.validationMessage(for: settings.vitalFilesDirectory) {
            return .invalid(message)
        }
        if settings.changeAdminPassword, settings.adminPassword.isEmpty {
            return .invalid(AppConstants.StatusText.adminPasswordRequired)
        }
        if settings.changeAdminPassword, !isLineSafe(settings.adminPassword) {
            return .invalid(AppConstants.StatusText.adminPasswordNewline)
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

enum RuntimeSettingsValidationResult: Equatable {
    case valid
    case invalid(String)

    var isValid: Bool {
        self == .valid
    }
}
