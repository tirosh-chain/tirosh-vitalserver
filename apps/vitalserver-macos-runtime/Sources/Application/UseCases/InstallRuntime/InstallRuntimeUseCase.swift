import Foundation
import Contracts
import Domain
import Errors

public struct InstallRuntimeRequest: Equatable, Sendable {
    public let mode: RuntimeInstallMode

    public init(
        mode: RuntimeInstallMode
    ) {
        self.mode = mode
    }
}

public struct InstallRuntimePlan: Equatable, Sendable {
    public let mode: RuntimeInstallMode
    public let operationPlan: RuntimeOperationPlan
    public let completionStatus: RuntimeStatusLevel
    public let completionMessage: String

    public init(
        mode: RuntimeInstallMode,
        operationPlan: RuntimeOperationPlan,
        completionStatus: RuntimeStatusLevel,
        completionMessage: String
    ) {
        self.mode = mode
        self.operationPlan = operationPlan
        self.completionStatus = completionStatus
        self.completionMessage = completionMessage
    }
}

public struct InstallRuntimeStartPlan: Equatable, Sendable {
    public let logMessage: String
    public let statusMessage: String

    public init(logMessage: String, statusMessage: String) {
        self.logMessage = logMessage
        self.statusMessage = statusMessage
    }
}

public enum InstallRuntimeStepExecutionPlan: Equatable, Sendable {
    case log(String)
    case prepareInstallDirectories
    case rotateRuntimeLogs
    case configureDeployEnvironment
    case prepareInstalledExecutables
    case provisionVMDisk
    case configureInstalledVMRuntime
    case createCloudInitSeed
    case writeInstalledRuntimeVersion
    case configureInstalledPermissions
    case startInstalledServices
    case applyStartOnBootPolicy
    case waitInstallRuntimeHealth
    case cleanupInstallSettings
    case unsupported(message: String)
}

public struct InstallRuntimeUseCase {
    public init() {}

    public func plan(for request: InstallRuntimeRequest) -> InstallRuntimePlan {
        switch request.mode {
        case .full:
            return InstallRuntimePlan(
                mode: .full,
                operationPlan: RuntimeOperationPlans.install,
                completionStatus: .healthy,
                completionMessage: "runtime install completed"
            )
        case .provision:
            return InstallRuntimePlan(
                mode: .provision,
                operationPlan: RuntimeOperationPlans.installProvision,
                completionStatus: .degraded,
                completionMessage: "runtime install provisioned; runtime services starting"
            )
        case .unknown:
            return InstallRuntimePlan(
                mode: request.mode,
                operationPlan: RuntimeOperationPlans.install,
                completionStatus: .critical,
                completionMessage: "runtime install failed"
            )
        }
    }

    public func startPlan(runtimeHomePath: String) -> InstallRuntimeStartPlan {
        InstallRuntimeStartPlan(
            logMessage: "runtime install started home=\(runtimeHomePath)",
            statusMessage: "runtime install started"
        )
    }

    public func stepExecutionPlan(_ step: RuntimeWorkflowStep) -> InstallRuntimeStepExecutionPlan {
        switch step {
        case .loadInstallSettings:
            return .log("install settings loaded")
        case .prepareInstallDirectories:
            return .prepareInstallDirectories
        case .rotateRuntimeLogs:
            return .rotateRuntimeLogs
        case .configureGuestRuntimeConfig:
            return .configureDeployEnvironment
        case .prepareInstalledExecutables:
            return .prepareInstalledExecutables
        case .provisionVMDisk:
            return .provisionVMDisk
        case .configureVMRuntime:
            return .configureInstalledVMRuntime
        case .createCloudInitSeed:
            return .createCloudInitSeed
        case .writeInstallRuntimeVersion:
            return .writeInstalledRuntimeVersion
        case .configureInstalledPermissions:
            return .configureInstalledPermissions
        case .startInstalledServices:
            return .startInstalledServices
        case .applyStartOnBootPolicy:
            return .applyStartOnBootPolicy
        case .waitInstallRuntimeHealth:
            return .waitInstallRuntimeHealth
        case .cleanupInstallSettings:
            return .cleanupInstallSettings
        default:
            return .unsupported(message: "unsupported command: install step \(step.rawValue)")
        }
    }

