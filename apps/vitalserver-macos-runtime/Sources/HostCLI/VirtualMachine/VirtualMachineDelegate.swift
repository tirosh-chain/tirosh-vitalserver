import Foundation
import Core
import Contracts
import HostInfrastructure
import Virtualization

final class VirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    let pidFile: URL
    private let fileStore: RuntimeFileWriting

    init(pidFile: URL, fileStore: RuntimeFileWriting = SystemRuntimeFileStore()) {
        self.pidFile = pidFile
        self.fileStore = fileStore
    }

    // Clean up process state when the guest shuts itself down.
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        ProcessState.removePidFile(pidFile, fileStore: fileStore)
        Foundation.exit(0)
    }
}
