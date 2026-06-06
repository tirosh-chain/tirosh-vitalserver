import Foundation
import Application
import Contracts
import Domain
import Errors

public struct RuntimeInstallStateReaders<Settings> {
    public var loadSettings: () throws -> Settings
    public var freshInstallPreflight: () -> RuntimeFreshInstallPreflightDocument
    public var provisionPayload: () -> RuntimeInstallProvisionPayloadDocument

    public init(
        loadSettings: @escaping () throws -> Settings,
        freshInstallPreflight: @escaping () -> RuntimeFreshInstallPreflightDocument,
        provisionPayload: @escaping () -> RuntimeInstallProvisionPayloadDocument
    ) {
        self.loadSettings = loadSettings
        self.freshInstallPreflight = freshInstallPreflight
        self.provisionPayload = provisionPayload
    }
}

public struct RuntimeInstallEffects<Settings> {
    public var executeStep: (RuntimeWorkflowStep, Settings) throws -> Void

    public init(
        executeStep: @escaping (RuntimeWorkflowStep, Settings) throws -> Void
    ) {
        self.executeStep = executeStep
    }
}

public struct RuntimeInstallStateWriter {
    public var writeState: (RuntimeInstallState, RuntimeInstallMode, RuntimeWorkflowStep?, String?, [String]) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeProgress: (RuntimeStepExecutionEvent) throws -> Void

    public init(
        writeState: @escaping (RuntimeInstallState, RuntimeInstallMode, RuntimeWorkflowStep?, String?, [String]) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void
    ) {
        self.writeState = writeState
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
    }
}

public struct RuntimeInstallDiagnostics {
    public var log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }
}

public struct RuntimeInstallWorkflow<Settings> {
    public var readers: RuntimeInstallStateReaders<Settings>
    public var effects: RuntimeInstallEffects<Settings>
    public var writer: RuntimeInstallStateWriter
    public var diagnostics: RuntimeInstallDiagnostics
    public var runtimeHomePath: () -> String
    private var useCase: InstallRuntimeUseCase {
        InstallRuntimeUseCase()
    }

    public init(
        readers: RuntimeInstallStateReaders<Settings>,
        effects: RuntimeInstallEffects<Settings>,
        writer: RuntimeInstallStateWriter,
        diagnostics: RuntimeInstallDiagnostics,
        runtimeHomePath: @escaping () -> String
    ) {
        self.readers = readers
        self.effects = effects
        self.writer = writer
        self.diagnostics = diagnostics
        self.runtimeHomePath = runtimeHomePath
    }

    public func run(_ installPlan: InstallRuntimePlan) throws {
        let context = RuntimeInstallTransitionContext(mode: installPlan.mode, plan: installPlan.operationPlan)
        let startDecision = try transitionAndPersist(
            from: .notStarted,
            event: .start,
            context: context,
            expectedCommands: [.loadSettings]
        )
        log("runtime install started home=\(runtimeHomePath())")
        try writer.writeStatus(.installing, .install, "runtime install started")

        let settings: Settings
        do {
            settings = try readers.loadSettings()
        } catch {
            _ = try transitionAndPersist(
                from: startDecision.state,
                event: .settingsLoadFailed(reason: error.localizedDescription),
                context: context,
                expectedCommands: []
            )
            writeCriticalStatusBestEffort("runtime install failed: \(error)")
            throw error
        }

        let settingsDecision = try transitionAndPersist(
            from: startDecision.state,
            event: .settingsLoaded,
            context: context,
            expectedCommands: setupCommands(installPlan.mode)
        )

        var decision = try verifySetup(
            from: settingsDecision.state,
            installPlan: installPlan,
            context: context
        )

        guard decision.blockers.isEmpty else {
            writeCriticalStatusBestEffort("runtime install setup blocked: \(decision.blockers.joined(separator: ","))")
            throw RuntimeInstallWorkflowError.operationFailed(
                "runtime install setup blocked blockers=\(decision.blockers.joined(separator: ","))"
            )
        }

        while true {
            guard let nextCommand = decision.commands.first else {
                throw RuntimeInstallWorkflowError.operationFailed(
                    "install workflow missing command state=\(decision.state)"
                )
            }
            switch nextCommand {
            case .executeStep(let step):
                try requireCommands([.executeStep(step)], in: decision)
                decision = try execute(step, settings: settings, from: decision.state, context: context)
            case .complete:
                try requireCommands([.complete], in: decision)
                try writer.writeStatus(installPlan.completionStatus, .install, installPlan.completionMessage)
                log("\(installPlan.completionMessage) home=\(runtimeHomePath())")
                return
            case .loadSettings, .readFreshInstallPreflight, .readProvisionPayload:
                throw RuntimeInstallWorkflowError.operationFailed(
                    "install workflow command appeared after setup command=\(nextCommand)"
                )
            }
        }
    }