    public func freshInstallPreflightDocument(
        settingsState: RuntimeInstallSettingsState,
        artifactStates: [RuntimeInstallArtifactState],
        serviceStates: [RuntimeFreshInstallServiceState],
        packageReceiptStates: [RuntimePackageReceiptState],
        proxyPortState: RuntimeHostProxyPortState?
    ) -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightPolicy.document(input: RuntimeFreshInstallPreflightInput(
            settingsState: settingsState,
            artifactStates: artifactStates,
            serviceStates: serviceStates,
            packageReceiptStates: packageReceiptStates,
            proxyPortState: proxyPortState
        ))
    }

    public func settingsLoadFailedStatusMessage(reason: String) -> String {
        "runtime install failed: \(reason)"
    }

    public func setupBlockedStatusMessage(blockers: [String]) -> String {
        "runtime install setup blocked: \(blockers.joined(separator: ","))"
    }

    public func setupBlockedFailureMessage(blockers: [String]) -> String {
        "runtime install setup blocked blockers=\(blockers.joined(separator: ","))"
    }

    public func missingCommandMessage(state: RuntimeInstallWorkflowState) -> String {
        "install workflow missing command state=\(state)"
    }

    public func postSetupCommandFailureMessage(_ command: RuntimeInstallWorkflowCommand) -> String {
        "install workflow command appeared after setup command=\(command)"
    }

    public func setupReadCommandFailureMessage(_ command: RuntimeInstallWorkflowCommand) -> String {
        "install workflow expected setup read command command=\(command)"
    }

    public func unknownInstallModeFailureMessage(_ mode: RuntimeInstallMode) -> String {
        "install mode unknown value=\(mode.rawValue)"
    }

    public func completionLogMessage(plan: InstallRuntimePlan, runtimeHomePath: String) -> String {
        "\(plan.completionMessage) home=\(runtimeHomePath)"
    }

    public func stepProgressEvent(
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String
    ) -> RuntimeStepExecutionEvent {
        RuntimeStepExecutionEvent(
            operation: .install,
            status: .installing,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message
        )
    }

    public func stepStartedMessage(_ step: RuntimeWorkflowStep) -> String {
        "step started: \(step.rawValue)"
    }

    public func stepCompletedMessage(_ step: RuntimeWorkflowStep) -> String {
        "step completed: \(step.rawValue)"
    }

    public func stepFailedMessage(_ step: RuntimeWorkflowStep, reason: String) -> String {
        "step failed: \(step.rawValue): \(reason)"
    }

    public func stepCompletedLogMessage(_ step: RuntimeWorkflowStep) -> String {
        "step=\(step.rawValue) status=completed"
    }

    public func installFailedStatusMessage(reason: String) -> String {
        "runtime install failed: \(reason)"
    }

    public func progressWriteFailedLogMessage(event: RuntimeStepExecutionEvent, reason: String) -> String {
        "runtime install progress write failed step=\(event.step.rawValue) status=\(event.stepStatus.rawValue) error=\(reason)"
    }

    public func criticalStatusWriteFailedLogMessage(reason: String) -> String {
        "runtime install status write failed status=critical error=\(reason)"
    }

    public func transition(
        from state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        context: RuntimeInstallTransitionContext,
        expectedCommands: [RuntimeInstallWorkflowCommand]? = nil
    ) throws -> RuntimeInstallTransitionDecision {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: state,
            event: event,
            context: context
        )
        if let expectedCommands {
            try requireCommands(expectedCommands, in: decision)
        }
        return decision
    }

    public func setupReadCommands(for plan: InstallRuntimePlan) throws -> [RuntimeInstallWorkflowCommand] {
        switch plan.mode {
        case .full:
            return [.readFreshInstallPreflight]
        case .provision:
            return [.readProvisionPayload]
        case .unknown(let value):
            throw InstallRuntimeUseCaseError.operationFailed("install mode unknown value=\(value)")
        }
    }

    public func setupReadCommand(
        from decision: RuntimeInstallTransitionDecision
    ) throws -> RuntimeInstallWorkflowCommand {
        guard decision.commands.count == 1, let command = decision.commands.first else {
            throw InstallRuntimeUseCaseError.operationFailed(
                "install workflow expected single setup read command state=\(decision.state) commands=\(decision.commands)"
            )
        }
        switch command {
        case .readFreshInstallPreflight, .readProvisionPayload:
            return command
        case .loadSettings, .executeStep, .complete:
            throw InstallRuntimeUseCaseError.operationFailed(setupReadCommandFailureMessage(command))
        }
    }

    public func expectedCommandsAfterFreshInstallPreflight(
        _ document: RuntimeFreshInstallPreflightDocument,
        plan: InstallRuntimePlan
    ) throws -> [RuntimeInstallWorkflowCommand] {
        guard plan.mode == .full else {
            throw InstallRuntimeUseCaseError.operationFailed("provision install must not use fresh install preflight")
        }
        guard document.passed, document.blockers.isEmpty else {
            return []
        }
        return firstStepCommand(plan.operationPlan)
    }

    public func expectedCommandsAfterProvisionPayload(
        _ document: RuntimeInstallProvisionPayloadDocument,
        plan: InstallRuntimePlan
    ) throws -> [RuntimeInstallWorkflowCommand] {
        guard plan.mode == .provision else {
            throw InstallRuntimeUseCaseError.operationFailed("full install must use fresh install preflight")
        }
        guard document.passed, document.blockers.isEmpty else {
            return []
        }
        return firstStepCommand(plan.operationPlan)
    }

    public func requireCommands(
        _ expectedCommands: [RuntimeInstallWorkflowCommand],
        in decision: RuntimeInstallTransitionDecision
    ) throws {
        guard decision.commands == expectedCommands else {
            throw InstallRuntimeUseCaseError.operationFailed(
                "unexpected install workflow commands state=\(decision.state) expected=\(expectedCommands) actual=\(decision.commands)"
            )
        }
    }

    private func firstStepCommand(_ plan: RuntimeOperationPlan) -> [RuntimeInstallWorkflowCommand] {
        guard let firstStep = plan.steps.first else {
            return [.complete]
        }
        return [.executeStep(firstStep)]
    }
}
