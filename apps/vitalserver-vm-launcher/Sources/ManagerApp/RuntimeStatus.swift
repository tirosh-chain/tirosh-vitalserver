import Foundation
import RuntimeCore

struct RuntimeStatus {
    var runtimeInstalled = false
    var vmServiceLoaded = false
    var proxyServiceLoaded = false
    var watchdogServiceLoaded = false
    var runtimeState: String?
    var operation: String?
    var statusMessage: String?
    var updatedAt: String?
    var runtimeVersion: String?
    var latestBackup: String?
    var vmIP: String?
    var guestHTTP: String?
    var hostProxyHTTP: String?
    var redisUIHTTP: String?
    var swaggerUIHTTP: String?
    var cpuUsagePercent: Double?
    var memory: ResourceUsage?
    var systemDisk: ResourceUsage?
    var dataStorage: ResourceUsage?
    var proxyPort = AppConstants.Product.defaultProxyPort
    var failureReasons: [RuntimeFailureReason] = []
    var progress: RuntimeProgressDocument?

    var isReady: Bool {
        runtimeInstalled
            && vmServiceLoaded
            && proxyServiceLoaded
            && watchdogServiceLoaded
            && runtimeState == AppConstants.Values.stateHealthy
            && vmIP != nil
            && isSuccessfulHTTPStatus(guestHTTP)
            && isSuccessfulHTTPStatus(hostProxyHTTP)
            && isSuccessfulHTTPStatus(redisUIHTTP)
            && isSuccessfulHTTPStatus(swaggerUIHTTP)
    }

    var displayMessage: String? {
        var lines: [String] = []
        if let statusMessage, !statusMessage.isEmpty {
            lines.append(statusMessage)
        }
        if !failureReasons.isEmpty {
            lines.append("\(AppConstants.Labels.failureReasons): \(failureReasonText)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    var failureReasonText: String {
        failureReasons.map(\.rawValue).joined(separator: ", ")
    }

    var progressDisplayMessage: String? {
        guard let progress else {
            return nil
        }
        if let step = progress.step,
           let stepStatus = progress.stepStatus {
            return "\(stepStatusDisplayName(stepStatus)): \(humanizeStepName(step))"
        }
        return progress.message.isEmpty ? nil : progress.message
    }

    private func stepStatusDisplayName(_ status: RuntimeProgressStepStatus) -> String {
        switch status {
        case .pending:
            return AppConstants.StatusText.waiting
        case .started:
            return AppConstants.StatusText.running
        case .completed:
            return AppConstants.StatusText.done
        case .failed:
            return AppConstants.StatusText.failed.capitalized
        case .skipped:
            return "Skipped"
        case .unknown(let value):
            return value.capitalized
        }
    }

    private func humanizeStepName(_ step: String) -> String {
        step
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func humanizeStepName(_ step: RuntimeWorkflowStep) -> String {
        humanizeStepName(step.rawValue)
    }

    private func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let vmIPFile: String
    let runtimeState: String
    let runtimeStatus: String
    let proxyLaunchDaemon: String

    init(
        launcher: String = AppConstants.Paths.launcher,
        uninstaller: String = AppConstants.Paths.uninstaller,
        vmIPFile: String = AppConstants.Paths.vmIPFile,
        runtimeState: String = AppConstants.Paths.runtimeState,
        runtimeStatus: String = AppConstants.Paths.runtimeStatus,
        proxyLaunchDaemon: String = AppConstants.Paths.proxyLaunchDaemon
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.vmIPFile = vmIPFile
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.proxyLaunchDaemon = proxyLaunchDaemon
    }
}