    private func verifySetup(
        from state: RuntimeInstallWorkflowState,
        installPlan: InstallRuntimePlan,
        context: RuntimeInstallTransitionContext
    ) throws -> RuntimeInstallTransitionDecision {
        switch installPlan.mode {
        case .full:
            let preflight = readers.freshInstallPreflight()
            return try transitionAndPersist(
                from: state,
                event: .freshInstallPreflightObserved(preflight),
                context: context,
                expectedCommands: preflight.passed && preflight.blockers.isEmpty
                    ? firstStepCommand(installPlan.operationPlan)
                    : []
            )
        case .provision:
            let payload = readers.provisionPayload()
            return try transitionAndPersist(
                from: state,
                event: .provisionPayloadObserved(payload),
                context: context,
                expectedCommands: payload.passed && payload.blockers.isEmpty
                    ? firstStepCommand(installPlan.operationPlan)
                    : []
            )
        case .unknown:
            throw RuntimeInstallWorkflowError.operationFailed("install mode unknown value=\(installPlan.mode.rawValue)")
        }
    }

    private func execute(
        _ step: RuntimeWorkflowStep,
        settings: Settings,
        from state: RuntimeInstallWorkflowState,
        context: RuntimeInstallTransitionContext
    ) throws -> RuntimeInstallTransitionDecision {
        let startedDecision = try transitionAndPersist(
            from: state,
            event: .stepStarted(step),
            context: context,
            expectedCommands: []
        )
        writeProgressBestEffort(
            event(step: step, stepStatus: .started, phase: .running, message: "step started: \(step.rawValue)")
        )
        do {
            try effects.executeStep(step, settings)
            writeProgressBestEffort(
                event(step: step, stepStatus: .completed, phase: .running, message: "step completed: \(step.rawValue)")
            )
            let decision = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepSucceeded(step),
                context: context
            )
            log("step=\(step.rawValue) status=completed")
            return decision
        } catch {
            writeProgressBestEffort(
                event(step: step, stepStatus: .failed, phase: .failed, message: "step failed: \(step.rawValue): \(error)")
            )
            _ = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepFailed(step, reason: error.localizedDescription),
                context: context,
                expectedCommands: []
            )
            writeCriticalStatusBestEffort("runtime install failed: \(error)")
            throw error
        }
    }

    private func transitionAndPersist(
        from state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        context: RuntimeInstallTransitionContext,
        expectedCommands: [RuntimeInstallWorkflowCommand]? = nil
    ) throws -> RuntimeInstallTransitionDecision {
        let decision = try useCase.transition(
            from: state,
            event: event,
            context: context,
            expectedCommands: expectedCommands
        )
        try persist(decision, mode: context.mode)
        return decision
    }

    private func persist(
        _ decision: RuntimeInstallTransitionDecision,
        mode: RuntimeInstallMode
    ) throws {
        guard let persistedState = decision.persistedState else {
            return
        }
        try writer.writeState(
            persistedState,
            mode,
            decision.currentStep,
            decision.message,
            decision.blockers
        )
    }

    private func requireCommands(
        _ expectedCommands: [RuntimeInstallWorkflowCommand],
        in decision: RuntimeInstallTransitionDecision
    ) throws {
        try useCase.requireCommands(expectedCommands, in: decision)
    }

    private func firstStepCommand(_ plan: RuntimeOperationPlan) -> [RuntimeInstallWorkflowCommand] {
        guard let firstStep = plan.steps.first else {
            return [.complete]
        }
        return [.executeStep(firstStep)]
    }

    private func setupCommands(_ mode: RuntimeInstallMode) -> [RuntimeInstallWorkflowCommand] {
        switch mode {
        case .full:
            return [.readFreshInstallPreflight]
        case .provision:
            return [.readProvisionPayload]
        case .unknown:
            return []
        }
    }

    private func event(
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

    private func writeProgressBestEffort(_ event: RuntimeStepExecutionEvent) {
        do {
            try writer.writeProgress(event)
        } catch {
            log("runtime install progress write failed step=\(event.step.rawValue) status=\(event.stepStatus.rawValue) error=\(error.localizedDescription)")
        }
    }

    private func writeCriticalStatusBestEffort(_ message: String) {
        do {
            try writer.writeStatus(.critical, .install, message)
        } catch {
            log("runtime install status write failed status=critical error=\(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        diagnostics.log(message)
    }
}
