import Foundation
import RuntimeCore
import RuntimeContracts
import HostRuntimeInfrastructure
import Virtualization

final class VirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    let pidFile: URL
    private let fileStore: RuntimeFileWriting

    init(pidFile: URL, fileStore: RuntimeFileWriting = LocalRuntimeFileStore()) {
        self.pidFile = pidFile
        self.fileStore = fileStore
    }

    // Clean up process state when the guest shuts itself down.
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        ProcessState.removePidFile(pidFile, fileStore: fileStore)
        Foundation.exit(0)
    }
}
