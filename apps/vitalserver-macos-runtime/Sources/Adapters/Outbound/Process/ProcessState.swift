import Foundation

public enum ProcessState {
    public static func defaultProcessExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
