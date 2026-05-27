import Foundation
import Contracts
import RuntimeControl

struct RuntimePresentationFormatter {
    func backupSizeText(_ backup: RuntimeBackup) -> String {
        guard let sizeBytes = backup.sizeBytes else {
            return AppConstants.StatusText.unknown
        }
        let gib = Double(sizeBytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: "%.1f GiB", gib)
        }
        let mib = Double(sizeBytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    func selectedBundleConfirmation(bundlePath: String) -> String {
        [
            AppConstants.StatusText.updateBundleConfirmation,
            bundlePath,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    func applySettingsConfirmation(settings: RuntimeSettings) -> String {
        [
            AppConstants.StatusText.applySettingsConfirmation,
            "Proxy port: \(settings.proxyPort)",
            "Public host: \(settings.publicHost.isEmpty ? "(same host)" : settings.publicHost)",
            "Public port: \(settings.publicPort)",
            "Network mode: \(settings.networkMode.rawValue)",
            "Disk size: \(settings.diskGiB) GiB",
            "Vital files directory: \(settings.vitalFilesDirectory)",
            "Redis backup retention: \(settings.redisBackupRetentionCount) archives",
            "Automatic recovery: \(settings.autoRecoveryEnabled ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
            "\(AppConstants.Labels.preventSystemSleep): \(settings.preventSystemSleep ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
            "Restart services: \(settings.restartAfterSave ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
        ].joined(separator: "\n")
    }

    func statusDisplayMessage(_ status: RuntimeStatus) -> String? {
        var lines: [String] = []
        if let statusMessage = status.statusMessage, !statusMessage.isEmpty {
            lines.append(statusMessage)
        }
        if !status.failureReasons.isEmpty {
            lines.append("\(AppConstants.Labels.failureReasons): \(failureReasonText(status))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func failureReasonText(_ status: RuntimeStatus) -> String {
        status.failureReasons.map(AppConstants.StatusText.domainError).joined(separator: ", ")
    }

    func runtimeStateText(_ state: RuntimeState?) -> String {
        AppConstants.StatusText.runtimeLifecycle(state?.rawValue)
    }

    func operationText(_ operation: RuntimeOperation?) -> String {
        AppConstants.StatusText.operation(operation?.rawValue)
    }

    func progressDisplayMessage(_ status: RuntimeStatus) -> String? {
        guard let progress = status.progress else {
            return nil
        }
        if let step = progress.step,
           let stepStatus = progress.stepStatus {
            return "\(stepStatusDisplayName(stepStatus)): \(humanizeStepName(step.rawValue))"
        }
        return progress.message.isEmpty ? nil : progress.message
    }

    func updateOperationInProgress(_ status: RuntimeStatus) -> Bool {
        RuntimeActiveOperationPolicy.isUpdateInProgress(status)
    }

    func updateOperationDisplayMessage(_ status: RuntimeStatus) -> String? {
        guard updateOperationInProgress(status) else {
            return nil
        }
        if let progressMessage = progressDisplayMessage(status) {
            return progressMessage
        }
        if let statusMessage = status.statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        if let operation = status.operation {
            return "\(operationText(operation)) in progress"
        }
        return AppConstants.StatusText.updateBundleApplying
    }

    func systemTimeText(_ timestamp: String?, timeZone: TimeZone = .current) -> String {
        guard let timestamp, !timestamp.isEmpty else {
            return AppConstants.StatusText.unknown
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

    func logExportDefaultName(date: Date = Date()) -> String {
        "vitalserver-logs-\(logExportTimestamp(date: date)).zip"
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

    private func logExportTimestamp(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func stepStatusDisplayName(_ status: RuntimeProgressStepStatus) -> String {
        AppConstants.StatusText.progressStepStatus(status.rawValue)
    }

    private func humanizeStepName(_ step: String) -> String {
        step
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
