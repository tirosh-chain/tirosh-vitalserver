import Contracts
import Core
import RuntimeWorkflow
import XCTest

final class RuntimeInstallWorkflowTests: XCTestCase {
    func testFullInstallExecutesPlanAndWritesHealthyCompletion() throws {
        let harness = RuntimeInstallWorkflowHarness()

        try harness.workflow.run(.full)

        XCTAssertEqual(harness.executedSteps, RuntimeOperationPlans.install.steps)
        XCTAssertEqual(harness.statuses.first?.level, .installing)
        XCTAssertEqual(harness.statuses.first?.operation, .install)
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.message, "runtime install completed")
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .started }.map(\.step),
            RuntimeOperationPlans.install.steps
        )
        XCTAssertEqual(
            harness.progressEvents.filter { $0.stepStatus == .completed }.map(\.step),
            RuntimeOperationPlans.install.steps
        )
        XCTAssertTrue(harness.stateEvents.contains("state:completed:full:-:runtime install completed:"))
        XCTAssertTrue(harness.logs.contains("runtime install completed home=/runtime-home"))
    }

    func testProvisionInstallCompletesDegradedWithoutClaimingHealth() throws {
        let harness = RuntimeInstallWorkflowHarness()

        try harness.workflow.run(.provision)

        XCTAssertEqual(harness.executedSteps, RuntimeOperationPlans.installProvision.steps)
        XCTAssertFalse(harness.executedSteps.contains(.waitInstallRuntimeHealth))
        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertEqual(harness.statuses.last?.message, "runtime install provisioned; runtime services starting")
        XCTAssertTrue(harness.stateEvents.contains("state:provisioned:provision:-:runtime install provisioned:"))
    }

    func testPreflightBlockedDoesNotExecuteStepsAndWritesExplicitState() {
        let harness = RuntimeInstallWorkflowHarness()
        harness.preflight = harness.preflightDocument(
            passed: false,
            blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"]
        )

        XCTAssertThrowsError(try harness.workflow.run(.full))

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertTrue(harness.stateEvents.contains(
            "state:preflight-blocked:full:-:fresh install preflight blocked:install-artifact-present:path=/usr/local/bin/vitalserver-vm"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertTrue(harness.statuses.last?.message.contains("runtime install preflight blocked") == true)
    }

    func testSettingsLoadFailureWritesFailedStateBeforeRethrowing() {
        let harness = RuntimeInstallWorkflowHarness()
        harness.loadError = RuntimeInstallWorkflowTestError.loadSettings

        XCTAssertThrowsError(try harness.workflow.run(.full))

        XCTAssertTrue(harness.executedSteps.isEmpty)
        XCTAssertTrue(harness.stateEvents.contains(
            "state:failed:full:-:install settings load failed:install-settings-load-failed:reason=settings unavailable"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
    }

    func testStepFailurePersistsFailedStateAndDoesNotComplete() {
        let harness = RuntimeInstallWorkflowHarness()
        harness.stepErrorStep = .provisionVMDisk
        harness.stepError = RuntimeInstallWorkflowTestError.stepFailed

        XCTAssertThrowsError(try harness.workflow.run(.full))

        XCTAssertTrue(harness.executedSteps.contains(.provisionVMDisk))
        XCTAssertFalse(harness.stateEvents.contains("state:completed:full:-:runtime install completed:"))
        XCTAssertTrue(harness.stateEvents.contains(
            "state:failed:full:provision-vm-disk:install step failed:install-step-failed:step=provision-vm-disk reason=step failed"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.progressEvents.last?.step, .provisionVMDisk)
        XCTAssertEqual(harness.progressEvents.last?.stepStatus, .failed)
    }

    func testProgressWriteFailureIsLoggedAndDoesNotStopInstall() throws {
        let harness = RuntimeInstallWorkflowHarness()
        harness.progressError = RuntimeInstallWorkflowTestError.progressWrite

        try harness.workflow.run(.provision)

        XCTAssertEqual(harness.statuses.last?.level, .degraded)
        XCTAssertTrue(harness.logs.contains {
            $0.contains("runtime install progress write failed")
        })
    }
}

private struct TestInstallSettings: Equatable {
    let vitalFilesDirectory: String
}

private final class RuntimeInstallWorkflowHarness {
    var settings = TestInstallSettings(vitalFilesDirectory: "/vital-files")
    var preflight: RuntimeFreshInstallPreflightDocument?
    var loadError: Error?
    var stepErrorStep: RuntimeWorkflowStep?
    var stepError: Error?
    var progressError: Error?
    var stateEvents: [String] = []
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedSteps: [RuntimeWorkflowStep] = []
    var logs: [String] = []

    var workflow: RuntimeInstallWorkflow<TestInstallSettings> {
        RuntimeInstallWorkflow(
            readers: RuntimeInstallStateReaders(
                loadSettings: {
                    if let loadError = self.loadError {
                        throw loadError
                    }
                    return self.settings
                },
                freshInstallPreflight: {
                    self.preflight ?? self.preflightDocument()
                }
            ),
            effects: RuntimeInstallEffects(
                executeStep: { step, _ in
                    self.executedSteps.append(step)
                    if self.stepErrorStep == step, let error = self.stepError {
                        throw error
                    }
                }
            ),
            writer: RuntimeInstallStateWriter(
                writeState: { state, mode, currentStep, message, blockers in
                    self.stateEvents.append([
                        "state",
                        state.rawValue,
                        mode.rawValue,
                        currentStep?.rawValue ?? "-",
                        message ?? "",
                        blockers.joined(separator: "|"),
                    ].joined(separator: ":"))
                },
                writeStatus: { level, operation, message in
                    self.statuses.append((level: level, operation: operation, message: message))
                },
                writeProgress: { event in
                    if let progressError = self.progressError {
                        throw progressError
                    }
                    self.progressEvents.append(event)
                }
            ),
            diagnostics: RuntimeInstallDiagnostics(
                log: { message in
                    self.logs.append(message)
                }
            ),
            runtimeHomePath: {
                "/runtime-home"
            }
        )
    }

    func preflightDocument(
        passed: Bool = true,
        blockers: [String] = []
    ) -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightDocument(
            passed: passed,
            proxyPort: 80,
            blockers: blockers,
            settingsState: .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80),
            artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")],
            serviceStates: RuntimeManagedService.stopOrder.map {
                RuntimeFreshInstallServiceState(label: $0.label, state: .notLoaded)
            },
            packageReceiptStates: [
                .absent(identifier: "com.tirosh.vitalserver.vm"),
                .absent(identifier: "com.tirosh.vitalserver"),
            ],
            proxyPortState: .clear(port: 80)
        )
    }
}

private extension RuntimeInstallCommand {
    static let full = RuntimeInstallCommand(
        mode: .full,
        plan: RuntimeOperationPlans.install,
        completionStatus: .healthy,
        completionMessage: "runtime install completed"
    )

    static let provision = RuntimeInstallCommand(
        mode: .provision,
        plan: RuntimeOperationPlans.installProvision,
        completionStatus: .degraded,
        completionMessage: "runtime install provisioned; runtime services starting"
    )
}

private enum RuntimeInstallWorkflowTestError: Error, LocalizedError {
    case loadSettings
    case stepFailed
    case progressWrite

    var errorDescription: String? {
        switch self {
        case .loadSettings:
            return "settings unavailable"
        case .stepFailed:
            return "step failed"
        case .progressWrite:
            return "progress write failed"
        }
    }
}
