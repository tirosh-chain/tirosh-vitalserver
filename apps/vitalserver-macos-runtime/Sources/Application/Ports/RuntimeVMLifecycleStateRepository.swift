import Contracts

public struct RuntimeVMLifecycleStateRecord: Equatable, Sendable {
    public let document: RuntimeVMLifecycleDocument
    public let revision: Int

    public init(document: RuntimeVMLifecycleDocument, revision: Int) {
        self.document = document
        self.revision = revision
    }
}

public struct RuntimeVMLifecycleStateMutation: Equatable, Sendable {
    public let document: RuntimeVMLifecycleDocument
    public let expectedRevision: Int?

    public init(document: RuntimeVMLifecycleDocument, expectedRevision: Int?) {
        self.document = document
        self.expectedRevision = expectedRevision
    }
}

public enum RuntimeVMLifecycleStateReadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeVMLifecycleStateRecord)
    case failed(String)
}

public protocol RuntimeVMLifecycleStateReading: Sendable {
    func loadVMLifecycleState() -> RuntimeVMLifecycleStateReadResult
}

public protocol RuntimeVMLifecycleStateMutating: Sendable {
    @discardableResult
    func saveVMLifecycleState(
        _ mutation: RuntimeVMLifecycleStateMutation
    ) throws -> RuntimeVMLifecycleStateRecord
}

public protocol RuntimeVMLifecycleStateRepository:
    RuntimeVMLifecycleStateReading,
    RuntimeVMLifecycleStateMutating
{}

public protocol RuntimeVMLifecycleTransitionDeciding: Sendable {
    func nextRevision(
        current: RuntimeVMLifecycleDocument?,
        currentRevision: Int?,
        proposed: RuntimeVMLifecycleDocument,
        expectedRevision: Int?
    ) throws -> Int
}
