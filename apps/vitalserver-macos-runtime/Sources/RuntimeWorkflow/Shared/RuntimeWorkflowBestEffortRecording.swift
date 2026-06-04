import Contracts
import Core

func writeRuntimeProgressBestEffort(
    _ event: RuntimeStepExecutionEvent,
    writeProgress: (RuntimeStepExecutionEvent) throws -> Void,
    log: (String) -> Void
) {
    do {
        try writeProgress(event)
    } catch {
        log(
            "failed to write runtime progress " +
                "step=\(event.step.rawValue) stepStatus=\(event.stepStatus.rawValue) error=\(error)"
        )
    }
}
