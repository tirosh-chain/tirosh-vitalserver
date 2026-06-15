public enum RuntimeVMProcessStopStatePolicy {
    public static func isSuccessfulStopState(
        _ state: RuntimeVMProcessState,
        allowMissingPidFile: Bool = false
    ) -> Bool {
        switch state {
        case .stopped, .stalePid:
            return true
        case .pidFileMissing:
            return allowMissingPidFile
        case .running, .pidFileInvalid, .signalFailed, .stopTimedOut, .readFailed, .unknown:
            return false
        }
    }

    public static func blockingFailureMessage(
        for state: RuntimeVMProcessState,
        allowMissingPidFile: Bool = false
    ) -> String? {
        if isSuccessfulStopState(state, allowMissingPidFile: allowMissingPidFile) {
            return nil
        }

        switch state {
        case .pidFileMissing:
            return "VM process pid file is missing; process stop state is not proven"
        case .pidFileInvalid(let message), .readFailed(let message):
            return message
        case .signalFailed(let pid, let signal, let errnoCode):
            return "failed to send signal to VM process pid=\(pid) signal=\(signal) errno=\(errnoCode)"
        case .stopTimedOut(let pid, let timeoutSeconds):
            return "VM process did not stop within \(timeoutSeconds)s pid=\(pid) pidFile state=\(state.rawValue)"
        case .running(let pid):
            return "VM process is still running pid=\(pid)"
        case .unknown(let value):
            return "unknown VM process state value=\(value)"
        case .stopped, .stalePid:
            return nil
        }
    }
}
