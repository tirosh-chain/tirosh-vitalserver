import Foundation
import RuntimeControl
import Errors

struct RuntimeClientActionRequest {
    let preparingMessage: String
    let waitingMessage: String
    let runningMessage: String
    let successMessage: String
    let refreshCommandLog: Bool
}

enum RuntimeClientActionRunResult: Equatable {
    case succeeded(RuntimeCommandResult)
    case commandFailed(RuntimeCommandResult)
    case actionFailed(String)

    var isSuccess: Bool {
        if case .succeeded = self {
            return true
        }
        return false
    }
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
struct RuntimeClientActionRunner {
    var processMessageFormatter = RuntimeProcessMessageFormatter()
    var prepareDelayNanoseconds: UInt64 = 200_000_000
    var refreshIntervalNanoseconds: UInt64 = 2_000_000_000

    func run(
        request: RuntimeClientActionRequest,
        presenter: any RuntimeClientActionPresentation,
        action: @escaping () async throws -> RuntimeCommandResult
    ) async -> RuntimeClientActionRunResult {
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
            let message = error.localizedDescription
            presenter.message = message
            presenter.operationDetail = message
            return .actionFailed(message)
        }
        if result.exitCode == 0 {
            presenter.message = processMessageFormatter.message(title: request.successMessage, result: result)
            presenter.operationDetail = request.successMessage
            return .succeeded(result)
        } else {
            let failureSummary = processMessageFormatter.summary(result)
            presenter.message = processMessageFormatter.message(
                title: failureSummary.isEmpty ? AppConstants.StatusText.commandCancelled : failureSummary,
                result: result
            )
            presenter.operationDetail = AppConstants.StatusText.commandCancelled
            return .commandFailed(result)
        }
    }

    private func sleep(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
