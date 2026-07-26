import Contracts

public enum RuntimeVMLifecycleProcessExitDecision: Equatable, Sendable {
    case stoppedVerified
    case terminalFailurePreserved
    case recordTerminalFailure(message: String)
    case blocked(reason: String)
}

public struct RuntimeVMLifecycleProcessExitPolicy: Sendable {
    public init() {}

    public func decide(
        lifecycleState: RuntimeVMLifecycleState,
        expectedProcessID: Int32
    ) -> RuntimeVMLifecycleProcessExitDecision {
        switch lifecycleState {
        case .stopped:
            return .stoppedVerified
        case .failed:
            return .terminalFailurePreserved
        case .starting, .bootstrapping, .running, .stopping:
            return .recordTerminalFailure(
                message: "VM process exited without terminal lifecycle state "
                    + "pid=\(expectedProcessID) previousState=\(lifecycleState.rawValue)"
            )
        case .unknown(let value):
            return .blocked(reason: "VM lifecycle state is unknown value=\(value)")
        }
    }

    public func decideAfterServiceStop(
        lifecycleState: RuntimeVMLifecycleState
    ) -> RuntimeVMLifecycleProcessExitDecision {
        switch lifecycleState {
        case .stopped:
            return .stoppedVerified
        case .failed:
            return .terminalFailurePreserved
        case .starting, .bootstrapping, .running, .stopping:
            return .recordTerminalFailure(
                message: "VM service stopped without terminal lifecycle state "
                    + "previousState=\(lifecycleState.rawValue)"
            )
        case .unknown(let value):
            return .blocked(reason: "VM lifecycle state is unknown value=\(value)")
        }
    }
}
