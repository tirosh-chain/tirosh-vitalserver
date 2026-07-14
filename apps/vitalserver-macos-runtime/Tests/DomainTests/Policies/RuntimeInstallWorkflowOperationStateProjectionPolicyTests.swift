import Contracts
import Domain
import XCTest

final class RuntimeInstallWorkflowOperationStateProjectionPolicyTests: XCTestCase {
    func testProjectsInstallStatesToExplicitGenericWorkflowEvents() throws {
        XCTAssertEqual(
            try projection(.started),
            .started(operationID: "install-1", operation: .install, message: "message")
        )
        XCTAssertEqual(
            try projection(.settingsLoaded),
            .updated(
                phase: .preparing,
                currentStep: nil,
                stepStatus: nil,
                message: "message",
                reasonCodes: ["reason"]
            )
        )
        XCTAssertEqual(
            try projection(.stepStarted, currentStep: .prepareInstallDirectories),
            .updated(
                phase: .running,
                currentStep: .prepareInstallDirectories,
                stepStatus: .started,
                message: "message",
                reasonCodes: ["reason"]
            )
        )
        XCTAssertEqual(
            try projection(.completed),
            .completed(message: "message")
        )
        XCTAssertEqual(
            try projection(.failed),
            .failed(message: "message", reasonCodes: ["reason"])
        )
    }

    func testRejectsStepStateWithoutCurrentStepAndUnknownState() {
        XCTAssertThrowsError(try projection(.stepStarted)) { error in
            XCTAssertEqual(
                error as? RuntimeInstallWorkflowOperationStateProjectionError,
                .missingCurrentStep("step-started")
            )
        }
        XCTAssertThrowsError(try projection(.unknown("future"))) { error in
            XCTAssertEqual(
                error as? RuntimeInstallWorkflowOperationStateProjectionError,
                .unknownState("future")
            )
        }
    }

    private func projection(
        _ state: RuntimeInstallState,
        currentStep: RuntimeWorkflowStep? = nil
    ) throws -> RuntimeWorkflowOperationTransitionEvent {
        try RuntimeInstallWorkflowOperationStateProjectionPolicy.event(
            operationID: "install-1",
            state: state,
            currentStep: currentStep,
            message: "message",
            blockers: ["reason"]
        )
    }
}
