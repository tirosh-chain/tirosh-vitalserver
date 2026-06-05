import Foundation
import Core
import Contracts
import HostInfrastructure
import Virtualization

final class VirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    let pidFile: URL
    private let lifecycleStore: RuntimeVMLifecycleStore
    private let fileStore: RuntimeFileWriting

    init(
        pidFile: URL,
        lifecycleStore: RuntimeVMLifecycleStore,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.pidFile = pidFile
        self.lifecycleStore = lifecycleStore
        self.fileStore = fileStore
    }

    // Clean up process state when the guest shuts itself down.
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        do {
            try lifecycleStore.write(state: .stopped, message: "VM guest stopped")
        } catch {
            fputs("failed to write VM lifecycle stopped state: \(error)\n", stderr)
        }
        ProcessState.removePidFile(pidFile, fileStore: fileStore)
        Foundation.exit(0)
    }
}
