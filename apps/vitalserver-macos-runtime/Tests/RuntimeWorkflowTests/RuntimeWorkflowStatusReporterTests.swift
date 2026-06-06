import Contracts
import Workflow
import XCTest

final class RuntimeWorkflowStatusReporterTests: XCTestCase {
    func testWriteBestEffortLogsStatusWriteFailure() {
        var logs: [String] = []
        let reporter = RuntimeWorkflowStatusReporter(
            writeStatus: { _, _, _ in throw TestWorkflowStatusReporterError.write },
            writeProgress: { _ in },
            log: { logs.append($0) }
        )

        reporter.writeBestEffort(.critical, operation: .applyBundle, message: "failed")

        XCTAssertTrue(logs.contains { $0.contains("failed to write runtime status") })
        XCTAssertTrue(logs.contains { $0.contains("status=critical") })
        XCTAssertTrue(logs.contains { $0.contains("operation=apply-bundle") })
    }

    func testPublishProgressLogsStepAndWritesProgressBestEffort() {
        let event = RuntimeStepExecutionEvent(
            operation: .applyBundle,
            status: .updating,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started: stop-runtime-services"
        )
        var progressEvents: [RuntimeStepExecutionEvent] = []
        var logs: [String] = []
        let reporter = RuntimeWorkflowStatusReporter(
            writeStatus: { _, _, _ in },
            writeProgress: { progressEvents.append($0) },
            log: { logs.append($0) }
        )

        reporter.publishProgress(event)

        XCTAssertEqual(progressEvents, [event])
        XCTAssertTrue(logs.contains("step=stop-runtime-services status=started"))
    }
}

private enum TestWorkflowStatusReporterError: Error {
    case write
}
