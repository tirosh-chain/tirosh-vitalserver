import Foundation
import RuntimeControl

struct RuntimeClientActionRequest {
    let preparingMessage: String
    let waitingMessage: String
    let runningMessage: String
    let successMessage: String
    let refreshCommandLog: Bool
}

@MainActor
protocol RuntimeClientActionPresentation: AnyObject {
    var isBusy: Bool { get set }
    var message: String { get set }
    var operationDetail: String { get set }
    var selectedLogSource: RuntimeLogSource { get set }

    func refreshLogs() async
    func refreshOperationDetail(pendingDetail: String) async
}

@MainActor
struct RuntimeViewModelCommandActionRunner {
    var processMessageFormatter = RuntimeProcessMessageFormatter()
    var prepareDelayNanoseconds: UInt64 = 200_000_000
    var refreshIntervalNanoseconds: UInt64 = 2_000_000_000

    func run(
        request: RuntimeClientActionRequest,
        presenter: any RuntimeClientActionPresentation,
        action: @escaping () async throws -> RuntimeCommandResult
    ) async -> Bool {
        presenter.isBusy = true
        defer {
            presenter.isBusy = false
            presenter.operationDetail = ""
        }

        presenter.message = request.preparingMessage
        presenter.operationDetail = request.preparingMessage
        await sleep(nanoseconds: prepareDelayNanoseconds)
        presenter.message = request.waitingMessage
        presenter.operationDetail = request.waitingMessage

        if request.refreshCommandLog {
            presenter.selectedLogSource = .command
            await presenter.refreshLogs()
        }
        presenter.message = request.runningMessage
        presenter.operationDetail = request.runningMessage
        let logRefreshTask = request.refreshCommandLog
            ? Task { @MainActor in
                while !Task.isCancelled {
                    await presenter.refreshLogs()
                    await presenter.refreshOperationDetail(pendingDetail: request.runningMessage)
                    await sleep(nanoseconds: refreshIntervalNanoseconds)
                }
            }
            : nil
        defer {
            logRefreshTask?.cancel()
            if request.refreshCommandLog {
                Task { @MainActor in
                    await presenter.refreshLogs()
                }
            }
        }

        let result: RuntimeCommandResult
        do {
            result = try await action()
        } catch {
            presenter.message = error.localizedDescription
            presenter.operationDetail = error.localizedDescription
            return false
        }
        if result.exitCode == 0 {
            presenter.message = processMessageFormatter.message(title: request.successMessage, result: result)
            presenter.operationDetail = request.successMessage
            return true
        } else {
            let failureSummary = processMessageFormatter.summary(result)
            presenter.message = processMessageFormatter.message(
                title: failureSummary.isEmpty ? AppConstants.StatusText.commandCancelled : failureSummary,
                result: result
            )
            presenter.operationDetail = AppConstants.StatusText.commandCancelled
            return false
        }
    }

    private func sleep(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
