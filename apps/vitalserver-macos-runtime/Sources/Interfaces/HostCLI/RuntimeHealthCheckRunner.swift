import Application
import Contracts
import Workflow

public enum RuntimeHealthCheckRunnerError: Error, CustomStringConvertible, Equatable {
    case runtimeHealthFailed

    public var description: String {
        switch self {
        case .runtimeHealthFailed:
            return "runtime health check failed"
        }
    }
}

public struct RuntimeHealthCheckRunner {
    private let workflow: RuntimeHealthRefreshWorkflow
    public var printStatus: () throws -> Void
    public var printLine: (String) -> Void

    public init(
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
        self.workflow = RuntimeHealthRefreshWorkflow(
            useCase: RefreshRuntimeHealthUseCase(
                ports: RuntimeHealthRefreshPorts(healthSnapshot: healthSnapshot)
            ),
            writer: RuntimeHealthRefreshWriter(
                writeStatus: writeStatus,
                writeStatusBestEffort: writeStatusBestEffort,
                recordObservedEventBestEffort: recordObservedEventBestEffort
            )
        )
        self.printStatus = printStatus
        self.printLine = printLine
    }

    public func run() throws {
        try printStatus()
        do {
            let decision = try workflow.refresh()
            printLine(decision.outputLine)
        } catch RuntimeHealthRefreshWorkflowError.operationFailed {
            printLine("health: failed")
            throw RuntimeHealthCheckRunnerError.runtimeHealthFailed
        }
    }
}
