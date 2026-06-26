import Foundation
import Contracts
import RuntimeControl
import Errors

public struct RuntimeSettingsValidator {
    private let vitalFilesDirectoryPolicy: RuntimeVitalFilesDirectoryPolicy
    private let backupRetentionRange: ClosedRange<Int>

    public init(
        vitalFilesDirectoryPolicy: RuntimeVitalFilesDirectoryPolicy = RuntimeVitalFilesDirectoryPolicy(),
        backupRetentionRange: ClosedRange<Int> = 1...30
    ) {
        self.vitalFilesDirectoryPolicy = vitalFilesDirectoryPolicy
        self.backupRetentionRange = backupRetentionRange
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
        if !backupRetentionRange.contains(settings.backupRetentionCount)
            || !RuntimeBackupSchedulePolicy.isValidRetentionCount(settings.backupRetentionCount) {
            return .invalid("VitalServer Helper backups must be between 1 and 30 archives.")
        }
        if settings.backupScheduleTimes.isEmpty
            || !settings.backupScheduleTimes.allSatisfy(RuntimeBackupSchedulePolicy.isValidTime) {
            return .invalid(AppConstants.StatusText.invalidBackupScheduleTimes)
        }
        if !RuntimeBackupSchedulePolicy.hasUniqueTimes(settings.backupScheduleTimes) {
            return .invalid(AppConstants.StatusText.duplicateBackupScheduleTimes)
        }
        if !RuntimeLogArchiveRetentionPolicy.isValidRetentionDays(settings.logArchiveRetentionDays) {
            return .invalid(AppConstants.StatusText.invalidLogArchiveRetention)
        }
        if !RuntimeSettingsReadPolicy.validLogArchiveMaximumGiB(settings.logArchiveMaximumGiB) {
            return .invalid(AppConstants.StatusText.invalidLogArchiveMaximum)
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
        if settings.containerMemoryLimitsEnabled,
           !containerMemoryLimitsAreValid(settings) {
            return .invalid(
                "Container memory limits must be within the allowed MiB ranges and total no more than 70% of the VM memory allocation."
            )
        }
        if settings.redisRelay.enabled {
            let target = settings.redisRelay.target
            if target.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || target.url != target.url.trimmingCharacters(in: .whitespacesAndNewlines)
                || !isLineSafe(target.url) {
                return .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
            }
            if !isValidRedisURL(target.url) {
                return .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
            }
            if !isLineSafe(target.username)
                || !isLineSafe(target.password) {
                return .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
            }
            if settings.redisRelay.intervalSeconds < 0.1
                || settings.redisRelay.scanCount < 1 {
                return .invalid(AppConstants.StatusText.invalidRedisRelayTarget)
            }
        }
        return .valid
    }

    private func isLineSafe(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private func isValidRedisURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme,
              ["redis", "rediss"].contains(scheme),
              components.host?.isEmpty == false else {
            return false
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return false
        }
        let path = components.path
        if path.isEmpty || path == "/" {
            return true
        }
        let rawDatabase = String(path.dropFirst())
        return !rawDatabase.contains("/") && Int(rawDatabase).map { $0 >= 0 } == true
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

    private func containerMemoryLimitsAreValid(_ settings: RuntimeSettings) -> Bool {
        let vmMemoryMiB = settings.memoryGiB * 1024
        let totalPercent = containerMemoryLimitPercent(
            settings.vitalServerContainerMemoryLimitMiB,
            vmMemoryMiB: vmMemoryMiB
        )
        + containerMemoryLimitPercent(
            settings.recorderIngressContainerMemoryLimitMiB,
            vmMemoryMiB: vmMemoryMiB
        )
        + containerMemoryLimitPercent(
            settings.redisContainerMemoryLimitMiB,
            vmMemoryMiB: vmMemoryMiB
        )
        return validLimit(
            settings.vitalServerContainerMemoryLimitMiB,
            minimum: AppConstants.SettingsLimits.minimumVitalServerContainerMemoryLimitMiB,
            maximum: min(AppConstants.SettingsLimits.maximumVitalServerContainerMemoryLimitMiB, vmMemoryMiB)
        )
        && validLimit(
            settings.recorderIngressContainerMemoryLimitMiB,
            minimum: AppConstants.SettingsLimits.minimumRecorderIngressContainerMemoryLimitMiB,
            maximum: min(AppConstants.SettingsLimits.maximumRecorderIngressContainerMemoryLimitMiB, vmMemoryMiB)
        )
        && validLimit(
            settings.redisContainerMemoryLimitMiB,
            minimum: AppConstants.SettingsLimits.minimumRedisContainerMemoryLimitMiB,
            maximum: min(AppConstants.SettingsLimits.maximumRedisContainerMemoryLimitMiB, vmMemoryMiB)
        )
        && totalPercent <= AppConstants.SettingsLimits.maximumCombinedContainerMemoryLimitPercent
    }

    private func validLimit(_ value: Int, minimum: Int, maximum: Int) -> Bool {
        value >= minimum && value <= max(minimum, maximum)
    }

    private func containerMemoryLimitPercent(_ valueMiB: Int, vmMemoryMiB: Int) -> Int {
        Int((Double(valueMiB) / Double(max(vmMemoryMiB, 1)) * 100.0).rounded())
    }
}

public enum RuntimeSettingsValidationResult: Equatable {
    case valid
    case invalid(String)

    public var isValid: Bool {
        self == .valid
    }
}
