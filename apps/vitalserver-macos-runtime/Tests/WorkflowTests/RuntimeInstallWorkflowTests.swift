import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeInstallWorkflowTests: XCTestCase {
    func testFullInstallExecutesPlanAndWritesHealthyCompletion() throws {
        let harness = InstallRuntimeUseCaseHarness()

        try harness.run(.full)

        XCTAssertEqual(harness.executedPlans, RuntimeOperationPlans.install.steps.map(InstallRuntimeUseCase().stepExecutionPlan))
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

    func testProvisionInstallCompletesInitializingWithoutClaimingHealth() throws {
        let harness = InstallRuntimeUseCaseHarness()

        try harness.run(.provision)

        XCTAssertEqual(harness.executedPlans, RuntimeOperationPlans.installProvision.steps.map(InstallRuntimeUseCase().stepExecutionPlan))
        XCTAssertFalse(harness.executedPlans.contains(.waitInstallRuntimeHealth))
        XCTAssertEqual(harness.statuses.first?.level, .installing)
        XCTAssertEqual(harness.statuses.last?.level, .initializing)
        XCTAssertEqual(harness.statuses.last?.message, "runtime initialized; runtime services starting")
        XCTAssertTrue(harness.progressEvents.allSatisfy { $0.status == .installing })
        XCTAssertTrue(harness.stateEvents.contains("state:provisioned:provision:-:runtime install provisioned:"))
    }

    func testPreflightBlockedDoesNotExecuteStepsAndWritesExplicitState() {
        let harness = InstallRuntimeUseCaseHarness()
        harness.preflight = harness.preflightDocument(
            passed: false,
            blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"]
        )

        XCTAssertThrowsError(try harness.run(.full))

        XCTAssertTrue(harness.executedPlans.isEmpty)
        XCTAssertTrue(harness.stateEvents.contains(
            "state:preflight-blocked:full:-:fresh install preflight blocked:install-artifact-present:path=/usr/local/bin/vitalserver-vm"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertTrue(harness.statuses.last?.message.contains("runtime install setup blocked") == true)
    }

    func testProvisionInstallBlocksWhenInstalledPayloadIsMissing() {
        let harness = InstallRuntimeUseCaseHarness()
        harness.provisionPayload = RuntimeInstallProvisionPayloadDocument(
            passed: false,
            blockers: ["install-payload-missing:path=/usr/local/bin/vitalserver-vm"],
            artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")]
        )

        XCTAssertThrowsError(try harness.run(.provision))

        XCTAssertTrue(harness.executedPlans.isEmpty)
        XCTAssertTrue(harness.stateEvents.contains(
            "state:provision-payload-blocked:provision:-:install provision payload blocked:install-payload-missing:path=/usr/local/bin/vitalserver-vm"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertTrue(harness.statuses.last?.message.contains("runtime install setup blocked") == true)
    }

    func testSettingsLoadFailureWritesFailedStateBeforeRethrowing() {
        let harness = InstallRuntimeUseCaseHarness()
        harness.loadError = InstallRuntimeUseCaseTestError.loadSettings

        XCTAssertThrowsError(try harness.run(.full))

        XCTAssertTrue(harness.executedPlans.isEmpty)
        XCTAssertTrue(harness.stateEvents.contains(
            "state:failed:full:-:install settings load failed:install-settings-load-failed:reason=settings unavailable"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
    }

    func testStepFailurePersistsFailedStateAndDoesNotComplete() {
        let harness = InstallRuntimeUseCaseHarness()
        harness.stepErrorPlan = .provisionVMDisk
        harness.stepError = InstallRuntimeUseCaseTestError.stepFailed

        XCTAssertThrowsError(try harness.run(.full))

        XCTAssertTrue(harness.executedPlans.contains(.provisionVMDisk))
        XCTAssertFalse(harness.stateEvents.contains("state:completed:full:-:runtime install completed:"))
        XCTAssertTrue(harness.stateEvents.contains(
            "state:failed:full:provision-vm-disk:install step failed:install-step-failed:step=provision-vm-disk reason=step failed"
        ))
        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.progressEvents.last?.step, .provisionVMDisk)
        XCTAssertEqual(harness.progressEvents.last?.stepStatus, .failed)
    }

    func testProgressWriteFailureIsLoggedAndDoesNotStopInstall() throws {
        let harness = InstallRuntimeUseCaseHarness()
        harness.progressError = InstallRuntimeUseCaseTestError.progressWrite

        try harness.run(.provision)

        XCTAssertEqual(harness.statuses.last?.level, .initializing)
        XCTAssertTrue(harness.logs.contains {
            $0.contains("runtime install progress write failed")
        })
    }
}

private struct TestInstallSettings: Equatable {
    let vitalFilesDirectory: String
}

private final class InstallRuntimeUseCaseHarness {
    var settings = TestInstallSettings(vitalFilesDirectory: "/vital-files")
    var preflight: RuntimeFreshInstallPreflightDocument?
    var provisionPayload: RuntimeInstallProvisionPayloadDocument?
    var loadError: Error?
    var stepErrorPlan: InstallRuntimeStepExecutionPlan?
    var stepError: Error?
    var progressError: Error?
    var stateEvents: [String] = []
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var executedPlans: [InstallRuntimeStepExecutionPlan] = []
    var logs: [String] = []

    func run(_ plan: InstallRuntimePlan) throws {
        try RuntimeInstallWorkflow().run(
            plan,
            context: InstallRuntimeExecutionContext(runtimeHomePath: "/runtime-home"),
            operations: operations
        )
    }

    var operations: InstallRuntimeOperations<TestInstallSettings> {
        InstallRuntimeOperations(
            readers: InstallRuntimeStateReaders(
                loadSettings: {
                    if let loadError = self.loadError {
                        throw loadError
                    }
                    return self.settings
                },
                freshInstallPreflight: {
                    self.preflight ?? self.preflightDocument()
                },
                provisionPayload: {
                    self.provisionPayload ?? self.provisionPayloadDocument()
                }
            ),
            effects: InstallRuntimeEffects(
                log: { message in
                    self.executedPlans.append(.log(message))
                },
                prepareInstallDirectories: { _ in
                    try self.execute(.prepareInstallDirectories)
                },
                rotateRuntimeLogs: {
                    try self.execute(.rotateRuntimeLogs)
                },
                configureDeployEnvironment: { _ in
                    try self.execute(.configureDeployEnvironment)
                },
                prepareInstalledExecutables: {
                    try self.execute(.prepareInstalledExecutables)
                },
                provisionVMDisk: { _ in
                    try self.execute(.provisionVMDisk)
                },
                configureInstalledVMRuntime: { _ in
                    try self.execute(.configureInstalledVMRuntime)
                },
                createCloudInitSeed: { _ in
                    try self.execute(.createCloudInitSeed)
                },
                writeInstalledRuntimeVersion: {
                    try self.execute(.writeInstalledRuntimeVersion)
                },
                configureInstalledPermissions: { _ in
                    try self.execute(.configureInstalledPermissions)
                },
                startInstalledServices: { _ in
                    try self.execute(.startInstalledServices)
                },
                applyStartOnBootPolicy: { _ in
                    try self.execute(.applyStartOnBootPolicy)
                },
                waitInstallRuntimeHealth: { _ in
                    try self.execute(.waitInstallRuntimeHealth)
                },
                cleanupInstallSettings: {
                    try self.execute(.cleanupInstallSettings)
                },
                describeError: { error in
                    error.localizedDescription
                },
                prepareHostStateStore: { _ in
                    try self.execute(.prepareHostStateStore)
                }
            ),
            writer: InstallRuntimeStateWriter(
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
            diagnostics: InstallRuntimeDiagnostics(
                log: { message in
                    self.logs.append(message)
                }
            )
        )
    }

    private func execute(_ plan: InstallRuntimeStepExecutionPlan) throws {
        executedPlans.append(plan)
        if stepErrorPlan == plan, let error = stepError {
            throw error
        }
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
            serviceStates: RuntimeManagedService.uninstallOrder.map {
                RuntimeFreshInstallServiceState(label: $0.label, state: .notLoaded)
            },
            packageReceiptStates: [
                .absent(identifier: "ai.tirosh.vitalserver.helper"),
            ],
            proxyPortState: .clear(port: 80)
        )
    }

    func provisionPayloadDocument() -> RuntimeInstallProvisionPayloadDocument {
        RuntimeInstallProvisionPayloadDocument(
            passed: true,
            blockers: [],
            artifactStates: [.present(path: "/usr/local/bin/vitalserver-vm")]
        )
    }
}

private extension InstallRuntimePlan {
    static let full = InstallRuntimePlan(
        mode: .full,
        operationPlan: RuntimeOperationPlans.install,
        activeStatus: .installing,
        completionStatus: .healthy,
        completionMessage: "runtime install completed"
    )

    static let provision = InstallRuntimePlan(
        mode: .provision,
        operationPlan: RuntimeOperationPlans.installProvision,
        activeStatus: .installing,
        completionStatus: .initializing,
        completionMessage: "runtime initialized; runtime services starting"
    )
}

private enum InstallRuntimeUseCaseTestError: Error, LocalizedError {
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
