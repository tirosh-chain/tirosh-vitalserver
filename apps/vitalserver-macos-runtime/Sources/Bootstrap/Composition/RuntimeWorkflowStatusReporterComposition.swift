import Contracts
import Errors

public enum RuntimeWorkflowStatusReporterComposition {
    public static func make(
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        log: @escaping (String) -> Void
    ) -> RuntimeWorkflowStatusReporter {
        RuntimeWorkflowStatusReporter(
            writeStatus: writeStatus,
            writeProgress: writeProgress,
            log: log
        )
    }
}
