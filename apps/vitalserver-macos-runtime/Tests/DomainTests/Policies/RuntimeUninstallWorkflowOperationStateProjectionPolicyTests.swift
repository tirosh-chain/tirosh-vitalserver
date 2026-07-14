import Contracts
import Domain
import XCTest

final class RuntimeUninstallWorkflowOperationStateProjectionPolicyTests: XCTestCase {
    func testStartedCreatesUninstallOperation() throws {
        XCTAssertEqual(
            try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                operationID: "uninstall-1",
                state: .started,
                message: "uninstall started",
                blockers: []
            ),
            .started(
                operationID: "uninstall-1",
                operation: .uninstall,
                message: "uninstall started"
            )
        )
    }

    func testExplicitStepsRemainDistinct() throws {
        let cases: [(RuntimeUninstallState, RuntimeWorkflowStep, RuntimeProgressStepStatus)] = [
            (.redisBackupRequested, .uninstallCreateRedisBackup, .started),
            (.redisBackupCompleted, .uninstallCreateRedisBackup, .completed),
            (.stopServicesRequested, .uninstallStopRuntimeServices, .started),
            (.filesRemovalStarted, .uninstallRemoveFiles, .started),
            (.receiptsForgetStarted, .uninstallForgetPackageReceipts, .started),
        ]

        for (state, step, status) in cases {
            XCTAssertEqual(
                try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                    operationID: "uninstall-1",
                    state: state,
                    message: state.rawValue,
                    blockers: []
                ),
                .updated(
                    phase: .running,
                    currentStep: step,
                    stepStatus: status,
                    message: state.rawValue,
                    reasonCodes: []
                )
            )
        }
    }

    func testBlockedStateBecomesTerminalFailureWithReasonCodes() throws {
        XCTAssertEqual(
            try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                operationID: "uninstall-1",
                state: .filesRemovalBlocked,
                message: "file removal blocked",
                blockers: ["path-busy"]
            ),
            .failed(message: "file removal blocked", reasonCodes: ["path-busy"])
        )
    }

    func testCompletedBecomesTerminalCompletion() throws {
        XCTAssertEqual(
            try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                operationID: "uninstall-1",
                state: .completed,
                message: "uninstall completed",
                blockers: []
            ),
            .completed(message: "uninstall completed")
        )
    }

    func testUnknownStateIsRejected() {
        XCTAssertThrowsError(
            try RuntimeUninstallWorkflowOperationStateProjectionPolicy.event(
                operationID: "uninstall-1",
                state: .unknown("future"),
                message: nil,
                blockers: []
            )
        ) { error in
            XCTAssertEqual(
                error as? RuntimeUninstallWorkflowOperationStateProjectionError,
                .unknownState("future")
            )
        }
    }
}
