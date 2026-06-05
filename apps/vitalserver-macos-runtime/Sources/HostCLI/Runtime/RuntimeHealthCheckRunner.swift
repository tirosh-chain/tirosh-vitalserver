import Application
import Contracts
import RuntimeWorkflow

struct RuntimeHealthCheckRunner {
    private let workflow: RuntimeHealthRefreshWorkflow
    var printStatus: () throws -> Void
    var printLine: (String) -> Void

    init(
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

    func run() throws {
        try printStatus()
        do {
            let decision = try workflow.refresh()
            printLine(decision.outputLine)
        } catch RuntimeWorkflowError.operationFailed {
            printLine("health: failed")
            throw LauncherError.runtimeHealthFailed
        }
    }
}
