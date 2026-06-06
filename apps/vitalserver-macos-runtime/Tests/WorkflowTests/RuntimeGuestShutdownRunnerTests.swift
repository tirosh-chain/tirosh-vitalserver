import Application
import Workflow
import XCTest

final class RuntimeGuestShutdownRunnerTests: XCTestCase {
    func testPrepareDelegatesShutdownPlanToExecutionPort() throws {
        var plans: [RuntimeGuestShutdownExecutionPlan] = []
        let runner = RuntimeGuestShutdownRunner(
            executeShutdownPlan: { plans.append($0) }
        )

        try runner.prepareForUpdate(version: "1.2.3")

        XCTAssertEqual(plans, [
            .prepare(
                version: "1.2.3",
                requestLog: "guest update shutdown requested version=1.2.3",
                readyLog: "guest update shutdown ready version=1.2.3"
            ),
        ])
    }

    func testPreparePropagatesExecutionPortFailure() {
        let runner = RuntimeGuestShutdownRunner(
            executeShutdownPlan: { _ in throw TestGuestShutdownRunnerError.executionFailed }
        )

        XCTAssertThrowsError(try runner.prepareForUpdate(version: "1.2.3")) { error in
            XCTAssertEqual(error as? TestGuestShutdownRunnerError, .executionFailed)
        }
    }
}

private enum TestGuestShutdownRunnerError: Error, Equatable {
    case executionFailed
}
