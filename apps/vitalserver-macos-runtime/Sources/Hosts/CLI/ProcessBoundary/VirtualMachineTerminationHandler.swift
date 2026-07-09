import Application
import Foundation
import OutboundAdapters
import Virtualization
import Errors

extension VirtualMachineTerminationHandler {
    static func hostCLI(
        virtualMachine: VZVirtualMachine,
        pidFile: URL,
        lifecycleWriter: any RuntimeVMLifecycleResourceWriting,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) -> VirtualMachineTerminationHandler {
        VirtualMachineTerminationHandler(
            virtualMachine: virtualMachine,
            pidFile: pidFile,
            fileStore: fileStore,
            writeLifecycle: { state, message in
                try lifecycleWriter.writeVMLifecycleResource(
                    state: state,
                    operation: nil,
                    terminalReason: nil,
                    message: message,
                    bootWindowSeconds: nil
                )
            }
        )
    }
}
