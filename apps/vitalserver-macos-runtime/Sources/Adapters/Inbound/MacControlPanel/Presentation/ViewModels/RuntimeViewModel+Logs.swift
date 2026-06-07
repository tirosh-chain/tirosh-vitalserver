import Foundation
import RuntimeControl
import Errors

@MainActor
extension RuntimeViewModel {
    func openLogs() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(hostClient.preferredLogsPath())
    }

    func exportLogs() async {
        guard controlClient.capabilities.canExportLogs else {
            message = AppConstants.StatusText.logExportUnavailable
            return
        }
        let defaultName = presentationFormatter.logExportDefaultName()
        guard let destination = nativeShell.chooseLogExportDestination(
            defaultName: defaultName,
            prompt: AppConstants.Actions.exportLogs
        ) else {
            return
        }
        if let validationMessage = nativeShell.logExportDestinationValidationMessage(for: destination) {
            message = validationMessage
            return
        }

        isBusy = true
        defer { isBusy = false }
        message = AppConstants.StatusText.logExportPreparing

        do {
            let result = try await hostClient.exportLogs(to: destination)
            let cleanupIssue = result.cleanupIssue.map { "\n\n\($0)" } ?? ""
            message = "\(AppConstants.StatusText.logExportCompleted)\n\n\(result.destination.path)\(cleanupIssue)"
        } catch {
            message = "\(AppConstants.StatusText.logExportFailed)\n\n\(error.localizedDescription)"
        }
    }

    func availableLogLineLimits() -> [Int] {
        RuntimeLogPresentationOptions.lineLimits
    }

    func availableLogSources() -> [RuntimeLogSourceOption] {
        RuntimeLogPresentationOptions.sources
    }

    func refreshLogs() async {
        guard !isRefreshingLogs else {
            return
        }
        isRefreshingLogs = true
        defer { isRefreshingLogs = false }

        let limit = max(logLineLimit, 1)
        let sourceID = selectedLogSource
        let nextLogText = await hostClient.loadLogTextResult(
            sourceID: sourceID,
            lineLimit: limit
        )
        .displayTextForRuntimeLog()
        if nextLogText != logText {
            logText = nextLogText
        }
    }

    func refreshLogsIfLive() async {
        if logStreaming {
            await refreshLogs()
        }
    }
}

private extension RuntimeHostTextReadResult {
    func displayTextForRuntimeLog() -> String {
        RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.noLogData)
            .displayText(self)
    }
}
