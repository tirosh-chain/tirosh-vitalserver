import Application
import Contracts
import XCTest
import Errors

final class RuntimeOperationReportingUseCaseTests: XCTestCase {
    func testOperationReportingMessagesComeFromUseCase() {
        let useCase = RuntimeOperationReportingUseCase()
        let event = RuntimeStepExecutionEvent(
            operation: .applyBundle,
            status: .updating,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started"
        )

        XCTAssertEqual(
            useCase.progressLogMessage(event: event),
            "step=stop-runtime-services status=started"
        )
        XCTAssertEqual(
            useCase.statusWriteFailedLogMessage(status: .critical, operation: .applyBundle, reason: "denied"),
            "failed to write runtime status status=critical operation=apply-bundle error=denied"
        )
        XCTAssertEqual(
            useCase.progressWriteFailedLogMessage(event: event, reason: "denied"),
            "failed to write runtime progress step=stop-runtime-services stepStatus=started error=denied"
        )
        XCTAssertEqual(
            useCase.observedEventRecordFailedLogMessage(status: .degraded, operation: .watchdog, reason: "denied"),
            "failed to record runtime observed event status=degraded operation=watchdog error=denied"
        )
    }
}
