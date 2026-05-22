import Foundation

struct RuntimePresentationFormatter {
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
            "Network mode: \(settings.networkMode)",
            "Disk size: \(settings.diskGiB) GiB",
            "Vital files directory: \(settings.vitalFilesDirectory)",
            "Automatic recovery: \(settings.autoRecoveryEnabled ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
            "Restart services: \(settings.restartAfterSave ? AppConstants.Values.boolTrue : AppConstants.Values.boolFalse)",
        ].joined(separator: "\n")
    }

    func logExportDefaultName(date: Date = Date()) -> String {
        "vitalserver-logs-\(logExportTimestamp(date: date)).zip"
    }

    private func logExportTimestamp(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
