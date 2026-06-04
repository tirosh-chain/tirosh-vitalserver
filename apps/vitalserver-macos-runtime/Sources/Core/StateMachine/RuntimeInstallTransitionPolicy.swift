import Contracts

public struct RuntimeInstallTransitionContext: Equatable, Sendable {
    public let mode: RuntimeInstallMode
    public let plan: RuntimeOperationPlan

    public init(mode: RuntimeInstallMode, plan: RuntimeOperationPlan) {
        self.mode = mode
        self.plan = plan
    }
}

public enum RuntimeInstallWorkflowState: Equatable, Sendable {
    case notStarted
    case started
    case settingsLoaded
    case preflightVerified
    case preflightBlocked
    case provisionPayloadVerified
    case provisionPayloadBlocked
    case stepStarted(RuntimeWorkflowStep)
    case stepCompleted(RuntimeWorkflowStep)
    case provisioned
    case completed
    case failed
}

public enum RuntimeInstallWorkflowEvent: Equatable, Sendable {
    case start
    case settingsLoaded
    case settingsLoadFailed(reason: String)
    case freshInstallPreflightObserved(RuntimeFreshInstallPreflightDocument)
    case provisionPayloadObserved(RuntimeInstallProvisionPayloadDocument)
    case stepStarted(RuntimeWorkflowStep)
    case stepSucceeded(RuntimeWorkflowStep)
    case stepFailed(RuntimeWorkflowStep, reason: String)
}

public enum RuntimeInstallWorkflowCommand: Equatable, Sendable {
    case loadSettings
    case readFreshInstallPreflight
    case readProvisionPayload
    case executeStep(RuntimeWorkflowStep)
    case complete
}

public struct RuntimeInstallTransitionDecision: Equatable, Sendable {
    public let state: RuntimeInstallWorkflowState
    public let persistedState: RuntimeInstallState?
    public let currentStep: RuntimeWorkflowStep?
    public let commands: [RuntimeInstallWorkflowCommand]
    public let blockers: [String]
    public let message: String?

    public init(
        state: RuntimeInstallWorkflowState,
        persistedState: RuntimeInstallState? = nil,
        currentStep: RuntimeWorkflowStep? = nil,
        commands: [RuntimeInstallWorkflowCommand] = [],
        blockers: [String] = [],
        message: String? = nil
    ) {
        self.state = state
        self.persistedState = persistedState
        self.currentStep = currentStep
        self.commands = commands
        self.blockers = blockers
        self.message = message
    }
}

public struct RuntimeInstallTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: RuntimeInstallWorkflowState
    public let event: RuntimeInstallWorkflowEvent
    public let reason: String

    public init(
        state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        reason: String = "invalid install transition"
    ) {
        self.state = state
        self.event = event
        self.reason = reason
    }

    public var description: String {
        "\(reason) state=\(state) event=\(event)"
    }
}

public enum RuntimeInstallTransitionPolicy {
    public static func transition(
        from state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        context: RuntimeInstallTransitionContext
    ) throws -> RuntimeInstallTransitionDecision {
        try validate(context)
        switch (state, event) {
        case (.notStarted, .start):
            return RuntimeInstallTransitionDecision(
                state: .started,
                persistedState: .started,
                commands: [.loadSettings],
                message: "runtime install started"
            )

        case (.started, .settingsLoaded):
            return RuntimeInstallTransitionDecision(
                state: .settingsLoaded,
                persistedState: .settingsLoaded,
                commands: setupCommands(context),
                message: "install settings loaded"
            )

        case (.started, .settingsLoadFailed(reason: let reason)):
            return RuntimeInstallTransitionDecision(
                state: .failed,
                persistedState: .failed,
                blockers: ["install-settings-load-failed:reason=\(reason)"],
                message: "install settings load failed"
            )

        case (.settingsLoaded, .freshInstallPreflightObserved(let document)):
            guard context.mode == .full else {
                throw error(state: state, event: event, reason: "provision install must not use fresh install preflight")
            }
            let blockers = preflightBlockers(document)
            guard blockers.isEmpty else {
                return RuntimeInstallTransitionDecision(
                    state: .preflightBlocked,
                    persistedState: .preflightBlocked,
                    blockers: blockers,
                    message: "fresh install preflight blocked"
                )
            }
            return RuntimeInstallTransitionDecision(
                state: .preflightVerified,
                persistedState: .preflightVerified,
                commands: firstStepCommand(context.plan),
                message: "fresh install preflight verified"
            )

        case (.settingsLoaded, .provisionPayloadObserved(let document)):
            guard context.mode == .provision else {
                throw error(state: state, event: event, reason: "full install must use fresh install preflight")
            }
            let blockers = provisionPayloadBlockers(document)
            guard blockers.isEmpty else {
                return RuntimeInstallTransitionDecision(
                    state: .provisionPayloadBlocked,
                    persistedState: .provisionPayloadBlocked,
                    blockers: blockers,
                    message: "install provision payload blocked"
                )
            }
            return RuntimeInstallTransitionDecision(
                state: .provisionPayloadVerified,
                persistedState: .provisionPayloadVerified,
                commands: firstStepCommand(context.plan),
                message: "install provision payload verified"
            )

        case (.preflightVerified, .stepStarted(let step)):
            guard firstStep(context.plan) == step else {
                throw error(state: state, event: event, reason: "install step is not first plan step")
            }
            return stepStartedDecision(step)

        case (.provisionPayloadVerified, .stepStarted(let step)):
            guard firstStep(context.plan) == step else {
                throw error(state: state, event: event, reason: "install step is not first plan step")
            }
            return stepStartedDecision(step)

        case (.stepCompleted(let previous), .stepStarted(let step)):
            guard nextStep(after: previous, in: context.plan) == step else {
                throw error(state: state, event: event, reason: "install step is not next plan step")
            }
            return stepStartedDecision(step)

        case (.stepStarted(let running), .stepSucceeded(let completed)):
            guard running == completed else {
                throw error(state: state, event: event, reason: "install step success does not match running step")
            }
            if let next = nextStep(after: completed, in: context.plan) {
                return RuntimeInstallTransitionDecision(
                    state: .stepCompleted(completed),
                    persistedState: .stepCompleted,
                    currentStep: completed,
                    commands: [.executeStep(next)],
                    message: "install step completed"
                )
            }
            return completionDecision(context)

        case (.stepStarted(let running), .stepFailed(let failed, reason: let reason)):
            guard running == failed else {
                throw error(state: state, event: event, reason: "install step failure does not match running step")
            }
            return RuntimeInstallTransitionDecision(
                state: .failed,
                persistedState: .failed,
                currentStep: failed,
                blockers: ["install-step-failed:step=\(failed.rawValue) reason=\(reason)"],
                message: "install step failed"
            )

        default:
            throw error(state: state, event: event)
        }
    }

