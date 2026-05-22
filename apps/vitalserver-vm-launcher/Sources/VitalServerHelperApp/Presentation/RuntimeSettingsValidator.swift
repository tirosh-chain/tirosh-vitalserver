import Foundation

struct RuntimeSettingsValidator {
    func validate(_ settings: RuntimeSettings, installedSettings: RuntimeSettings) -> RuntimeSettingsValidationResult {
        if settings.networkMode == AppConstants.Values.networkBridged {
            return .invalid(AppConstants.StatusText.bridgedModeUnavailable)
        }
        if settings.diskGiB < installedSettings.diskGiB {
            return .invalid(AppConstants.StatusText.diskDecreaseUnavailable)
        }
        if !(1...65_535).contains(settings.proxyPort) || !(1...65_535).contains(settings.publicPort) {
            return .invalid(AppConstants.StatusText.invalidPort)
        }
        if settings.vitalFilesDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !settings.vitalFilesDirectory.hasPrefix("/") {
            return .invalid(AppConstants.StatusText.vitalFilesDirectoryRequired)
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
