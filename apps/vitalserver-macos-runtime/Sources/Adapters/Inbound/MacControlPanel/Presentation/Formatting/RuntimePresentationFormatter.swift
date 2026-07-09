import Foundation
import Contracts
import RuntimeControl
import Errors

public protocol RuntimePresentationVocabulary {
    var unknownText: String { get }
    var updateBundleConfirmationText: String { get }
    var applySettingsConfirmationText: String { get }
    var failureReasonsLabel: String { get }
    var updateBundleApplyingText: String { get }
    var trueText: String { get }
    var falseText: String { get }
    var preventSystemSleepLabel: String { get }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String
    func runtimeLifecycleText(_ rawValue: String?) -> String
    func operationText(_ rawValue: String?) -> String
    func progressStepStatusText(_ rawValue: String) -> String
}

public struct RuntimePresentationFormatter {
    public struct ServiceURLPresentation: Equatable {
        public let displayURL: String
        public let openURL: String?

        public init(displayURL: String, openURL: String?) {
            self.displayURL = displayURL
            self.openURL = openURL
        }
    }

    private let vocabulary: any RuntimePresentationVocabulary

    public init(vocabulary: any RuntimePresentationVocabulary) {
        self.vocabulary = vocabulary
    }

    public func vitalServerStatusURL(settings: RuntimeSettings) -> ServiceURLPresentation {
        serviceStatusURL(
            explicitURL: settings.vitalServerURL
        )
    }

    public func remoteConsoleStatusURL(settings: RuntimeSettings) -> ServiceURLPresentation {
        serviceStatusURL(
            explicitURL: settings.remoteConsoleURL
        )
    }

    public func backupSizeText(_ backup: RuntimeBackup) -> String {
        guard let sizeBytes = backup.sizeBytes else {
            return vocabulary.unknownText
        }
        let gib = Double(sizeBytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(sizeBytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    public func selectedBundleConfirmation(bundlePath: String?) -> String {
        guard let bundlePath, !bundlePath.isEmpty else {
            return vocabulary.updateBundleConfirmationText
        }
        return [
            vocabulary.updateBundleConfirmationText,
            bundlePath,
        ].joined(separator: "\n\n")
    }

    public func applySettingsConfirmation(settings: RuntimeSettings) -> String {
        [
            vocabulary.applySettingsConfirmationText,
            "Proxy port: \(settings.proxyPort)",
            "VitalServer URL: \(settings.vitalServerURL)",
            "Remote Console URL: \(settings.remoteConsoleURL)",
            "Network mode: \(settings.networkMode.rawValue)",
            "Disk size: \(settings.diskGiB) GiB",
            "Vital files directory: \(settings.vitalFilesDirectory)",
            "VitalServer Helper backup retention: \(settings.backupRetentionCount) archives",
            "VitalServer Helper backup times: \(settings.backupScheduleTimes.joined(separator: ", "))",
            "Log archive retention: \(settings.logArchiveRetentionDays) days",
            "Log archive size limit: \(settings.logArchiveMaximumGiB) GiB",
            "Automatic recovery: \(boolText(settings.autoRecoveryEnabled))",
            "\(vocabulary.preventSystemSleepLabel): \(boolText(settings.preventSystemSleep))",
            "Restart VM runtime when required: \(boolText(settings.restartAfterSave))",
        ].joined(separator: "\n")
    }

    public func statusDisplayMessage(_ status: RuntimeStatus) -> String? {
        var lines: [String] = []
        if !status.failureReasons.isEmpty {
            lines.append("\(vocabulary.failureReasonsLabel): \(failureReasonText(status))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public func failureReasonText(_ status: RuntimeStatus) -> String {
        status.failureReasons.map(vocabulary.domainErrorText).joined(separator: ", ")
    }

    public func runtimeStateText(_ state: RuntimeState?) -> String {
        vocabulary.runtimeLifecycleText(state?.rawValue)
    }

    public func operationText(_ operation: RuntimeOperation?) -> String {
        vocabulary.operationText(operation?.rawValue)
    }

    public func activeOperationText(_ operationState: RuntimeOperationState) -> String {
        operationText(operationState.operationForPresentation)
    }

    public func updateOperationInProgress(_ operationState: RuntimeOperationState) -> Bool {
        RuntimeActiveOperationPolicy.isUpdateOperation(operationState.operationForPresentation)
    }

    public func updateOperationDisplayMessage(
        _ status: RuntimeStatus,
        operationState: RuntimeOperationState
    ) -> String? {
        guard updateOperationInProgress(operationState) else {
            return nil
        }
        if let operation = operationState.operationForPresentation {
            return "\(operationText(operation)) in progress"
        }
        return vocabulary.updateBundleApplyingText
    }

    public func systemTimeText(_ timestamp: String?, timeZone: TimeZone = .current) -> String {
        guard let timestamp, !timestamp.isEmpty else {
            return vocabulary.unknownText
        }
        guard let date = iso8601Date(timestamp) else {
            return timestamp
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        return formatter.string(from: date)
    }

    public func systemTimeTextWithAge(_ timestamp: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let text = systemTimeText(timestamp, timeZone: timeZone)
        guard let timestamp,
              !timestamp.isEmpty,
              let date = iso8601Date(timestamp)
        else {
            return text
        }
        return "\(text) · \(ageText(since: date, now: now)) ago"
    }

    public func logExportDefaultName(date: Date = Date()) -> String {
        "vitalserver-logs-\(logExportTimestamp(date: date)).zip"
    }

    private func boolText(_ value: Bool) -> String {
        value ? vocabulary.trueText : vocabulary.falseText
    }

    private func iso8601Date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }

    private func ageText(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 48 {
            return "\(hours)h"
        }
        return "\(hours / 24)d"
    }

    private func logExportTimestamp(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func serviceStatusURL(explicitURL: String) -> ServiceURLPresentation {
        let trimmed = explicitURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ServiceURLPresentation(displayURL: vocabulary.unknownText, openURL: nil)
        }
        return ServiceURLPresentation(displayURL: trimmed, openURL: trimmed)
    }

}

private struct AppRuntimePresentationVocabulary: RuntimePresentationVocabulary {
    var unknownText: String { AppConstants.StatusText.unknown }
    var updateBundleConfirmationText: String { AppConstants.StatusText.updateBundleConfirmation }
    var applySettingsConfirmationText: String { AppConstants.StatusText.applySettingsConfirmation }
    var failureReasonsLabel: String { AppConstants.Labels.failureReasons }
    var updateBundleApplyingText: String { AppConstants.StatusText.updateBundleApplying }
    var trueText: String { AppConstants.Values.boolTrue }
    var falseText: String { AppConstants.Values.boolFalse }
    var preventSystemSleepLabel: String { AppConstants.Labels.preventSystemSleep }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String {
        AppConstants.StatusText.domainError(reason)
    }

    func runtimeLifecycleText(_ rawValue: String?) -> String {
        AppConstants.StatusText.runtimeLifecycle(rawValue)
    }

    func operationText(_ rawValue: String?) -> String {
        AppConstants.StatusText.operation(rawValue)
    }

    func progressStepStatusText(_ rawValue: String) -> String {
        AppConstants.StatusText.progressStepStatus(rawValue)
    }
}

extension RuntimePresentationFormatter {
    init() {
        self.init(vocabulary: AppRuntimePresentationVocabulary())
    }
}
