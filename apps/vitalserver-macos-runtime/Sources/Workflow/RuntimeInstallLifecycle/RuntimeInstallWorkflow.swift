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
        let startPlan = useCase.startPlan(runtimeHomePath: runtimeHomePath())
        log(startPlan.logMessage)
        try writer.writeStatus(.installing, .install, startPlan.statusMessage)

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
            writeCriticalStatusBestEffort(useCase.settingsLoadFailedStatusMessage(error: error))
            throw error
        }

        let settingsDecision = try transitionAndPersist(
            from: startDecision.state,
            event: .settingsLoaded,
            context: context,
            expectedCommands: try useCase.setupReadCommands(for: installPlan)
        )

        var decision = try verifySetup(
            from: settingsDecision.state,
            installPlan: installPlan,
            context: context
        )

        guard decision.blockers.isEmpty else {
            writeCriticalStatusBestEffort(useCase.setupBlockedStatusMessage(blockers: decision.blockers))
            throw RuntimeInstallWorkflowError.operationFailed(
                useCase.setupBlockedFailureMessage(blockers: decision.blockers)
            )
        }

        while true {
            guard let nextCommand = decision.commands.first else {
                throw RuntimeInstallWorkflowError.operationFailed(
                    useCase.missingCommandMessage(state: decision.state)
                )
            }
            switch nextCommand {
            case .executeStep(let step):
                try requireCommands([.executeStep(step)], in: decision)
                decision = try execute(step, settings: settings, from: decision.state, context: context)
            case .complete:
                try requireCommands([.complete], in: decision)
                try writer.writeStatus(installPlan.completionStatus, .install, installPlan.completionMessage)
                log(useCase.completionLogMessage(plan: installPlan, runtimeHomePath: runtimeHomePath()))
                return
            case .loadSettings, .readFreshInstallPreflight, .readProvisionPayload:
                throw RuntimeInstallWorkflowError.operationFailed(
                    useCase.postSetupCommandFailureMessage(nextCommand)
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
                expectedCommands: try useCase.expectedCommandsAfterFreshInstallPreflight(
                    preflight,
                    plan: installPlan
                )
            )
        case .provision:
            let payload = readers.provisionPayload()
            return try transitionAndPersist(
                from: state,
                event: .provisionPayloadObserved(payload),
                context: context,
                expectedCommands: try useCase.expectedCommandsAfterProvisionPayload(
                    payload,
                    plan: installPlan
                )
            )
        case .unknown:
            throw RuntimeInstallWorkflowError.operationFailed(useCase.unknownInstallModeFailureMessage(installPlan.mode))
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
            useCase.stepProgressEvent(
                step: step,
                stepStatus: .started,
                phase: .running,
                message: useCase.stepStartedMessage(step)
            )
        )
        do {
            try effects.executeStep(step, settings)
            writeProgressBestEffort(
                useCase.stepProgressEvent(
                    step: step,
                    stepStatus: .completed,
                    phase: .running,
                    message: useCase.stepCompletedMessage(step)
                )
            )
            let decision = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepSucceeded(step),
                context: context
            )
            log(useCase.stepCompletedLogMessage(step))
            return decision
        } catch {
            writeProgressBestEffort(
                useCase.stepProgressEvent(
                    step: step,
                    stepStatus: .failed,
                    phase: .failed,
                    message: useCase.stepFailedMessage(step, error: error)
                )
            )
            _ = try transitionAndPersist(
                from: startedDecision.state,
                event: .stepFailed(step, reason: error.localizedDescription),
                context: context,
                expectedCommands: []
            )
            writeCriticalStatusBestEffort(useCase.installFailedStatusMessage(error: error))
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

    private func writeProgressBestEffort(_ event: RuntimeStepExecutionEvent) {
        do {
            try writer.writeProgress(event)
        } catch {
            log(useCase.progressWriteFailedLogMessage(event: event, error: error))
        }
    }

    private func writeCriticalStatusBestEffort(_ message: String) {
        do {
            try writer.writeStatus(.critical, .install, message)
        } catch {
            log(useCase.criticalStatusWriteFailedLogMessage(error: error))
        }
    }

    private func log(_ message: String) {
        diagnostics.log(message)
    }
}
