import Application
import Contracts
import Errors

public struct RuntimeHealthCheckRunner {
    private let useCase: RefreshRuntimeHealthUseCase
    private let operations: RefreshRuntimeHealthOperations
    public var printStatus: () throws -> Void
    public var printLine: (String) -> Void

    public init(
        useCase: RefreshRuntimeHealthUseCase,
        printStatus: @escaping () throws -> Void,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        recordObservedEventBestEffort: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) -> Void,
        printLine: @escaping (String) -> Void
    ) {
        self.useCase = useCase
        self.operations = RefreshRuntimeHealthOperations(
            healthSnapshot: healthSnapshot,
            writeStatus: writeStatus,
            writeStatusBestEffort: writeStatusBestEffort,
            recordObservedEventBestEffort: recordObservedEventBestEffort
        )
        self.printStatus = printStatus
        self.printLine = printLine
    }

    public func run() throws {
        try printStatus()
        do {
            let decision = try useCase.refresh(operations: operations)
            printLine(decision.outputLine)
        } catch RefreshRuntimeHealthUseCaseError.operationFailed {
            printLine("health: failed")
            throw RuntimeHealthCheckRunnerError.runtimeHealthFailed
        }
    }
}
