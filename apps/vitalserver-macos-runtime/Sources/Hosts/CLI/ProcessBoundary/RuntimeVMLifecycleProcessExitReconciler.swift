import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Errors

enum RuntimeVMLifecycleProcessExitReconciler {
    static func reconcileBeforeServiceStart(
        paths: LauncherPaths,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        processExists: (pid_t) -> Bool = ProcessState.defaultProcessExists,
        log: @escaping (String) -> Void
    ) throws {
        let processState = ProcessState.inspect(
            pidFile: paths.pidFile,
            fileStore: fileStore,
            processExists: processExists
        )
        switch processState {
        case .stalePid(let pid):
            try reconcile(
                expectedVMProcessID: pid_t(pid),
                paths: paths,
                log: log
            )
            ProcessState.removePidFile(paths.pidFile, fileStore: fileStore, log: log)
        case .pidFileMissing:
            let owner = SQLiteRuntimeVMLifecycleResourceStore(
                databaseURL: paths.installed.runtimeStateDatabase,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
            let read = owner.loadVMLifecycleResource()
            if read.state == .missing || read.document?.state == .stopped || read.document?.state == .failed {
                return
            }
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle reconciliation blocked before service start "
                    + "processState=\(processState.rawValue) lifecycleReadState=\(read.state.rawValue) "
                    + "lifecycleState=\(read.document?.state.rawValue ?? "missing") "
                    + "error=\(read.readError ?? "none")"
            )
        case .running, .pidFileInvalid, .readFailed, .signalFailed, .stopTimedOut, .unknown, .stopped:
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle reconciliation blocked before service start processState=\(processState.rawValue)"
            )
        }
    }

    static func reconcile(
        expectedVMProcessID: pid_t,
        paths: LauncherPaths,
        log: @escaping (String) -> Void
    ) throws {
        let owner = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: paths.installed.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let read = owner.loadVMLifecycleResource()
        guard read.state == .loaded, let current = read.document else {
            let readError = read.readError ?? "none"
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle proof is unavailable after observed process exit "
                    + "pid=\(expectedVMProcessID) state=\(read.state.rawValue) "
                    + "error=\(readError)"
            )
        }

        switch RuntimeVMLifecycleProcessExitPolicy().decide(
            lifecycleState: current.state,
            expectedProcessID: Int32(expectedVMProcessID)
        ) {
        case .stoppedVerified:
            log("VM lifecycle stopped proof verified after process exit pid=\(expectedVMProcessID)")
        case .terminalFailurePreserved:
            log("VM lifecycle terminal failure preserved after process exit pid=\(expectedVMProcessID)")
        case .recordTerminalFailure(let message):
            _ = try owner.writeVMLifecycleResource(
                state: .failed,
                operation: current.operation,
                terminalReason: .processExitedWithoutTerminalState,
                message: message,
                bootWindowSeconds: nil
            )
            log(message)
        case .blocked(let reason):
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle reconciliation blocked after process exit "
                    + "pid=\(expectedVMProcessID) reason=\(reason)"
            )
        }
    }

    static func reconcileAfterServiceStop(
        paths: LauncherPaths,
        log: @escaping (String) -> Void
    ) throws {
        let owner = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: paths.installed.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let read = owner.loadVMLifecycleResource()
        if read.state == .missing {
            log("VM lifecycle is explicitly missing after service stop; no prior VM run requires reconciliation")
            return
        }
        guard read.state == .loaded, let current = read.document else {
            let readError = read.readError ?? "none"
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle proof is unavailable after service stop "
                    + "state=\(read.state.rawValue) error=\(readError)"
            )
        }

        switch RuntimeVMLifecycleProcessExitPolicy().decideAfterServiceStop(
            lifecycleState: current.state
        ) {
        case .stoppedVerified:
            log("VM lifecycle stopped proof verified after service stop")
        case .terminalFailurePreserved:
            log("VM lifecycle terminal failure preserved after service stop")
        case .recordTerminalFailure(let message):
            _ = try owner.writeVMLifecycleResource(
                state: .failed,
                operation: current.operation,
                terminalReason: .serviceStoppedWithoutTerminalState,
                message: message,
                bootWindowSeconds: nil
            )
            log(message)
        case .blocked(let reason):
            throw LauncherError.runtimeOperationFailed(
                "VM lifecycle reconciliation blocked after service stop reason=\(reason)"
            )
        }
    }
}