    private static func validate(_ context: RuntimeInstallTransitionContext) throws {
        guard context.plan.operation == .install, context.plan.invalidSteps.isEmpty else {
            throw RuntimeInstallTransitionError(
                state: .notStarted,
                event: .start,
                reason: "invalid install plan"
            )
        }
        switch context.mode {
        case .full:
            guard context.plan.steps.contains(.waitInstallRuntimeHealth) else {
                throw RuntimeInstallTransitionError(
                    state: .notStarted,
                    event: .start,
                    reason: "full install plan must wait for runtime health"
                )
            }
        case .provision:
            guard !context.plan.steps.contains(.waitInstallRuntimeHealth) else {
                throw RuntimeInstallTransitionError(
                    state: .notStarted,
                    event: .start,
                    reason: "install provision plan must not claim runtime health"
                )
            }
        case .unknown(let value):
            throw RuntimeInstallTransitionError(
                state: .notStarted,
                event: .start,
                reason: "install mode unknown value=\(value)"
            )
        }
    }

    private static func preflightBlockers(_ document: RuntimeFreshInstallPreflightDocument) -> [String] {
        if document.passed, document.blockers.isEmpty {
            return []
        }
        if !document.blockers.isEmpty {
            return document.blockers
        }
        return ["fresh-install-preflight-failed-without-blockers"]
    }

    private static func provisionPayloadBlockers(_ document: RuntimeInstallProvisionPayloadDocument) -> [String] {
        if document.passed, document.blockers.isEmpty {
            return []
        }
        if !document.blockers.isEmpty {
            return document.blockers
        }
        return ["install-provision-payload-failed-without-blockers"]
    }

    private static func setupCommands(_ context: RuntimeInstallTransitionContext) -> [RuntimeInstallWorkflowCommand] {
        switch context.mode {
        case .full:
            return [.readFreshInstallPreflight]
        case .provision:
            return [.readProvisionPayload]
        case .unknown:
            return []
        }
    }

    private static func firstStepCommand(_ plan: RuntimeOperationPlan) -> [RuntimeInstallWorkflowCommand] {
        guard let step = firstStep(plan) else {
            return [.complete]
        }
        return [.executeStep(step)]
    }

    private static func firstStep(_ plan: RuntimeOperationPlan) -> RuntimeWorkflowStep? {
        plan.steps.first
    }

    private static func nextStep(
        after step: RuntimeWorkflowStep,
        in plan: RuntimeOperationPlan
    ) -> RuntimeWorkflowStep? {
        guard let index = plan.steps.firstIndex(of: step) else {
            return nil
        }
        let nextIndex = plan.steps.index(after: index)
        guard nextIndex < plan.steps.endIndex else {
            return nil
        }
        return plan.steps[nextIndex]
    }

    private static func stepStartedDecision(_ step: RuntimeWorkflowStep) -> RuntimeInstallTransitionDecision {
        RuntimeInstallTransitionDecision(
            state: .stepStarted(step),
            persistedState: .stepStarted,
            currentStep: step,
            message: "install step started"
        )
    }

    private static func completionDecision(
        _ context: RuntimeInstallTransitionContext
    ) -> RuntimeInstallTransitionDecision {
        switch context.mode {
        case .full:
            return RuntimeInstallTransitionDecision(
                state: .completed,
                persistedState: .completed,
                commands: [.complete],
                message: "runtime install completed"
            )
        case .provision:
            return RuntimeInstallTransitionDecision(
                state: .provisioned,
                persistedState: .provisioned,
                commands: [.complete],
                message: "runtime install provisioned"
            )
        case .unknown(let value):
            return RuntimeInstallTransitionDecision(
                state: .failed,
                persistedState: .failed,
                blockers: ["install-mode-unknown:value=\(value)"],
                message: "install mode unknown"
            )
        }
    }

    private static func error(
        state: RuntimeInstallWorkflowState,
        event: RuntimeInstallWorkflowEvent,
        reason: String = "invalid install transition"
    ) -> RuntimeInstallTransitionError {
        RuntimeInstallTransitionError(state: state, event: event, reason: reason)
    }
}
