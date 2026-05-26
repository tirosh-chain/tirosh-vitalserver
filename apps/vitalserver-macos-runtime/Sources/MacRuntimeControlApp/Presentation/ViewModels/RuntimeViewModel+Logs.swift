import Foundation
import RuntimeControl

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

        isBusy = true
        defer { isBusy = false }
        message = AppConstants.StatusText.logExportPreparing

        do {
            let result = try await hostClient.exportLogs(to: destination)
            message = "\(AppConstants.StatusText.logExportCompleted)\n\n\(result.destination.path)"
        } catch {
            message = "\(AppConstants.StatusText.logExportFailed)\n\n\(error.localizedDescription)"
        }
    }

    func availableLogLineLimits() -> [Int] {
        RuntimeLogOptions.lineLimits
    }

    func availableLogSources() -> [RuntimeLogSourceOption] {
        RuntimeLogOptions.sources
    }

    func refreshLogs() async {
        guard !isRefreshingLogs else {
            return
        }
        isRefreshingLogs = true
        defer { isRefreshingLogs = false }

        let limit = max(logLineLimit, 1)
        let sourceID = selectedLogSource
        let helperMessage = message
        logText = await hostClient.loadLogText(
            sourceID: sourceID,
            helperMessage: helperMessage,
            lineLimit: limit
        )
    }

    func refreshLogsIfLive() async {
        if logStreaming {
            await refreshLogs()
        }
    }
}

private enum RuntimeLogOptions {
    static let lineLimits = [100, 500, 1000]

    static let sources: [RuntimeLogSourceOption] = [
        RuntimeLogSourceOption(id: .helperMessage, title: "Helper message"),
        RuntimeLogSourceOption(id: .install, title: "Install log"),
        RuntimeLogSourceOption(id: .command, title: "Command log"),
        RuntimeLogSourceOption(id: .launcher, title: "VM launcher"),
        RuntimeLogSourceOption(id: .proxyOutput, title: "Host proxy output"),
        RuntimeLogSourceOption(id: .proxyError, title: "Host proxy error"),
        RuntimeLogSourceOption(id: .updateActivation, title: "Update activation"),
        RuntimeLogSourceOption(id: .containers, title: "Containers"),
    ]
}
