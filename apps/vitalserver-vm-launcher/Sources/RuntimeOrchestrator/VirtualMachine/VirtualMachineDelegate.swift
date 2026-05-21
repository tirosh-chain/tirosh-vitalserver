import Foundation
import Virtualization

final class VirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    let pidFile: URL

    init(pidFile: URL) {
        self.pidFile = pidFile
    }

    // Clean up process state when the guest shuts itself down.
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        ProcessState.removePidFile(pidFile)
        Foundation.exit(0)
    }
}
