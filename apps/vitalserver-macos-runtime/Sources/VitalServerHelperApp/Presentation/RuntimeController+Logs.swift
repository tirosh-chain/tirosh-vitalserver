import Foundation
import RuntimeControl

@MainActor
extension RuntimeController {
    func openLogs() {
        guard runtimeClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(runtimeClient.preferredLogsPath())
    }

    func exportLogs() async {
        guard runtimeClient.capabilities.canExportLogs else {
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
            let result = try await runtimeClient.exportLogs(to: destination)
            message = "\(AppConstants.StatusText.logExportCompleted)\n\n\(result.destination.path)"
        } catch {
            message = "\(AppConstants.StatusText.logExportFailed)\n\n\(error.localizedDescription)"
        }
    }

    func availableLogLineLimits() -> [Int] {
        RuntimeLogOptions.lineLimits
    }

    func availableLogSources() -> [LogSourceOption] {
        RuntimeLogOptions.sources
    }

    func refreshLogs() {
        let limit = max(logLineLimit, 1)
        logText = runtimeClient.logText(
            sourceID: selectedLogSource,
            helperMessage: message,
            lineLimit: limit
        )
    }

    func refreshLogsIfLive() {
        if logStreaming {
            refreshLogs()
        }
    }
}

private enum RuntimeLogOptions {
    static let lineLimits = [100, 500, 1000]

    static let sources: [LogSourceOption] = [
        LogSourceOption(id: .helperMessage, title: "Helper message"),
        LogSourceOption(id: .install, title: "Install log"),
        LogSourceOption(id: .command, title: "Command log"),
        LogSourceOption(id: .launcher, title: "VM launcher"),
        LogSourceOption(id: .proxyOutput, title: "Host proxy output"),
        LogSourceOption(id: .proxyError, title: "Host proxy error"),
        LogSourceOption(id: .updateActivation, title: "Update activation"),
        LogSourceOption(id: .containers, title: "Containers"),
    ]
}
