import Contracts
import Domain

public typealias RuntimeVMLifecycleStateTransitionError = RuntimeVMLifecycleTransitionError

public struct RuntimeVMLifecycleTransitionUseCase {
    public init() {}

    public func nextRevision(
        current: RuntimeVMLifecycleDocument?,
        currentRevision: Int?,
        proposed: RuntimeVMLifecycleDocument,
        expectedRevision: Int?
    ) throws -> Int {
        try RuntimeVMLifecycleTransitionPolicy().nextRevision(
            current: current,
            currentRevision: currentRevision,
            proposed: proposed,
            expectedRevision: expectedRevision
        )
    }
}

extension RuntimeVMLifecycleTransitionUseCase: RuntimeVMLifecycleTransitionDeciding {}
