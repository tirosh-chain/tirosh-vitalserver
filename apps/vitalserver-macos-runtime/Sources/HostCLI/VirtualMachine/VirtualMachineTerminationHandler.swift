import Application
import Foundation
import HostAdapters
import HostInfrastructure
import Virtualization

typealias VirtualMachineTerminationHandler = HostAdapters.VirtualMachineTerminationHandler

extension VirtualMachineTerminationHandler {
    static func hostCLI(
        virtualMachine: VZVirtualMachine,
        pidFile: URL,
        lifecycleStore: RuntimeVMLifecycleStore,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) -> VirtualMachineTerminationHandler {
        VirtualMachineTerminationHandler(
            virtualMachine: virtualMachine,
            pidFile: pidFile,
            fileStore: fileStore,
            writeLifecycle: { state, message in
                try lifecycleStore.write(state: state, message: message)
            }
        )
    }
}
