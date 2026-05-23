import Core
import Contracts
import XCTest
@testable import HostCLI

final class RuntimeInstallRunnerTests: XCTestCase {
    func testRunExecutesInstallPlanAndWritesHealthyStatus() throws {
        let harness = InstallHarness()

        try harness.runner.run()

        XCTAssertEqual(harness.executedSteps, RuntimeOperationPlans.install.steps)
        XCTAssertEqual(harness.statuses.first?.level, .installing)
        XCTAssertEqual(harness.statuses.first?.operation, .install)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .install)
        XCTAssertEqual(harness.statuses.last?.message, "runtime install completed")
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .started }.map(\.step),
            RuntimeOperationPlans.install.steps
        )
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .completed }.map(\.step),
            RuntimeOperationPlans.install.steps
        )
        XCTAssertTrue(harness.logs.contains("runtime install started home=/runtime-home"))
        XCTAssertTrue(harness.logs.contains("runtime install completed home=/runtime-home"))
    }

    func testRunWritesCriticalStatusWhenSettingsLoadFails() throws {
        let harness = InstallHarness()
        harness.loadError = TestInstallError.load

        XCTAssertThrowsError(try harness.runner.run())

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertTrue(harness.statuses.isEmpty)
    }

    func testRunWritesCriticalStatusWhenStepFails() throws {
        let harness = InstallHarness()
        harness.stepError = TestInstallError.step

        XCTAssertThrowsError(try harness.runner.run())

        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .install)
        XCTAssertTrue(harness.statuses.last?.message.contains("runtime install failed") == true)
    }
}

private final class InstallHarness {
    var settings = InstallSettings(vitalFilesDirectory: "/vital-files")
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedSteps: [RuntimeWorkflowStep] = []
    var logs: [String] = []
    var loadError: Error?
    var stepError: Error?

    var runner: RuntimeInstallRunner {
        RuntimeInstallRunner(
            loadSettings: {
                if let loadError = self.loadError {
                    throw loadError
                }
                return self.settings
            },
            executeStep: { step, _ in
                self.executedSteps.append(step)
                if let stepError = self.stepError {
                    throw stepError
                }
            },
            writeStatus: { level, operation, message in
                self.statuses.append((level: level, operation: operation, message: message))
            },
            writeProgress: { event in
                self.progressEvents.append(event)
            },
            runtimeHomePath: {
                "/runtime-home"
            },
            log: { message in
                self.logs.append(message)
            }
        )
    }
}

private enum TestInstallError: Error {
    case load
    case step
}
