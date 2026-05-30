import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

@MainActor
final class RuntimeViewModelCommandActionRunnerTests: XCTestCase {
    func testSuccessfulActionUpdatesPresentationAndRefreshesCommandLog() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeViewModelCommandActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let didRun = await runner.run(
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

        XCTAssertTrue(didRun)
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "Completed\n\nstarted")
        XCTAssertEqual(presenter.operationDetail, "")
        XCTAssertEqual(presenter.selectedLogSource, .command)
        XCTAssertGreaterThanOrEqual(presenter.refreshLogsCount, 1)
    }

    func testFailedExitCodeUsesCommandResultSummary() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeViewModelCommandActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let didRun = await runner.run(
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

        XCTAssertFalse(didRun)
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "denied")
        XCTAssertEqual(presenter.operationDetail, "")
    }

    func testThrownActionReportsLocalizedError() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeViewModelCommandActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let didRun = await runner.run(
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

        XCTAssertFalse(didRun)
        XCTAssertFalse(presenter.isBusy)
        XCTAssertEqual(presenter.message, "Action failed.")
        XCTAssertEqual(presenter.operationDetail, "")
    }

    func testActionCanRunWithoutCommandLogRefresh() async {
        let presenter = FakeClientActionPresenter()
        let runner = RuntimeViewModelCommandActionRunner(
            prepareDelayNanoseconds: 0,
            refreshIntervalNanoseconds: 0
        )

        let didRun = await runner.run(
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

        XCTAssertTrue(didRun)
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
