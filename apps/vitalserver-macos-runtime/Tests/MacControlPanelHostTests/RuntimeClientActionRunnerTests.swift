import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeClientActionRunnerTests: XCTestCase {
    func testSuccessfulActionUpdatesPresentationAndRefreshesCommandLog() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeClientActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let result = await runner.run(
            request: RuntimeClientActionRequest(
                preparingMessage: "Preparing",
                waitingMessage: "Waiting",
                runningMessage: "Running",
                successMessage: "Completed",
                refreshCommandLog: true
            ),
            presenter: presenter,
            action: {
                RuntimeCommandResult(exitCode: 0, stdout: "started", stderr: "")
            }
        )

        guard case .succeeded(let commandResult) = result else {
            return XCTFail("Expected succeeded result, got \(result)")
        }
        XCTAssertEqual(commandResult.exitCode, 0)
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "Completed\n\nstarted")
        XCTAssertEqual(presenter.operationDetail, "")
        XCTAssertEqual(presenter.selectedLogSource, .command)
        XCTAssertGreaterThanOrEqual(presenter.refreshLogsCount, 1)
    }

    func testFailedExitCodeUsesCommandResultSummary() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeClientActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let result = await runner.run(
            request: RuntimeClientActionRequest(
                preparingMessage: "Preparing",
                waitingMessage: "Waiting",
                runningMessage: "Running",
                successMessage: "Completed",
                refreshCommandLog: true
            ),
            presenter: presenter,
            action: {
                RuntimeCommandResult(exitCode: 2, stdout: "", stderr: "denied")
            }
        )

        guard case .commandFailed(let commandResult) = result else {
            return XCTFail("Expected commandFailed result, got \(result)")
        }
        XCTAssertEqual(commandResult.exitCode, 2)
        XCTAssertEqual(commandResult.stderr, "denied")
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "denied")
        XCTAssertEqual(presenter.operationDetail, "")
    }

    func testThrownActionReportsLocalizedError() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeClientActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let result = await runner.run(
            request: RuntimeClientActionRequest(
                preparingMessage: "Preparing",
                waitingMessage: "Waiting",
                runningMessage: "Running",
                successMessage: "Completed",
                refreshCommandLog: true
            ),
            presenter: presenter,
            action: {
                throw ActionError.failed
            }
        )

        XCTAssertEqual(result, .actionFailed("Action failed."))
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "Action failed.")
        XCTAssertEqual(presenter.operationDetail, "")
    }

    func testActionCanRunWithoutCommandLogRefresh() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeClientActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let result = await runner.run(
            request: RuntimeClientActionRequest(
                preparingMessage: "Preparing",
                waitingMessage: "Waiting",
                runningMessage: "Running",
                successMessage: "Completed",
                refreshCommandLog: false
            ),
            presenter: presenter,
            action: {
                RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(presenter.selectedLogSource, .helperMessage)
        XCTAssertEqual(presenter.refreshLogsCount, 0)
        XCTAssertEqual(presenter.refreshOperationDetailCount, 0)
    }
}

@MainActor
private final class FakeClientActionPresenter: RuntimeClientActionPresentation {
    var isBusy = false
    var message = ""
    var operationDetail = ""
    var selectedLogSource = RuntimeLogSource.helperMessage
    var refreshLogsCount = 0
    var refreshOperationDetailCount = 0

    func refreshLogs() async {
        refreshLogsCount += 1
    }

    func refreshOperationDetail(pendingDetail: String) async {
        refreshOperationDetailCount += 1
        operationDetail = pendingDetail
    }
}

private enum ActionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Action failed."
    }
}
