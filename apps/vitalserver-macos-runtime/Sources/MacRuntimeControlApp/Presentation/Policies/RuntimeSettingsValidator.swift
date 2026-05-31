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
}

enum RuntimeSettingsValidationResult: Equatable {
    case valid
    case invalid(String)

    var isValid: Bool {
        self == .valid
    }
}
